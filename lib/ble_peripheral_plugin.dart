import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class BlePeripheralPlugin {
  static const MethodChannel _methodChannel =
  MethodChannel('ble_peripheral_plugin/methods');
  static const EventChannel _eventChannel =
  EventChannel('ble_peripheral_plugin/events');

  static Stream<Map<String, dynamic>>? _eventStream;
  static const int MAX_MTU = 512;

  // ---------------- Enhanced Peripheral Methods (Unchanged) ----------------

  /// Start peripheral mode with service/characteristic UUIDs
  static Future<void> startPeripheral(
      String serviceUuid, String txUuid, String rxUuid) async {
    await _methodChannel.invokeMethod('startPeripheral', {
      'serviceUuid': serviceUuid,
      'txUuid': txUuid,
      'rxUuid': rxUuid,
    });
  }

  static Future<void> stopPeripheral() async {
    await _methodChannel.invokeMethod('stopPeripheral');
  }

  /// Send notification (Peripheral → Central)
  static Future<void> sendNotification(String charUuid, Uint8List value) async {
    await _methodChannel.invokeMethod('sendNotification', {
      'charUuid': charUuid,
      'value': value,
    });
  }

  // ---------------- Enhanced Central Methods with Multi-Connection Support ----------------

  /// Start scanning for BLE devices
  static Future<void> startScan(String serviceUuid) async {
    await _methodChannel.invokeMethod('startScan', {'serviceUuid': serviceUuid});
  }

  static Future<void> stopScan() async {
    await _methodChannel.invokeMethod('stopScan');
  }

  /// ✅ UPDATED: Connect to a specific device (adds to multiple connections)
  static Future<void> connect(String deviceId) async {
    await _methodChannel.invokeMethod('connect',{"deviceId":deviceId});
  }

  /// ✅ NEW: Disconnect a specific device
  static Future<void> disconnect(String deviceId) async {
    await _methodChannel.invokeMethod('disconnect',{"deviceId":deviceId});
  }

  /// ✅ NEW: Disconnect all central connections
  static Future<void> disconnectAll() async {
    await _methodChannel.invokeMethod('disconnectAll');
  }

  /// ✅ UPDATED: Write to a specific device's characteristic
  static Future<void> writeCharacteristic(
      String deviceId, String charUuid, Uint8List value) async {
    await _methodChannel.invokeMethod('writeCharacteristic', {
      'deviceId': deviceId,
      'charUuid': charUuid,
      'value': value,
    });
  }

  /// ✅ UPDATED: Request MTU for a specific device
  static Future<void> requestMtu(String deviceId, [int mtu = MAX_MTU]) async {
    await _methodChannel.invokeMethod('requestMtu', {
      'deviceId': deviceId,
      'mtu': mtu,
    });
  }

  // ---------------- Enhanced Connection Management ----------------

  /// ✅ NEW: Get list of all connected device IDs
  static Future<List<String>> getConnectedDevices() async {
    final result = await _methodChannel.invokeMethod<List<dynamic>>('getConnectedDevices');
    return result?.map((id) => id.toString()).toList() ?? [];
  }

  /// ✅ NEW: Check if a specific device is connected
  static Future<bool> isDeviceConnected(String deviceId) async {
    final result = await _methodChannel.invokeMethod<bool>(
        'isDeviceConnected',
        {'deviceId': deviceId}
    );
    return result ?? false;
  }

  // ---------------- Events & Utilities ----------------

  /// Event stream for BLE notifications and state changes
  static Stream<Map<String, dynamic>> get events {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event));
    return _eventStream!;
  }

  static Future<void> enableLogs(bool enable) async {
    await _methodChannel.invokeMethod('enableLogs', {'enable': enable});
  }

  /// Check if Bluetooth is ON (iOS + Android)
  static Future<bool> isBluetoothOn() async {
    final result = await _methodChannel.invokeMethod<bool>('isBluetoothOn');
    return result ?? false;
  }

  /// Stop all BLE operations (peripheral + central)
  static Future<void> stopAll() async {
    await _methodChannel.invokeMethod('stopAll');
  }
}