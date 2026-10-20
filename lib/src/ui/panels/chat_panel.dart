import 'package:fortress_earth/src/campaign.dart';
import 'package:fortress_earth/src/ui/panels/panel.dart';
import 'package:fortress_earth/src/ui/theme.dart';
import 'package:malison/malison.dart';

/// The generals' reports, newest at the bottom.
class ChatPanel extends Panel {
  final Campaign campaign;

  ChatPanel(super.x, super.y, super.width, super.height, this.campaign);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void renderPanel(Terminal terminal) {
    terminal.writeAt(0, 0, "Reports");

    // Fill the panel from the bottom up with the newest reports that fit.
    var lines = <(String, Color)>[];
    var bottom = terminal.height - 1;
    var room = bottom - 1;
    for (var i = campaign.reports.length - 1; i >= 0 && room > 0; i--) {
      var report = campaign.reports[i];
      var date = '${_months[report.time.month - 1]} ${report.time.day}';
      var wrapped = _wrap('$date  ${report.text}', terminal.width);
      var color = switch (report.kind) {
        ReportKind.info => TextTheme.normal,
        ReportKind.good => TextTheme.ok,
        ReportKind.warning => TextTheme.warning,
        ReportKind.bad => TextTheme.danger,
      };
      // A blank line between reports.
      var needed = wrapped.length + (lines.isEmpty ? 0 : 1);
      if (needed > room) break;
      if (lines.isNotEmpty) lines.insert(0, ('', color));
      lines.insertAll(0, [for (var line in wrapped) (line, color)]);
      room -= needed;
    }

    var y = bottom - lines.length + 1;
    for (var (text, color) in lines) {
      terminal.writeAt(0, y++, text, color);
    }
  }

  /// Breaks [text] into lines of at most [width] characters, at spaces.
  static List<String> _wrap(String text, int width) {
    var lines = <String>[];
    var line = '';
    for (var word in text.split(' ')) {
      if (line.isEmpty) {
        line = word;
      } else if (line.length + 1 + word.length <= width) {
        line = '$line $word';
      } else {
        lines.add(line);
        line = word;
      }
      while (line.length > width) {
        lines.add(line.substring(0, width));
        line = line.substring(width);
      }
    }
    if (line.isNotEmpty) lines.add(line);
    return lines;
  }
}
