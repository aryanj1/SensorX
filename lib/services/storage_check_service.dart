import 'package:flutter/services.dart';

class StorageCheckResult {
  final bool needsWarning;
  final double? freeMb;
  final double estimatedMb;

  const StorageCheckResult({
    required this.needsWarning,
    this.freeMb,
    required this.estimatedMb,
  });
}

class StorageCheckService {
  static const double _photoMb = 10.0;
  static const double _videoMb = 150.0;
  static const double _bufferFactor = 1.2;
  static const double _minRemainingMb = 500.0;
  static const _channel = MethodChannel('com.blu.storage/free_space');

  static Future<StorageCheckResult> check({
    required int photos,
    required int videos,
  }) async {
    final estimatedMb = (photos * _photoMb + videos * _videoMb) * _bufferFactor;
    try {
      final freeMb = await _channel.invokeMethod<double>('getFreeDiskSpaceMb');
      if (freeMb == null) {
        return StorageCheckResult(
          needsWarning: false,
          freeMb: null,
          estimatedMb: estimatedMb,
        );
      }
      final needsWarning =
          estimatedMb > freeMb || (freeMb - estimatedMb) < _minRemainingMb;
      return StorageCheckResult(
        needsWarning: needsWarning,
        freeMb: freeMb,
        estimatedMb: estimatedMb,
      );
    } catch (_) {
      // Platform channel unavailable (iOS, simulator, test) — proceed without warning.
      return StorageCheckResult(
        needsWarning: false,
        freeMb: null,
        estimatedMb: estimatedMb,
      );
    }
  }
}
