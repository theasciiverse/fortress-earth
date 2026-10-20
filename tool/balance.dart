/// Plays wars without a screen, as fast as the machine allows, to see how
/// the campaign balances: a passive commander who gives no orders, and a
/// simple active one who answers each landing with the nearest free armies.
///
/// Usage: dart run tool/balance.dart [games per policy]
library;

import 'package:fortress_earth/src/armies.dart';
import 'package:fortress_earth/src/autopilot.dart';
import 'package:fortress_earth/src/campaign.dart';
import 'package:fortress_earth/src/constants.dart';
import 'package:fortress_earth/src/data/earth_terrain.dart';
import 'package:fortress_earth/src/simulation.dart';
import 'package:fortress_earth/src/tile.dart';
import 'package:fortress_earth/src/world.dart';

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
  final commander = Autopilot(sim);

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
      var city = commander.closestCity(core.pos);
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
