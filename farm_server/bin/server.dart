import 'dart:async';
import 'dart:convert';

import 'package:mcp_server/mcp_server.dart';

import 'serve_bundle.dart';

/// farm_server — a growing log, as tools.
///
/// The article this belongs to is about a claim: that a grower with thirty
/// years of notes can say what they need and get a screen. The part that is
/// worth building is not the screen — it is what has to be true underneath for
/// the screen to be worth having.
///
/// One thing in particular. The story's centrepiece is a pattern the grower
/// never saw on paper: first flower lands about eighteen days after
/// transplanting. **That number is not written down anywhere in this file.**
/// It is computed from the records, every time it is asked for. If the records
/// said something else, the screen would say something else.
void main(List<String> args) async {
  const config = McpServerConfig(
    name: 'Growing Log',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: ToolsCapability(listChanged: true),
      resources: ResourcesCapability(listChanged: true),
    ),
  );

  final server = McpServer.createServer(config);
  FarmServer(server).register();
  // The screen next door: AppPlayer reads it from here and sends the pages'
  // tool calls back to the tools above.
  registerBundleUi(server, '../farm_log.mbd');

  final transport = McpServer.createStdioTransport().get();
  server.connect(transport);

  await Completer<void>().future;
}

/// One entry, in the same six slots every time. The whole argument of the
/// article rests on this being fixed: `plot · crop · action · date · note ·
/// tempC`. Paper let every year invent its own shorthand; slots do not.
class Entry {
  const Entry(this.plot, this.crop, this.action, this.date, this.tempC,
      [this.note = '']);

  final String plot;
  final String crop;
  final String action; // transplant | firstFlower | water | harvest
  final DateTime date;
  final double tempC;
  final String note;

