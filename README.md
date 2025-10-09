# ble\_peripheral\_plugin

A Flutter plugin that provides access to **Bluetooth Low Energy (BLE) Peripheral and Central functionality**.

With this plugin, a Flutter app can:

* Advertise services and characteristics as a **peripheral**
* Scan for nearby devices and connect as a **central**
* Exchange data between connected devices using BLE characteristics

This plugin is written in **Kotlin (Android)** and **Swift (iOS)** with a unified Dart API.

---

## ✨ Features

* 📡 Act as both **Peripheral** (advertise) and **Central** (scan/connect)
* 🔄 Read/write BLE characteristics
* ⚡ Support for write-without-response for faster communication
* 🔒 Works cross-platform (Android + iOS)

---

## Table of contents

* [Installation](#-installation)
* [Usage](#-usage)
* [API (quick reference)](#api-quick-reference)
* [Permissions](#-permissions)
* [Contributing](#-contributing)
* [License](#-license)

---

## 🚀 Installation

Add the dependency in your app’s `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  ble_peripheral_plugin:
    git:
      url: https://github.com/Ammar-Ishfaq/BLE-Peripheral-Central-Plugin.git
      ref: main   # or a tag like "v1.0.0"

   
```

Then run:

```bash
flutter pub get
```

---

## 📲 Usage

Import the package:

```dart
import 'package:ble_peripheral_plugin/ble_peripheral_plugin.dart';
```

### Start advertising & scanning

```dart
await BleBroadcastPlugin.start();
```

> `start()` will initialize the plugin and begin advertising (peripheral) and scanning (central) according to the default configuration or configuration you pass (see API).

### Send data

```dart
await BleBroadcastPlugin.sendData("Hello BLE");
```


### Listen for BLE lifecycle & status events

```dart
BleBroadcastPlugin.events.listen(_handleBleEvent);

void _handleBleEvent(BleEvent event) {
  print('🔔 Event: ${event.type} | ${event.message}');
}
```

The event stream provides updates on connection state, errors, advertising status, and other lifecycle notifications.

### Simple send & receive example

```dart
// Start BLE (advertising + scanning)
await BleBroadcastPlugin.start();

// Listen for messages
BleBroadcastPlugin.events.listen((event) {
  if (event['type'] == 'rx' || event['type'] == 'notification') {
    final value = event['value'] as Uint8List;
    print("📩 Received: ${String.fromCharCodes(value)}");
  }
});

// Send a message
await BleBroadcastPlugin.sendData("Hello from Flutter 🚀");
```

### Advanced event handling

For production apps, handle BLE events in detail:

```dart
void _handleBleEvent(Map<String, dynamic> event) async {
  final type = event['type'];

  switch (type) {
    case "rx":
    case "notification":
      final value = event['value'] as Uint8List;
      print("📩 Received: ${String.fromCharCodes(value)}");
      break;

    case "scanResult":
        // Only connect you found
        await BleBroadcastPlugin.connect(deviceId);
      break;

    case "connected":
      BleBroadcastPlugin.requestMtu(512);
      break;

    case "disconnected":
      // remove the device from the list
      break;

    case "mtu_changed":
      debugPrint('MTU changed to: ${event['mtu']} for $deviceId');
      break;

    case "mtu_change_failed":
      debugPrint('MTU change failed: ${event['status']}');
      break;
  }
}
```

This allows you to react to connection changes, process messages, and automatically connect when devices are discovered.

### Stop all BLE activity

```dart
await BleBroadcastPlugin.stop();
```

---

## API (quick reference)

> This README lists the most commonly used top-level calls and streams. For full API details see the plugin's dart docs and example app.

* `BleBroadcastPlugin.start()` — Initialize the plugin and start advertising/scanning.
* `BleBroadcastPlugin.stop()` — Stop advertising, scanning and disconnect any connections.
* `BleBroadcastPlugin.sendData(String data)` — Send UTF-8 text data to connected device(s).
* `BleBroadcastPlugin.events` — `Stream<BleEvent>` that emits status and lifecycle events (advertising started, connection lost, error, etc.).

> Note: If you require binary payloads or larger messages, consider splitting them and implementing a framing protocol in your app code.

---

## 🔑 Permissions

This plugin does **not** request runtime permissions automatically. You must handle permissions in your app (for example using [`permission_handler`](https://pub.dev/packages/permission_handler)).

### Android

Add the following to `android/app/src/main/AndroidManifest.xml` (or your library manifest) depending on your target SDK:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<!-- For Android 12+ -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- If you use location-based scanning on older Android versions -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

Request the dangerous permissions at runtime (Android 6+/Marshmallow and Android 12+ policies) before starting BLE operations. Example suggestion: check and request `Permission.bluetooth`, `Permission.bluetoothScan`, `Permission.bluetoothAdvertise`, `Permission.bluetoothConnect`, and `Permission.locationWhenInUse` as needed.

### iOS

Add the Bluetooth usage description(s) to your app's `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to communicate with nearby devices.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app advertises services to nearby Bluetooth devices.</string>
```

On iOS the system will prompt the user for Bluetooth permission; ensure your wording explains why the app needs Bluetooth (best practice: include how it improves the user experience).

---

## ⚠️ Platform notes & troubleshooting

* **Test on real devices.** BLE is unreliable or unavailable in many emulators/simulators.
* **Android variations.** Manufacturer customizations (Xiaomi, Huawei, Samsung, etc.) and Android OS version differences can affect advertising, scanning, and background behavior.
* **iOS background advertising/scan limits.** Background operations are restricted on iOS — use `CoreBluetooth` background modes if necessary and follow Apple docs.
* **MTU & payload size.** Typical BLE payloads are small. Implement chunking and acknowledgements if you need to transfer larger messages.
* **Pairing vs. Connection.** Some iOS devices may present pairing dialogs depending on the services/characteristics used. Keep characteristic security and permissions in mind.
* **Battery & performance.** Aggressive scanning or advertising drains battery. Tune intervals and stop services when not required.

If you hit platform-specific issues, include: OS version, device model, a minimal reproduction, and logs — then open an issue with that information.

---


## 💡 Contributing

Contributions are welcome — please follow these steps:

1. Fork the repository.
2. Create a feature branch: `git checkout -b feat/my-feature`.
3. Commit your changes and open a pull request.

When opening issues or PRs, please include device model, OS version, and reproduction steps for platform bugs.

---

## 📄 License

This project is licensed under the **MIT License** — see `LICENSE` for details.

---

## 🔗 Helpful links

* Flutter plugin development docs: [https://docs.flutter.dev/development/packages-and-plugins/developing-packages](https://docs.flutter.dev/development/packages-and-plugins/developing-packages)
* Android BLE overview: [https://developer.android.com/guide/topics/connectivity/bluetooth/ble-overview](https://developer.android.com/guide/topics/connectivity/bluetooth/ble-overview)
* iOS CoreBluetooth: [https://developer.apple.com/documentation/corebluetooth](https://developer.apple.com/documentation/corebluetooth)


