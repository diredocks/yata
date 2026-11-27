import 'dart:io';

import 'package:collection/collection.dart';
import 'package:result_dart/result_dart.dart';

import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/sync_dirty_fields.dart';
import '../../data/sync_outbox.dart';
import '../../data/todo_settings_sync.dart';
import '../../models/todo_list.dart';
import '../sync_guard.dart';
import 'microsoft_todo_api.dart';
import 'substrate_push_context.dart';
import 'substrate_sync_mappers.dart';

final _log = appLogFor('SyncEngine');

/// Entity-specific push handlers for settings, deletions, folder groups,
/// folders, and attachment uploads.
class EntityPushHandlers {
  const EntityPushHandlers(this.ctx);

  final PushContext ctx;

  AsyncAppResult<Unit> pushSetting(SyncOutboxOp op) async {
    final wireValue = extractSettingValueForKey(ctx.readState(), op.localId);
    if (wireValue != null) {
      final result = await ctx.todoApi.patchSetting(op.localId, wireValue);
      if (result.isError()) return Failure(result.exceptionOrNull()!);
    }
    await ctx.commitOp(seq: op.seq);
    return const Success(unit);
  }

  AsyncAppResult<Unit> pushDelete(SyncOutboxOp op) async {
    final result = await _performDelete(op);
    if (result.isError()) return result;
    await ctx.commitOp(seq: op.seq);
    return const Success(unit);
  }

  AsyncAppResult<Unit> _performDelete(SyncOutboxOp op) {
    final remoteId =
        op.remoteId ?? ctx.resolveSessionRemoteId(op.entityType, op.localId);
    if (remoteId == null) return Future.value(const Success(unit));

    switch (op.entityType) {
      case SyncEntityType.step:
        final taskRemoteId = ctx.resolveParentTaskRemoteId(op);
        if (taskRemoteId == null) return Future.value(const Success(unit));
        return ctx.todoApi.deleteStep(taskRemoteId, remoteId);
      case SyncEntityType.attachment:
        final taskRemoteId = ctx.resolveParentTaskRemoteId(op);
        if (taskRemoteId == null) return Future.value(const Success(unit));
        return ctx.todoApi.deleteLinkedEntity(taskRemoteId, remoteId);
      case SyncEntityType.task:
        ctx.markDeletedRemoteKey(op.entityType, remoteId);
        return ctx.todoApi.deleteTask(remoteId);
      case SyncEntityType.list:
        ctx.markDeletedRemoteKey(op.entityType, remoteId);
        return ctx.todoApi
            .deleteFolder(remoteId)
            .recover(
              (e) => e.isCantDeleteDefaultFolder
                  ? const Success(unit)
                  : Failure(e),
            );
      case SyncEntityType.group:
        ctx.markDeletedRemoteKey(op.entityType, remoteId);
        return ctx.todoApi.deleteFolderGroup(remoteId);
      case SyncEntityType.setting:
        return Future.value(const Success(unit));
    }
  }

  AsyncAppResult<Unit> pushGroupUpsert(SyncOutboxOp op) async {
    final group = ctx.resolveGroup(op.localId);
    if (group == null) {
      await ctx.commitOp(seq: op.seq);
      return const Success(unit);
    }

    final AppResult<RemoteFolderGroup> remoteResult;
    if (group.remoteId == null) {
      remoteResult = await ctx.todoApi.createFolderGroup(
        name: group.title,
        orderDateTime: group.orderDateTime ?? ctx.nowUtc,
      );
    } else {
      final dirtyFields = ctx.decodeEnumFields(
        op.fields,
        GroupDirtyField.values,
      );
      final patchPayload = buildGroupPatchPayload(
        group,
        dirtyFields: dirtyFields,
      );
      if (patchPayload.isEmpty) {
        await ctx.commitOp(seq: op.seq, group: group);
        return const Success(unit);
      }
      _log.fine(
        'push PATCH group=${group.id} remote=${shortSyncId(group.remoteId)} '
        'keys=${patchPayload.keys.toList()}',
      );
      remoteResult = await ctx.todoApi.patchFolderGroup(
        group.remoteId!,
        patchPayload,
      );
    }

    if (remoteResult.isError()) return Failure(remoteResult.exceptionOrNull()!);
    final remoteGroup = remoteResult.getOrNull()!;
    ctx.recordCreatedRemoteId(SyncEntityType.group, group.id, remoteGroup.id);
    await ctx.commitOp(
      seq: op.seq,
      group: group.copyWith(
        remoteId: remoteGroup.id,
        title: remoteGroup.name.isNotEmpty ? remoteGroup.name : group.title,
        orderDateTime: remoteGroup.orderDateTime ?? group.orderDateTime,
        updatedAt: ctx.nowUtc,
      ),
    );
    return const Success(unit);
  }

