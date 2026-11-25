import 'package:collection/collection.dart';

/// Line-level 3-way merge for plain-text task notes, aligning with MS To Do's
/// `lh.m.a` non-destructive conflict merge on 409/412 `Body` collisions.
String mergeThreeWayNoteText({
  required String? base,
  required String local,
  required String remote,
}) {
  final normLocal = _normalizeLineEndings(local);
  final normRemote = _normalizeLineEndings(remote);
  final normBase = base == null ? null : _normalizeLineEndings(base);

  if (normLocal == normRemote) return normLocal;
  if (normBase == null) {
    if (normRemote.isEmpty) return normLocal;
    if (normLocal.isEmpty) return normRemote;
    if (normLocal.contains(normRemote)) return normLocal;
    if (normRemote.contains(normLocal)) return normRemote;
    return '$normLocal\n$normRemote';
  }
  if (normRemote == normBase) return normLocal;
  if (normLocal == normBase) return normRemote;

  final baseLines = _splitLines(normBase);
  final localLines = _splitLines(normLocal);
  final remoteLines = _splitLines(normRemote);

  final localHunks = _diffHunks(baseLines, localLines);
  final remoteHunks = _diffHunks(baseLines, remoteLines);

  final mergedLines = <String>[];
  var basePos = 0;
  var lIdx = 0;
  var rIdx = 0;

  while (lIdx < localHunks.length || rIdx < remoteHunks.length) {
    final lNext = lIdx < localHunks.length ? localHunks[lIdx] : null;
    final rNext = rIdx < remoteHunks.length ? remoteHunks[rIdx] : null;

    final nextStart = _minNonNull(lNext?.baseStart, rNext?.baseStart)!;
    if (basePos < nextStart) {
      mergedLines.addAll(baseLines.sublist(basePos, nextStart));
      basePos = nextStart;
    }

    if (lNext != null &&
        rNext != null &&
        _hunksOverlapOrTouchAtSamePoint(lNext, rNext)) {
      // Collect the overlapping cluster from both sides.
      var clusterEnd = lNext.baseEnd > rNext.baseEnd
          ? lNext.baseEnd
          : rNext.baseEnd;
      final lClusterStart = lIdx;
      final rClusterStart = rIdx;
      lIdx += 1;
      rIdx += 1;
      while (true) {
        var extended = false;
        while (lIdx < localHunks.length &&
            localHunks[lIdx].baseStart < clusterEnd) {
          if (localHunks[lIdx].baseEnd > clusterEnd) {
            clusterEnd = localHunks[lIdx].baseEnd;
          }
          lIdx += 1;
          extended = true;
        }
        while (rIdx < remoteHunks.length &&
            remoteHunks[rIdx].baseStart < clusterEnd) {
          if (remoteHunks[rIdx].baseEnd > clusterEnd) {
            clusterEnd = remoteHunks[rIdx].baseEnd;
          }
          rIdx += 1;
          extended = true;
        }
        if (!extended) break;
      }

      final localRep = _materializeCluster(
        baseLines,
        localHunks.sublist(lClusterStart, lIdx),
        basePos,
        clusterEnd,
      );
      final remoteRep = _materializeCluster(
        baseLines,
        remoteHunks.sublist(rClusterStart, rIdx),
        basePos,
        clusterEnd,
      );

      if (const ListEquality<String>().equals(localRep, remoteRep)) {
        mergedLines.addAll(localRep);
      } else if (clusterEnd - basePos == 1 &&
          localRep.length == 1 &&
          remoteRep.length == 1) {
        final inlineMerged = _tryInlineMergeLine(
          baseLines[basePos],
          localRep.single,
          remoteRep.single,
        );
        if (inlineMerged != null) {
          mergedLines.add(inlineMerged);
        } else {
          mergedLines.addAll(localRep);
          mergedLines.addAll(remoteRep);
        }
      } else {
        mergedLines.addAll(localRep);
        final localRepLines = localRep.toSet();
        for (final line in remoteRep) {
          if (!localRepLines.contains(line)) {
            mergedLines.add(line);
          }
        }
      }
      basePos = clusterEnd;
    } else if (lNext != null &&
        (rNext == null || lNext.baseStart < rNext.baseStart)) {
      mergedLines.addAll(lNext.replacement);
      basePos = lNext.baseEnd;
      lIdx += 1;
    } else if (rNext != null) {
      mergedLines.addAll(rNext.replacement);
      basePos = rNext.baseEnd;
      rIdx += 1;
    }
  }

  if (basePos < baseLines.length) {
    mergedLines.addAll(baseLines.sublist(basePos));
  }

  return mergedLines.join('\n');
}

