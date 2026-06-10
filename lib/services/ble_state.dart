import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:blu/services/cache_service.dart';

class BleState {
  BleState._();
  static BluetoothDevice? currentDevice;
  static TTLFileCache? currentCache;
}
