import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fortress_earth/src/constants.dart' as game;
import 'package:fortress_earth/src/new_game.dart';
import 'package:fortress_earth/src/ui/input.dart';
import 'package:fortress_earth_tty/src/ansi_terminal.dart';
import 'package:fortress_earth_tty/src/keys.dart';
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
Timer? _timer;
bool _done = false;

const _usage =
    '''Usage: fortress-earth [options]

  --version     print the version and exit

Fortress Earth draws the whole world at once and needs a terminal of at
least ${game.width}x${game.height}. Ctrl+C or Alt+Q quits.
FORTRESS_EARTH_LOG=FILE writes key presses and messages to FILE.''';

void main(List<String> arguments) {
  for (var argument in arguments) {
    switch (argument) {
      case '--version':
        stdout.writeln('fortress-earth (terminal build)');
        return;
      case '--help' || '-h':
        stdout.writeln(_usage);
        return;
      default:
        stderr.writeln('Unknown option $argument.\n\n$_usage');
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

  _ui.push(newGameScreen());

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

  _timer = Timer.periodic(
    Duration(microseconds: 1000000 ~/ _ui.framesPerSecond),
    (_) => _tick(),
  );
  _tick();
}

/// A terminal of the game's fixed size, centred in the real one.
AnsiTerminal _makeTerminal() {
  _columns = stdout.terminalColumns;
  _lines = stdout.terminalLines;
  var terminal = AnsiTerminal(
    game.width,
    game.height,
    stdout,
    originX: ((_columns - game.width) ~/ 2).clamp(0, _columns),
    originY: ((_lines - game.height) ~/ 2).clamp(0, _lines),
  );
  _log?.writeln('terminal ${_columns}x$_lines');
  return terminal;
}

/// Shows how big the terminal needs to be, centred.
void _showTooSmall() {
  var lines = [
    'Fortress Earth needs a terminal of at least ${game.width}x${game.height}.',
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

  if (columns < game.width || lines < game.height) {
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

    // Q is a city's key, so Alt+Q quits, with Ctrl+C.
    if (key.keyCode == ctrlC || (key.alt && key.keyCode == KeyCode.q)) {
      _quit();
      return;
    }

    // Keys wait with the game while the terminal is too small.
    if (_tooSmall) continue;

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

  ui.keyPress.bind(Input.debugNeedGradient, KeyCode.n, alt: true);
  ui.keyPress.bind(Input.debugShowFramerate, KeyCode.d, alt: true);
  ui.keyPress.bind(Input.debugAddCore, KeyCode.x, alt: true, shift: true);
}
