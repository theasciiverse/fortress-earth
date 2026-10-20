import 'package:fortress_earth/src/armies.dart';
import 'package:fortress_earth/src/city.dart';
import 'package:fortress_earth/src/constants.dart';
import 'package:fortress_earth/src/simulation.dart';
import 'package:piecemeal/piecemeal.dart';

/// A simple commander for `--demo` and the balance tool. It gives the same
/// orders a player gives through the army dialogs:
/// sends the nearest free armies to the city closest to each new landing,
/// expanded, and lets them seek and destroy once there.
class Autopilot {
  final Simulation sim;
  final Map<EvilArmy, List<PlayerArmy>> _assigned = {};

  Autopilot(this.sim);

  void update() {
    for (var core in sim.armies.evilArmies) {
      if (!core.isAlive || _assigned.containsKey(core)) continue;
      var target = closestCity(core.pos);
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

  /// The city nearest to [pos].
  City closestCity(Vec pos) {
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