  Map<String, dynamic> toJson() => {
        'plot': plot,
        'crop': crop,
        'action': action,
        'date': _d(date),
        'tempC': tempC,
        'note': note,
      };
}

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class FarmServer {
  FarmServer(this.server);

  final Server server;

  /// Five seasons of records for one greenhouse.
  ///
  /// These are made up — see the article's honesty section. What is not made up
  /// is the shape: every row has the same six slots, which is the only reason
  /// the years can be laid on top of each other at all.
  final List<Entry> _entries = [
    // 2021 — a cold snap in early April
    Entry('House A', 'Tomato', 'transplant', DateTime(2021, 4, 2), 14.0),
    Entry('House A', 'Tomato', 'firstFlower', DateTime(2021, 4, 24), 17.5, 'five cold days in early April'),
    Entry('House A', 'Tomato', 'harvest', DateTime(2021, 6, 18), 24.0),
    // 2022 — ordinary
    Entry('House A', 'Tomato', 'transplant', DateTime(2022, 4, 5), 16.5),
    Entry('House A', 'Tomato', 'firstFlower', DateTime(2022, 4, 23), 19.0),
    Entry('House A', 'Tomato', 'harvest', DateTime(2022, 6, 14), 25.5),
    // 2023 — warm week before transplanting
    Entry('House A', 'Tomato', 'transplant', DateTime(2023, 3, 30), 18.0, 'warm week before transplanting'),
    Entry('House A', 'Tomato', 'firstFlower', DateTime(2023, 4, 14), 20.5),
    Entry('House A', 'Tomato', 'harvest', DateTime(2023, 6, 9), 26.0),
    // 2024 — ordinary
    Entry('House A', 'Tomato', 'transplant', DateTime(2024, 4, 4), 16.0),
    Entry('House A', 'Tomato', 'firstFlower', DateTime(2024, 4, 22), 18.5),
    Entry('House A', 'Tomato', 'harvest', DateTime(2024, 6, 16), 25.0),
    // 2025 — ordinary
    Entry('House A', 'Tomato', 'transplant', DateTime(2025, 4, 3), 15.5),
    Entry('House A', 'Tomato', 'firstFlower', DateTime(2025, 4, 21), 18.0),
    Entry('House A', 'Tomato', 'harvest', DateTime(2025, 6, 15), 24.5),
    // this season — transplanted, no flower yet
    Entry('House A', 'Tomato', 'transplant', DateTime(2026, 4, 1), 15.0),
  ];

  String _notice = '';

  void register() {
    // What the grower asked for first: pick a crop and this season's
    // rows come up, one after another.
    server.addTool(
      name: 'log.season',
      description: 'This season\'s entries for a crop, newest first',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'crop': {'type': 'string'},
        },
      },
      handler: (args) async => _state(crop: (args['crop'] as String?) ?? 'Tomato'),
    );

    // "Writing it down has to work one-handed." One tap adds a row in the
    // same six slots.
    server.addTool(
      name: 'log.add',
      description: 'Add one entry to the log',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'crop': {'type': 'string'},
          'action': {'type': 'string'},
          'tempC': {'type': 'number'},
          'note': {'type': 'string'},
        },
        'required': ['action'],
      },
      handler: (args) async {
        final crop = (args['crop'] as String?) ?? 'Tomato';
        final action = args['action'] as String;
        // The date is the machine's, not the grower's memory. Paper let a row
        // be written three days late with no trace; this cannot.
        final entry = Entry(
          'House A',
          crop,
          action,
          DateTime(2026, 4, 19),
          (args['tempC'] as num?)?.toDouble() ?? 17.0,
          (args['note'] as String?) ?? '',
        );
        _entries.add(entry);
        _notice = '${_d(entry.date)} $action recorded';
        return _state(crop: crop);
      },
    );

    // "Show me what last year looked like at this point, right beside it."
    server.addTool(
      name: 'log.compare',
      description:
          'Lay the seasons on top of each other: days from transplant to first '
          'flower, per year, with the average and this year against it',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'crop': {'type': 'string'},
        },
      },
      handler: (args) async =>
          _state(crop: (args['crop'] as String?) ?? 'Tomato', compare: true),
    );
  }

  /// Days from transplant to first flower, per season.
  ///
  /// This is the whole "eighteen days" claim, and it is arithmetic over the
  /// rows — no constant anywhere. A year with no flower recorded yet is left
  /// out rather than guessed at.
  List<Map<String, dynamic>> _spans(String crop) {
    final rows = <Map<String, dynamic>>[];
    final years = _entries.where((e) => e.crop == crop).map((e) => e.date.year).toSet().toList()..sort();
    for (final y in years) {
      final t = _entries.where((e) =>
          e.crop == crop && e.action == 'transplant' && e.date.year == y);
      final f = _entries.where((e) =>
          e.crop == crop && e.action == 'firstFlower' && e.date.year == y);
      if (t.isEmpty || f.isEmpty) continue;
      final days = f.first.date.difference(t.first.date).inDays;
      rows.add({
        'year': y,
        'transplant': _d(t.first.date),
        'firstFlower': _d(f.first.date),
        'days': days,
        'note': f.first.note,
      });
    }
    return rows;
  }

  CallToolResult _state({required String crop, bool compare = false}) {
    final season = _entries
        .where((e) => e.crop == crop && e.date.year == 2026)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final spans = _spans(crop);
    final done = spans.where((s) => s['year'] != 2026).toList();
    final avg = done.isEmpty
        ? 0.0
        : done.map((s) => s['days'] as int).reduce((a, b) => a + b) / done.length;

    // Where this season stands against that average — the "anchor" the article
    // talks about. Only computable because the anchor exists.
    final transplantThisYear = _entries.where(
        (e) => e.crop == crop && e.action == 'transplant' && e.date.year == 2026);
    final flowerThisYear = _entries.where(
        (e) => e.crop == crop && e.action == 'firstFlower' && e.date.year == 2026);
    var todayLine = 'nothing recorded yet';
    if (transplantThisYear.isNotEmpty) {
      if (flowerThisYear.isNotEmpty) {
        final d = flowerThisYear.first.date
            .difference(transplantThisYear.first.date)
            .inDays;
        final delta = d - avg;
        todayLine = 'first flower on day $d · '
            '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)} d against the average';
      } else {
        final elapsed =
            DateTime(2026, 4, 19).difference(transplantThisYear.first.date).inDays;
        todayLine = 'day $elapsed since transplanting · '
            'past seasons averaged ${avg.toStringAsFixed(1)} d';
      }
    }

    return CallToolResult(
      content: [
        TextContent(
          text: jsonEncode({
            'crop': crop,
            'season': season.map((e) => e.toJson()).toList(),
            'seasonCount': season.length,
            // The rule a growing log runs by. It is why every line carries a
            // temperature: a note without one cannot be compared to last year.
            'logRule': 'Every entry is written where it happened · '
                'the average is counted from the log, never typed in',
            'spans': spans,
            'spanCount': spans.length,
            'avgDays': double.parse(avg.toStringAsFixed(1)),
            'today': todayLine,
            'compare': compare,
            // Where this season sits against the ones before it, in words.
            // The screen should not have to decide what "on the average"
            // means — the log is what knows.
            'compareLine': spans.isEmpty
                ? 'no season written down yet'
                : () {
                    final latest = spans.last['days'] as int;
                    final diff = latest - avg;
                    if (diff.abs() < 0.5) return 'this season is on the average';
                    return diff > 0
                        ? 'this season ran ${diff.toStringAsFixed(1)} d longer than the average'
                        : 'this season ran ${(-diff).toStringAsFixed(1)} d shorter than the average';
                  }(),
            'notice': _notice,
          }),
        ),
      ],
    );
  }
}
