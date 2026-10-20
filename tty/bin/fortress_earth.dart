import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fortress_earth/src/constants.dart' as game;
import 'package:fortress_earth/src/new_game.dart';
import 'package:fortress_earth/src/random.dart';
import 'package:fortress_earth/src/ui/game_screen.dart';
import 'package:fortress_earth/src/ui/input.dart';
import 'package:fortress_earth_tty/src/ansi_terminal.dart';
import 'package:fortress_earth_tty/src/keys.dart';
import 'package:fortress_earth_tty/src/preview_terminal.dart';
import 'package:fortress_earth_tty/src/quit_dialog.dart';
import 'package:fortress_earth_tty/src/windows_console.dart';
import 'package:malison/malison.dart';
import 'package:malison/malison_web.dart';

/// Where log lines go when `FORTRESS_EARTH_LOG` names a file; nowhere
/// otherwise, since stdout and stderr are the game screen.
IOSink? _log;

late final UserInterface<Input> _ui;

/// The size of the real terminal the screen was last laid out for.
int _columns = 0;
int _lines = 0;

/// Whether the terminal is too small and the message about it is showing.
/// The game waits until the terminal is big enough.
bool _tooSmall = false;

WindowsConsole? _windowsConsole;

/// `--demo`: the computer plays.
bool _demo = false;

/// `--preview`: the 100x30 view for the catalog preview.
bool _preview = false;

/// `--quit-after SECONDS`: end by itself, for recordings.
Duration? _quitAfter;

/// The game screen last seen on top, for the preview's reports and date.
GameScreen? _game;

/// The smallest terminal: the whole screen, or the preview's view.
int get _minWidth => _preview ? PreviewTerminal.viewWidth : game.width;
int get _minHeight => _preview ? PreviewTerminal.viewHeight : game.height;
Timer? _timer;
bool _done = false;

const _usage =
    '''Usage: fortress-earth [options]

  --demo        watch the computer fight the war
  --preview     the 100x30 view recorded for the catalog: reports and a
                window of the map that follows the war
  --seed N      seed the random numbers, for a repeatable war
  --quit-after SECONDS
                quit by itself after this long, for recordings
  --version     print the version and exit

Fortress Earth draws the whole world at once and needs a terminal of at
least ${game.width}x${game.height}. Q or Esc on the map asks to leave;
Ctrl+C or Alt+Q leaves at once.
FORTRESS_EARTH_LOG=FILE writes key presses and messages to FILE.''';

void main(List<String> arguments) {
  for (var i = 0; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--version':
        stdout.writeln('fortress-earth (terminal build)');
        return;
      case '--help' || '-h':
        stdout.writeln(_usage);
        return;
      case '--demo':
        _demo = true;
      case '--preview':
        _preview = true;
      case '--seed' when i + 1 < arguments.length:
        var seed = int.tryParse(arguments[++i]);
        if (seed == null) {
          stderr.writeln('--seed needs a number.');
          exitCode = 2;
          return;
        }
        seedGameRandom(seed);
      case '--quit-after' when i + 1 < arguments.length:
        var seconds = double.tryParse(arguments[++i]);
        if (seconds == null || seconds <= 0) {
          stderr.writeln('--quit-after needs a number of seconds.');
          exitCode = 2;
          return;
        }
        _quitAfter = Duration(milliseconds: (seconds * 1000).round());
      default:
        stderr.writeln('Unknown option ${arguments[i]}.\n\n$_usage');
        exitCode = 2;
        return;
    }
  }

  if (!stdin.hasTerminal || !stdout.hasTerminal) {
    stderr.writeln('Fortress Earth needs to run in a terminal.');
    exitCode = 1;
    return;
  }

  var logPath = Platform.environment['FORTRESS_EARTH_LOG'];
  if (logPath != null && logPath.isNotEmpty) {
    _log = File(logPath).openWrite(mode: FileMode.append);
  }

  // The game prints notes to the browser console; keep them off the screen.
  runZonedGuarded(
    _run,
    (error, stack) {
      _restoreTerminal();
      stderr.writeln('Fortress Earth crashed: $error\n$stack');
      _log?.writeln('crash: $error\n$stack');
      _log?.flush().whenComplete(() => exit(70));
      if (_log == null) exit(70);
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => _log?.writeln(line),
    ),
  );
}

void _run() {
  stdout.encoding = utf8;
  stdin.echoMode = false;
  stdin.lineMode = false;
  if (Platform.isWindows) _windowsConsole = WindowsConsole()..enable();

  // Alternate screen, hidden cursor, cleared screen.
  stdout.write('\x1b[?1049h\x1b[?25l\x1b[0m\x1b[2J');

  // As in the game's browser entry point, lib/web_engine.dart.
  _ui = UserInterface<Input>(_makeTerminal());
  _bindKeys(_ui);

  _ui.push(newGameScreen(demo: _demo));

  _ui.handlingInput = true;
  _ui.running = true;

  // A closed terminal ends the game like Ctrl+C.
  stdin.listen(_input, onDone: _quit, onError: (Object _) => _quit());

  // Ctrl+C arrives as a signal, since Dart leaves signals on in raw mode.
  ProcessSignal.sigint.watch().listen((_) => _quit());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => _quit());
    ProcessSignal.sighup.watch().listen((_) => _quit());
  }

  if (_quitAfter case var after?) Timer(after, _quit);

  _timer = Timer.periodic(
    Duration(microseconds: 1000000 ~/ _ui.framesPerSecond),
    (_) => _tick(),
  );
  _tick();
}

