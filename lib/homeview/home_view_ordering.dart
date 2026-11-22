import '../models/todo_list.dart';

/// Top-level sidebar entry shown below the smart lists divider in `HomeViewScreen`.
sealed class HomeSidebarEntry {
  const HomeSidebarEntry();

  DateTime? get orderDateTime;
  String get stableKey;
}

/// Collapsible folder group and its ordered member custom lists.
final class HomeGroupEntry extends HomeSidebarEntry {
  const HomeGroupEntry({
    required this.group,
    required this.lists,
  });

  final ListGroup group;
  final List<TodoList> lists;

  @override
  DateTime? get orderDateTime => group.orderDateTime;

  @override
  String get stableKey => 'group_${group.id}';
}

/// Top-level ungrouped custom list row in the sidebar.
final class HomeListEntry extends HomeSidebarEntry {
  const HomeListEntry({required this.list});

  final TodoList list;

  @override
  DateTime? get orderDateTime => list.orderDateTime;

  @override
  String get stableKey => 'list_${list.id}';
}

/// Compares two optional timestamps in descending `OrderDateTime` order
/// (higher timestamp = closer to top), falling back to original index order.
int compareOrderDateTimeDesc(
  DateTime? a,
  DateTime? b,
  int indexA,
  int indexB,
) {
  if (a != null && b != null) {
    final cmp = b.toUtc().compareTo(a.toUtc());
    if (cmp != 0) return cmp;
  } else if (a != null) {
    return -1;
  } else if (b != null) {
    return 1;
  }
  return indexA.compareTo(indexB);
}

List<T> _stableSortByOrderDesc<T>(
  List<T> items,
  DateTime? Function(T item) orderOf,
) {
  if (!items.any((item) => orderOf(item) != null)) {
    return [...items];
  }
  final indexed = [
    for (var i = 0; i < items.length; i++) (index: i, item: items[i]),
  ];
  indexed.sort(
    (a, b) => compareOrderDateTimeDesc(
      orderOf(a.item),
      orderOf(b.item),
      a.index,
      b.index,
    ),
  );
  return [for (final entry in indexed) entry.item];
}

/// Sorts folder groups descending by [ListGroup.orderDateTime].
List<ListGroup> sortGroupsByOrder(List<ListGroup> groups) =>
    _stableSortByOrderDesc(groups, (g) => g.orderDateTime);

/// Sorts custom lists descending by [TodoList.orderDateTime].
List<TodoList> sortCustomListsByOrder(List<TodoList> lists) =>
    _stableSortByOrderDesc(lists, (l) => l.orderDateTime);

/// Keeps smart lists in canonical order followed by custom lists sorted
/// descending by [TodoList.orderDateTime].
List<TodoList> sortListsPreservingSmartLists(List<TodoList> lists) {
  final smart = [for (final l in lists) if (l.isSmartList) l];
  final custom = sortCustomListsByOrder(
    [for (final l in lists) if (!l.isSmartList) l],
  );
  return [...smart, ...custom];
}

/// Builds interleaved top-level sidebar entries (groups + ungrouped custom
/// lists), sorted descending by `OrderDateTime`, with each group's member
/// lists also sorted descending by `OrderDateTime`.
List<HomeSidebarEntry> buildOrderedHomeSidebarEntries({
  required List<ListGroup> groups,
  required List<TodoList> lists,
}) {
  final customLists = [for (final l in lists) if (!l.isSmartList) l];
  final validGroupIds = {for (final g in groups) g.id};

  final entries = <HomeSidebarEntry>[
    for (final group in groups)
      HomeGroupEntry(
        group: group,
        lists: sortCustomListsByOrder(
          [for (final l in customLists) if (l.groupId == group.id) l],
        ),
      ),
    for (final list in customLists)
      if (list.groupId == null || !validGroupIds.contains(list.groupId))
        HomeListEntry(list: list),
  ];

  return _stableSortByOrderDesc(entries, (e) => e.orderDateTime);
}
