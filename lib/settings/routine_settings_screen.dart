import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/state/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../notifications/notification_service.dart';
import '../theme/todo_theme.dart';
import 'settings_presenter.dart';

/// Secondary settings screen for "Plan your day reminders" (`RoutineSettingsActivity`).
class RoutineSettingsScreen extends ConsumerWidget {
  const RoutineSettingsScreen({super.key});

  List<int> _orderedWeekdays(WeekStart startOfWeek) {
    final first = startOfWeek.resolvedWeekday;
    return List.generate(7, (i) => ((first - 1 + i) % 7) + 1);
  }

  String _weekdayLabel(MaterialLocalizations localizations, int weekday) {
    // narrowWeekdays is indexed Sunday (0) .. Saturday (6).
    final index = weekday == DateTime.sunday ? 0 : weekday;
    return localizations.narrowWeekdays[index];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todoProvider);
    final presenter = ref.read(settingsPresenterProvider);
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryColor = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;

    final selectedDays = state.routineNotificationDays.toSet();
    final orderedDays = _orderedWeekdays(state.startOfWeek);
    final formattedTime = TimeOfDay(
      hour: state.routineNotificationHour,
      minute: state.routineNotificationMinute,
    ).format(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.routineNotifications),
        backgroundColor: theme.appBarTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        scrolledUnderElevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.25),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(l10n.turnOnReminder),
            value: state.routineNotificationEnabled,
            onChanged: (value) async {
              presenter.setRoutineNotificationEnabled(value);
              if (value) {
                await ref
                    .read(notificationServiceProvider)
                    .requestPermissions();
              }
            },
          ),
          if (state.routineNotificationEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                l10n.routineTimeSectionDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondaryColor,
                ),
              ),
            ),
            InkWell(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: state.routineNotificationHour,
                    minute: state.routineNotificationMinute,
                  ),
                );
                if (picked != null) {
                  presenter.setRoutineNotificationTime(
                    picked.hour,
                    picked.minute,
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  formattedTime,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Text(
                l10n.routineDayPickerSectionDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: secondaryColor,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final weekday in orderedDays)
                    _DayCircleButton(
                      label: _weekdayLabel(materialL10n, weekday),
                      selected: selectedDays.contains(weekday),
                      onTap: () {
                        final next = Set<int>.from(selectedDays);
                        if (next.contains(weekday)) {
                          if (next.length <= 1) return;
                          next.remove(weekday);
                        } else {
                          next.add(weekday);
                        }
                        presenter.setRoutineNotificationDays(next.toList());
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayCircleButton extends StatelessWidget {
  const _DayCircleButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? theme.colorScheme.primary : Colors.transparent,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
