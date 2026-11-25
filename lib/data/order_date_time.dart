/// Default spacing (`4096s`) used by Microsoft To Do for `OrderDateTime`
/// and `CommittedOrder` positioning (higher timestamp = closer to top).
const Duration kOrderDateTimeStep = Duration(seconds: 4096);

/// Minimum neighbor spacing (`16s`) before Microsoft To Do re-spaces all items
/// (`bj/u.java:197`).
const Duration kOrderDateTimeMinGap = Duration(seconds: 16);

/// Computes updated descending `OrderDateTime` / `CommittedOrder` values for
/// [reorderedOrders] after an item has moved to [movedIndex].
///
/// Returns a map of index -> new UTC [DateTime]. Updates only [movedIndex]
/// when surrounding timestamps are already monotonic and have > 16s gap;
/// otherwise re-spaces all items descending in [kOrderDateTimeStep] (`4096s`)
/// increments.
Map<int, DateTime> computeReorderedOrderDateTimes(
  List<DateTime?> reorderedOrders,
  int movedIndex, {
  DateTime? fallbackNow,
}) {
  final n = reorderedOrders.length;
  if (n == 0 || movedIndex < 0 || movedIndex >= n) {
    return const {};
  }

  final prev = movedIndex > 0 ? reorderedOrders[movedIndex - 1]?.toUtc() : null;
  final next = movedIndex + 1 < n
      ? reorderedOrders[movedIndex + 1]?.toUtc()
      : null;

  var beforeAllOrdered = true;
  DateTime? prevCursor;
  for (var i = 0; i < movedIndex; i++) {
    final raw = reorderedOrders[i];
    if (raw == null) {
      beforeAllOrdered = false;
      break;
    }
    final utc = raw.toUtc();
    if ((prevCursor != null && utc.isAfter(prevCursor)) ||
        (prev != null && utc.isBefore(prev))) {
      beforeAllOrdered = false;
      break;
    }
    prevCursor = utc;
  }

  var afterAllAtMostNext = next != null;
  var sawNullAfter = false;
  DateTime? afterCursor = next;
  for (var i = movedIndex + 1; i < n; i++) {
    final raw = reorderedOrders[i];
    if (raw == null) {
      sawNullAfter = true;
      continue;
    }
    if (sawNullAfter || afterCursor == null) {
      afterAllAtMostNext = false;
      break;
    }
    final utc = raw.toUtc();
    if (utc.isAfter(afterCursor) || (next != null && utc.isAfter(next))) {
      afterAllAtMostNext = false;
      break;
    }
    afterCursor = utc;
  }

  var afterAllNull = true;
  for (var i = movedIndex + 1; i < n; i++) {
    if (reorderedOrders[i] != null) {
      afterAllNull = false;
      break;
    }
  }

  final canUpdateMovedOnly =
      (prev == null &&
          beforeAllOrdered &&
          next != null &&
          afterAllAtMostNext) ||
      (prev != null && next == null && beforeAllOrdered && afterAllNull) ||
      (prev != null &&
          next != null &&
          prev.isAfter(next) &&
          prev.difference(next) > kOrderDateTimeMinGap &&
          beforeAllOrdered &&
          afterAllAtMostNext);

  if (canUpdateMovedOnly) {
    return {
      movedIndex: computeInsertedOrderDateTime(
        prev: prev,
        next: next,
        fallbackNow: fallbackNow,
      ),
    };
  }

  final nonNull = reorderedOrders
      .whereType<DateTime>()
      .map((d) => d.toUtc())
      .toList();
  DateTime anchor;
  if (nonNull.isNotEmpty) {
    anchor = nonNull.reduce((a, b) => b.isAfter(a) ? b : a);
  } else {
    anchor = (fallbackNow ?? DateTime.now()).toUtc();
  }
  return {
    for (var i = 0; i < n; i++)
      i: anchor.subtract(Duration(seconds: kOrderDateTimeStep.inSeconds * i)),
  };
}

/// Computes a new `OrderDateTime` or `CommittedOrder` between [prev] (above)
/// and [next] (below) in descending-order lists.
DateTime computeInsertedOrderDateTime({
  DateTime? prev,
  DateTime? next,
  DateTime? fallbackNow,
}) {
  final prevUtc = prev?.toUtc();
  final nextUtc = next?.toUtc();
  if (prevUtc != null && nextUtc != null) {
    if (prevUtc.isAfter(nextUtc)) {
      final midMicros =
          (prevUtc.microsecondsSinceEpoch + nextUtc.microsecondsSinceEpoch) ~/
          2;
      return DateTime.fromMicrosecondsSinceEpoch(midMicros, isUtc: true);
    }
    return nextUtc.add(const Duration(milliseconds: 1));
  }
  if (prevUtc == null && nextUtc != null) {
    return nextUtc.add(kOrderDateTimeStep);
  }
  if (prevUtc != null && nextUtc == null) {
    return prevUtc.subtract(kOrderDateTimeStep);
  }
  return (fallbackNow ?? DateTime.now()).toUtc();
}

/// Computes an initial `OrderDateTime` when creating an item at either the
/// top (`addToTop == true`) or bottom (`addToTop == false`) of a list.
DateTime computeNewOrderDateTime({
  required Iterable<DateTime?> existingOrders,
  required bool addToTop,
  DateTime? fallbackNow,
}) {
  final nonNull = existingOrders
      .whereType<DateTime>()
      .map((d) => d.toUtc())
      .toList();
  if (nonNull.isEmpty) {
    return (fallbackNow ?? DateTime.now()).toUtc();
  }
  if (addToTop) {
    final maxDt = nonNull.reduce((a, b) => b.isAfter(a) ? b : a);
    final now = (fallbackNow ?? DateTime.now()).toUtc();
    final minNext = maxDt.add(kOrderDateTimeStep);
    return now.isAfter(minNext) ? now : minNext;
  }
  final minDt = nonNull.reduce((a, b) => b.isBefore(a) ? b : a);
  return minDt.subtract(kOrderDateTimeStep);
}
