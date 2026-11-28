bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Local calendar date as `yyyy-MM-dd`.
String localDateKey(DateTime date) => date.toIso8601String().substring(0, 10);
