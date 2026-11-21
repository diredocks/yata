import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';

Future<void> showCreateListDialog({
  required BuildContext context,
  required void Function(String title, ListThemeColor color) onCreate,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CreateListDialog(onCreate: onCreate),
  );
}

class _CreateListDialog extends StatefulWidget {
  const _CreateListDialog({required this.onCreate});

  final void Function(String title, ListThemeColor color) onCreate;

  @override
  State<_CreateListDialog> createState() => _CreateListDialogState();
}

class _CreateListDialogState extends State<_CreateListDialog> {
  final _controller = TextEditingController();
  var _selectedColor = ListThemeColor.blue;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onCreate(_controller.text, _selectedColor);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.newList),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(hintText: l10n.listNameHint),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.listThemeColor,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
            for (final color in ListThemeColor.values)
              GestureDetector(
                onTap: () => setState(() => _selectedColor = color),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: TodoColors.swatchColorFor(color),
                    shape: BoxShape.circle,
                    border: _selectedColor == color
                        ? Border.all(
                            color: Theme.of(context).colorScheme.onSurface,
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
                  child: _selectedColor == color
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: TodoColors.isLightTheme(color)
                              ? TodoColors.accentFor(color)
                              : Colors.white,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.create),
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

Future<void> showRenameListDialog({
  required BuildContext context,
  required String initialTitle,
  required void Function(String newTitle) onRename,
}) {
  final l10n = AppLocalizations.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => _SingleFieldDialog(
      title: l10n.renameList,
      hintText: l10n.listNameHint,
      confirmLabel: l10n.save,
      initialValue: initialTitle,
      onConfirm: onRename,
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
  required void Function(Set<String> memberIds) onSave,
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
  final void Function(Set<String> memberIds) onSave;

  @override
  State<_GroupListsDialog> createState() => _GroupListsDialogState();
}

class _GroupListsDialogState extends State<_GroupListsDialog> {
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = {
      for (final list in widget.customLists)
        if (list.groupId == widget.group.id) list.id,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.modifyGroupLists),
      content: SizedBox(
        width: 320,
        child: widget.customLists.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l10n.emptyListTitle),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final list in widget.customLists)
                    CheckboxListTile(
                      value: _selectedIds.contains(list.id),
                      title: Text(list.title),
                      secondary: Icon(
                        list.icon,
                        color: TodoColors.accentFor(list.themeColor),
                      ),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedIds.add(list.id);
                          } else {
                            _selectedIds.remove(list.id);
                          }
                        });
                      },
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
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

Future<void> showChangeThemeDialog({
  required BuildContext context,
  required ListThemeColor currentColor,
  ListThemePhoto? currentPhoto,
  required void Function(ListThemeColor color, ListThemePhoto? photo)
      onSelectTheme,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _ChangeThemeDialog(
      currentColor: currentColor,
      currentPhoto: currentPhoto,
      onSelectTheme: onSelectTheme,
    ),
  );
}

class _ChangeThemeDialog extends StatefulWidget {
  const _ChangeThemeDialog({
    required this.currentColor,
    this.currentPhoto,
    required this.onSelectTheme,
  });

  final ListThemeColor currentColor;
  final ListThemePhoto? currentPhoto;
  final void Function(ListThemeColor color, ListThemePhoto? photo)
      onSelectTheme;

  @override
  State<_ChangeThemeDialog> createState() => _ChangeThemeDialogState();
}

class _ChangeThemeDialogState extends State<_ChangeThemeDialog> {
  late bool _showPhotos;

  @override
  void initState() {
    super.initState();
    _showPhotos = widget.currentPhoto != null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.changeTheme),
      content: Column(
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
          const SizedBox(height: 14),
          if (!_showPhotos)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in ListThemeColor.values)
                  GestureDetector(
                    onTap: () {
                      widget.onSelectTheme(color, null);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: TodoColors.swatchColorFor(color),
                        shape: BoxShape.circle,
                        border: widget.currentPhoto == null &&
                                widget.currentColor == color
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
                      child: widget.currentPhoto == null &&
                              widget.currentColor == color
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
              ],
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final photo in ListThemePhoto.values)
                  GestureDetector(
                    key: ValueKey('photo_theme_${photo.name}'),
                    onTap: () {
                      widget.onSelectTheme(widget.currentColor, photo);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: widget.currentPhoto == photo
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
                      child: widget.currentPhoto == photo
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
              ],
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
