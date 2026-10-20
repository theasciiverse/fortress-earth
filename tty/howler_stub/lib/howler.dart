/// Silent stand-in for the part of `package:howler` (a port of howler.js,
/// browser only) that Fortress Earth uses, so the game compiles natively.
/// Sounds are accepted and never played.
library;

typedef HowlEventListener =
    Function(Howl howl, String eventType, int? id, String? message);

class Howl {
  Howl({
    List<String>? src,
    bool autoplay = false,
    bool loop = false,
    bool preload = true,
    double volume = 1,
    HowlEventListener? onload,
  });

  int? play([dynamic sprite, bool internal = false]) => null;

  Howl stopAll() => this;
}
