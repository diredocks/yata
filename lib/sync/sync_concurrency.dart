/// Runs [action] across [items] with at most [maxConcurrent] in-flight calls,
/// preserving input order in the returned list and aborting on the first error.
Future<List<R>> mapWithConcurrency<T, R>(
  List<T> items,
  int maxConcurrent,
  Future<R> Function(T item) action,
) async {
  if (items.isEmpty) return const [];
  final results = List<R?>.filled(items.length, null);
  var nextIndex = 0;
  var aborted = false;
  Future<void> worker() async {
    while (!aborted && nextIndex < items.length) {
      final index = nextIndex;
      nextIndex += 1;
      try {
        results[index] = await action(items[index]);
      } catch (_) {
        aborted = true;
        rethrow;
      }
    }
  }

  final workerCount = maxConcurrent < items.length
      ? maxConcurrent
      : items.length;
  await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
  return [for (final result in results) result as R];
}

/// Runs [action] across [items] with at most [maxConcurrent] in-flight calls,
/// aborting on the first error.
Future<void> runWithConcurrency<T>(
  List<T> items,
  int maxConcurrent,
  Future<void> Function(T item) action,
) async {
  await mapWithConcurrency<T, void>(items, maxConcurrent, action);
}
