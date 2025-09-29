import Flutter
import UIKit
import CoreBluetooth

public class BlePeripheralPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // Channels
    private var methodChannel: FlutterMethodChannel!
    private var eventChannel: FlutterEventChannel!
    private var eventSink: FlutterEventSink?

    // 🆕 BITCHAT Advertising Properties
    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private var isAdvertisingData = false
    private var isScanningAdvertisements = false
    private let advertisingServiceUUID = CBUUID(string: "12345678-1234-5678-1234-56789abc0000")

    // Existing GATT properties
    private var txCharacteristic: CBMutableCharacteristic?
    private var rxCharacteristic: CBMutableCharacteristic?
    private var serviceUUID: CBUUID?
    private var txUUID: CBUUID?
    private var rxUUID: CBUUID?
    private var subscribers = Set<CBCentral>()
    private var discoveredPeripherals = [CBPeripheral]()
    private var connectedPeripherals = [CBPeripheral]()
    private var peripheralRX: CBCharacteristic?

    // State tracking
    private var isPeripheralMode = false
    private var isCentralMode = false
    private var loggingEnabled = true

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BlePeripheralPlugin()
        instance.methodChannel = FlutterMethodChannel(name: "ble_peripheral_plugin/methods", binaryMessenger: registrar.messenger())
        instance.eventChannel = FlutterEventChannel(name: "ble_peripheral_plugin/events", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)
        instance.eventChannel.setStreamHandler(instance)

        // Initialize managers
        instance.initializeManagers()
    }

    private func initializeManagers() {
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
        }

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    // MARK: - Stream Handler
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - Method Call Handler
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        // 🆕 BITCHAT Advertising Methods
        case "startAdvertisingData":
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing data", details: nil))
                return
            }
            startAdvertisingData(data: data)
            result(nil)

        case "stopAdvertisingData":
            stopAdvertisingData()
            result(nil)

        case "startScanForAdvertisements":
            startScanForAdvertisements()
            result(nil)

        case "stopScanForAdvertisements":
            stopScanForAdvertisements()
            result(nil)

        // Existing methods
        case "isBluetoothOn":
            if let centralManager = centralManager {
                result(centralManager.state == .poweredOn)
            } else if let peripheralManager = peripheralManager {
                result(peripheralManager.state == .poweredOn)
            } else {
                result(false)
            }

        case "startPeripheral":
            guard let args = call.arguments as? [String: String],
                  let service = args["serviceUuid"],
                  let tx = args["txUuid"],
                  let rx = args["rxUuid"] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing service/tx/rx UUIDs", details: nil))
                return
            }
            startPeripheral(service: service, tx: tx, rx: rx)
            result(nil)

        case "stopPeripheral":
            stopPeripheral()
            result(nil)

        case "sendNotification":
            guard let args = call.arguments as? [String: Any],
                  let charUuid = args["charUuid"] as? String,
                  let value = args["value"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing charUuid or value", details: nil))
                return
            }
            sendNotification(charUuid: charUuid, value: value.data)
            result(nil)

        case "startScan":
            guard let args = call.arguments as? [String: String],
                  let service = args["serviceUuid"] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing service UUID", details: nil))
                return
            }
            startScan(service: service)
            result(nil)

        case "stopScan":
            stopScan()
            result(nil)

        case "connect":
            guard let args = call.arguments as? [String: String],
                  let deviceId = args["deviceId"] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing deviceId", details: nil))
                return
            }
            connect(deviceId: deviceId)
            result(nil)

        case "disconnect":
            disconnectAll()
            result(nil)

        case "writeCharacteristic":
            guard let args = call.arguments as? [String: Any],
                  let charUuid = args["charUuid"] as? String,
                  let value = args["value"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing charUuid or value", details: nil))
                return
            }
            writeCharacteristic(charUuid: charUuid, value: value.data)
            result(nil)

        case "requestMtu":
            if let args = call.arguments as? [String: Any],
               let deviceId = args["deviceId"] as? String,
               let peripheral = connectedPeripherals.first(where: { $0.identifier.uuidString == deviceId }) {
                let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
                result(mtu)
            } else {
                result(185) // default safe MTU for iOS
            }

        case "enableLogs":
            if let args = call.arguments as? [String: Any],
               let enable = args["enable"] as? Bool {
                loggingEnabled = enable
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // 🆕 BITCHAT: Start Advertising Data
    private func startAdvertisingData(data: String) {
        stopAdvertisingData()

        guard let peripheralManager = peripheralManager, peripheralManager.state == .poweredOn else {
            sendEvent(["type": "error", "message": "Bluetooth not available for advertising"])
            return
        }

        let service = CBMutableService(type: advertisingServiceUUID, primary: true)

        // Create a characteristic to hold our data
        let dataCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: "12345678-1234-5678-1234-56789abc0001"),
            properties: [.read],
            value: data.data(using: .utf8),
            permissions: [.readable]
        )

        service.characteristics = [dataCharacteristic]
        peripheralManager.add(service)

        // Start advertising
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [advertisingServiceUUID],
            CBAdvertisementDataLocalNameKey: "BITCHAT"
        ])

        isAdvertisingData = true
        sendEvent(["type": "advertising_started"])
        log("✅ Advertising data started: \(data.prefix(20))...")
    }

    // 🆕 BITCHAT: Stop Advertising Data
    private func stopAdvertisingData() {
        if isAdvertisingData {
            peripheralManager?.stopAdvertising()
            isAdvertisingData = false
            sendEvent(["type": "advertising_stopped"])
            log("🛑 Advertising data stopped")
        }
    }

    // 🆕 BITCHAT: Start Scanning for Advertisements
    private func startScanForAdvertisements() {
        guard let centralManager = centralManager, centralManager.state == .poweredOn else {
            sendEvent(["type": "error", "message": "Bluetooth not available for scanning"])
            return
        }

        centralManager.scanForPeripherals(
            withServices: [advertisingServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        isScanningAdvertisements = true
        sendEvent(["type": "ad_scan_started"])
        log("🔍 Scanning for advertisements started")
    }

    // 🆕 BITCHAT: Stop Scanning Advertisements
    private func stopScanForAdvertisements() {
        centralManager?.stopScan()
        isScanningAdvertisements = false
        sendEvent(["type": "ad_scan_stopped"])
        log("🛑 Advertisement scanning stopped")
    }

    // MARK: - Existing Peripheral Methods
    private func startPeripheral(service: String, tx: String, rx: String) {
        isPeripheralMode = true
        if let peripheralManager = peripheralManager, peripheralManager.state == .poweredOn {
            setupPeripheral(service: service, tx: tx, rx: rx)
        } else {
            log("Bluetooth not available for peripheral mode")
            sendEvent(["type": "error", "message": "Bluetooth not available"])
        }
    }

    private func setupPeripheral(service: String, tx: String, rx: String) {
        serviceUUID = CBUUID(string: service)
        txUUID = CBUUID(string: tx)
        rxUUID = CBUUID(string: rx)

        txCharacteristic = CBMutableCharacteristic(
            type: txUUID!,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )

        rxCharacteristic = CBMutableCharacteristic(
            type: rxUUID!,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )

        let service = CBMutableService(type: serviceUUID!, primary: true)
        service.characteristics = [txCharacteristic!, rxCharacteristic!]

        peripheralManager?.add(service)
        peripheralManager?.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID!]])
        sendEvent(["type": "peripheral_started"])
        log("Peripheral started with service: \(service)")
    }

    private func stopPeripheral() {
        isPeripheralMode = false
        peripheralManager?.stopAdvertising()
        if let serviceUUID = serviceUUID {
            peripheralManager?.removeAllServices()
        }
        subscribers.removeAll()
        sendEvent(["type": "peripheral_stopped"])
        log("Peripheral stopped")
    }

    private func sendNotification(charUuid: String, value: Data) {
        guard let characteristic = txCharacteristic,
              let txUUID = txUUID,
              charUuid.uppercased() == txUUID.uuidString.uppercased() else {
            log("Invalid characteristic UUID for notification: \(charUuid)")
            return
        }

        let sent = peripheralManager?.updateValue(value, for: characteristic, onSubscribedCentrals: Array(subscribers)) ?? false
        if sent {
            log("Notification sent to \(subscribers.count) subscribers")
        } else {
            log("Failed to send notification")
        }
    }

    // MARK: - Existing Central Methods
    private func startScan(service: String) {
        isCentralMode = true
        let uuid = CBUUID(string: service)
        if let centralManager = centralManager, centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [uuid], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            sendEvent(["type": "scan_started"])
            log("Scan started for service: \(service)")
        } else {
            log("Bluetooth not available for scanning")
            sendEvent(["type": "error", "message": "Bluetooth not available for scanning"])
        }
    }

    private func stopScan() {
        centralManager?.stopScan()
        sendEvent(["type": "scan_stopped"])
        log("Scan stopped")
    }

    private func connect(deviceId: String) {
        if let peripheral = discoveredPeripherals.first(where: { $0.identifier.uuidString == deviceId }) {
            centralManager?.connect(peripheral, options: nil)
            log("Connecting to device: \(deviceId)")
        } else {
            log("Device not found: \(deviceId)")
        }
    }

    private func disconnectAll() {
        connectedPeripherals.forEach { centralManager?.cancelPeripheralConnection($0) }
        connectedPeripherals.removeAll()
        sendEvent(["type": "disconnected"])
        log("All devices disconnected")
    }

    private func writeCharacteristic(charUuid: String, value: Data) {
        for peripheral in connectedPeripherals {
            if let rx = peripheralRX, rx.uuid.uuidString.uppercased() == charUuid.uppercased() {
                peripheral.writeValue(value, for: rx, type: .withResponse)
                log("Writing to characteristic: \(charUuid)")
            }
        }
    }

    // MARK: - Event sending
    private func sendEvent(_ payload: [String: Any]) {
        DispatchQueue.main.async {
            self.eventSink?(payload)
        }
    }

    private func log(_ message: String) {
        if loggingEnabled {
            print("[BlePeripheralPlugin] \(message)")
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BlePeripheralPlugin: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let isOn = peripheral.state == .poweredOn
        log("Peripheral manager state: \(peripheral.state.rawValue), isOn: \(isOn)")
        sendEvent(["type": "bluetooth_state", "isOn": isOn])

        if peripheral.state == .poweredOn && isPeripheralMode {
            if let serviceUUID = serviceUUID, let txUUID = txUUID, let rxUUID = rxUUID {
                setupPeripheral(service: serviceUUID.uuidString, tx: txUUID.uuidString, rx: rxUUID.uuidString)
            }
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribers.insert(central)
        sendEvent(["type": "server_connected", "deviceId": central.identifier.uuidString])
        log("Central subscribed: \(central.identifier.uuidString)")
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.remove(central)
        sendEvent(["type": "server_disconnected", "deviceId": central.identifier.uuidString])
        log("Central unsubscribed: \(central.identifier.uuidString)")
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if let value = req.value {
                sendEvent(["type": "rx", "value": value, "deviceId": req.central.identifier.uuidString])
                log("Received write request from: \(req.central.identifier.uuidString)")
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }

    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            log("Advertising error: \(error.localizedDescription)")
            sendEvent(["type": "advertising_failed", "message": error.localizedDescription])
        } else {
            log("Advertising started successfully")
        }
    }
}

