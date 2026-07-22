import 'dart:typed_data';

enum SyncQueueState { waiting, sending, error }

enum SyncOperationKind { upload, delete, move }

class SyncQueueEntry {
  const SyncQueueEntry({
    required this.path,
    required this.state,
    required this.updatedAt,
    this.kind = SyncOperationKind.upload,
    this.destinationPath,
    this.attempts = 0,
    this.error,
    this.retryable = true,
  });

  final String path;
  final SyncQueueState state;
  final SyncOperationKind kind;
  final String? destinationPath;
  final int attempts;
  final String? error;
  final bool retryable;
  final DateTime updatedAt;

  SyncQueueEntry copyWith({
    SyncQueueState? state,
    int? attempts,
    String? error,
    bool clearError = false,
    bool? retryable,
    DateTime? updatedAt,
  }) => SyncQueueEntry(
    path: path,
    state: state ?? this.state,
    kind: kind,
    destinationPath: destinationPath,
    attempts: attempts ?? this.attempts,
    error: clearError ? null : error ?? this.error,
    retryable: retryable ?? this.retryable,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  factory SyncQueueEntry.fromJson(Map<String, Object?> json) => SyncQueueEntry(
    path: json['path']! as String,
    state: SyncQueueState.values.byName(json['state']! as String),
    kind: SyncOperationKind.values.byName(
      json['kind']?.toString() ?? SyncOperationKind.upload.name,
    ),
    destinationPath: json['destinationPath'] as String?,
    attempts: json['attempts'] as int? ?? 0,
    error: json['error'] as String?,
    retryable: json['retryable'] as bool? ?? true,
    updatedAt: DateTime.parse(json['updatedAt']! as String),
  );

  Map<String, Object?> toJson() => {
    'path': path,
    'state': state.name,
    'kind': kind.name,
    'destinationPath': destinationPath,
    'attempts': attempts,
    'error': error,
    'retryable': retryable,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

enum ConflictResolution { local, remote, merged, deferred }

class SyncProgress {
  const SyncProgress({required this.message, this.completed, this.total});
  final String message;
  final int? completed;
  final int? total;

  double? get fraction => completed == null || total == null || total == 0
      ? null
      : (completed! / total!).clamp(0, 1);

  String? get counter =>
      completed == null || total == null ? null : '$completed / $total';
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
