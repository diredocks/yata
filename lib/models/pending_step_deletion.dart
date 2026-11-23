/// Queued remote subtask deletion awaiting the next sync pass.
class PendingStepDeletion {
  const PendingStepDeletion({
    required this.taskRemoteId,
    required this.stepRemoteId,
  });

  final String taskRemoteId;
  final String stepRemoteId;

  factory PendingStepDeletion.fromJson(Map<String, dynamic> json) =>
      PendingStepDeletion(
        taskRemoteId: json['taskRemoteId'] as String,
        stepRemoteId: json['stepRemoteId'] as String,
      );

  Map<String, dynamic> toJson() => {
    'taskRemoteId': taskRemoteId,
    'stepRemoteId': stepRemoteId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingStepDeletion &&
          other.taskRemoteId == taskRemoteId &&
          other.stepRemoteId == stepRemoteId);

  @override
  int get hashCode => Object.hash(taskRemoteId, stepRemoteId);
}
