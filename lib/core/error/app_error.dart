import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_error.freezed.dart';

/// Typed domain error; `sealed` so consumers must cover every branch.
@freezed
sealed class AppError with _$AppError {
  /// Remote/API/transport failure.
  const factory AppError.network({
    @Default('A network error occurred. Please try again.') String message,
    String? code,
    int? statusCode,
    @Default(true) bool isRetryable,
  }) = NetworkError;

  /// Drift/SQLite or persisted-payload failure.
  const factory AppError.database({
    @Default('A local database error occurred.') String message,
    String? operation,
    String? details,
  }) = DatabaseError;

  /// Requested entity/row does not exist (e.g. `StateError` from `getSingle`).
  const factory AppError.notFound({
    @Default('The requested item could not be found.') String message,
    String? entity,
    String? id,
  }) = NotFoundError;

  /// User input or payload failed validation.
  const factory AppError.validation({
    @Default('The provided input is invalid.') String message,
    String? field,
  }) = ValidationError;

  /// Authentication/authorization failure.
  const factory AppError.auth({
    @Default('Authentication failed. Please sign in again.') String message,
    String? code,
    @Default(false) bool requiresReauth,
  }) = AuthError;

  /// Anything that could not be classified above.
  const factory AppError.unknown({
    @Default('An unexpected error occurred.') String message,
    String? details,
  }) = UnknownError;
}

extension AppErrorX on AppError {
  String get userMessage => switch (this) {
    NetworkError(:final message) => message,
    DatabaseError(:final message) => message,
    NotFoundError(:final message) => message,
    ValidationError(:final message) => message,
    AuthError(:final message) => message,
    UnknownError(:final message) => message,
  };

  String describe() => switch (this) {
    NetworkError(:final message, :final code, :final statusCode) => [
      'NetworkError',
      message,
      if (code != null) 'code=$code',
      if (statusCode != null) 'status=$statusCode',
    ].join(' | '),
    DatabaseError(:final message, :final operation, :final details) => [
      'DatabaseError',
      message,
      if (operation != null) 'operation=$operation',
      if (details != null) 'details=$details',
    ].join(' | '),
    NotFoundError(:final message, :final entity, :final id) => [
      'NotFoundError',
      message,
      if (entity != null) 'entity=$entity',
      if (id != null) 'id=$id',
    ].join(' | '),
    ValidationError(:final message, :final field) => [
      'ValidationError',
      message,
      if (field != null) 'field=$field',
    ].join(' | '),
    AuthError(:final message, :final code) => [
      'AuthError',
      message,
      if (code != null) 'code=$code',
    ].join(' | '),
    UnknownError(:final message, :final details) => [
      'UnknownError',
      message,
      if (details != null) 'details=$details',
    ].join(' | '),
  };

  bool get isRetryable => switch (this) {
    NetworkError(:final isRetryable, :final statusCode) =>
      isRetryable &&
          (statusCode == null || statusCode >= 500 || statusCode == 429),
    _ => false,
  };

  bool get isNotFound => switch (this) {
    NotFoundError() => true,
    NetworkError(:final statusCode, :final code) =>
      statusCode == 404 ||
          code == 'ErrorItemNotFound' ||
          code == 'itemNotFound' ||
          code == 'ParentFolderDoesNotContainTaskWithGivenId',
    _ => false,
  };

  bool get isConflict => switch (this) {
    NetworkError(:final statusCode, :final code) =>
      statusCode == 409 ||
          statusCode == 412 ||
          code == 'ErrorIrresolvableConflict',
    _ => false,
  };

  bool get isDeltaExpired => switch (this) {
    NetworkError(:final statusCode, :final code) =>
      statusCode == 410 ||
          code == 'SyncStateNotFound' ||
          code == 'SyncStateInvalid' ||
          code == 'resyncRequired',
    _ => false,
  };

  bool get isFolderGroupNotEmpty => switch (this) {
    NetworkError(:final code) => code == 'FolderGroupNotEmpty',
    _ => false,
  };

  bool get isCantDeleteDefaultFolder => switch (this) {
    NetworkError(:final code) => code == 'CantDeleteDefaultFolder',
    _ => false,
  };
}
