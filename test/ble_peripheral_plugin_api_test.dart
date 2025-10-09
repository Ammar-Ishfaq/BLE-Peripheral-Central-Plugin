import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_peripheral_plugin/ble_peripheral_plugin.dart';

void main() {
  const MethodChannel methodChannel = MethodChannel('ble_peripheral_plugin/methods');
  const EventChannel eventChannel = EventChannel('ble_peripheral_plugin/events');

  TestWidgetsFlutterBinding.ensureInitialized();

  group('BleBroadcastPlugin API', () {
    final List<MethodCall> methodCallLog = [];

    setUp(() {
      methodCallLog.clear();

      // Mock method channel
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
        methodCallLog.add(methodCall);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
    });

    test('startPeripheral calls platform method with correct arguments', () async {
      await BleBroadcastPlugin.startPeripheral('service', 'tx', 'rx');

      expect(methodCallLog, hasLength(1));
      expect(methodCallLog[0].method, 'startPeripheral');
      expect(methodCallLog[0].arguments['serviceUuid'], 'service');
      expect(methodCallLog[0].arguments['txUuid'], 'tx');
      expect(methodCallLog[0].arguments['rxUuid'], 'rx');
    });

    test('stopPeripheral calls platform method', () async {
      await BleBroadcastPlugin.stopPeripheral();

      expect(methodCallLog, hasLength(1));
      expect(methodCallLog[0].method, 'stopPeripheral');
    });

    test('startScan calls platform method with serviceUuid', () async {
      await BleBroadcastPlugin.startScan('service-uuid');

      expect(methodCallLog, hasLength(1));
      expect(methodCallLog[0].method, 'startScan');
      expect(methodCallLog[0].arguments['serviceUuid'], 'service-uuid');
    });

    test('connect calls platform method with deviceId', () async {
      await BleBroadcastPlugin.connect('device-123');

      expect(methodCallLog, hasLength(1));
      expect(methodCallLog[0].method, 'connect');
      expect(methodCallLog[0].arguments['deviceId'], 'device-123');
    });

    test('disconnect calls platform method with deviceId', () async {
      await BleBroadcastPlugin.disconnect('device-123');

      expect(methodCallLog, hasLength(1));
      expect(methodCallLog[0].method, 'disconnect');
      expect(methodCallLog[0].arguments['deviceId'], 'device-123');
    });

    test('disconnectAll calls platform method', () async {
      await BleBroadcastPlugin.disconnectAll();

      expect(methodCallLog, hasLength(1));
      expect(methodCallLog[0].method, 'disconnectAll');
    });

    test('requestMtu calls platform method with default MTU', () async {
      await BleBroadcastPlugin.requestMtu('device-123');

      expect(methodCallLog, hasLength(1));
      expect(methodCallLog[0].method, 'requestMtu');
      expect(methodCallLog[0].arguments['deviceId'], 'device-123');
      expect(methodCallLog[0].arguments['mtu'], 512);
    });

    test('requestMtu calls platform method with custom MTU', () async {
      await BleBroadcastPlugin.requestMtu('device-123', 256);

      expect(methodCallLog, hasLength(1));
      expect(methodCallLog[0].method, 'requestMtu');
      expect(methodCallLog[0].arguments['mtu'], 256);
    });

    test('isBluetoothOn returns boolean', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
        if (methodCall.method == 'isBluetoothOn') {
          return true;
        }
        return null;
      });

      final result = await BleBroadcastPlugin.isBluetoothOn();
      expect(result, isTrue);
    });

    test('getConnectedDevices returns list of device IDs', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
        if (methodCall.method == 'getConnectedDevices') {
          return ['device-1', 'device-2', 'device-3'];
        }
        return null;
      });

      final devices = await BleBroadcastPlugin.getConnectedDevices();
      expect(devices, hasLength(3));
      expect(devices, contains('device-1'));
    });

    test('isDeviceConnected returns boolean', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
        if (methodCall.method == 'isDeviceConnected') {
          return methodCall.arguments['deviceId'] == 'device-123';
        }
        return null;
      });

      final connected = await BleBroadcastPlugin.isDeviceConnected('device-123');
      expect(connected, isTrue);

      final notConnected = await BleBroadcastPlugin.isDeviceConnected('device-999');
      expect(notConnected, isFalse);
    });
  });
}
