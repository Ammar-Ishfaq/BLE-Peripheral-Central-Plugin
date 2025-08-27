import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'ble_peripheral_plugin_method_channel.dart';

abstract class BlePeripheralPluginPlatform extends PlatformInterface {
  /// Constructs a BlePeripheralPluginPlatform.
  BlePeripheralPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static BlePeripheralPluginPlatform _instance = MethodChannelBlePeripheralPlugin();

  /// The default instance of [BlePeripheralPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelBlePeripheralPlugin].
  static BlePeripheralPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [BlePeripheralPluginPlatform] when
  /// they register themselves.
  static set instance(BlePeripheralPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
