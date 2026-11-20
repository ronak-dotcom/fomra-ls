/// When a line in a lead's notes was written, from the stamp it starts with:
/// typed notes "[20/11/2026 13:03] …" (day/month) and voice notes
/// "[20 Nov 2026, 13:03] …". Null when the line has no stamp (e.g. the
/// automatic nearby-places block).
DateTime? noteEntryTime(String entry) {
  final t = entry.trimLeft();
  final dmy = RegExp(r'^\[(\d{1,2})/(\d{1,2})/(\d{4}) (\d{1,2}):(\d{2})\]')
      .firstMatch(t);
  if (dmy != null) {
    return _at(int.parse(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!),
        int.parse(dmy[4]!), int.parse(dmy[5]!));
  }
  final named = RegExp(
          r'^\[(\d{1,2}) ([A-Za-z]{3}) (\d{4}),? (\d{1,2}):(\d{2})\]')
      .firstMatch(t);
  if (named != null) {
    final month = _months.indexOf(named[2]!.toLowerCase()) + 1;
    if (month == 0) return null;
    return _at(int.parse(named[3]!), month, int.parse(named[1]!),
        int.parse(named[4]!), int.parse(named[5]!));
  }
  return null;
}

const _months = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

DateTime? _at(int y, int m, int d, int h, int min) {
  if (m < 1 || m > 12 || d < 1 || d > 31 || h > 23 || min > 59) return null;
  return DateTime(y, m, d, h, min);
}
