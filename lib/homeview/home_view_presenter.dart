import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../models/todo_list.dart';
import '../data/todo_provider.dart';

/// Presenter for `homeview/HomeViewFragment`, matching `homeview/HomeViewPresenter`.
class HomeViewPresenter {
  HomeViewPresenter(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  void selectList(String listId) {
    _store.selectList(listId);
  }

  void addList(
    String title,
    ListThemeColor themeColor, {
    String? groupId,
    String? emoji,
    ListThemePhoto? themePhoto,
  }) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final newList = TodoList(
      id: _store.nextId('list'),
      title: trimmed,
      groupId: groupId,
      emoji: emoji,
      themeColor: themeColor,
      themePhoto: themePhoto,
      icon: Icons.format_list_bulleted,
    );
    final updated = [..._state.lists, newList];
    _store.commit(
      _state.copyWith(
        lists: updated,
        selectedListId: newList.id,
        clearSelectedTaskId: true,
      ),
    );
    _store.storage.saveLists(updated);
    _store.storage.saveSelectedListId(newList.id);
  }

  void toggleGroupExpanded(String groupId) {
    final updated = [
      for (final group in _state.groups)
        if (group.id == groupId)
          group.copyWith(isExpanded: !group.isExpanded)
        else
          group,
    ];
    _store.commit(_state.copyWith(groups: updated));
    _store.storage.saveGroups(updated);
  }

  String _deduplicateGroupTitle(String title, {String? excludeGroupId}) {
    final existing = {
      for (final g in _state.groups)
        if (g.id != excludeGroupId) g.title,
    };
    if (!existing.contains(title)) return title;
    var index = 1;
    while (existing.contains('$title ($index)')) {
      index += 1;
    }
    return '$title ($index)';
  }

  ListGroup? addGroup(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return null;
    final newGroup = ListGroup(
      id: _store.nextId('group'),
      title: _deduplicateGroupTitle(trimmed),
      isExpanded: true,
    );
    final updated = [..._state.groups, newGroup];
    _store.commit(_state.copyWith(groups: updated));
    _store.storage.saveGroups(updated);
    return newGroup;
  }

  void renameGroup(String groupId, String newTitle) {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final deduped = _deduplicateGroupTitle(trimmed, excludeGroupId: groupId);
    final updated = [
      for (final group in _state.groups)
        if (group.id == groupId) group.copyWith(title: deduped) else group,
    ];
    _store.commit(_state.copyWith(groups: updated));
    _store.storage.saveGroups(updated);
  }

  void deleteGroup(String groupId) {
    final updatedGroups =
        _state.groups.where((g) => g.id != groupId).toList();
    final updatedLists = [
      for (final list in _state.lists)
        if (list.groupId == groupId)
          list.copyWith(clearGroupId: true)
        else
          list,
    ];
    _store.commit(_state.copyWith(groups: updatedGroups, lists: updatedLists));
    _store.storage.saveGroups(updatedGroups);
    _store.storage.saveLists(updatedLists);
  }

  void moveListToGroup(String listId, String? groupId) {
    final updated = [
      for (final list in _state.lists)
        if (list.id == listId && !list.isSmartList)
          list.copyWith(groupId: groupId, clearGroupId: groupId == null)
        else
          list,
    ];
    _store.commit(_state.copyWith(lists: updated));
    _store.storage.saveLists(updated);
  }

  void setGroupLists(String groupId, Set<String> memberListIds) {
    final updated = [
      for (final list in _state.lists)
        if (!list.isSmartList && memberListIds.contains(list.id))
          list.copyWith(groupId: groupId)
        else if (list.groupId == groupId && !memberListIds.contains(list.id))
          list.copyWith(clearGroupId: true)
        else
          list,
    ];
    _store.commit(_state.copyWith(lists: updated));
    _store.storage.saveLists(updated);
  }
}

final homeViewPresenterProvider = Provider<HomeViewPresenter>((ref) {
  return HomeViewPresenter(ref);
});
