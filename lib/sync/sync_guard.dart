import 'dart:async';

import 'package:http/http.dart' as http;

import '../auth/microsoft_auth_service.dart';
import '../core/error/app_error.dart';
import '../core/result/app_result.dart';

AppError appErrorFromSyncException(Object error) => switch (error) {
  AppError() => error,
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

AppError appErrorFromAuthException(MicrosoftAuthException error) =>
    AppError.auth(
      message: error.message,
      code: error.code,
      requiresReauth: error.requiresReauth,
    );

/// Boundary for HTTP/auth clients.
Future<AppResult<T>> guardApiCall<T extends Object>(
  FutureOr<T> Function() call, {
  String? operation,
}) =>
    guardAsync(call, operation: operation, onError: appErrorFromSyncException);
