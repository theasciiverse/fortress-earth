/// Plays wars without a screen, as fast as the machine allows, to see how
/// the campaign balances: a passive commander who gives no orders, and a
/// simple active one who answers each landing with the nearest free armies.
///
/// Usage: dart run tool/balance.dart [games per policy]
library;

import 'package:fortress_earth/src/armies.dart';
import 'package:fortress_earth/src/campaign.dart';
import 'package:fortress_earth/src/city.dart';
import 'package:fortress_earth/src/constants.dart';
import 'package:fortress_earth/src/data/earth_terrain.dart';
import 'package:fortress_earth/src/simulation.dart';
import 'package:fortress_earth/src/tile.dart';
import 'package:fortress_earth/src/world.dart';
import 'package:piecemeal/piecemeal.dart';

void main(List<String> args) {
  var games = args.isEmpty ? 4 : int.parse(args.first);
  var policies = args.length > 1 ? [args[1] == 'active'] : [false, true];
  for (var active in policies) {
    print(active ? 'Active commander:' : 'Passive commander:');
    for (var i = 0; i < games; i++) {
      print('  ${_play(active)}');
    }
  }
}

String _play(bool active) {
  final world = World(
    mapWidth,
    mapHeight,
    (v) => Tile(v, getTerrainRoughness(v), backgroundColor: getTerrainColor(v)),
  );
  final sim = Simulation(world, Armies());
  final campaign = Campaign(sim);
  final commander = _Commander(sim, campaign);

  var ticks = 0;
  // Two years of play at most.
  while (campaign.outcome == null && ticks < 24 * 730) {
    sim.update();
    campaign.update();
    if (active) commander.update();
    ticks++;
  }

  var details = StringBuffer();
  if (campaign.outcome == null) {
    for (var core in sim.armies.evilArmies.where((c) => c.isAlive)) {
      var tile = world.tiles[core.pos];
      var city = commander._closestCity(core.pos);
      var good = 0;
      var evil = 0;
      for (var t in world.tiles) {
        if ((t.pos - core.pos).lengthSquared <= 25) {
          good += t.good;
          evil += t.evil;
        }
      }
      details.write(
        '\n      core at ${core.pos} (${city.name}, '
        '${(city.pos - core.pos).length.toStringAsFixed(0)} tiles), '
        'core tile evil ${tile.evil}, within 5: evil $evil good $good',
      );
    }
    var evilTiles = world.tiles.where((t) => t.isEvil).length;
    details.write('\n      evil tiles on the map: $evilTiles');
  }

  var days = world.currentTime.difference(beginningOfPlay).inDays;
  var seconds = (ticks / 60).toStringAsFixed(0);
  var result = campaign.outcome?.name ?? 'undecided';
  return '$result on day $days (${seconds}s at 60 fps), '
      'landings ${campaign.destroyed} destroyed ${campaign.collapsed} '
      'withered of ${campaign.landed}, '
      'cities lost ${campaign.citiesLost}, '
      'armies alive ${sim.armies.playerArmies.values.where((a) => a.isAlive).length}'
      '$details';
}

/// Sends the nearest free armies to the city closest to each new landing,
/// and lets them seek and destroy once there.
class _Commander {
  final Simulation sim;
  final Campaign campaign;
  final Map<EvilArmy, List<PlayerArmy>> _assigned = {};

  _Commander(this.sim, this.campaign);

  void update() {
    for (var core in sim.armies.evilArmies) {
      if (!core.isAlive || _assigned.containsKey(core)) continue;
      var target = _closestCity(core.pos);
      var busy = _assigned.values.expand((armies) => armies).toSet();
      var free =
          sim.armies.playerArmies.values
              .where((army) => army.isAlive && !busy.contains(army))
              .toList()
            ..sort(
              (a, b) => (a.pos - target.pos).lengthSquared.compareTo(
                (b.pos - target.pos).lengthSquared,
              ),
            );
      var sent = free.take(3).toList();
      for (var army in sent) {
        army.setDestination(target.pos);
        army.setRangeMode(RangeMode.expanded);
        sim.world.clearDemand(army);
      }
      _assigned[core] = sent;
    }

    for (var entry in _assigned.entries) {
      var core = entry.key;
      for (var army in entry.value) {
        if (!army.isAlive || !army.hasArrived) continue;
        var mode = core.isAlive ? RangeMode.seekAndDestroy : RangeMode.tight;
        if (army.maxDeploymentRange != _range(mode)) {
          army.setRangeMode(mode);
          sim.world.clearDemand(army);
        }
      }
    }
    _assigned.removeWhere(
      (core, armies) => !core.isAlive && armies.every((a) => a.hasArrived),
    );
  }

  static double _range(RangeMode mode) => switch (mode) {
    RangeMode.tight => 3,
    RangeMode.expanded => defaultMaxDeploymentRange,
    RangeMode.seekAndDestroy => double.infinity,
  };

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
}
