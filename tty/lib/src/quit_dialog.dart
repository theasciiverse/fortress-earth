import 'package:fortress_earth/src/ui/draw.dart';
import 'package:fortress_earth/src/ui/input.dart';
import 'package:fortress_earth/src/ui/theme.dart';
import 'package:malison/malison.dart';
import 'package:malison/malison_web.dart';

/// Asks whether to leave the game, over the map. Y leaves through [onQuit];
/// N, Esc or Q again goes back. The war waits meanwhile.
class QuitDialog extends Screen<Input> {
  final void Function() onQuit;

  bool _wasRunning = false;

  QuitDialog(this.onQuit);

  @override
  bool get isTransparent => true;

  /// Pauses the war while the question is open.
  void open() {
    _wasRunning = ui.running;
    ui.running = false;
  }

  void _back() {
    ui.running = _wasRunning;
    ui.pop();
  }

  @override
  bool handleInput(Input input) {
    if (input == Input.cancel) _back();
    return true;
  }

  @override
  bool keyDown(int keyCode, {required bool shift, required bool alt}) {
    if (keyCode == KeyCode.y) {
      onQuit();
    } else if (keyCode == KeyCode.n || keyCode == KeyCode.q) {
      _back();
    }
    return true;
  }

  @override
  void render(Terminal terminal) {
    const text = 'Leave Fortress Earth?  Y / N';
    const boxWidth = text.length + 8;
    final x = (terminal.width - boxWidth) ~/ 2;
    final y = (terminal.height - 5) ~/ 2;
    final box = terminal.rect(x, y, boxWidth, 5);
    box.clear();
    Draw.box(terminal, x, y, boxWidth, 5, TextTheme.important);
    box.writeAt(4, 2, text, TextTheme.important);
  }
}
