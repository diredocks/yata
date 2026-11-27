import 'package:result_dart/result_dart.dart';

import '../core/error/app_error.dart';
import '../core/result/app_result.dart';

/// Runs [action] across [items] with at most [maxConcurrent] in-flight calls,
/// preserving input order and short-circuiting on the first [Failure] or when
/// [shouldStop] returns true, without throwing exceptions.
AsyncAppResult<List<R>> mapResultsWithConcurrency<T, R extends Object>(
  List<T> items,
  int maxConcurrent,
  AsyncAppResult<R> Function(T item) action, {
  bool Function()? shouldStop,
}) async {
  if (items.isEmpty) return const Success([]);
  final results = List<R?>.filled(items.length, null);
  AppError? firstError;
  var nextIndex = 0;

  Future<void> worker() async {
    while (firstError == null &&
        shouldStop?.call() != true &&
        nextIndex < items.length) {
      final index = nextIndex++;
      final res = await action(items[index]);
      res.fold(
        (value) => results[index] = value,
        (error) => firstError ??= error,
      );
    }
  }

  final workerCount = maxConcurrent < items.length
      ? maxConcurrent
      : items.length;
  await Future.wait(List.generate(workerCount, (_) => worker()));

  if (firstError != null) return Failure(firstError!);
  if (shouldStop?.call() == true) {
    return Success(results.nonNulls.toList());
  }
  return Success([for (final result in results) result as R]);
}

/// Runs [action] across [items] with at most [maxConcurrent] in-flight calls,
/// short-circuiting on the first [Failure].
AsyncAppResult<Unit> runResultsWithConcurrency<T>(
  List<T> items,
  int maxConcurrent,
  AsyncAppResult<Unit> Function(T item) action, {
  bool Function()? shouldStop,
}) => mapResultsWithConcurrency<T, Unit>(
  items,
  maxConcurrent,
  action,
  shouldStop: shouldStop,
).map((_) => unit);
