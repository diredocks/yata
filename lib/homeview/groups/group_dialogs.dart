import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/todo_list.dart';
import '../../theme/todo_theme.dart';
import '../../ui/list_icons.dart';

/// Dialogs for list groups matching `homeview/groups/BaseGroupDialog`.
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

Future<bool?> showGroupListsDialog({
  required BuildContext context,
  required ListGroup group,
  required List<TodoList> customLists,
  required void Function(Set<String> memberListIds) onSave,
}) {
  return showDialog<bool>(
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
                        iconForSmartList(list.smartType),
                        color: TodoColors.listAccentFor(
                          list,
                          brightness: Theme.of(context).brightness,
                        ),
                      ),
                contentPadding: EdgeInsets.zero,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_selectedIds);
            Navigator.of(context).pop(true);
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
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    // Pop this dialog before invoking onConfirm so any follow-up dialog
    // (such as showGroupListsDialog) is not popped by this call.
    Navigator.of(context).pop();
    widget.onConfirm(text);
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
