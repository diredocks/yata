import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';

const List<String> _defaultListEmojis = [
  '📋',
  '🛒',
  '💼',
  '🏠',
  '📚',
  '✈️',
  '🎯',
  '💡',
  '🎉',
  '❤️',
  '🎵',
  '🍎',
  '💪',
  '💰',
  '🌱',
  '🐾',
  '🎮',
  '📷',
  '🛠️',
  '📅',
  '⭐',
  '🔥',
  '✅',
  '📝',
];

class ListEditorResult {
  const ListEditorResult({
    required this.title,
    this.emoji,
    required this.themeColor,
    this.themePhoto,
  });

  final String title;
  final String? emoji;
  final ListThemeColor themeColor;
  final ListThemePhoto? themePhoto;
}

/// Unified list creation & editing dialog matching `edit_list_dialog.xml`.
Future<ListEditorResult?> showListEditorDialog({
  required BuildContext context,
  required String dialogTitle,
  required String confirmLabel,
  String initialTitle = '',
  String? initialEmoji,
  ListThemeColor initialColor = ListThemeColor.blue,
  ListThemePhoto? initialPhoto,
}) {
  return showDialog<ListEditorResult>(
    context: context,
    builder: (_) => _EditListDialog(
      dialogTitle: dialogTitle,
      confirmLabel: confirmLabel,
      initialTitle: initialTitle,
      initialEmoji: initialEmoji,
      initialColor: initialColor,
      initialPhoto: initialPhoto,
    ),
  );
}

class _EditListDialog extends StatefulWidget {
  const _EditListDialog({
    required this.dialogTitle,
    required this.confirmLabel,
    required this.initialTitle,
    this.initialEmoji,
    required this.initialColor,
    this.initialPhoto,
  });

  final String dialogTitle;
  final String confirmLabel;
  final String initialTitle;
  final String? initialEmoji;
  final ListThemeColor initialColor;
  final ListThemePhoto? initialPhoto;

  @override
  State<_EditListDialog> createState() => _EditListDialogState();
}

class _EditListDialogState extends State<_EditListDialog> {
  late final TextEditingController _controller;
  late ListThemeColor _selectedColor;
  ListThemePhoto? _selectedPhoto;
  String? _selectedEmoji;
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
    _selectedEmoji = widget.initialEmoji;
    _selectedColor = widget.initialColor;
    _selectedPhoto = widget.initialPhoto;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(context).pop(
      ListEditorResult(
        title: trimmed,
        emoji: _selectedEmoji,
        themeColor: _selectedColor,
        themePhoto: _selectedPhoto,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final attentionColor =
        isDark ? TodoColors.attentionDark : TodoColors.attentionLight;

    return AlertDialog(
      title: Text(widget.dialogTitle),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: () =>
                        setState(() => _showEmojiPicker = !_showEmojiPicker),
                    borderRadius: BorderRadius.circular(24),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: _selectedEmoji != null
                            ? Text(
                                _selectedEmoji!,
                                style: const TextStyle(fontSize: 26),
                              )
                            : Icon(
                                Icons.sentiment_satisfied_alt_outlined,
                                size: 28,
                                color: attentionColor,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      decoration: InputDecoration(hintText: l10n.listNameHint),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ],
              ),
              if (_showEmojiPicker) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final emoji in _defaultListEmojis)
                      InkWell(
                        onTap: () => setState(() {
                          _selectedEmoji = emoji;
                          _showEmojiPicker = false;
                        }),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedEmoji == emoji
                                ? attentionColor.withValues(alpha: 0.16)
                                : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_selectedEmoji != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() {
                        _selectedEmoji = null;
                        _showEmojiPicker = false;
                      }),
                      child: Text(l10n.removeEmoji),
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              ThemePickerView(
                selectedColor: _selectedColor,
                selectedPhoto: _selectedPhoto,
                onSelectTheme: (color, photo) => setState(() {
                  _selectedColor = color;
                  _selectedPhoto = photo;
                }),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            final canSubmit = value.text.trim().isNotEmpty;
            return FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: Text(widget.confirmLabel),
            );
          },
        ),
      ],
    );
  }
}

Future<void> showCreateGroupDialog({
  required BuildContext context,
  required void Function(String title) onCreate,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => _SingleFieldDialog(
      title: l10n.newGroup,
      hintText: l10n.groupNameHint,
      confirmLabel: l10n.create,
      onConfirm: onCreate,
    ),
  );
}

Future<void> showRenameGroupDialog({
  required BuildContext context,
  required String initialTitle,
  required void Function(String newTitle) onRename,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => _SingleFieldDialog(
      title: l10n.renameGroup,
      hintText: l10n.groupNameHint,
      confirmLabel: l10n.save,
      initialValue: initialTitle,
      onConfirm: onRename,
    ),
  );
}

Future<void> showGroupListsDialog({
  required BuildContext context,
  required ListGroup group,
  required List<TodoList> customLists,
  required void Function(Set<String> memberListIds) onSave,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _GroupListsDialog(
      group: group,
      customLists: customLists,
      onSave: onSave,
    ),
  );
}

