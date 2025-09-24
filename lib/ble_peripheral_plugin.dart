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

  /// Checks whether Bluetooth is enabled on the device
  static Future<bool> isBluetoothOn() async {
    final bool isOn = await _methodChannel.invokeMethod('isBluetoothOn');
    return isOn;
  }

  /// Start monitoring Bluetooth state changes
  static Future<void> startBluetoothStateMonitoring() async {
    await _methodChannel.invokeMethod('startBluetoothStateMonitoring');
  }

  /// Stop monitoring Bluetooth state changes
  static Future<void> stopBluetoothStateMonitoring() async {
    await _methodChannel.invokeMethod('stopBluetoothStateMonitoring');
  }

  /// Request MTU size (Central → Peripheral)
  static Future<void> requestMtu([int mtu = MAX_MTU]) async {
    await _methodChannel.invokeMethod('requestMtu', {
      'mtu': mtu,
    });
  }

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
  static Future<void> sendNotification(
      String charUuid, Uint8List value) async {
    await _methodChannel.invokeMethod('sendNotification', {
      'charUuid': charUuid,
      'value': value,
    });
  }

  // ---------------- Central ----------------

  static Future<void> startScan(String serviceUuid) async {
    await _methodChannel.invokeMethod('startScan', {"serviceUuid": serviceUuid});
  }

  static Future<void> stopScan() async {
    await _methodChannel.invokeMethod('stopScan');
  }

  static Future<void> connect(String deviceId) async {
    await _methodChannel.invokeMethod('connect', {"deviceId": deviceId});
  }

  static Future<void> disconnect() async {
    await _methodChannel.invokeMethod('disconnect');
  }

  /// Write to peripheral characteristic (Central → Peripheral)
  static Future<void> writeCharacteristic(
      String charUuid, Uint8List value) async {
    await _methodChannel.invokeMethod('writeCharacteristic', {
      'charUuid': charUuid,
      'value': value,
    });
  }

  // ---------------- Events ----------------

  static Stream<Map<String, dynamic>> get events {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event));
    return _eventStream!;
  }

  static Future<void> enableLogs(bool enable) async {
    await _methodChannel.invokeMethod('enableLogs', {"enable": enable});
  }
}

// Extension for easier Bluetooth state handling
extension BluetoothStateExtensions on Map<String, dynamic> {
  bool get isBluetoothStateChanged => this['type'] == 'bluetooth_state_changed';
  bool get isBluetoothOn => this['isOn'] == true;
  String get bluetoothState => this['state']?.toString() ?? 'unknown';

  bool get isBluetoothPoweredOn => this['state'] == 'poweredOn';
  bool get isBluetoothPoweredOff => this['state'] == 'poweredOff';
  bool get isBluetoothTurningOn => this['state'] == 'turningOn';
  bool get isBluetoothTurningOff => this['state'] == 'turningOff';
  bool get isBluetoothUnauthorized => this['state'] == 'unauthorized';
  bool get isBluetoothUnsupported => this['state'] == 'unsupported';
  bool get isBluetoothResetting => this['state'] == 'resetting';
  bool get isBluetoothUnknown => this['state'] == 'unknown';
}