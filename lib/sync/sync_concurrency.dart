import 'package:result_dart/result_dart.dart';

import '../core/error/app_error.dart';
import '../core/result/app_result.dart';

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
      final index = nextIndex;
      nextIndex += 1;
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
  await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
  if (firstError != null) return Failure(firstError!);
  if (shouldStop?.call() == true) {
    return Success([for (final result in results) ?result]);
  }
  return Success([for (final result in results) result as R]);
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