/// A terminal of the game's fixed size, or the preview's view, centred in
/// the real one.
RenderableTerminal _makeTerminal() {
  _columns = stdout.terminalColumns;
  _lines = stdout.terminalLines;
  _log?.writeln('terminal ${_columns}x$_lines');
  var out = AnsiTerminal(
    _minWidth,
    _minHeight,
    stdout,
    originX: ((_columns - _minWidth) ~/ 2).clamp(0, _columns),
    originY: ((_lines - _minHeight) ~/ 2).clamp(0, _lines),
  );
  if (!_preview) return out;
  return PreviewTerminal(out, () => _game?.campaign);
}

/// Shows how big the terminal needs to be, centred.
void _showTooSmall() {
  var lines = [
    'Fortress Earth needs a terminal of at least ${_minWidth}x$_minHeight.',
    'This one is ${_columns}x$_lines. Make the window bigger',
    'or the font smaller, or press Ctrl+C to quit.',
  ];

  var buffer = StringBuffer('\x1b[0m\x1b[2J');
  var top = (_lines - lines.length) ~/ 2;
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (line.length > _columns) line = line.substring(0, _columns);
    var x = (_columns - line.length) ~/ 2;
    buffer.write('\x1b[${top + i + 1};${x + 1}H$line');
  }
  stdout.write(buffer.toString());
  _log?.writeln('too small: ${_columns}x$_lines');
}

void _tick() {
  if (_done) return;

  var columns = stdout.terminalColumns;
  var lines = stdout.terminalLines;
  var resized = columns != _columns || lines != _lines;

  if (columns < _minWidth || lines < _minHeight) {
    if (!_tooSmall || resized) {
      _tooSmall = true;
      _columns = columns;
      _lines = lines;
      _showTooSmall();
    }
    return;
  }

  if (_tooSmall || resized) {
    _tooSmall = false;
    stdout.write('\x1b[0m\x1b[2J');
    // A new terminal draws every cell, at the new centre.
    _ui.setTerminal(_makeTerminal());
    _ui.dirty();
  }

  // The preview lays the screen out itself, from the game's map and panels.
  if (_ui.topScreen case GameScreen screen) {
    _game = screen;
    if (_preview) screen.drawPanels = false;
  }

  // Space pauses: the game screen stops updating, but dialogs still draw.
  if (_ui.running) {
    _ui.refresh();
  } else {
    _ui.redraw();
  }
}

void _input(List<int> bytes) {
  for (var key in decodeKeys(bytes)) {
    if (_done) return;
    _log?.writeln('key $key');

    // Ctrl+C and Alt+Q quit at once.
    if (key.keyCode == ctrlC || (key.alt && key.keyCode == KeyCode.q)) {
      _quit();
      return;
    }

    // Keys wait with the game while the terminal is too small.
    if (_tooSmall) continue;

    // On the map (no order being given), Q or Esc asks whether to leave.
    // Q is Quito's key only while picking a city.
    if (_ui.topScreen is GameScreen &&
        !key.shift &&
        !key.alt &&
        (key.keyCode == KeyCode.q || key.keyCode == KeyCode.escape)) {
      final dialog = QuitDialog(_quit);
      _ui.push(dialog);
      dialog.open();
      continue;
    }

    // A terminal sends no key releases and cannot report Shift held on its
    // own, so press and release it around every shifted key.
    if (key.shift) _ui.keyDown(KeyCode.shift, shift: true, alt: key.alt);
    _ui.keyDown(key.keyCode, shift: key.shift, alt: key.alt);
    _ui.keyUp(key.keyCode, shift: key.shift, alt: key.alt);
    if (key.shift) _ui.keyUp(KeyCode.shift, alt: key.alt);
  }

  // Draw the result now rather than on the next tick.
  if (!_tooSmall) _ui.redraw();
}

void _quit() {
  if (_done) return;
  _done = true;
  _timer?.cancel();
  _restoreTerminal();
  _log?.writeln('quit');
  var log = _log;
  if (log == null) exit(0);
  log.flush().whenComplete(() => exit(0));
}

void _restoreTerminal() {
  stdout.write('\x1b[0m\x1b[?25h\x1b[?1049l');
  try {
    stdin.lineMode = true;
    stdin.echoMode = true;
    _windowsConsole?.restore();
  } on Object {
    // The terminal may already be gone.
  }
}

/// The game's key bindings, as in `lib/web_engine.dart`. Alt+F (full screen)
/// does nothing in a terminal.
void _bindKeys(UserInterface<Input> ui) {
  ui.keyPress.bind(Input.pause, KeyCode.space);
  ui.keyPress.bind(Input.cancel, KeyCode.escape);
  ui.keyPress.bind(Input.cancel, KeyCode.delete);

  ui.keyPress.bind(Input.go, KeyCode.g);
  ui.keyPress.bind(Input.tight, KeyCode.t);
  ui.keyPress.bind(Input.expanded, KeyCode.e);
  ui.keyPress.bind(Input.destroy, KeyCode.d);

  ui.keyPress.bind(Input.fullscreen, KeyCode.f, alt: true);
  ui.keyPress.bind(Input.sound, KeyCode.s, alt: true);

  // F1, ? and H show how to play.
  ui.keyPress.bind(Input.help, f1);
  ui.keyPress.bind(Input.help, KeyCode.slash, shift: true);
  ui.keyPress.bind(Input.help, KeyCode.h);

  ui.keyPress.bind(Input.debugNeedGradient, KeyCode.n, alt: true);
  ui.keyPress.bind(Input.debugShowFramerate, KeyCode.d, alt: true);
  ui.keyPress.bind(Input.debugAddCore, KeyCode.x, alt: true, shift: true);
}
