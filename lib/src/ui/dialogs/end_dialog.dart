import 'package:fortress_earth/src/campaign.dart';
import 'package:fortress_earth/src/constants.dart';
import 'package:fortress_earth/src/ui/draw.dart';
import 'package:fortress_earth/src/ui/input.dart';
import 'package:fortress_earth/src/ui/theme.dart';
import 'package:malison/malison.dart';
import 'package:malison/malison_web.dart';

/// Shown over the map when the war is over. Enter starts a new one, by
/// popping with `true`.
class EndDialog extends Screen<Input> {
  final Campaign campaign;

  EndDialog(this.campaign);

  @override
  bool get isTransparent => true;

  @override
  bool handleInput(Input input) {
    if (input == Input.ok) {
      ui.pop(true);
      return true;
    }
    return false;
  }

  @override
  bool keyDown(int keyCode, {required bool shift, required bool alt}) {
    if (keyCode == KeyCode.enter) {
      ui.pop(true);
      return true;
    }
    return false;
  }

  @override
  void render(Terminal terminal) {
    const boxWidth = 50;
    const boxHeight = 11;
    var x = (width - boxWidth) ~/ 2;
    var y = (mapHeight - boxHeight) ~/ 2;

    var won = campaign.outcome == Outcome.victory;
    var color = won ? TextTheme.ok : TextTheme.danger;

    var box = terminal.rect(x, y, boxWidth, boxHeight);
    box.clear();
    Draw.box(terminal, x, y, boxWidth, boxHeight, color);

    void centre(int row, String text, Color textColor) {
      box.writeAt((boxWidth - text.length) ~/ 2, row, text, textColor);
    }

    centre(2, won ? 'EARTH HOLDS' : 'EARTH HAS FALLEN', color);

    var days = campaign.sim.world.currentTime
        .difference(beginningOfPlay)
        .inDays;
    var held = campaign.sim.world.cities.length - campaign.citiesLost;
    centre(4, 'Day $days of the war', TextTheme.normal);
    centre(
      5,
      'Landings destroyed ${campaign.destroyed}, withered '
      '${campaign.collapsed}, of ${campaign.landed}',
      TextTheme.normal,
    );
    centre(
      6,
      'Cities held: $held of ${campaign.sim.world.cities.length}',
      TextTheme.normal,
    );

    centre(8, 'Enter: a new war', TextTheme.highlight);
  }
}
