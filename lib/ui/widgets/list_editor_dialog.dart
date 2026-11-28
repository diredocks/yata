import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/todo_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/todo_list.dart';
import '../../theme/custom_background_service.dart';
import 'theme_picker_sheet.dart';
import '../../theme/todo_theme.dart';

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
    this.customBackgroundPath,
  });

  final String title;
  final String? emoji;
  final ListThemeColor themeColor;
  final ListThemePhoto? themePhoto;
  final String? customBackgroundPath;
}

/// Unified list creation & editing dialog matching `edit_list_dialog.xml`
/// (`tasksview/renamelist/RenameTaskListDialogFragment`).
Future<ListEditorResult?> showListEditorDialog({
  required BuildContext context,
  required String dialogTitle,
  required String confirmLabel,
  String initialTitle = '',
  String? initialEmoji,
  ListThemeColor initialColor = ListThemeColor.blue,
  ListThemePhoto? initialPhoto,
  String? initialCustomBackgroundPath,
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
      initialCustomBackgroundPath: initialCustomBackgroundPath,
    ),
  );
}

class _EditListDialog extends ConsumerStatefulWidget {
  const _EditListDialog({
    required this.dialogTitle,
    required this.confirmLabel,
    required this.initialTitle,
    this.initialEmoji,
    required this.initialColor,
    this.initialPhoto,
    this.initialCustomBackgroundPath,
  });

  final String dialogTitle;
  final String confirmLabel;
  final String initialTitle;
  final String? initialEmoji;
  final ListThemeColor initialColor;
  final ListThemePhoto? initialPhoto;
  final String? initialCustomBackgroundPath;

  @override
  ConsumerState<_EditListDialog> createState() => _EditListDialogState();
}

class _EditListDialogState extends ConsumerState<_EditListDialog> {
  late final TextEditingController _controller;
  late ListThemeColor _selectedColor;
  ListThemePhoto? _selectedPhoto;
  String? _selectedCustomBackgroundPath;
  String? _selectedEmoji;
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
    _selectedEmoji = widget.initialEmoji;
    _selectedColor = widget.initialColor;
    _selectedPhoto = widget.initialPhoto;
    _selectedCustomBackgroundPath = widget.initialCustomBackgroundPath;
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
        customBackgroundPath: _selectedCustomBackgroundPath,
      ),
    );
  }

  Future<void> _handleAddCustom() async {
    final savedPath = await pickAndSaveCustomBackground(
      context: context,
      ref: ref,
    );
    if (savedPath != null && mounted) {
      setState(() {
        _selectedPhoto = null;
        _selectedCustomBackgroundPath = savedPath;
      });
    }
  }

  Future<void> _handleDeleteCustom(CustomBackground bg) async {
    final deleted = await confirmAndDeleteCustomBackground(
      context: context,
      ref: ref,
      background: bg,
    );
    if (deleted && _selectedCustomBackgroundPath == bg.filePath && mounted) {
      setState(() {
        _selectedCustomBackgroundPath = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final attentionColor = isDark
        ? TodoColors.attentionDark
        : TodoColors.attentionLight;

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
                selectedCustomBackgroundPath: _selectedCustomBackgroundPath,
                customBackgrounds: ref.watch(
                  todoProvider.select((s) => s.customBackgrounds),
                ),
                onSelectTheme: (color, photo, customPath) => setState(() {
                  _selectedColor = color;
                  _selectedPhoto = photo;
                  _selectedCustomBackgroundPath = customPath;
                }),
                onAddCustomBackground: _handleAddCustom,
                onDeleteCustomBackground: _handleDeleteCustom,
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
