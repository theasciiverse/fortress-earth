import 'dart:collection';
import 'dart:math';

import 'package:fortress_earth/src/armies.dart';
import 'package:fortress_earth/src/campaign.dart';
import 'package:fortress_earth/src/constants.dart';
import 'package:fortress_earth/src/shared_state.dart';
import 'package:fortress_earth/src/simulation.dart';
import 'package:fortress_earth/src/ui/audio.dart';
import 'package:fortress_earth/src/ui/dialogs/army_actions_dialog.dart';
import 'package:fortress_earth/src/ui/dialogs/end_dialog.dart';
import 'package:fortress_earth/src/ui/dialogs/help_dialog.dart';
import 'package:fortress_earth/src/new_game.dart';
import 'package:fortress_earth/src/ui/input.dart';
import 'package:fortress_earth/src/ui/panels/armies_panel.dart';
import 'package:fortress_earth/src/ui/panels/chat_panel.dart';
import 'package:fortress_earth/src/ui/panels/cities_panel.dart';
import 'package:fortress_earth/src/ui/theme.dart';
import 'package:malison/malison.dart';
import 'package:malison/malison_web.dart';
import 'package:piecemeal/piecemeal.dart';

class GameScreen extends Screen<Input> {
  final void Function()? fullscreenCallback;

  final Stopwatch _stopwatch = Stopwatch();

  int _latestUpdateTime = 0;

  int _latestRenderTime = 0;

  double _gradientLowClamp = 0;

  double _gradientHighClamp = 1;

  late UnitPanel _unitPanel;

  late final ChatPanel _chatPanel = ChatPanel(
    mapOffsetLeft,
    mapOffsetTop + mapHeight ~/ 1.7,
    32,
    height - (mapOffsetTop + mapHeight ~/ 1.7),
    campaign,
  );

  late final CitiesPanel _citiesPanel = CitiesPanel(
    mapOffsetLeft + mapWidth - 30,
    mapOffsetTop + mapHeight - 4,
    30,
    16,
    sim.world.cities,
    state,
    campaign,
  );

  /// The war around the simulation: landings, cities, reports, the end.
  final Campaign campaign;

  /// Whether the end of the war has been shown.
  bool _endShown = false;

  bool _showNeedGradient = false;

  bool _showFramerate = false;

  final UISharedState state;

  final Simulation sim;

  final List<PlayerArmy> _selectedArmies = [];

  GameScreen(this.sim, this.state, {this.fullscreenCallback})
    : campaign = Campaign(sim) {
    // TODO: move to field definition
    _unitPanel = UnitPanel(
      mapOffsetLeft + 50,
      mapOffsetTop + mapHeight - 2,
      47,
      14,
      sim.armies,
      UnmodifiableListView<PlayerArmy>(_selectedArmies),
    );
  }

  @override
  void activate(Screen<Input> popped, Object? result) {
    if (popped is EndDialog) {
      if (result == true) {
        ui.goTo(newGameScreen(fullscreenCallback: fullscreenCallback));
      }
      return;
    }

    if (result == null) {
      _selectedArmies.clear();
      return;
    }
    assert(popped is ArmyActionsDialog);

    if (result is GoDialogResult) {
      for (final army in result.armies) {
        army.setDestination(result.destination.pos);
        sim.world.clearDemand(army);
      }
      _selectedArmies.clear();
    } else if (result is ModeDialogResult) {
      print("changed mode of ${result.armies} to ${result.rangeMode}");
      for (final army in result.armies) {
        army.setRangeMode(result.rangeMode);
        sim.world.clearDemand(army);
      }
      _selectedArmies.clear();
    } else {
      throw UnimplementedError('$result');
    }
  }

  @override
  bool handleInput(Input input) {
    switch (input) {
      case Input.pause:
        ui.running = !ui.running;
        break;

      case Input.fullscreen:
        if (fullscreenCallback != null) fullscreenCallback!();
        break;

      case Input.sound:
        switchAudioOnOff();
        break;

      case Input.help:
        final help = HelpDialog();
        ui.push(help);
        help.open();
        break;

      case Input.debugNeedGradient:
        _showNeedGradient = !_showNeedGradient;
        break;

      case Input.debugShowFramerate:
        _showFramerate = !_showFramerate;
        break;

      case Input.debugAddCore:
        sim.addEnemyCore();
        break;

      default:
        return false;
    }

    return true;
  }

  @override
  bool keyDown(int keyCode, {required bool shift, required bool alt}) {
    var army = _getArmyFromKeyCode(keyCode);
    // A destroyed army takes no orders until it has regrouped.
    if (army != null && !army.isAlive) return true;
    if (army != null) {
      assert(_selectedArmies.isEmpty);
      _selectedArmies.add(army);
      ui.push(
        ArmyActionsDialog(
          50,
          mapOffsetTop + mapHeight - 6,
          sim.world,
          // The initial list of armies starts with one.
          UnmodifiableListView(_selectedArmies),
          state,
          (additionalKeyCode) {
            var additional = _getArmyFromKeyCode(additionalKeyCode);
            if (additional == null) {
              return false;
            }
            if (_selectedArmies.contains(additional)) {
              _selectedArmies.remove(additional);
            } else {
              _selectedArmies.add(additional);
            }
            return true;
          },
        ),
      );
      audioPlayer.bleep();
      return true;
    }

    print("unhandled keyDown: $keyCode (${String.fromCharCode(keyCode)})");
    return false;
  }

