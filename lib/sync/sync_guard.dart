import 'dart:async';

import 'package:http/http.dart' as http;

import '../auth/microsoft_auth_service.dart';
import '../core/error/app_error.dart';
import '../core/result/app_result.dart';
import 'microsoft_todo_models.dart';

AppError appErrorFromSyncException(Object error) => switch (error) {
  SyncApiException() => appErrorFromSyncApiException(error),
  MicrosoftAuthException() => appErrorFromAuthException(error),
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

AppError appErrorFromSyncApiException(SyncApiException error) {
  if (error.isAuthError) {
    return AppError.auth(
      message: error.message,
      code: error.errorCode,
      requiresReauth: true,
    );
  }
  if (error.isNotFound) {
    return AppError.notFound(message: error.message, id: error.errorCode);
  }
  return AppError.network(
    message: error.message,
    code: error.errorCode,
    statusCode: error.statusCode,
    isRetryable: error.statusCode >= 500 || error.isThrottled,
  );
}

AppError appErrorFromAuthException(MicrosoftAuthException error) =>
    AppError.auth(
      message: error.message,
      code: error.code,
      requiresReauth: error.requiresReauth,
    );

/// Boundary for the throwing HTTP/auth clients.
Future<AppResult<T>> guardApiCall<T extends Object>(
  FutureOr<T> Function() call, {
  String? operation,
}) =>
    guardAsync(call, operation: operation, onError: appErrorFromSyncException);
