import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_peripheral_plugin/ble_peripheral_plugin_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelBlePeripheralPlugin platform = MethodChannelBlePeripheralPlugin();
  const MethodChannel channel = MethodChannel('ble_peripheral_plugin');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
