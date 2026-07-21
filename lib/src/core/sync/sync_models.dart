import 'dart:typed_data';

enum ConflictResolution { local, remote, merged, deferred }

class SyncProgress {
  const SyncProgress({required this.message, this.completed, this.total});
  final String message;
  final int? completed;
  final int? total;

  double? get fraction => completed == null || total == null || total == 0
      ? null
      : (completed! / total!).clamp(0, 1);

  String? get counter => completed == null || total == null ? null : '$completed / $total';
}

class SyncConflict {
  const SyncConflict({
    required this.path,
    required this.local,
    required this.remote,
    required this.base,
  });
  final String path;
  final Uint8List local;
  final Uint8List remote;
  final Uint8List? base;
}

class SyncResult {
  const SyncResult({
    required this.downloaded,
    required this.uploaded,
    required this.conflicts,
  });
  final int downloaded;
  final int uploaded;
  final List<SyncConflict> conflicts;
}
