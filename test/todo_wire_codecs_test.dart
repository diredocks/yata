import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TimeOfDay;
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/todo_wire_codecs.dart';

void main() {
  group('ThemeColor & ThemeBackground codecs', () {
    test('round-trips all 14 solid colors', () {
      const expectedWire = {
        ListThemeColor.blue: 'dark_blue',
        ListThemeColor.rose: 'dark_rose',
        ListThemeColor.teal: 'dark_teal',
        ListThemeColor.green: 'dark_green',
        ListThemeColor.purple: 'dark_purple',
        ListThemeColor.red: 'dark_red',
        ListThemeColor.grey: 'dark_grey',
        ListThemeColor.lightBlue: 'light_blue',
        ListThemeColor.lightRose: 'light_rose',
        ListThemeColor.lightTeal: 'light_teal',
        ListThemeColor.lightGreen: 'light_green',
        ListThemeColor.lightPurple: 'light_purple',
        ListThemeColor.lightRed: 'light_red',
        ListThemeColor.lightGrey: 'light_grey',
      };

      for (final color in ListThemeColor.values) {
        final wire = encodeThemeColor(color, null);
        expect(wire, expectedWire[color]);
        expect(encodeFolderThemeColor(color), expectedWire[color]);

        final decoded = decodeThemeColor(wire);
        expect(decoded.themeColor, color);
        expect(decoded.themePhoto, isNull);
      }
    });

    test('round-trips all 9 photo themes and ThemeBackground pairs', () {
      const expectedPhotos = {
        ListThemePhoto.beach: 'photo_beach',
        ListThemePhoto.desert: 'photo_desert',
        ListThemePhoto.fern: 'photo_fern',
        ListThemePhoto.field: 'photo_field',
        ListThemePhoto.gradient: 'photo_gradient',
        ListThemePhoto.lighthouse: 'photo_lighthouse',
        ListThemePhoto.safari: 'photo_safari',
        ListThemePhoto.sea: 'photo_sea',
        ListThemePhoto.tvTower: 'photo_tv_tower',
      };

      for (final photo in ListThemePhoto.values) {
        final settingWire = encodeThemeColor(ListThemeColor.blue, photo);
        expect(settingWire, expectedPhotos[photo]);
        expect(encodeFolderThemeBackground(photo), expectedPhotos[photo]);

        final decodedSetting = decodeThemeColor(settingWire);
        expect(decodedSetting.themePhoto, photo);

        final decodedFolder = decodeFolderTheme(
          themeColor: 'light_teal',
          themeBackground: expectedPhotos[photo],
        );
        expect(decodedFolder.themeColor, ListThemeColor.lightTeal);
        expect(decodedFolder.themePhoto, photo);
      }

      expect(encodeFolderThemeBackground(null), isNull);
    });

    test('maps legacy color aliases cleanly', () {
      expect(decodeThemeColor('blue').themeColor, ListThemeColor.blue);
      expect(decodeThemeColor('skyblue').themeColor, ListThemeColor.blue);
      expect(decodeThemeColor('purple').themeColor, ListThemeColor.purple);
      expect(decodeThemeColor('red').themeColor, ListThemeColor.red);
      expect(decodeThemeColor('green').themeColor, ListThemeColor.green);
      expect(decodeThemeColor('gray').themeColor, ListThemeColor.grey);
      expect(decodeThemeColor('dark_gray').themeColor, ListThemeColor.grey);
      expect(decodeThemeColor('light_gray').themeColor, ListThemeColor.lightGrey);
    });
  });

  group('Folder emoji split & compose codecs', () {
    test('encodes and decodes leading emojis including ZWJ, flag, skin tone', () {
      expect(encodeFolderName('Shopping', '🛒'), '🛒 Shopping');
      expect(encodeFolderName('Shopping', null), 'Shopping');
      expect(encodeFolderName('Shopping', '  '), 'Shopping');

      final standard = decodeFolderName('🛒 Shopping');
      expect(standard.emoji, '🛒');
      expect(standard.title, 'Shopping');

      final noSpace = decodeFolderName('🛒Shopping');
      expect(noSpace.emoji, '🛒');
      expect(noSpace.title, 'Shopping');

      final zwj = decodeFolderName('👨‍💻 Engineering');
      expect(zwj.emoji, '👨‍💻');
      expect(zwj.title, 'Engineering');

      final flag = decodeFolderName('🇯🇵 Tokyo Trip');
      expect(flag.emoji, '🇯🇵');
      expect(flag.title, 'Tokyo Trip');

      final skinTone = decodeFolderName('👋🏽 Greet');
      expect(skinTone.emoji, '👋🏽');
      expect(skinTone.title, 'Greet');

      final emojiOnly = decodeFolderName('🛒');
      expect(emojiOnly.emoji, isNull);
      expect(emojiOnly.title, '🛒');

      final plain = decodeFolderName('Work Tasks');
      expect(plain.emoji, isNull);
      expect(plain.title, 'Work Tasks');
    });
  });

  group('Sort, Filter, Group, WeekStart, and Setting codecs', () {
    test('encodes and decodes SortType 0..6 and legacy strings', () {
      expect(encodeSortType(TaskSortOption.defaultOrder), 0);
      expect(encodeSortType(TaskSortOption.alphabetical), 1);
      expect(encodeSortType(TaskSortOption.dueDate), 2);
      expect(encodeSortType(TaskSortOption.creationDate), 3);
      expect(encodeSortType(TaskSortOption.addedToMyDay), 5);
      expect(encodeSortType(TaskSortOption.importance), 6);

      expect(decodeSortType(0), TaskSortOption.defaultOrder);
      expect(decodeSortType(4), TaskSortOption.defaultOrder);
      expect(decodeSortType(1), TaskSortOption.alphabetical);
      expect(decodeSortType(2), TaskSortOption.dueDate);
      expect(decodeSortType('3'), TaskSortOption.creationDate);
      expect(decodeSortType(5), TaskSortOption.addedToMyDay);
      expect(decodeSortType('6'), TaskSortOption.importance);
      expect(decodeSortType('importance'), TaskSortOption.importance);
      expect(decodeSortType('alphabetical'), TaskSortOption.alphabetical);
    });

    test('encodes and decodes PlannedDueDateFilter 0..5', () {
      expect(encodePlannedDueDateFilter(PlannedDueDateFilter.overdue), 0);
      expect(encodePlannedDueDateFilter(PlannedDueDateFilter.today), 1);
      expect(encodePlannedDueDateFilter(PlannedDueDateFilter.tomorrow), 2);
      expect(encodePlannedDueDateFilter(PlannedDueDateFilter.thisWeek), 3);
      expect(encodePlannedDueDateFilter(PlannedDueDateFilter.later), 4);
      expect(encodePlannedDueDateFilter(PlannedDueDateFilter.all), 5);

      for (final f in PlannedDueDateFilter.values) {
        expect(decodePlannedDueDateFilter(encodePlannedDueDateFilter(f)), f);
        expect(
          decodePlannedDueDateFilter('${encodePlannedDueDateFilter(f)}'),
          f,
        );
      }
    });

    test('encodes and decodes PlannedGroupOption 0..2', () {
      expect(encodePlannedGroupOption(PlannedGroupOption.ungroup), 0);
      expect(encodePlannedGroupOption(PlannedGroupOption.byDueDate), 1);
      expect(encodePlannedGroupOption(PlannedGroupOption.byList), 2);

      for (final g in PlannedGroupOption.values) {
        expect(decodePlannedGroupOption(encodePlannedGroupOption(g)), g);
        expect(decodePlannedGroupOption('${encodePlannedGroupOption(g)}'), g);
      }
    });

    test('encodes and decodes start_week_from 0, 1, 2, 7', () {
      expect(encodeWeekStart(WeekStart.system), 0);
      expect(encodeWeekStart(WeekStart.sunday), 1);
      expect(encodeWeekStart(WeekStart.monday), 2);
      expect(encodeWeekStart(WeekStart.saturday), 7);

      expect(decodeWeekStart(0), WeekStart.system);
      expect(decodeWeekStart('1'), WeekStart.sunday);
      expect(decodeWeekStart(2), WeekStart.monday);
      expect(decodeWeekStart('7'), WeekStart.saturday);
    });

    test('encodes and decodes notification times and RoutineNotification', () {
      expect(encodeRoutineNotificationEnabled(true), 'true');
      expect(encodeRoutineNotificationEnabled(false), 'false');
      expect(decodeRoutineNotificationEnabled('true'), isTrue);
      expect(decodeRoutineNotificationEnabled('false'), isFalse);
      expect(decodeRoutineNotificationEnabled('Enabled'), isTrue);

      const dueTime = TimeOfDay(hour: 9, minute: 15);
      final wireDue = encodeTimeOfDaySetting(dueTime);
      expect(wireDue, startsWith('1970-01-01T'));
      expect(decodeTimeOfDaySetting(wireDue), dueTime);

      const routineTime = TimeOfDay(hour: 8, minute: 30);
      final wireRoutine = encodeRoutineConfig(routineTime);
      expect(wireRoutine, contains(';Monday,Tuesday,Wednesday,Thursday,Friday,Saturday,Sunday'));
      expect(decodeRoutineConfigTime(wireRoutine), routineTime);
    });
  });

  group('Timestamps, Days, Recurrence, HTML & OrderDateTime', () {
    test('formats 7-digit UTC timestamps and ignores 0001-01-01 sentinels', () {
      final ts = formatSubstrateUtcTimestamp(
        DateTime.utc(2026, 11, 22, 10, 20, 30, 123, 456),
      );
      expect(ts, '2026-11-22T10:20:30.1234560Z');
      expect(parseSubstrateTimestamp('0001-01-01T00:00:00Z'), isNull);
      expect(
        parseSubstrateTimestamp(ts)?.toUtc(),
        DateTime.utc(2026, 11, 22, 10, 20, 30, 123, 456),
      );
    });

    test('parses legacy negative-subsecond UTC and timezone-less Substrate timestamps', () {
      final legacyZeroDash = parseSubstrateTimestamp('2020-05-01T10:00:00.000-1234Z');
      expect(legacyZeroDash, isNotNull);
      expect(legacyZeroDash!.isUtc, isTrue);
      expect(legacyZeroDash.year, 2020);
      expect(legacyZeroDash.month, 5);
      expect(legacyZeroDash.day, 1);
      expect(legacyZeroDash.hour, 10);

      final legacyDashOnly = parseSubstrateTimestamp('2020-05-01T10:00:00.-1234Z');
      expect(legacyDashOnly, isNotNull);
      expect(legacyDashOnly!.isUtc, isTrue);
      expect(legacyDashOnly.millisecond, 123);
      expect(legacyDashOnly.microsecond, 400);

      final tzLess = parseSubstrateTimestamp('2024-05-01T10:00:00.1234567');
      expect(tzLess, isNotNull);
      expect(tzLess!.isUtc, isTrue);
      expect(tzLess, DateTime.utc(2024, 5, 1, 10, 0, 0, 123, 456));

      final explicitOffset = parseSubstrateTimestamp('2024-05-01T18:00:00+08:00');
      expect(explicitOffset, isNotNull);
      expect(explicitOffset!.isUtc, isTrue);
      expect(explicitOffset, DateTime.utc(2024, 5, 1, 10, 0, 0));

      expect(parseSubstrateTimestamp('0001-01-01T00:00:00'), isNull);
      expect(parseSubstrateTimestamp('   '), isNull);
    });

    test('parses Substrate days with T00, YYYY-MM-DD, 0001-01-01, and +14h heuristic', () {
      expect(parseSubstrateDay('0001-01-01'), isNull);
      expect(parseSubstrateDay('0001-01-01T00:00:00Z'), isNull);
      expect(parseSubstrateDay('2026-11-22'), DateTime(2026, 11, 22));
      expect(
        parseSubstrateDay({'DateTime': '2026-11-22T00:00:00.0000000', 'TimeZone': 'UTC'}),
        DateTime(2026, 11, 22),
      );
      // UTC timestamp representing local midnight in UTC+8 (16:00Z previous day)
      final shifted = parseSubstrateDay('2026-11-21T16:00:00Z');
      expect(shifted, isNotNull);
    });

    test('encodes and decodes Substrate Recurrence with WeekDays', () {
      expect(encodeSubstrateRecurrence(RecurrenceType.none), isNull);

      final daily = encodeSubstrateRecurrence(RecurrenceType.daily)!;
      expect(daily['RecurrenceType'], 'Daily');
      expect(decodeSubstrateRecurrence(daily), RecurrenceType.daily);

      final weekdays = encodeSubstrateRecurrence(RecurrenceType.weekdays)!;
      expect(weekdays['RecurrenceType'], 'WeekDays');
      expect(weekdays['WeekDays'], [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
      ]);
      expect(decodeSubstrateRecurrence(weekdays), RecurrenceType.weekdays);

      final weekly = encodeSubstrateRecurrence(
        RecurrenceType.weekly,
        dueDate: DateTime(2026, 11, 22), // Sunday
      )!;
      expect(weekly['WeekDays'], ['Sunday']);
      expect(decodeSubstrateRecurrence(weekly), RecurrenceType.weekly);

      final monthly = encodeSubstrateRecurrence(RecurrenceType.monthly)!;
      expect(decodeSubstrateRecurrence(monthly), RecurrenceType.monthly);

      final yearly = encodeSubstrateRecurrence(RecurrenceType.yearly)!;
      expect(decodeSubstrateRecurrence(yearly), RecurrenceType.yearly);

      expect(
        decodeSubstrateRecurrence({
          'RecurrenceType': 'Custom',
          'IntervalType': 'Months',
          'Interval': 2,
        }),
        RecurrenceType.monthly,
      );
    });

    test('strips HTML body content when ContentType is HTML', () {
      const html = '<html><head><style>p{margin:0}</style></head>'
          '<body><p>Hello &amp; welcome&nbsp;</p><p>Line&nbsp;2<br/>Line 3&#39;s &quot;end&quot;</p></body></html>';
      expect(
        stripHtmlToPlainText(html, contentType: 'HTML'),
        'Hello & welcome \nLine 2\nLine 3\'s "end"',
      );
      expect(
        stripHtmlToPlainText('<not html>', contentType: 'Text'),
        '<not html>',
      );
    });

    test('computes OrderDateTime midpoint, top, and bottom with 4096s spacing', () {
      final t1 = DateTime.utc(2026, 11, 22, 12, 0, 0);
      final t2 = DateTime.utc(2026, 11, 22, 10, 0, 0);

      final mid = computeInsertedOrderDateTime(prev: t1, next: t2);
      expect(mid, DateTime.utc(2026, 11, 22, 11, 0, 0));

      final top = computeInsertedOrderDateTime(prev: null, next: t1);
      expect(top, t1.add(kOrderDateTimeStep));

      final bottom = computeInsertedOrderDateTime(prev: t2, next: null);
      expect(bottom, t2.subtract(kOrderDateTimeStep));

      final bumpedTop = computeNewOrderDateTime(
        existingOrders: [t1],
        addToTop: true,
        fallbackNow: t1,
      );
      expect(bumpedTop.isAfter(t1), isTrue);
      expect(bumpedTop.difference(t1) >= kOrderDateTimeStep, isTrue);

      final bumpedBottom = computeNewOrderDateTime(
        existingOrders: [t2],
        addToTop: false,
      );
      expect(bumpedBottom, t2.subtract(kOrderDateTimeStep));
    });

    test('computeReorderedOrderDateTimes handles wide-gap single moves, <=16s/equal/inverted re-spacing, and null boundaries', () {
      final t1 = DateTime.utc(2026, 11, 22, 14, 0, 0);
      final t2 = DateTime.utc(2026, 11, 22, 12, 0, 0);
      final t3 = DateTime.utc(2026, 11, 22, 10, 0, 0);

      // Single-item top move
      final toTop = computeReorderedOrderDateTimes([null, t1, t2, t3], 0);
      expect(toTop.keys.toList(), [0]);
      expect(toTop[0], t1.add(kOrderDateTimeStep));

      // Single-item middle move (gap > 16s)
      final toMid = computeReorderedOrderDateTimes([t1, null, t2, t3], 1);
      expect(toMid.keys.toList(), [1]);
      expect(toMid[1], DateTime.utc(2026, 11, 22, 13, 0, 0));

      // Single-item bottom move
      final toBot = computeReorderedOrderDateTimes([t1, t2, t3, null], 3);
      expect(toBot.keys.toList(), [3]);
      expect(toBot[3], t3.subtract(kOrderDateTimeStep));

      // Tight <= 16s gap re-spaces all items in 4096s descending steps
      final tClose = t1.subtract(const Duration(seconds: 10));
      final tight = computeReorderedOrderDateTimes([t1, null, tClose], 1);
      expect(tight.keys.toList(), [0, 1, 2]);
      expect(tight[0], t1);
      expect(tight[1], t1.subtract(kOrderDateTimeStep));
      expect(tight[2], t1.subtract(kOrderDateTimeStep * 2));

      // Equal / inverted neighbors re-space all items
      final equal = computeReorderedOrderDateTimes([t1, t2, t1], 1);
      expect(equal.keys.toList(), [0, 1, 2]);
      expect(equal[0]!.isAfter(equal[1]!), isTrue);
      expect(equal[1]!.isAfter(equal[2]!), isTrue);

      // Inverted neighbors [t2, t1, moved] where t2 < t1 re-space all items
      final inverted = computeReorderedOrderDateTimes([t2, t1, null], 2);
      expect(inverted.keys.toList(), [0, 1, 2]);
      expect(inverted[0], t1);
      expect(inverted[1], t1.subtract(kOrderDateTimeStep));
      expect(inverted[2], t1.subtract(kOrderDateTimeStep * 2));

      // Trailing null boundary: ordered item placed right before trailing nulls updates only movedIndex
      final boundary = computeReorderedOrderDateTimes([t1, t2, null, null], 1);
      expect(boundary.keys.toList(), [1]);
      expect(boundary[1], t1.subtract(kOrderDateTimeStep));

      // Moving item past a null in the middle breaks trailing-null separation -> re-spaces all
      final afterNull = computeReorderedOrderDateTimes([t1, null, t2], 2);
      expect(afterNull.keys.toList(), [0, 1, 2]);
      expect(afterNull[0]!.isAfter(afterNull[1]!), isTrue);
      expect(afterNull[1]!.isAfter(afterNull[2]!), isTrue);
    });
  });
}