  void profile() {
    ui.running = true;
    for (var i = 0; i < 1000; i++) {
      update();
      ui.refresh();
    }
  }

  @override
  void render(Terminal terminal) {
    _stopwatch.reset();
    _stopwatch.start();

    terminal.clear();

    // Map.
    for (int x = 0; x < mapWidth; x++) {
      for (int y = 0; y < mapHeight; y++) {
        final screenX = mapOffsetLeft + x;
        final screenY = mapOffsetTop + y;
        final vec = Vec(x, y);
        final tile = sim.world.tiles[vec];

        String char;
        Color? foregroundColor;
        Color backgroundColor = tile.backgroundColor;
        if (_showNeedGradient) {
          //double value = tile.debugEvilDemandGradient;
          double value = tile.getDebugArmyDemandGradient(
            sim.armies.playerArmies[KeyCode.zero]!,
          );
          _gradientLowClamp = min(value, _gradientLowClamp);
          _gradientHighClamp = max(value, _gradientHighClamp);
          double normalized = _normalizeValue(
            value,
            _gradientLowClamp,
            _gradientHighClamp,
          );
          int index = (normalized * 10).floor();
          char = const [0, 1, 2, 3, 4, 5, 5, 6, 7, 8, 9][index].toString();
        } else if (sim.world.cities.containsKey(vec)) {
          if (state.citiesPanelActive) {
            char = String.fromCharCode(
              sim.world.cities[vec]!.keyCode,
            ).toUpperCase();
            foregroundColor = Color.black;
            backgroundColor = tile.isEvil ? Color.red : Color.yellow;
          } else {
            char = '■';
            foregroundColor = tile.isEvil ? Color.red : Color.yellow;
          }
        } else if (tile.isNeutral) {
          char = '░';
        } else {
          char = '▓';
        }
        foregroundColor ??= tile.foregroundColor;

        terminal.writeAt(
          screenX,
          screenY,
          char,
          foregroundColor,
          backgroundColor,
        );
      }
    }

    // Evil armies on map.
    for (final army in sim.armies.evilArmies) {
      if (!army.isAlive) continue;
      terminal.drawChar(
        mapOffsetLeft + army.pos.x,
        mapOffsetTop + army.pos.y,
        'X'.codeUnitAt(0),
        Color.black,
        army.color,
      );
    }

    // Player armies on map.
    for (final army in sim.armies.playerArmies.values) {
      if (!army.isAlive) continue;
      terminal.drawChar(
        mapOffsetLeft + army.pos.x,
        mapOffsetTop + army.pos.y,
        army.keyCode,
        Color.black,
        army.color,
      );
    }

    // Army table / panel.
    _unitPanel.render(terminal);

    // Chat panel.
    _chatPanel.render(terminal);

    // Cities panel.
    _citiesPanel.render(terminal);

    _renderTitle(terminal);

    if (_showFramerate) {
      final renderMilliseconds = (_latestRenderTime / 1000)
          .toStringAsFixed(3)
          .padLeft(6);
      final updateMilliseconds = (_latestUpdateTime / 1000)
          .toStringAsFixed(3)
          .padLeft(6);
      terminal.writeAt(0, 0, "render: ${renderMilliseconds}ms  ");
      terminal.writeAt(18, 0, "update: ${updateMilliseconds}ms  ");
    }

    _latestRenderTime = _stopwatch.elapsedMicroseconds;
    _stopwatch.stop();
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// The name, the date and how the war stands, top right.
  void _renderTitle(Terminal terminal) {
    const titleWidth = 30;
    final x = width - titleWidth;
    final time = sim.world.currentTime;
    final lines = [
      ('Fortress Earth', TextTheme.important),
      (
        '${_months[time.month - 1]} ${time.day}, ${time.year}',
        TextTheme.normal,
      ),
      (
        'Landings ${campaign.landed}/${Campaign.landings}  '
            'Cities lost ${campaign.citiesLost}',
        TextTheme.normal,
      ),
      if (!ui.running) ('PAUSED (Space)', TextTheme.warning),
    ];
    for (var i = 0; i < lines.length; i++) {
      final (text, color) = lines[i];
      terminal.writeAt(x, i, ' ' * titleWidth, color, Color.black);
      terminal.writeAt(
        x + (titleWidth - text.length) ~/ 2,
        i,
        text,
        color,
        Color.black,
      );
    }
  }

  @override
  void update() {
    _stopwatch.reset();
    _stopwatch.start();

    if (campaign.outcome != null) {
      if (!_endShown) {
        _endShown = true;
        ui.push(EndDialog(campaign));
      }
      return;
    }

    sim.update();
    campaign.update();

    dirty();

    _latestUpdateTime = _stopwatch.elapsedMicroseconds;
  }

  PlayerArmy? _getArmyFromKeyCode(int keyCode) {
    return sim.armies.playerArmies[keyCode];
  }

  static double _normalizeValue(double value, double minimum, double maximum) {
    return ((value - minimum).clamp(minimum, maximum) / (maximum - minimum));
  }
}
