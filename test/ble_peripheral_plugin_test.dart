import 'package:flutter_test/flutter_test.dart';
import 'package:ble_peripheral_plugin/ble_peripheral_plugin.dart';
import 'package:ble_peripheral_plugin/ble_peripheral_plugin_platform_interface.dart';
import 'package:ble_peripheral_plugin/ble_peripheral_plugin_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBlePeripheralPluginPlatform
    with MockPlatformInterfaceMixin
    implements BlePeripheralPluginPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final BlePeripheralPluginPlatform initialPlatform = BlePeripheralPluginPlatform.instance;

  test('$MethodChannelBlePeripheralPlugin is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBlePeripheralPlugin>());
  });

  test('getPlatformVersion', () async {
    BlePeripheralPlugin blePeripheralPlugin = BlePeripheralPlugin();
    MockBlePeripheralPluginPlatform fakePlatform = MockBlePeripheralPluginPlatform();
    BlePeripheralPluginPlatform.instance = fakePlatform;

    expect(await blePeripheralPlugin.getPlatformVersion(), '42');
  });
}