String _normalizeLineEndings(String raw) =>
    raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

List<String> _splitLines(String text) =>
    text.isEmpty ? const <String>[] : text.split('\n');

int? _minNonNull(int? a, int? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a < b ? a : b;
}

bool _hunksOverlapOrTouchAtSamePoint(_EditHunk a, _EditHunk b) {
  if (a.baseStart == a.baseEnd && b.baseStart == b.baseEnd) {
    return a.baseStart == b.baseStart;
  }
  return a.baseStart < b.baseEnd && b.baseStart < a.baseEnd;
}

class _EditHunk {
  const _EditHunk({
    required this.baseStart,
    required this.baseEnd,
    required this.replacement,
  });

  final int baseStart;
  final int baseEnd;
  final List<String> replacement;
}

List<_EditHunk> _diffHunks(List<String> base, List<String> target) {
  final n = base.length;
  final m = target.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (base[i] == target[j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }

  final hunks = <_EditHunk>[];
  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && base[i] == target[j]) {
      i += 1;
      j += 1;
      continue;
    }
    final bStart = i;
    final tStart = j;
    while (i < n || j < m) {
      if (i < n && j < m && base[i] == target[j]) break;
      if (i < n && (j == m || dp[i + 1][j] >= dp[i][j + 1])) {
        i += 1;
      } else {
        j += 1;
      }
    }
    hunks.add(
      _EditHunk(
        baseStart: bStart,
        baseEnd: i,
        replacement: target.sublist(tStart, j),
      ),
    );
  }
  return hunks;
}

List<String> _materializeCluster(
  List<String> baseLines,
  List<_EditHunk> hunks,
  int start,
  int end,
) {
  final out = <String>[];
  var pos = start;
  for (final h in hunks) {
    if (pos < h.baseStart) {
      out.addAll(baseLines.sublist(pos, h.baseStart));
    }
    out.addAll(h.replacement);
    pos = h.baseEnd;
  }
  if (pos < end) {
    out.addAll(baseLines.sublist(pos, end));
  }
  return out;
}

String? _tryInlineMergeLine(String base, String local, String remote) {
  // Check if local and remote modified disjoint prefix/suffix segments.
  int commonPrefix(String a, String b) {
    final len = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < len && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }

  int commonSuffix(String a, String b, int minIndexA, int minIndexB) {
    var i = 0;
    while (a.length - 1 - i >= minIndexA &&
        b.length - 1 - i >= minIndexB &&
        a.codeUnitAt(a.length - 1 - i) == b.codeUnitAt(b.length - 1 - i)) {
      i++;
    }
    return i;
  }

  final lp = commonPrefix(base, local);
  final ls = commonSuffix(base, local, lp, lp);
  final lBaseEnd = base.length - ls;

  final rp = commonPrefix(base, remote);
  final rs = commonSuffix(base, remote, rp, rp);
  final rBaseEnd = base.length - rs;

  if (lBaseEnd < rp) {
    // Local edited strictly before remote's edit.
    return local.substring(0, local.length - ls) +
        base.substring(lBaseEnd, rp) +
        remote.substring(rp);
  }
  if (rBaseEnd < lp) {
    // Remote edited strictly before local's edit.
    return remote.substring(0, remote.length - rs) +
        base.substring(rBaseEnd, lp) +
        local.substring(lp);
  }
  return null;
}
