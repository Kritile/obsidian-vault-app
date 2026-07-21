enum MotionPreference { expressive, balanced, minimal }

class StorageUsage {
  const StorageUsage({
    required this.currentVaultBytes,
    required this.inactiveVaultBytes,
    required this.imageBytes,
  });

  final int currentVaultBytes;
  final int inactiveVaultBytes;
  final int imageBytes;

  int get totalBytes => currentVaultBytes + inactiveVaultBytes + imageBytes;
}
