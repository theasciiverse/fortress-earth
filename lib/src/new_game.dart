import 'package:fortress_earth/src/armies.dart';
import 'package:fortress_earth/src/constants.dart';
import 'package:fortress_earth/src/data/earth_terrain.dart';
import 'package:fortress_earth/src/shared_state.dart';
import 'package:fortress_earth/src/simulation.dart';
import 'package:fortress_earth/src/tile.dart';
import 'package:fortress_earth/src/ui/game_screen.dart';
import 'package:fortress_earth/src/world.dart';

/// A new war: a fresh world, armies and campaign.
GameScreen newGameScreen({void Function()? fullscreenCallback}) {
  final world = World(
    mapWidth,
    mapHeight,
    (v) => Tile(v, getTerrainRoughness(v), backgroundColor: getTerrainColor(v)),
  );
  final sim = Simulation(world, Armies());
  return GameScreen(
    sim,
    UISharedState(),
    fullscreenCallback: fullscreenCallback,
  );
}
