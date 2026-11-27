import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_date_time.dart';
import '../data/todo_provider.dart';
import '../models/todo_list.dart';
import 'home_view_ordering.dart';

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
    String? customBackgroundPath,
  }) {
    final existingOrders = groupId != null
        ? _state.lists
              .where((l) => !l.isSmartList && l.groupId == groupId)
              .map((l) => l.orderDateTime)
        : [
            ..._state.lists
                .where((l) => !l.isSmartList && l.groupId == null)
                .map((l) => l.orderDateTime),
            ..._state.groups.map((g) => g.orderDateTime),
          ];
    final newList = TodoList(
      id: _store.nextId('list'),
      title: title,
      groupId: groupId,
      emoji: emoji,
      themeColor: themeColor,
      themePhoto: themePhoto,
      customBackgroundPath: customBackgroundPath,
      sortAscending: false,
      orderDateTime: computeNewOrderDateTime(
        existingOrders: existingOrders,
        addToTop: false,
      ),
    );
    final updated = sortListsPreservingSmartLists([..._state.lists, newList]);
    _store.commit(
      _state.copyWith(
        lists: updated,
        selectedListId: newList.id,
        selectedTaskId: null,
      ),
    );
    _store.repository.saveLists(_state.lists);
    _store.settings.saveSelectedListId(newList.id);
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
    _store.repository.saveGroups(updated);
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

  ListGroup addGroup(String title) {
    final trimmed = title.trim();
    final existingOrders = [
      ..._state.lists
          .where((l) => !l.isSmartList && l.groupId == null)
          .map((l) => l.orderDateTime),
      ..._state.groups.map((g) => g.orderDateTime),
    ];
    final newGroup = ListGroup(
      id: _store.nextId('group'),
      title: _deduplicateGroupTitle(trimmed),
      isExpanded: true,
      orderDateTime: computeNewOrderDateTime(
        existingOrders: existingOrders,
        addToTop: false,
      ),
    );
    final updated = sortGroupsByOrder([..._state.groups, newGroup]);
    _store.commit(_state.copyWith(groups: updated));
    _store.repository.saveGroups(_state.groups);
    return newGroup;
  }

  void renameGroup(String groupId, String newTitle) {
    final trimmed = newTitle.trim();
    final deduped = _deduplicateGroupTitle(trimmed, excludeGroupId: groupId);
    final updated = [
      for (final group in _state.groups)
        if (group.id == groupId) group.copyWith(title: deduped) else group,
    ];
    _store.commit(_state.copyWith(groups: updated));
    _store.repository.saveGroups(updated);
  }

  void deleteGroup(String groupId) {
    final updatedGroups = _state.groups.where((g) => g.id != groupId).toList();
    final updatedLists = [
      for (final list in _state.lists)
        if (list.groupId == groupId) list.copyWith(groupId: null) else list,
    ];
    _store.commit(_state.copyWith(groups: updatedGroups, lists: updatedLists));
    _store.repository.saveGroups(updatedGroups);
    _store.repository.saveLists(updatedLists);
  }

  void setGroupLists(String groupId, Set<String> memberListIds) {
    final updated = [
      for (final list in _state.lists)
        if (!list.isSmartList && memberListIds.contains(list.id))
          list.copyWith(groupId: groupId)
        else if (list.groupId == groupId && !memberListIds.contains(list.id))
          list.copyWith(groupId: null)
        else
          list,
    ];
    _store.commit(_state.copyWith(lists: updated));
    _store.repository.saveLists(updated);
  }

  void reorderTopLevelEntries(
    List<HomeSidebarEntry> entries,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= entries.length) return;
    if (newIndex < 0 || newIndex >= entries.length || oldIndex == newIndex) {
      return;
    }

    final reordered = [...entries];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final newPositions = computeReorderedOrderDateTimes([
      for (final e in reordered) e.orderDateTime,
    ], newIndex);
    final groupOrderUpdates = <String, DateTime>{};
    final listOrderUpdates = <String, DateTime>{};
    for (final entry in newPositions.entries) {
      switch (reordered[entry.key]) {
        case HomeGroupEntry(:final group):
          groupOrderUpdates[group.id] = entry.value;
        case HomeListEntry(:final list):
          listOrderUpdates[list.id] = entry.value;
      }
    }

    final updatedGroups = groupOrderUpdates.isEmpty
        ? _state.groups
        : sortGroupsByOrder([
            for (final group in _state.groups)
              if (groupOrderUpdates.containsKey(group.id))
                group.copyWith(orderDateTime: groupOrderUpdates[group.id])
              else
                group,
          ]);
    final updatedLists = listOrderUpdates.isEmpty
        ? _state.lists
        : sortListsPreservingSmartLists([
            for (final list in _state.lists)
              if (listOrderUpdates.containsKey(list.id))
                list.copyWith(orderDateTime: listOrderUpdates[list.id])
              else
                list,
          ]);

    _store.commit(_state.copyWith(groups: updatedGroups, lists: updatedLists));
    if (groupOrderUpdates.isNotEmpty) {
      _store.repository.saveGroups(_state.groups);
    }
    if (listOrderUpdates.isNotEmpty) {
      _store.repository.saveLists(_state.lists);
    }
  }

  void reorderGroupLists(
    String groupId,
    List<TodoList> orderedMembers,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex < 0 || oldIndex >= orderedMembers.length) return;
    if (newIndex < 0 ||
        newIndex >= orderedMembers.length ||
        oldIndex == newIndex) {
      return;
    }

    final reordered = [...orderedMembers];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final newPositions = computeReorderedOrderDateTimes([
      for (final l in reordered) l.orderDateTime,
    ], newIndex);
    final listOrderUpdates = <String, DateTime>{
      for (final entry in newPositions.entries)
        reordered[entry.key].id: entry.value,
    };

    final updatedLists = sortListsPreservingSmartLists([
      for (final list in _state.lists)
        if (listOrderUpdates.containsKey(list.id))
          list.copyWith(orderDateTime: listOrderUpdates[list.id])
        else
          list,
    ]);
    _store.commit(_state.copyWith(lists: updatedLists));
    _store.repository.saveLists(_state.lists);
  }
}

final homeViewPresenterProvider = Provider<HomeViewPresenter>((ref) {
  return HomeViewPresenter(ref);
});