class _GroupListsDialog extends StatefulWidget {
  const _GroupListsDialog({
    required this.group,
    required this.customLists,
    required this.onSave,
  });

  final ListGroup group;
  final List<TodoList> customLists;
  final void Function(Set<String> memberListIds) onSave;

  @override
  State<_GroupListsDialog> createState() => _GroupListsDialogState();
}

class _GroupListsDialogState extends State<_GroupListsDialog> {
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.customLists
        .where((l) => l.groupId == widget.group.id)
        .map((l) => l.id)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.modifyGroupLists),
      content: SizedBox(
        width: 300,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final list in widget.customLists)
              CheckboxListTile(
                value: _selectedIds.contains(list.id),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _selectedIds.add(list.id);
                    } else {
                      _selectedIds.remove(list.id);
                    }
                  });
                },
                title: Text(list.title),
                secondary: list.emoji != null
                    ? Text(list.emoji!, style: const TextStyle(fontSize: 20))
                    : Icon(
                        list.icon,
                        color: TodoColors.accentFor(list.themeColor),
                      ),
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_selectedIds);
            Navigator.of(context).pop();
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _SingleFieldDialog extends StatefulWidget {
  const _SingleFieldDialog({
    required this.title,
    required this.hintText,
    required this.confirmLabel,
    required this.onConfirm,
    this.initialValue = '',
  });

  final String title;
  final String hintText;
  final String confirmLabel;
  final String initialValue;
  final void Function(String value) onConfirm;

  @override
  State<_SingleFieldDialog> createState() => _SingleFieldDialogState();
}

class _SingleFieldDialogState extends State<_SingleFieldDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onConfirm(_controller.text);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            final canSubmit = value.text.trim().isNotEmpty;
            return FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: Text(widget.confirmLabel),
            );
          },
        ),
      ],
    );
  }
}

/// Bottom sheet matching `theme_picker_bottom_sheet.xml`.
Future<void> showThemePickerBottomSheet({
  required BuildContext context,
  required ListThemeColor currentColor,
  ListThemePhoto? currentPhoto,
  required void Function(ListThemeColor color, ListThemePhoto? photo)
      onSelectTheme,
}) async {
  final l10n = AppLocalizations.of(context);
  var selectedColor = currentColor;
  var selectedPhoto = currentPhoto;

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? TodoColors.secondaryTextDark
                                .withValues(alpha: 0.4)
                            : TodoColors.secondaryTextLight
                                .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      l10n.theme,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ThemePickerView(
                      selectedColor: selectedColor,
                      selectedPhoto: selectedPhoto,
                      onSelectTheme: (color, photo) {
                        setModalState(() {
                          selectedColor = color;
                          selectedPhoto = photo;
                        });
                        onSelectTheme(color, photo);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Horizontal theme picker matching `theme_picker_view.xml`.
class ThemePickerView extends StatefulWidget {
  const ThemePickerView({
    super.key,
    required this.selectedColor,
    this.selectedPhoto,
    required this.onSelectTheme,
  });

  final ListThemeColor selectedColor;
  final ListThemePhoto? selectedPhoto;
  final void Function(ListThemeColor color, ListThemePhoto? photo)
      onSelectTheme;

  @override
  State<ThemePickerView> createState() => _ThemePickerViewState();
}

class _ThemePickerViewState extends State<ThemePickerView> {
  late bool _showPhotos;

  @override
  void initState() {
    super.initState();
    _showPhotos = widget.selectedPhoto != null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ChoiceChip(
              label: Text(l10n.themeTabColor),
              selected: !_showPhotos,
              onSelected: (_) => setState(() => _showPhotos = false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(l10n.themeTabPhoto),
              selected: _showPhotos,
              onSelected: (_) => setState(() => _showPhotos = true),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: !_showPhotos
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ListThemeColor.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final color = ListThemeColor.values[index];
                    final isSelected = widget.selectedPhoto == null &&
                        widget.selectedColor == color;
                    return Center(
                      child: GestureDetector(
                        onTap: () => widget.onSelectTheme(color, null),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: TodoColors.swatchColorFor(color),
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: theme.colorScheme.onSurface,
                                    width: 2.5,
                                  )
                                : (TodoColors.isLightTheme(color)
                                    ? Border.all(
                                        color: TodoColors.accentFor(color)
                                            .withValues(alpha: 0.45),
                                        width: 1,
                                      )
                                    : null),
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: TodoColors.isLightTheme(color)
                                      ? TodoColors.accentFor(color)
                                      : Colors.white,
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ListThemePhoto.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final photo = ListThemePhoto.values[index];
                    final isSelected = widget.selectedPhoto == photo;
                    return Center(
                      child: GestureDetector(
                        key: ValueKey('photo_theme_${photo.name}'),
                        onTap: () =>
                            widget.onSelectTheme(widget.selectedColor, photo),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: theme.colorScheme.primary,
                                    width: 2.5,
                                  )
                                : null,
                            image: DecorationImage(
                              image: AssetImage(TodoColors.photoAssetFor(photo)),
                              fit: BoxFit.cover,
                            ),
                          ),
                          child: isSelected
                              ? const Center(
                                  child: Icon(
                                    Icons.check,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