// MARK: - CBCentralManagerDelegate & CBPeripheralDelegate
extension BlePeripheralPlugin: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let isOn = central.state == .poweredOn
        log("Central manager state: \(central.state.rawValue), isOn: \(isOn)")
        sendEvent(["type": "bluetooth_state", "isOn": isOn])

        if central.state == .poweredOn && isCentralMode {
            if let serviceUUID = serviceUUID {
                central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            }
        }

        if central.state == .poweredOn && isScanningAdvertisements {
            startScanForAdvertisements()
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {

        // 🆕 Handle BITCHAT advertisements
        if isScanningAdvertisements {
            if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
               let data = serviceData[advertisingServiceUUID] {

                if let message = String(data: data, encoding: .utf8) {
                    log("📨 Received advertisement from \(peripheral.identifier.uuidString): \(message.prefix(30))...")

                    sendEvent([
                        "type": "advertisement_received",
                        "data": message,
                        "deviceId": peripheral.identifier.uuidString,
                        "rssi": RSSI.intValue
                    ])
                }
            }
        }

        // Existing GATT scan handling
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
        }
        sendEvent(["type": "scanResult", "deviceId": peripheral.identifier.uuidString, "name": peripheral.name ?? ""])
        log("Discovered peripheral: \(peripheral.identifier.uuidString)")
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID].compactMap { $0 })
        connectedPeripherals.append(peripheral)
        sendEvent(["type": "connected", "deviceId": peripheral.identifier.uuidString])
        log("Connected to peripheral: \(peripheral.identifier.uuidString)")
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripherals.removeAll { $0.identifier == peripheral.identifier }
        sendEvent(["type": "disconnected", "deviceId": peripheral.identifier.uuidString])
        log("Disconnected from peripheral: \(peripheral.identifier.uuidString)")
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([rxUUID, txUUID].compactMap { $0 }, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            if char.uuid == txUUID {
                peripheral.setNotifyValue(true, for: char)
            }
            if char.uuid == rxUUID {
                peripheralRX = char
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let value = characteristic.value else { return }
        sendEvent(["type": "notification", "value": value, "deviceId": peripheral.identifier.uuidString])
        log("Received notification from: \(peripheral.identifier.uuidString)")
    }
}