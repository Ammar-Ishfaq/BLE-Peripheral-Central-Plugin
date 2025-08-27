import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ble_peripheral_plugin_platform_interface.dart';

/// An implementation of [BlePeripheralPluginPlatform] that uses method channels.
class MethodChannelBlePeripheralPlugin extends BlePeripheralPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('ble_peripheral_plugin');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
