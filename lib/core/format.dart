import 'package:intl/intl.dart';

final DateFormat _date = DateFormat('dd MMM yyyy');
final DateFormat _dateTime = DateFormat('dd MMM yyyy, HH:mm');
final DateFormat _time = DateFormat('HH:mm');
final DateFormat _day = DateFormat('EEEE, dd MMMM yyyy');
final DateFormat _iso = DateFormat('yyyy-MM-dd');

String fmtDate(DateTime? d) => d == null ? '—' : _date.format(d);
String fmtDateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);
String fmtTime(DateTime? d) => d == null ? '—' : _time.format(d);
String fmtDay(DateTime d) => _day.format(d);
String isoDate(DateTime d) => _iso.format(d);
DateTime? parseIsoDate(String? s) =>
    (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

DateTime? msToDate(Object? ms) => ms == null ? null
    : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());

int dateToMs(DateTime d) => d.millisecondsSinceEpoch;

/// Midnight of the day [d] falls in.
DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// A human relative description used in list rows ("in 2 days", "3h ago").
String relative(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = when.difference(ref);
  final future = !diff.isNegative;
  final mins = diff.abs().inMinutes;
  String unit;
  if (mins < 1) {
    return 'just now';
  } else if (mins < 60) {
    unit = '${mins}m';
  } else if (mins < 60 * 24) {
    unit = '${diff.abs().inHours}h';
  } else {
    unit = '${diff.abs().inDays}d';
  }
  return future ? 'in $unit' : '$unit ago';
}

/// Formats a weight without a trailing `.0`.
String fmtWeight(double? kg) {
  if (kg == null) return '—';
  final s = kg.toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s} kg';
}

String titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
