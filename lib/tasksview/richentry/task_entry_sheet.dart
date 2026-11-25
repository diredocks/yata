import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../detailview/recurrence/task_pickers.dart';
import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import '../../theme/todo_theme.dart';

class TaskEntrySheet extends StatefulWidget {
  const TaskEntrySheet({
    super.key,
    required this.lists,
    required this.currentList,
    required this.onSubmit,
    this.startOfWeek = WeekStart.system,
  });

  final List<TodoList> lists;
  final TodoList currentList;
  final WeekStart startOfWeek;
  final void Function({
    required String title,
    String? targetListId,
    DateTime? dueDate,
    DateTime? reminderAt,
    RecurrenceType recurrence,
    Map<String, dynamic>? rawRecurrence,
  })
  onSubmit;

  @override
  State<TaskEntrySheet> createState() => _TaskEntrySheetState();
}

class _TaskEntrySheetState extends State<TaskEntrySheet>
    with WidgetsBindingObserver {
  static const _windowFocusChannel = MethodChannel(
    'top.clickfling.yata/window_focus',
  );
  static final StreamController<void> _windowFocusGainedController =
      StreamController<void>.broadcast();
  static bool _windowFocusHandlerRegistered = false;

  static void _ensureWindowFocusHandler() {
    if (_windowFocusHandlerRegistered) return;
    _windowFocusHandlerRegistered = true;
    _windowFocusChannel.setMethodCallHandler((call) async {
      if (call.method == 'windowFocusGained') {
        _windowFocusGainedController.add(null);
      }
    });
  }

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Animation<double>? _routeAnimation;
  StreamSubscription<void>? _windowFocusSub;
  late String _targetListId;
  DateTime? _dueDate;
  DateTime? _reminderAt;
  RecurrenceType _recurrence = RecurrenceType.none;
  Map<String, dynamic>? _rawRecurrence;

  bool get _showListPicker =>
      widget.currentList.isSmartList &&
      widget.currentList.smartType != SmartListType.tasks;

  DateTime? _defaultDueDate() {
    if (widget.currentList.smartType == SmartListType.planned) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ensureWindowFocusHandler();
    _windowFocusSub = _windowFocusGainedController.stream.listen((_) {
      if (!mounted) return;
      if (_routeAnimation?.status == AnimationStatus.completed &&
          MediaQuery.viewInsetsOf(context).bottom == 0) {
        _requestKeyboard();
      }
    });
    _targetListId = widget.currentList.isSmartList
        ? 'tasks'
        : widget.currentList.id;
    _dueDate = _defaultDueDate();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final anim = ModalRoute.of(context)?.animation;
    if (anim != null && anim != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
      _routeAnimation = anim;
      if (anim.status == AnimationStatus.completed) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _requestKeyboard());
      } else {
        anim.addStatusListener(_onRouteAnimationStatus);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _routeAnimation?.status == AnimationStatus.completed) {
      _requestKeyboard();
    }
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _requestKeyboard();
    }
  }

  void _requestKeyboard() {
    if (!mounted) return;
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    } else {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    }
  }

  @override
  void dispose() {
    _windowFocusSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _controller.dispose();
    _focusNode.dispose();
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
      rawRecurrence: _rawRecurrence,
    );
    _controller.clear();
    setState(() {
      _dueDate = _defaultDueDate();
      _reminderAt = null;
      _recurrence = RecurrenceType.none;
      _rawRecurrence = null;
    });
    _focusNode.requestFocus();
  }

  Future<void> _pickDueDate() async {
    final result = await showDueDatePickerSheet(
      context,
      startOfWeek: widget.startOfWeek,
      initialDate: _dueDate,
    );
    if (result != null && result.date != null && mounted) {
      setState(() => _dueDate = result.date);
    }
  }

  Future<void> _pickReminder() async {
    final picked = await showReminderPickerSheet(
      context,
      startOfWeek: widget.startOfWeek,
      initialReminder: _reminderAt,
    );
    if (picked != null && mounted) {
      setState(() => _reminderAt = picked);
    }
  }

  Future<void> _pickRecurrence() async {
    final picked = await showRecurrencePickerSheet(
      context,
      initialRecurrence: _recurrence,
      initialRawRecurrence: _rawRecurrence,
      dueDate: _dueDate,
    );

    if (picked != null && mounted) {
      setState(() {
        _recurrence = picked.recurrence;
        _rawRecurrence = picked.rawRecurrence;
        _dueDate ??= defaultDueDateForRecurrence(
          picked.recurrence,
          reminderAt: _reminderAt,
        );
      });
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
                  color: TodoColors.listAccentFor(
                    list,
                    brightness: Theme.of(ctx).brightness,
                  ),
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
                      focusNode: _focusNode,
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
                  if (_showListPicker) ...[
                    ActionChip(
                      avatar: Icon(
                        targetList.icon,
                        size: 16,
                        color: TodoColors.listAccentFor(
                          targetList,
                          brightness: Theme.of(context).brightness,
                        ),
                      ),
                      label: Text(
                        targetList.smartType == SmartListType.tasks
                            ? l10n.tasks
                            : targetList.title,
                      ),
                      onPressed: _pickList,
                    ),
                    const SizedBox(width: 8),
                  ],
                  InputChip(
                    avatar: const Icon(Icons.calendar_today_outlined, size: 16),
                    label: Text(
                      _dueDate == null
                          ? l10n.addDueDate
                          : l10n.dueOn(formatRelativeDate(context, _dueDate!)),
                    ),
                    selected: _dueDate != null,
                    showCheckmark: false,
                    onSelected: (_) => _pickDueDate(),
                    onDeleted: _dueDate != null
                        ? () => setState(() {
                            _dueDate = null;
                            _recurrence = RecurrenceType.none;
                            _rawRecurrence = null;
                          })
                        : null,
                  ),
                  const SizedBox(width: 8),
                  InputChip(
                    avatar: const Icon(Icons.notifications_none, size: 16),
                    label: Text(
                      _reminderAt == null
                          ? l10n.remindMe
                          : formatReminderLabel(context, _reminderAt!),
                    ),
                    selected: _reminderAt != null,
                    showCheckmark: false,
                    onSelected: (_) => _pickReminder(),
                    onDeleted: _reminderAt != null
                        ? () => setState(() => _reminderAt = null)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  InputChip(
                    avatar: const Icon(Icons.repeat, size: 16),
                    label: Text(
                      formatRecurrenceLabel(l10n, _recurrence, _rawRecurrence),
                    ),
                    selected: _recurrence != RecurrenceType.none,
                    showCheckmark: false,
                    onSelected: (_) => _pickRecurrence(),
                    onDeleted: _recurrence != RecurrenceType.none
                        ? () => setState(() {
                            _recurrence = RecurrenceType.none;
                            _rawRecurrence = null;
                          })
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
