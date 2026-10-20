import 'dart:math';

/// The random numbers behind the whole game, so that a war can be repeated
/// from a seed (`--seed`, for recordings and testing).
Random gameRandom = Random();

/// Starts the game's random numbers over from [seed].
void seedGameRandom(int seed) {
  gameRandom = Random(seed);
}