  AsyncAppResult<Unit> pushFolderUpsert(SyncOutboxOp op) async {
    final list = ctx.resolveList(op.localId);
    if (list == null ||
        (list.isSmartList && list.smartType != SmartListType.tasks)) {
      await ctx.commitOp(seq: op.seq);
      return const Success(unit);
    }

    final parentGroupRemoteId = ctx.resolveGroupRemoteId(list.groupId);
    final AppResult<RemoteTodoFolder> remoteResult;
    if (!list.isSmartList && list.remoteId == null) {
      remoteResult = await ctx.todoApi.createFolder(
        buildFolderCreatePayload(
          list,
          parentGroupRemoteId: parentGroupRemoteId,
          nowUtc: ctx.nowUtc,
        ),
      );
    } else if (list.remoteId != null) {
      final dirtyFields = ctx.decodeEnumFields(
        op.fields,
        ListDirtyField.values,
      );
      final patchPayload = buildFolderPatchPayload(
        list,
        parentGroupRemoteId: parentGroupRemoteId,
        dirtyFields: dirtyFields,
      );
      if (patchPayload.isEmpty) {
        await ctx.commitOp(seq: op.seq, list: list);
        return const Success(unit);
      }
      _log.fine(
        'push PATCH folder=${list.id} remote=${shortSyncId(list.remoteId)} '
        'keys=${patchPayload.keys.toList()}',
      );
      remoteResult = await ctx.todoApi.patchFolder(
        list.remoteId!,
        patchPayload,
      );
    } else {
      await ctx.commitOp(seq: op.seq);
      return const Success(unit);
    }

    if (remoteResult.isError()) return Failure(remoteResult.exceptionOrNull()!);
    final remoteFolder = remoteResult.getOrNull()!;
    ctx.recordCreatedRemoteId(SyncEntityType.list, list.id, remoteFolder.id);
    await ctx.commitOp(
      seq: op.seq,
      list: list.copyWith(
        remoteId: remoteFolder.id,
        title: list.title,
        orderDateTime: remoteFolder.orderDateTime ?? list.orderDateTime,
        updatedAt: ctx.nowUtc,
      ),
    );
    return const Success(unit);
  }

  AsyncAppResult<Unit> pushAttachmentUpsert(SyncOutboxOp op) async {
    final task = op.parentLocalId != null
        ? ctx.resolveTask(op.parentLocalId!)
        : null;
    if (task == null) {
      await ctx.commitOp(seq: op.seq);
      return const Success(unit);
    }
    final att = task.attachments.firstWhereOrNull((a) => a.id == op.localId);
    if (att == null || att.remoteId != null) {
      await ctx.commitOp(seq: op.seq);
      return const Success(unit);
    }
    final taskRemoteId =
        task.remoteId ??
        op.parentRemoteId ??
        ctx.resolveSessionRemoteId(SyncEntityType.task, task.id);
    if (taskRemoteId == null) {
      return const Success(unit);
    }
    final localPath = att.localPath;
    if (localPath == null || localPath.isEmpty) {
      await ctx.commitOp(seq: op.seq);
      return const Success(unit);
    }
    final file = File(localPath);
    if (!await file.exists()) {
      _log.warning('Attachment file missing on disk for ${att.id}: $localPath');
      await ctx.commitOp(seq: op.seq);
      return const Success(unit);
    }

    final bytesResult = await guardApiCall(
      () => file.readAsBytes(),
      operation: 'readAttachment',
    );
    if (bytesResult.isError()) return Failure(bytesResult.exceptionOrNull()!);

    final uploadResult = await ctx.todoApi.uploadAttachment(
      taskRemoteId,
      fileName: att.displayName,
      bytes: bytesResult.getOrNull()!,
      contentType: att.contentType,
    );
    if (uploadResult.isError()) return Failure(uploadResult.exceptionOrNull()!);
    final uploaded = uploadResult.getOrNull()!;

    ctx.recordCreatedRemoteId(SyncEntityType.attachment, att.id, uploaded.id);
    final updatedAttachments = [
      for (final item in task.attachments)
        if (item.id == att.id)
          item.copyWith(
            remoteId: uploaded.id,
            size: uploaded.size > 0 ? uploaded.size : item.size,
            contentType: uploaded.contentType ?? item.contentType,
            lastModifiedDateTime:
                uploaded.lastModifiedDateTime ?? item.lastModifiedDateTime,
            isTransferring: false,
          )
        else
          item,
    ];
    final folderRemoteId = ctx.resolveList(task.listId)?.remoteId;
    await ctx.commitOp(
      seq: op.seq,
      task: task.copyWith(
        attachments: updatedAttachments,
        updatedAt: ctx.nowUtc,
      ),
      followUpFolderRemoteId: folderRemoteId,
    );
    _log.fine(
      'push UPLOAD attachment=${att.id} remote=${shortSyncId(uploaded.id)} '
      'task=${shortSyncId(taskRemoteId)} name="${att.displayName}"',
    );
    return const Success(unit);
  }
}
