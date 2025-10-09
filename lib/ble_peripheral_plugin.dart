import 'dart:async';
import 'package:flutter/services.dart';

/// BitChat-style BLE broadcast plugin
/// – No GATT connections
/// – Pure advertising + scanning
/// – Short broadcast packets (≤31 bytes)
class BleBroadcastPlugin {
  static const MethodChannel _m = MethodChannel('ble_broadcast/methods');
  static const EventChannel _e = EventChannel('ble_broadcast/events');
  static Stream<Map<String, dynamic>>? _stream;

  static Stream<Map<String, dynamic>> get events =>
      _stream ??= _e.receiveBroadcastStream()
          .map((e) => Map<String, dynamic>.from(e));

  /// Start continuous advertising of [payload] (<=31 bytes)
  static Future<void> startAdvertising(Uint8List payload) async =>
      _m.invokeMethod('startAdvertising', {'payload': payload});

  static Future<void> stopAdvertising() async =>
      _m.invokeMethod('stopAdvertising');

  /// Start continuous scanning
  static Future<void> startScanning() async =>
      _m.invokeMethod('startScanning');

  static Future<void> stopScanning() async =>
      _m.invokeMethod('stopScanning');

  /// Check BLE state
  static Future<bool> isBluetoothOn() async =>
      (await _m.invokeMethod<bool>('isBluetoothOn')) ?? false;

  static Future<void> enableLogs(bool enable) async =>
      _m.invokeMethod('enableLogs', {'enable': enable});
}
