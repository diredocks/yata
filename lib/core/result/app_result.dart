import 'dart:async';

import 'package:result_dart/result_dart.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import '../error/app_error.dart';
import '../logging/app_logger.dart';

/// Non-nullable by requirement: use `Failure(AppError.notFound(...))` for
/// empty results instead of `AppResult<T?>`.
typedef AppResult<T extends Object> = ResultDart<T, AppError>;

typedef AsyncAppResult<T extends Object> = AsyncResultDart<T, AppError>;

AppResult<T> guardSync<T extends Object>(
  T Function() call, {
  String? operation,
  AppError Function(Object error)? onError,
}) {
  try {
    return Success(call());
  } catch (error) {
    return _report<T>((onError ?? _unknownError(operation))(error), operation);
  }
}

AppResult<Unit> guardSyncUnit(void Function() call, {String? operation}) =>
    guardSync(() {
      call();
      return unit;
    }, operation: operation);

Future<AppResult<T>> guardAsync<T extends Object>(
  FutureOr<T> Function() call, {
  String? operation,
  AppError Function(Object error)? onError,
}) async {
  try {
    return Success(await call());
  } catch (error) {
    return _report<T>((onError ?? _unknownError(operation))(error), operation);
  }
}

Future<AppResult<Unit>> guardAsyncUnit(
  FutureOr<void> Function() call, {
  String? operation,
}) => guardAsync(() async {
  await call();
  return unit;
}, operation: operation);

/// `StateError` -> [AppError.notFound], `SqliteException`/decode errors ->
/// [AppError.database], anything else -> [AppError.unknown].
Future<AppResult<T>> guardDbCall<T extends Object>(
  FutureOr<T> Function() call, {
  String? operation,
}) => guardAsync(
  call,
  operation: operation,
  onError: (error) {
    return switch (error) {
      StateError() => AppError.notFound(
        message: error.message.toString(),
        entity: operation,
      ),
      SqliteException() => AppError.database(
        message: error.message,
        operation: operation ?? error.operation,
        details: error.explanation ?? error.causingStatement,
      ),
      FormatException() => AppError.database(
        message: 'A stored record could not be decoded.',
        operation: operation,
        details: error.message,
      ),
      TypeError() => AppError.database(
        message: 'A stored record has an unexpected shape.',
        operation: operation,
        details: error.toString(),
      ),
      _ => AppError.unknown(
        message: 'Unexpected data layer failure.',
        details: error.toString(),
      ),
    };
  },
);

Future<AppResult<Unit>> guardDbUnit(
  FutureOr<void> Function() call, {
  String? operation,
}) => guardDbCall(() async {
  await call();
  return unit;
}, operation: operation);

/// Single logging point for every guard.
AppResult<T> _report<T extends Object>(AppError error, String? operation) {
  appLogFor(operation ?? 'app').severe(error.describe());
  return Failure<T, AppError>(error);
}

AppError Function(Object error) _unknownError(String? operation) =>
    (error) => AppError.unknown(
      message:
          'Unexpected failure${operation == null ? '' : ' during $operation'}.',
      details: error.toString(),
    );
