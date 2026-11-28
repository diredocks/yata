import 'package:material_ui/material_ui.dart';

import '../models/todo_list.dart';

IconData iconForSmartList(SmartListType? type) {
  return switch (type) {
    SmartListType.myDay => Icons.wb_sunny_outlined,
    SmartListType.important => Icons.star_outline,
    SmartListType.planned => Icons.calendar_today_outlined,
    SmartListType.all => Icons.all_inclusive,
    SmartListType.completed => Icons.check_circle_outline,
    SmartListType.tasks => Icons.home_outlined,
    null => Icons.format_list_bulleted,
  };
}
