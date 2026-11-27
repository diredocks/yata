import 'package:flutter_test/flutter_test.dart';
import 'package:yata/data/sync_outbox.dart';

void main() {
  group('SyncOutboxOp & SyncEntityKey', () {
    test('exposes typed entityKey and nullable remoteKey', () {
      const opWithoutRemote = SyncOutboxOp(
        seq: 1,
        entityType: SyncEntityType.task,
        kind: SyncOpKind.upsert,
        localId: 't1',
      );
      expect(opWithoutRemote.entityKey, (
        type: SyncEntityType.task,
        localId: 't1',
      ));
      expect(opWithoutRemote.remoteKey, isNull);

      const opWithRemote = SyncOutboxOp(
        seq: 2,
        entityType: SyncEntityType.list,
        kind: SyncOpKind.delete,
        localId: 'l1',
        remoteId: 'rl-1',
      );
      expect(opWithRemote.entityKey, (
        type: SyncEntityType.list,
        localId: 'l1',
      ));
      expect(opWithRemote.remoteKey, (
        type: SyncEntityType.list,
        remoteId: 'rl-1',
      ));
    });
  });

  group('SyncOutboxQueue', () {
    test('coalesces non-in-flight upserts and isolates in-flight batch', () {
      final queue = SyncOutboxQueue();
      queue.enqueueUpsert(
        entityType: SyncEntityType.task,
        localId: 't1',
        fields: {'title'},
      );
      queue.enqueueUpsert(
        entityType: SyncEntityType.task,
        localId: 't1',
        fields: {'note'},
      );
      expect(queue.ops.length, 1);
      expect(queue.ops.single.fields, {'title', 'note'});

      final batch = queue.beginBatch();
      expect(batch.length, 1);

      queue.enqueueUpsert(
        entityType: SyncEntityType.task,
        localId: 't1',
        fields: {'dueDate'},
      );
      expect(queue.ops.length, 2);
      queue.endBatch();
    });

    test(
      'cancelPendingUpserts and cancelPendingDeletes respect in-flight seq',
      () {
        final queue = SyncOutboxQueue();
        queue.enqueueUpsert(entityType: SyncEntityType.task, localId: 't1');
        queue.beginBatch();
        queue.enqueueUpsert(entityType: SyncEntityType.task, localId: 't1');
        queue.enqueueDelete(
          entityType: SyncEntityType.task,
          localId: 't2',
          remoteId: 'rt-2',
        );

        expect(queue.cancelPendingUpserts(SyncEntityType.task, 't1'), isTrue);
        expect(queue.ops.where((o) => o.localId == 't1').length, 1);
        expect(queue.cancelPendingUpserts(SyncEntityType.task, 't1'), isFalse);

        expect(queue.cancelPendingDeletes(SyncEntityType.task, 't2'), isTrue);
        expect(queue.hasPending(SyncEntityType.task, 't2'), isFalse);
        queue.endBatch();
      },
    );

    test(
      'tracks ackedEntitySeq and deletedRemoteSeq via SyncEntityKey/SyncRemoteKey',
      () {
        final queue = SyncOutboxQueue();
        queue.enqueueUpsert(entityType: SyncEntityType.task, localId: 't1');
        queue.enqueueDelete(
          entityType: SyncEntityType.task,
          localId: 't2',
          remoteId: 'rt-2',
        );
        final pullStartSeq = queue.lastSeq;

        queue.enqueueUpsert(entityType: SyncEntityType.group, localId: 'g1');
        queue.ackBatch([1, 2]);

        expect(queue.modifiedLocalIdsSince(SyncEntityType.task, pullStartSeq), {
          't1',
          't2',
        });
        expect(
          queue.modifiedLocalIdsSince(
            SyncEntityType.group,
            pullStartSeq,
            includePriorPending: false,
          ),
          {'g1'},
        );
        expect(queue.deletedRemoteIdsSince(SyncEntityType.task, pullStartSeq), {
          'rt-2',
        });

        final protection = queue.capturePullProtection(
          pullStartSeq: pullStartSeq,
          pruneProtectSinceSeq: pullStartSeq,
        );
        expect(protection.dirtyIds(SyncEntityType.task), {'t1', 't2'});
        expect(protection.dirtyIds(SyncEntityType.group), {'g1'});
        expect(protection.pruneKeepIds(SyncEntityType.group), {'g1'});
        expect(protection.deletedRemotes(SyncEntityType.task), {'rt-2'});
        expect(protection.dirtyIds(SyncEntityType.list), isEmpty);
      },
    );

    test('captureCurrentProtection captures only current pending state', () {
      final queue = SyncOutboxQueue();
      queue.enqueueSetting('theme');
      queue.enqueueDelete(
        entityType: SyncEntityType.list,
        localId: 'l1',
        remoteId: 'rl-1',
      );

      final current = queue.captureCurrentProtection();
      expect(current.dirtyIds(SyncEntityType.setting), {'theme'});
      expect(current.deletedRemotes(SyncEntityType.list), {'rl-1'});
      expect(current.pruneKeepIds(SyncEntityType.list), isEmpty);
    });

    test(
      'pruneOrphanedEntities removes non-delete ops for missing entities',
      () {
        final queue = SyncOutboxQueue();
        queue.enqueueUpsert(
          entityType: SyncEntityType.group,
          localId: 'g_dead',
        );
        queue.enqueueUpsert(entityType: SyncEntityType.list, localId: 'l_live');
        queue.enqueueUpsert(entityType: SyncEntityType.task, localId: 't_dead');
        queue.enqueueUpsert(
          entityType: SyncEntityType.attachment,
          localId: 'att1',
          parentLocalId: 't_dead',
        );
        queue.enqueueDelete(
          entityType: SyncEntityType.task,
          localId: 't_del',
          remoteId: 'rt-del',
        );
        queue.enqueueSetting('start_week_from');

        final changed = queue.pruneOrphanedEntities(
          validGroupIds: {},
          validListIds: {'l_live'},
          validTaskIds: {},
        );

        expect(changed, isTrue);
        expect(queue.hasPending(SyncEntityType.group, 'g_dead'), isFalse);
        expect(queue.hasPending(SyncEntityType.task, 't_dead'), isFalse);
        expect(queue.hasPending(SyncEntityType.attachment, 'att1'), isFalse);
        expect(queue.hasPending(SyncEntityType.list, 'l_live'), isTrue);
        expect(queue.hasPending(SyncEntityType.task, 't_del'), isTrue);
        expect(
          queue.hasPending(SyncEntityType.setting, 'start_week_from'),
          isTrue,
        );
      },
    );
  });
}
