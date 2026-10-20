import 'package:fortress_earth/src/armies.dart';
import 'package:fortress_earth/src/city.dart';
import 'package:fortress_earth/src/simulation.dart';
import 'package:piecemeal/piecemeal.dart';

/// How a city is doing, as the cities panel shows it.
enum CityStatus {
  /// No enemy units near.
  ok,

  /// Enemy units within [Campaign.threatRadius] tiles.
  threat,

  /// Enemy units hold the city itself.
  lost,
}

/// How the war ended, once it has.
enum Outcome {
  /// Every landing came down and every enemy unit is gone.
  victory,

  /// Too many cities fell at once, or every army was destroyed.
  defeat,
}

/// The kind of a [Report], which decides its colour.
enum ReportKind { info, good, warning, bad }

/// A message from the generals in the chat panel.
class Report {
  final DateTime time;
  final String text;
  final ReportKind kind;

  const Report(this.time, this.text, this.kind);
}

/// The war around the simulation: when the Arrivals land, how the cities
/// stand, what the generals report, and when it is won or lost.
///
/// The simulation itself (armies spreading over the map, fighting for tiles)
/// is unchanged; this only watches it and adds enemy landings on a schedule.
class Campaign {
  /// The number of landings in a war.
  static const landings = 10;

  /// Days from the start of play to the first landing.
  static const firstLandingDay = 20;

  /// Days between the first two landings; each later gap is
  /// [landingGapShrink] days shorter, down to [shortestLandingGap].
  static const firstLandingGap = 60;
  static const landingGapShrink = 5;
  static const shortestLandingGap = 30;

  /// Enemy units this close to a city (in tiles) make it threatened.
  static const threatRadius = 4;

  /// The war is lost when this many cities are in enemy hands at once.
  static const citiesLostForDefeat = 6;

  /// Dead units each living army gets back as recruits every day.
  static const recruitsPerDay = 5;

  /// Landings come down at least [landingMinDistance] and at most
  /// [landingMaxDistance] tiles from a city: they are after the cities, and
  /// a landing far from any city could never be reached.
  static const landingMinDistance = 5;
  static const landingMaxDistance = 12;

  /// A landing that has stopped producing units and has no more than this
  /// many left on the whole map is beaten: the stragglers die off.
  static const stragglers = 50;

  /// A landing that has stopped producing and is surrounded (no enemy land
  /// next to its tile, some of ours) loses this share of the force on its
  /// tile a day, at least one unit. Starved out, it counts as destroyed.
  static const siegePerDay = 0.1;

  /// Days before a destroyed army is back.
  static const daysToReform = 30;

  /// Where destroyed armies regroup, as the armies start: in the Atlantic.
  static const regroupPosition = Vec(72, 18);

  final Simulation sim;

  final List<Report> reports = [];

  final Map<City, CityStatus> _status = {};

  /// Landings so far.
  int landed = 0;

  /// Landings destroyed by the player so far.
  int destroyed = 0;

  /// Landings that withered and collapsed so far.
  int collapsed = 0;

  /// Landings over, destroyed or collapsed.
  int get beaten => destroyed + collapsed;

  final Set<EvilArmy> _collapsing = {};

  Outcome? outcome;

  final Set<EvilArmy> _knownAlive = {};
  final Map<PlayerArmy, bool> _armyArrived = {};
  final Map<PlayerArmy, DateTime> _armyDiedAt = {};

  /// Land tiles connected over land to a city, where landings can be
  /// reached; units cannot cross the sea.
  late final Set<Vec> _reachable = _landReachableFromCities();

  late DateTime _nextLanding;
  int _nextGap = firstLandingGap;
  late int _lastDay;

  Campaign(this.sim) {
    var start = sim.world.currentTime;
    _nextLanding = start.add(const Duration(days: firstLandingDay));
    _lastDay = _day(start);

    for (var city in sim.world.cities.values) {
      _status[city] = CityStatus.ok;
    }
    for (var army in sim.armies.playerArmies.values) {
      _armyArrived[army] = army.hasArrived;
    }

    _report(
      'HQ: Something is coming down from orbit. Hold the cities.',
      ReportKind.info,
    );
    _report(
      'Press an army\'s number, then G and a city\'s letter to send it there.',
      ReportKind.info,
    );
    _report('Space pauses.', ReportKind.info);
  }

