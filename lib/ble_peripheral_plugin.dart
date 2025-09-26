import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class BlePeripheralPlugin {
  static const MethodChannel _method =
  MethodChannel('ble_peripheral_plugin/methods');
  static const EventChannel _event =
  EventChannel('ble_peripheral_plugin/events');

  static Stream<Map<String, dynamic>>? _eventStream;
  static const int MAX_MTU = 512;

  /// Request MTU size (Central → Peripheral)
  static Future<void> requestMtu([int mtu = MAX_MTU]) async {
    await _method.invokeMethod('requestMtu', {
      'mtu': mtu,
    });
  }
  /// Start peripheral mode with service/characteristic UUIDs
  static Future<void> startPeripheral(
      String serviceUuid, String txUuid, String rxUuid) async {
    await _method.invokeMethod('startPeripheral', {
      'serviceUuid': serviceUuid,
      'txUuid': txUuid,
      'rxUuid': rxUuid,
    });
  }

  static Future<void> stopPeripheral() async {
    await _method.invokeMethod('stopPeripheral');
  }

  /// Send notification (Peripheral → Central)
  static Future<void> sendNotification(
      String charUuid, Uint8List value) async {
    await _method.invokeMethod('sendNotification', {
      'charUuid': charUuid,
      'value': value,
    });
  }

  // ---------------- Central ----------------

  static Future<void> startScan(String serviceUuid) async {
    await _method.invokeMethod('startScan', {"serviceUuid": serviceUuid});
  }

  static Future<void> stopScan() async {
    await _method.invokeMethod('stopScan');
  }

  static Future<void> connect(String deviceId) async {
    await _method.invokeMethod('connect', {"deviceId": deviceId});
  }

  static Future<void> disconnect() async {
    await _method.invokeMethod('disconnect');
  }

  /// Write to peripheral characteristic (Central → Peripheral)
  static Future<void> writeCharacteristic(String charUuid,
      Uint8List value) async {
    await _method.invokeMethod('writeCharacteristic', {
      'charUuid': charUuid,
      'value': value,
    });
  }

  // ---------------- Events ----------------

  static Stream<Map<String, dynamic>> get events {
    _eventStream ??= _event
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event));
    return _eventStream!;
  }

  static Future<void> enableLogs(bool enable) async {
    await _method.invokeMethod('enableLogs', {"enable": enable});
  }

  /// Check if Bluetooth is ON (iOS + Android)
  static Future<bool> isBluetoothOn() async {
    final result = await _method.invokeMethod<bool>('isBluetoothOn');
    return result ?? false;
  }

  /// Check if Bluetooth Peripheral Is supported on Android
  static Future<bool> isBluetoothPeripheralSupported() async {
    final result = await _method.invokeMethod<bool>(
        'isBluetoothPeripheralSupported');
    return result ?? false;
  }

}
