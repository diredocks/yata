import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';

class TaskEntrySheet extends StatefulWidget {
  const TaskEntrySheet({
    super.key,
    required this.lists,
    required this.currentList,
    required this.onSubmit,
  });

  final List<TodoList> lists;
  final TodoList currentList;
  final void Function({
    required String title,
    String? targetListId,
    DateTime? dueDate,
    DateTime? reminderAt,
    RecurrenceType recurrence,
  }) onSubmit;

  @override
  State<TaskEntrySheet> createState() => _TaskEntrySheetState();
}

class _TaskEntrySheetState extends State<TaskEntrySheet> {
  final _controller = TextEditingController();
  late String _targetListId;
  DateTime? _dueDate;
  DateTime? _reminderAt;
  RecurrenceType _recurrence = RecurrenceType.none;

  @override
  void initState() {
    super.initState();
    _targetListId = widget.currentList.isSmartList
        ? 'tasks'
        : widget.currentList.id;
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(
      title: text,
      targetListId: _targetListId,
      dueDate: _dueDate,
      reminderAt: _reminderAt,
      recurrence: _recurrence,
    );
    Navigator.of(context).pop();
  }

  Future<void> _pickDueDate() async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.today),
              title: Text(l10n.today),
              onTap: () => Navigator.pop(ctx, 'today'),
            ),
            ListTile(
              leading: const Icon(Icons.wb_twilight),
              title: Text(l10n.tomorrow),
              onTap: () => Navigator.pop(ctx, 'tomorrow'),
            ),
            ListTile(
              leading: const Icon(Icons.next_week),
              title: Text(l10n.nextWeek),
              onTap: () => Navigator.pop(ctx, 'next_week'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(l10n.pickDate),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'today') {
      setState(() => _dueDate = today);
    } else if (choice == 'tomorrow') {
      setState(() => _dueDate = today.add(const Duration(days: 1)));
    } else if (choice == 'next_week') {
      setState(() => _dueDate = today.add(const Duration(days: 7)));
    } else if (choice == 'pick') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _dueDate ?? today,
        firstDate: today.subtract(const Duration(days: 365)),
        lastDate: today.add(const Duration(days: 365 * 5)),
      );
      if (picked != null && mounted) {
        setState(() => _dueDate = picked);
      }
    }
  }

  Future<void> _pickRecurrence() async {
    final l10n = AppLocalizations.of(context);
    final options = <(RecurrenceType, String)>[
      (RecurrenceType.daily, l10n.repeatDaily),
      (RecurrenceType.weekdays, l10n.repeatWeekdays),
      (RecurrenceType.weekly, l10n.repeatWeekly),
      (RecurrenceType.monthly, l10n.repeatMonthly),
      (RecurrenceType.yearly, l10n.repeatYearly),
    ];

    final picked = await showModalBottomSheet<RecurrenceType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (type, label) in options)
              ListTile(
                leading: const Icon(Icons.repeat),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, type),
              ),
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() => _recurrence = picked);
    }
  }

  Future<void> _pickList() async {
    final selectableLists = widget.lists
        .where((l) => !l.isSmartList || l.smartType == SmartListType.tasks)
        .toList();

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final list in selectableLists)
              ListTile(
                leading: Icon(
                  list.icon,
                  color: TodoColors.accentFor(list.themeColor),
                ),
                title: Text(list.title),
                trailing: list.id == _targetListId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, list.id),
              ),
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() => _targetListId = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasText = _controller.text.trim().isNotEmpty;
    final targetList = widget.lists.firstWhere(
      (l) => l.id == _targetListId,
      orElse: () => widget.currentList,
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? TodoColors.secondaryBackgroundDark
              : TodoColors.primaryBackgroundLight,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        padding: const EdgeInsets.only(top: 10, bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? TodoColors.secondaryTextDark
                            : TodoColors.secondaryTextLight,
                        width: 1.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleSubmit(),
                      decoration: InputDecoration(
                        hintText: l10n.addTaskPlaceholder,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: hasText ? _handleSubmit : null,
                    icon: Icon(
                      Icons.arrow_upward_rounded,
                      color: hasText
                          ? (isDark
                              ? TodoColors.attentionDark
                              : TodoColors.attentionLight)
                          : theme.disabledColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  if (widget.currentList.isSmartList) ...[
                    ActionChip(
                      avatar: Icon(
                        targetList.icon,
                        size: 16,
                        color: TodoColors.accentFor(targetList.themeColor),
                      ),
                      label: Text(targetList.title),
                      onPressed: _pickList,
                    ),
                    const SizedBox(width: 8),
                  ],
                  InputChip(
                    avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      _dueDate == null
                          ? l10n.addDueDate
                          : DateFormat.MMMd().format(_dueDate!),
                    ),
                    selected: _dueDate != null,
                    onSelected: (_) => _pickDueDate(),
                    onDeleted: _dueDate != null
                        ? () => setState(() => _dueDate = null)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  InputChip(
                    avatar: const Icon(Icons.notifications_none, size: 16),
                    label: Text(
                      _reminderAt == null
                          ? l10n.remindMe
                          : DateFormat.jm().format(_reminderAt!),
                    ),
                    selected: _reminderAt != null,
                    onSelected: (_) async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null && mounted) {
                        final now = DateTime.now();
                        setState(() {
                          _reminderAt = DateTime(
                            now.year,
                            now.month,
                            now.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      }
                    },
                    onDeleted: _reminderAt != null
                        ? () => setState(() => _reminderAt = null)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  InputChip(
                    avatar: const Icon(Icons.repeat, size: 16),
                    label: Text(
                      _recurrence == RecurrenceType.none
                          ? l10n.repeat
                          : _recurrence.name,
                    ),
                    selected: _recurrence != RecurrenceType.none,
                    onSelected: (_) => _pickRecurrence(),
                    onDeleted: _recurrence != RecurrenceType.none
                        ? () => setState(() => _recurrence = RecurrenceType.none)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