  /// The status of [city] as of the last [update].
  CityStatus statusOf(City city) => _status[city] ?? CityStatus.ok;

  /// Cities in enemy hands.
  int get citiesLost =>
      _status.values.where((status) => status == CityStatus.lost).length;

  /// Called after every simulation step.
  void update() {
    if (outcome != null) return;
    var now = sim.world.currentTime;

    if (landed < landings && !now.isBefore(_nextLanding)) _land(now);

    _updateLandings();
    _updateCities();
    _updateArmies(now);

    var day = _day(now);
    if (day != _lastDay) {
      _lastDay = day;
      for (var army in sim.armies.playerArmies.values) {
        if (army.isAlive) army.recruit(recruitsPerDay);
      }
      _wither(now);
    }

    _checkOutcome();
  }

  void _land(DateTime now) {
    var before = sim.armies.evilArmies.length;
    sim.addEnemyCore(
      where: (tile) {
        if (!_reachable.contains(tile.pos)) return false;
        var distance = (_closestCity(tile.pos).pos - tile.pos).length;
        return distance >= landingMinDistance && distance <= landingMaxDistance;
      },
    );
    if (sim.armies.evilArmies.length == before) return;

    landed++;
    var core = sim.armies.evilArmies.last;
    _knownAlive.add(core);
    var near = _closestCity(core.pos);
    _report(
      'Landing $landed of $landings: Arrivals came down '
      'near ${near.name}.',
      ReportKind.bad,
    );

    _nextLanding = now.add(Duration(days: _nextGap));
    _nextGap = (_nextGap - landingGapShrink).clamp(
      shortestLandingGap,
      firstLandingGap,
    );
  }

  void _updateLandings() {
    for (var core in _knownAlive.toList()) {
      if (core.isAlive) continue;
      _knownAlive.remove(core);
      var near = _closestCity(core.pos).name;
      if (_collapsing.remove(core)) {
        collapsed++;
        _report('The landing near $near has withered away.', ReportKind.good);
      } else {
        destroyed++;
        _report('The landing near $near is destroyed.', ReportKind.good);
      }
    }
  }

  /// Landings that no longer produce: starved by a siege, or collapsed
  /// when down to a few stragglers. Their remaining units die off.
  void _wither(DateTime now) {
    for (var core in _knownAlive) {
      if (core.isGeneratingUnits(now)) continue;

      if (_isBesieged(core.pos)) {
        var tile = sim.world.tiles[core.pos];
        var here = tile.unitsOf(core);
        tile.attrit(core, (here * siegePerDay).ceil());
        if (tile.unitsOf(core) == 0) {
          core.isAlive = false;
          continue;
        }
      }

      if (core.fieldedUnits <= stragglers) {
        _collapsing.add(core);
        core.isAlive = false;
      }
    }
  }

  /// Whether every land tile next to [pos] is free of the enemy and at least
  /// one is held by the player.
  bool _isBesieged(Vec pos) {
    var tiles = sim.world.tiles;
    var width = sim.world.mapWidth;
    var ours = false;
    for (var dir in Direction.all) {
      var next = pos + dir;
      if (next.y < 0 || next.y >= sim.world.mapHeight) continue;
      var tile = tiles[Vec((next.x + width) % width, next.y)];
      if (tile.isOcean) continue;
      if (tile.isEvil) return false;
      if (tile.isGood) ours = true;
    }
    return ours;
  }

  void _updateCities() {
    for (var city in sim.world.cities.values) {
      var status = _cityStatus(city);
      var old = _status[city]!;
      if (status == old) continue;
      _status[city] = status;

      switch ((old, status)) {
        case (_, CityStatus.lost):
          _report('${city.name} has fallen.', ReportKind.bad);
        case (CityStatus.lost, _):
          _report('${city.name} is ours again.', ReportKind.good);
        case (CityStatus.ok, CityStatus.threat):
          _report('Enemy units near ${city.name}.', ReportKind.warning);
        case (CityStatus.threat, CityStatus.ok):
          _report('${city.name} is clear.', ReportKind.good);
        default:
          break;
      }
    }
  }

