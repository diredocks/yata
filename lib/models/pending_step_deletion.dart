import 'package:freezed_annotation/freezed_annotation.dart';

part 'pending_step_deletion.freezed.dart';
part 'pending_step_deletion.g.dart';

/// A step deletion that still has to be pushed to the remote API.
@freezed
abstract class PendingStepDeletion with _$PendingStepDeletion {
  const factory PendingStepDeletion({
    required String taskRemoteId,
    required String stepRemoteId,
  }) = _PendingStepDeletion;

  factory PendingStepDeletion.fromJson(Map<String, dynamic> json) =>
      _$PendingStepDeletionFromJson(json);
}
