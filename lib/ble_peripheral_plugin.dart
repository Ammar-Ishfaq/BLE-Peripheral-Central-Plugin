import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class BlePeripheralPlugin {
  static const MethodChannel _method = MethodChannel('ble_peripheral_plugin/methods');
  static const EventChannel _event = EventChannel('ble_peripheral_plugin/events');

  static Stream<Map<String, dynamic>>? _eventStream;
  static const int MAX_MTU = 512;

  // 🆕 BITCHAT advertising methods
  static Future<void> startAdvertisingData(String data) async {
    await _method.invokeMethod('startAdvertisingData', {
      'data': data,
    });
  }

  static Future<void> stopAdvertisingData() async {
    await _method.invokeMethod('stopAdvertisingData');
  }

  static Future<void> startScanForAdvertisements() async {
    await _method.invokeMethod('startScanForAdvertisements');
  }

  static Future<void> stopScanForAdvertisements() async {
    await _method.invokeMethod('stopScanForAdvertisements');
  }

  // Existing methods
  static Future<void> requestMtu([int mtu = MAX_MTU]) async {
    await _method.invokeMethod('requestMtu', {
      'mtu': mtu,
    });
  }

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

  static Future<void> sendNotification(
      String charUuid, Uint8List value) async {
    await _method.invokeMethod('sendNotification', {
      'charUuid': charUuid,
      'value': value,
    });
  }

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

  static Future<void> writeCharacteristic(
      String charUuid, Uint8List value) async {
    await _method.invokeMethod('writeCharacteristic', {
      'charUuid': charUuid,
      'value': value,
    });
  }

  static Stream<Map<String, dynamic>> get events {
    _eventStream ??= _event
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event));
    return _eventStream!;
  }

  static Future<void> enableLogs(bool enable) async {
    await _method.invokeMethod('enableLogs', {"enable": enable});
  }

  static Future<bool> isBluetoothOn() async {
    final result = await _method.invokeMethod<bool>('isBluetoothOn');
    return result ?? false;
  }
}