  CityStatus _cityStatus(City city) {
    var tiles = sim.world.tiles;
    if (tiles[city.pos].isEvil) return CityStatus.lost;

    for (var dy = -threatRadius; dy <= threatRadius; dy++) {
      for (var dx = -threatRadius; dx <= threatRadius; dx++) {
        var pos = city.pos + Vec(dx, dy);
        if (!tiles.bounds.contains(pos)) continue;
        if (Vec(dx, dy).lengthSquared > threatRadius * threatRadius) continue;
        if (tiles[pos].isEvil) return CityStatus.threat;
      }
    }
    return CityStatus.ok;
  }

  void _updateArmies(DateTime now) {
    for (var army in sim.armies.playerArmies.values) {
      var label = '${String.fromCharCode(army.keyCode)} ${army.name}';

      if (!army.isAlive) {
        var diedAt = _armyDiedAt[army];
        if (diedAt == null) {
          _armyDiedAt[army] = now;
          _report(
            '$label overrun near ${_closestCity(army.pos).name}.',
            ReportKind.bad,
          );
        } else if (now.difference(diedAt).inDays >= daysToReform) {
          _armyDiedAt.remove(army);
          army.reform(regroupPosition);
          _armyArrived[army] = true;
          _report(
            '$label has regrouped in the Atlantic, awaiting orders.',
            ReportKind.info,
          );
        }
        continue;
      }

      var arrived = army.hasArrived;
      if (arrived && !_armyArrived[army]!) {
        var city = army.deployedAt;
        if (city != null) {
          _report('$label in position at ${city.name}.', ReportKind.info);
        }
      }
      _armyArrived[army] = arrived;
    }
  }

  void _checkOutcome() {
    if (citiesLost >= citiesLostForDefeat) {
      _end(
        Outcome.defeat,
        '$citiesLost cities are in enemy hands. Earth has fallen.',
      );
      return;
    }

    if (sim.armies.playerArmies.values.every((army) => !army.isAlive)) {
      _end(Outcome.defeat, 'Every army is destroyed. Earth has fallen.');
      return;
    }

    // Units of a destroyed landing die off by themselves.
    if (landed == landings && _knownAlive.isEmpty) {
      _end(Outcome.victory, 'The last of the Arrivals is gone. Earth holds.');
    }
  }

  void _end(Outcome result, String text) {
    outcome = result;
    _report(text, result == Outcome.victory ? ReportKind.good : ReportKind.bad);
  }

  void _report(String text, ReportKind kind) {
    reports.add(Report(sim.world.currentTime, text, kind));
    print('report: $text');
  }

  /// Flood fill over land from every city, through the same eight
  /// neighbours units move to, wrapping east to west.
  Set<Vec> _landReachableFromCities() {
    var tiles = sim.world.tiles;
    var width = sim.world.mapWidth;
    var reached = <Vec>{};
    var queue = [for (var city in sim.world.cities.values) city.pos];
    reached.addAll(queue);
    while (queue.isNotEmpty) {
      var pos = queue.removeLast();
      for (var dir in Direction.all) {
        var next = pos + dir;
        if (next.y < 0 || next.y >= sim.world.mapHeight) continue;
        next = Vec((next.x + width) % width, next.y);
        if (reached.contains(next) || tiles[next].isOcean) continue;
        reached.add(next);
        queue.add(next);
      }
    }
    return reached;
  }

  City _closestCity(Vec pos) {
    City? closest;
    var best = 0;
    for (var city in sim.world.cities.values) {
      var distance = (city.pos - pos).lengthSquared;
      if (closest == null || distance < best) {
        closest = city;
        best = distance;
      }
    }
    return closest!;
  }

  static int _day(DateTime time) => time.difference(DateTime.utc(2000)).inDays;
}
