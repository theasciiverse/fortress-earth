import 'package:fortress_earth/src/constants.dart';
import 'package:fortress_earth/src/ui/draw.dart';
import 'package:fortress_earth/src/ui/input.dart';
import 'package:fortress_earth/src/ui/theme.dart';
import 'package:malison/malison.dart';
import 'package:malison/malison_web.dart';

/// How to play, over the map. The war waits while it is open; Esc, Enter,
/// F1, ? or H closes it.
class HelpDialog extends Screen<Input> {
  /// Whether the war was running when help opened, to carry on after.
  bool _wasRunning = false;

  static const _boxWidth = 84;

  static const List<(String, Color)> _lines = [
    (
      'The Arrivals are coming down from orbit, one landing after another.',
      TextTheme.important,
    ),
    (
      'Hold the twelve great cities until the last of them is gone.',
      TextTheme.important,
    ),
    ('', TextTheme.normal),
    ('ORDERS', TextTheme.highlight),
    ('  0 to 9      pick an army (from the Armies panel)', TextTheme.normal),
    (
      '  then G      go: the city letters light up on the map; press one',
      TextTheme.normal,
    ),
    ('  then T      tight: hold close to the city', TextTheme.normal),
    (
      '  then E      expanded: spread out further from the city',
      TextTheme.normal,
    ),
    ('  then D      destroy: go after the enemy anywhere', TextTheme.normal),
    ('  Esc         cancel an order', TextTheme.normal),
    ('  Space       pause and carry on', TextTheme.normal),
    ('  F1, ?, H    this help', TextTheme.normal),
    (
      '  Q or Esc    on the map: leave the game (it asks first)',
      TextTheme.normal,
    ),
    ('  Ctrl+C      leave at once', TextTheme.normal),
    ('', TextTheme.normal),
    ('THE MAP', TextTheme.highlight),
    ('  ■           a city; red when the enemy holds it', TextTheme.normal),
    ('  1 2 ... 0   your armies', TextTheme.normal),
    (
      '  X           a landing, which sends out enemy units for its first 30 days',
      TextTheme.normal,
    ),
    (
      '  ▓           land held by you (white) or by the enemy (red)',
      TextTheme.normal,
    ),
    (
      '  ░           land nobody holds; units cross land, never the sea',
      TextTheme.normal,
    ),
    ('', TextTheme.normal),
    ('THE WAR', TextTheme.highlight),
    (
      '  A landing ends when you take its tile, or when it has stopped sending',
      TextTheme.normal,
    ),
    (
      '  out units and you surround it: then it starves. Its units die with it.',
      TextTheme.normal,
    ),
    (
      '  Armies get recruits every day. An army that is overrun comes back',
      TextTheme.normal,
    ),
    ('  30 days later, in the Atlantic, ready for orders.', TextTheme.normal),
    (
      '  Six cities lost at once, or every army gone, and Earth has fallen.',
      TextTheme.normal,
    ),
    (
      '  Watch the Reports panel: your generals tell you what is happening.',
      TextTheme.normal,
    ),
  ];

  @override
  bool get isTransparent => true;

  @override
  void activate(Screen<Input> popped, Object? result) {}

  /// Pauses the war when help opens.
  void open() {
    _wasRunning = ui.running;
    ui.running = false;
  }

  void _close() {
    ui.running = _wasRunning;
    ui.pop();
  }

  @override
  bool handleInput(Input input) {
    if (input == Input.cancel || input == Input.help || input == Input.ok) {
      _close();
    }
    // Nothing else reaches the war while help is open.
    return true;
  }

  @override
  bool keyDown(int keyCode, {required bool shift, required bool alt}) {
    if (keyCode == KeyCode.enter) _close();
    return true;
  }

  @override
  void render(Terminal terminal) {
    final boxHeight = _lines.length + 6;
    final x = (width - _boxWidth) ~/ 2;
    final y = (height - boxHeight) ~/ 2;

    final box = terminal.rect(x, y, _boxWidth, boxHeight);
    box.clear();
    Draw.box(terminal, x, y, _boxWidth, boxHeight, TextTheme.important);
    box.writeAt(2, 0, ' Fortress Earth: how to play ', TextTheme.important);

    for (var i = 0; i < _lines.length; i++) {
      final (text, color) = _lines[i];
      box.writeAt(3, i + 2, text, color);
    }

    const close = 'Esc or Enter: back to the war';
    box.writeAt(
      (_boxWidth - close.length) ~/ 2,
      boxHeight - 2,
      close,
      TextTheme.highlight,
    );
  }
}
