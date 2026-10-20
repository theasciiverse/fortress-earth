import 'package:fortress_earth/src/campaign.dart';
import 'package:fortress_earth/src/constants.dart' as game;
import 'package:fortress_earth/src/ui/panels/chat_panel.dart';
import 'package:fortress_earth/src/ui/theme.dart';
import 'package:fortress_earth_tty/src/ansi_terminal.dart';
import 'package:malison/malison.dart';
import 'package:piecemeal/piecemeal.dart';

/// The game's full screen, shown as a 100x30 view for the catalog preview
/// (`--preview`): the game's own reports panel on the left, and on the right
/// a window of the map that cuts to wherever the war is, with the date in
/// its corner.
///
/// The game draws only its map into this terminal (`GameScreen.drawPanels`
/// is off); every cell of the view is the game's own drawing.
class PreviewTerminal extends RenderableTerminal {
  static const viewWidth = 100;
  static const viewHeight = 30;
  static const reportsWidth = 32;
  static const mapViewWidth = viewWidth - reportsWidth;

  @override
  final int width = game.width;

  @override
  final int height = game.height;

  final List<Glyph> _glyphs = List.filled(
    game.width * game.height,
    Glyph.clear,
  );

  final AnsiTerminal _out;

  /// The campaign whose reports, date and landings are shown, and where the
  /// war is.
  final Campaign? Function() _campaign;

  /// The top left of the map window.
  int _left = 0;
  int _top = 0;

  PreviewTerminal(this._out, this._campaign);

  @override
  Vec get size => Vec(width, height);

  @override
  void drawGlyph(int x, int y, Glyph glyph) {
    if (x < 0 || x >= width || y < 0 || y >= height) return;
    _glyphs[y * width + x] = glyph;
  }

  @override
  Vec pixelToChar(Vec pixel) => pixel;

  @override
  void render() {
    var campaign = _campaign();
    _follow(campaign);

    // The map window.
    for (var y = 0; y < viewHeight; y++) {
      for (var x = 0; x < mapViewWidth; x++) {
        var glyph = _glyphs[(_top + y) * width + _left + x];
        _out.drawGlyph(reportsWidth + x, y, glyph);
      }
    }

    if (campaign != null) {
      // The generals' reports, drawn by the game's own panel.
      var reports = _out.rect(0, 0, reportsWidth, viewHeight);
      reports.clear();
      ChatPanel(0, 0, reportsWidth, viewHeight, campaign).render(reports);

      // Date and landings, top right of the map window.
      var time = campaign.sim.world.currentTime;
      var lines = [
        ' Fortress Earth ',
        ' ${_months[time.month - 1]} ${time.day}, ${time.year} ',
        ' Landings ${campaign.landed}/${Campaign.landings} ',
      ];
      for (var i = 0; i < lines.length; i++) {
        var text = lines[i];
        _out.writeAt(
          viewWidth - text.length,
          i,
          text,
          i == 0 ? TextTheme.important : TextTheme.normal,
          Color.black,
        );
      }
    }

    _out.render();
  }

  /// Cuts the map window to the newest landing, or the last one, or the
  /// middle of the map before the first. A cut redraws the window once;
  /// gliding redrew all of it every frame and made the cast ten times
  /// bigger.
  void _follow(Campaign? campaign) {
    var target = Vec(game.mapWidth ~/ 2, game.mapHeight ~/ 2);
    var landings = campaign?.sim.armies.evilArmies ?? const [];
    for (var core in landings.reversed) {
      target = core.pos;
      if (core.isAlive) break;
    }

    var maxLeft = game.mapWidth - mapViewWidth;
    var maxTop = game.mapHeight - viewHeight;
    var left = (target.x - mapViewWidth ~/ 2).clamp(0, maxLeft);
    var top = (target.y - viewHeight ~/ 2).clamp(0, maxTop);

    _left = left;
    _top = top;
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
}
