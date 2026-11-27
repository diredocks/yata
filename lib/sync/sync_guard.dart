import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:result_dart/result_dart.dart';

import '../core/error/app_error.dart';
import '../core/result/app_result.dart';

/// Formats long Substrate / Exchange IDs compactly for diagnostic logs.
String shortSyncId(String? id) {
  if (id == null) return 'null';
  final trimmed = id.trim();
  if (trimmed.isEmpty) return 'empty';
  if (trimmed.length <= 20) return trimmed;
  return '${trimmed.substring(0, 8)}..${trimmed.substring(trimmed.length - 8)}';
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

AppError appErrorFromSyncException(Object error) => switch (error) {
  AppError() => error,
  http.ClientException() => AppError.network(
    message: 'The network request failed: ${error.message}',
  ),
  TimeoutException() => const AppError.network(
    message: 'The request timed out. Please try again.',
  ),
  _ => AppError.unknown(
    message: 'An unexpected sync failure occurred.',
    details: error.toString(),
  ),
};

AppError appErrorFromHttpStatus({
  required int statusCode,
  required String message,
  String? errorCode,
}) {
  if (statusCode == 401) {
    return AppError.auth(
      message: message,
      code: errorCode,
      requiresReauth: true,
    );
  }
  if (statusCode == 404 ||
      errorCode == 'ErrorItemNotFound' ||
      errorCode == 'itemNotFound' ||
      errorCode == 'ParentFolderDoesNotContainTaskWithGivenId') {
    return AppError.notFound(message: message, id: errorCode);
  }
  return AppError.network(
    message: message,
    code: errorCode,
    statusCode: statusCode,
    isRetryable: statusCode >= 500 || statusCode == 429,
  );
}

/// Boundary for HTTP/auth clients.
Future<AppResult<T>> guardApiCall<T extends Object>(
  FutureOr<T> Function() call, {
  String? operation,
}) =>
    guardAsync(call, operation: operation, onError: appErrorFromSyncException);
