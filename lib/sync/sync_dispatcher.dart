import 'dart:async';

/// Why a sync pass was requested. Carried on commands so logs and error
/// reporting stay greppable across the push/pull boundary.
enum SyncReason {
  localMutation('local_mutation'),
  outboxPending('outbox_pending'),
  debounced('debounced'),
  manual('manual'),
  periodic('periodic'),
  appPaused('app_paused'),
  appResumed('app_resumed'),
  startup('startup'),
  accountChanged('account_changed'),
  realtimeReconnected('realtime_reconnected'),
  realtimeEvent('realtime_event'),
  realtimeOverflow('realtime_overflow'),
  homeWidget('home_widget');

  const SyncReason(this.label);

  final String label;
}

enum PullScope { selective, delta, full }

class PullCommand {
  const PullCommand(
    this.scope,
    this.reason, {
    this.folderRemoteIds,
    this.pruneProtectSinceSeq,
  });

  final PullScope scope;
  final SyncReason reason;
  final Set<String>? folderRemoteIds;
  final int? pruneProtectSinceSeq;

  PullCommand merge(PullCommand other) {
    final earliestPruneSeq = switch ((
      pruneProtectSinceSeq,
      other.pruneProtectSinceSeq,
    )) {
      (final a?, final b?) => a < b ? a : b,
      (final a?, null) => a,
      (null, final b?) => b,
      (null, null) => null,
    };
    if (scope == PullScope.selective && other.scope == PullScope.selective) {
      return PullCommand(
        PullScope.selective,
        other.reason,
        folderRemoteIds: {...?folderRemoteIds, ...?other.folderRemoteIds},
        pruneProtectSinceSeq: earliestPruneSeq,
      );
    }
    final winner = other.scope.index > scope.index ? other : this;
    return PullCommand(
      winner.scope,
      winner.reason,
      folderRemoteIds: winner.scope == PullScope.selective
          ? winner.folderRemoteIds
          : null,
      pruneProtectSinceSeq: earliestPruneSeq,
    );
  }
}

/// Coalescing timer with a bounded maximum postponement cap.
class CoalescingDebouncer {
  CoalescingDebouncer(this.maxCoalesceDelay);

  final Duration maxCoalesceDelay;
  Timer? _timer;
  DateTime? _startedAt;
  DateTime? _deadline;

  bool get isActive => _timer != null && _timer!.isActive;

  Duration schedule(Duration delay, void Function() onFire) {
    final now = DateTime.now();
    final isPending = _deadline != null && _deadline!.isAfter(now);
    final DateTime fireAt;
    if (isPending && _startedAt != null) {
      final cap = _startedAt!.add(
        delay > maxCoalesceDelay ? delay : maxCoalesceDelay,
      );
      final extended = now.add(delay);
      fireAt = extended.isAfter(cap) ? cap : extended;
    } else {
      _startedAt = now;
      fireAt = now.add(delay);
    }

    _timer?.cancel();
    _deadline = fireAt;
    final fireIn = fireAt.difference(now);
    _timer = Timer(fireIn, () {
      cancel();
      onFire();
    });
    return fireIn;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _startedAt = null;
    _deadline = null;
  }
}

/// Single-lane async runner that coalesces overlapping triggers into a single
/// queued follow-up command while an execution cycle is in flight.
class CoalescingRunner<T> {
  CoalescingRunner({required this.coalesce});

  final T Function(T queued, T incoming) coalesce;

  Future<void>? _inFlight;
  T? _queued;

  bool get isRunning => _inFlight != null;
  bool get hasQueued => _queued != null;

  void enqueue(T command) {
    _queued = _queued == null ? command : coalesce(_queued as T, command);
  }

  void clearQueued() {
    _queued = null;
  }

  Future<void> run(
    T command, {
    required bool Function() isCancelled,
    required Future<void> Function(T item) execute,
    void Function(T merged)? onCoalesced,
    Future<void> Function()? onCycleComplete,
  }) {
    final active = _inFlight;
    if (active != null) {
      enqueue(command);
      onCoalesced?.call(_queued as T);
      return active;
    }

    final completer = Completer<void>();
    _inFlight = completer.future;
    unawaited(() async {
      T? next = command;
      try {
        while (next != null && !isCancelled()) {
          final current = next;
          next = null;
          await execute(current);
          if (!isCancelled()) {
            next = _queued;
            _queued = null;
          }
        }
      } finally {
        _queued = null;
        _inFlight = null;
      }
      try {
        if (!isCancelled() && onCycleComplete != null) {
          await onCycleComplete();
        }
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }
}
