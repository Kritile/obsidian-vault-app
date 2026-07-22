import 'dart:io';

import 'package:flutter/services.dart';

class StorageCapacityService {
  const StorageCapacityService();

  static const _channel = MethodChannel('dev.pavelvault/storage');

  Future<int?> availableBytes(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      if (Platform.isAndroid) {
        return await _channel.invokeMethod<int>('getFreeSpace', {'path': path});
      }
      if (Platform.isLinux) {
        final result = await Process.run('df', ['-Pk', path]);
        if (result.exitCode != 0) return null;
        final lines = result.stdout.toString().trim().split('\n');
        if (lines.length < 2) return null;
        final fields = lines.last.trim().split(RegExp(r'\s+'));
        return fields.length >= 4 ? int.tryParse(fields[3])! * 1024 : null;
      }
      if (Platform.isWindows) {
        final root = Directory(path).absolute.path.substring(0, 2);
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-PSDrive -Name ${root[0]}).Free',
        ]);
        return result.exitCode == 0
            ? int.tryParse(result.stdout.toString().trim())
            : null;
      }
    } on Object {
      return null;
    }
    return null;
  }
}

class InsufficientSpaceException implements Exception {
  const InsufficientSpaceException({
    required this.requiredBytes,
    required this.availableBytes,
    required this.location,
  });

  final int requiredBytes;
  final int availableBytes;
  final String location;

  @override
  String toString() =>
      'Недостаточно места ($location): требуется ${_mb(requiredBytes)} МБ, доступно ${_mb(availableBytes)} МБ';

  static int _mb(int bytes) => (bytes / (1024 * 1024)).ceil();
}
