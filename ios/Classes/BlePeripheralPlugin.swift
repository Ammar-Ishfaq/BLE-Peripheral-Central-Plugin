import Flutter
import UIKit
import CoreBluetooth

public class BlePeripheralPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // MARK: - Plugin Setup
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BlePeripheralPlugin()

        instance.methodChannel = FlutterMethodChannel(
            name: "ble_peripheral_plugin/methods",
            binaryMessenger: registrar.messenger()
        )
        instance.eventChannel = FlutterEventChannel(
            name: "ble_peripheral_plugin/events",
            binaryMessenger: registrar.messenger()
        )

        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)
        instance.eventChannel.setStreamHandler(instance)

        instance.initializeManagers()
    }

    // MARK: - Channels
    private var methodChannel: FlutterMethodChannel!
    private var eventChannel: FlutterEventChannel!
    private var eventSink: FlutterEventSink?

    // MARK: - Peripheral (GATT Server) Properties
    private var peripheralManager: CBPeripheralManager?
    private var peripheralService: CBMutableService?
    private var txCharacteristic: CBMutableCharacteristic?
    private var rxCharacteristic: CBMutableCharacteristic?

    // Store subscribed centrals for notifications :cite[1]
    private var subscribedCentrals = Set<CBCentral>()

    // MARK: - Central (GATT Client) Properties - ENHANCED FOR MULTIPLE CONNECTIONS

    // ✅ ENHANCED: Proper management of multiple peripherals
    private var centralManager: CBCentralManager?
    private var discoveredPeripherals = [String: CBPeripheral]() // deviceId -> Peripheral
    private var connectedPeripherals = [String: CBPeripheral]() // deviceId -> Peripheral
    private var peripheralCharacteristics = [String: [CBCharacteristic]]() // deviceId -> Characteristics

    // MARK: - State Tracking
    private var serviceUUID: CBUUID?
    private var txUUID: CBUUID?
    private var rxUUID: CBUUID?
    private var loggingEnabled = true

    // ✅ NEW: Target service for scanning
    private var scanServiceUUID: CBUUID?

    // MARK: - Stream Handler
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - Method Call Handler - ENHANCED
    // MARK: - Method Call Handler - ENHANCED
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isBluetoothOn":
            result(isBluetoothOn())

        case "startPeripheral":
            guard let args = call.arguments as? [String: Any],
                  let service = args["serviceUuid"] as? String, !service.isEmpty,
                  let tx = args["txUuid"] as? String, !tx.isEmpty,
                  let rx = args["rxUuid"] as? String, !rx.isEmpty
            else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing or invalid service/tx/rx UUIDs. All UUIDs must be non-empty strings.",
                    details: nil
                ))
                return
            }
            startPeripheral(service: service, tx: tx, rx: rx)
            result(nil)

        case "stopPeripheral":
            stopPeripheral()
            result(nil)

        case "sendNotification":
            guard let args = call.arguments as? [String: Any],
                  let charUuid = args["charUuid"] as? String, !charUuid.isEmpty,
                  let value = args["value"] as? FlutterStandardTypedData
            else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing or invalid charUuid or value. charUuid must be non-empty string and value must be valid data.",
                    details: nil
                ))
                return
            }
            sendNotification(charUuid: charUuid, value: value.data)
            result(nil)

        case "startScan":
            guard let args = call.arguments as? [String: Any],
                  let service = args["serviceUuid"] as? String, !service.isEmpty
            else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing or invalid service UUID. Must be a non-empty string.",
                    details: nil
                ))
                return
            }
            startScan(service: service)
            result(nil)

        case "stopScan":
            stopScan()
            result(nil)

        case "connect":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String, !deviceId.isEmpty
            else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing or invalid deviceId. Must be a non-empty string.",
                    details: nil
                ))
                return
            }
            connect(deviceId: deviceId)
            result(nil)

        case "disconnect":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String, !deviceId.isEmpty
            else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing or invalid deviceId. Must be a non-empty string.",
                    details: nil
                ))
                return
            }
            disconnect(deviceId: deviceId)
            result(nil)

        case "disconnectAll":
            disconnectAll()
            result(nil)

        case "writeCharacteristic":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String, !deviceId.isEmpty,
                  let charUuid = args["charUuid"] as? String, !charUuid.isEmpty,
                  let value = args["value"] as? FlutterStandardTypedData
            else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing or invalid deviceId, charUuid, or value. All must be provided and valid.",
                    details: nil
                ))
                return
            }
            writeCharacteristic(deviceId: deviceId, charUuid: charUuid, value: value.data)
            result(nil)

        case "requestMtu":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String, !deviceId.isEmpty,
                  let mtuValue = args["mtu"] as? Int
            else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing or invalid deviceId or mtu. deviceId must be non-empty string and mtu must be integer.",
                    details: nil
                ))
                return
            }
            requestMtu(deviceId: deviceId, mtu: mtuValue)
            result(nil)

        case "getConnectedDevices":
            result(Array(connectedPeripherals.keys))

        case "isDeviceConnected":
            guard let args = call.arguments as? [String: Any],
                  let deviceId = args["deviceId"] as? String, !deviceId.isEmpty
            else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing or invalid deviceId. Must be a non-empty string.",
                    details: nil
                ))
                return
            }
            let isConnected = connectedPeripherals[deviceId] != nil
            result(isConnected)

        case "enableLogs":
            guard let args = call.arguments as? [String: Any],
                  let enable = args["enable"] as? Bool
            else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing or invalid enable parameter. Must be a boolean.",
                    details: nil
                ))
                return
            }
            loggingEnabled = enable
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
    // MARK: - Initialization
    private func initializeManagers() {
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [
                CBPeripheralManagerOptionShowPowerAlertKey: false
            ])
        }

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil, options: [
                CBCentralManagerOptionShowPowerAlertKey: false
            ])
        }
    }

    private func isBluetoothOn() -> Bool {
        let peripheralState = peripheralManager?.state ?? .unknown
        let centralState = centralManager?.state ?? .unknown

        return peripheralState == .poweredOn || centralState == .poweredOn
    }

    // MARK: - Peripheral Methods (GATT Server)
    private func startPeripheral(service: String, tx: String, rx: String) {
        serviceUUID = CBUUID(string: service)
        txUUID = CBUUID(string: tx)
        rxUUID = CBUUID(string: rx)

        guard let peripheralManager = peripheralManager, peripheralManager.state == .poweredOn else {
            sendEvent(["type": "error", "message": "Bluetooth not available for peripheral"])
            return
        }

        setupPeripheralService()
    }

    private func setupPeripheralService() {
        guard let serviceUUID = serviceUUID,
              let txUUID = txUUID,
              let rxUUID = rxUUID
        else {
            return
        }

        // Create characteristics
        txCharacteristic = CBMutableCharacteristic(
            type: txUUID,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable]
        )

        rxCharacteristic = CBMutableCharacteristic(
            type: rxUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )

        // Create service
        peripheralService = CBMutableService(type: serviceUUID, primary: true)
        peripheralService!.characteristics = [txCharacteristic!, rxCharacteristic!]

        // Add service to peripheral manager :cite[1]
        peripheralManager?.add(peripheralService!)

        // Start advertising
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ]
        peripheralManager?.startAdvertising(advertisementData)

        sendEvent(["type": "peripheral_started"])
        log("Peripheral started advertising service: \(serviceUUID.uuidString)")
    }

    private func stopPeripheral() {
        peripheralManager?.stopAdvertising()
        if let service = peripheralService {
            peripheralManager?.remove(service)
        }
        subscribedCentrals.removeAll()
        sendEvent(["type": "peripheral_stopped"])
        log("Peripheral stopped")
    }

    private func sendNotification(charUuid: String, value: Data) {
        guard let characteristic = txCharacteristic,
              let characteristicUUID = txUUID,
              charUuid == characteristicUUID.uuidString
        else {
            log("Invalid characteristic UUID for notification: \(charUuid)")
            return
        }

        characteristic.value = value

        // Send to all subscribed centrals :cite[1]
        let sent = peripheralManager?.updateValue(
            value,
            for: characteristic,
            onSubscribedCentrals: Array(subscribedCentrals)
        ) ?? false

        if sent {
            log("Notification sent to \(subscribedCentrals.count) subscribers")
        } else {
            log("Notification queue full, could not send immediately")
            // In a production app, you would implement a retry mechanism here
        }
    }

    // MARK: - Central Methods (GATT Client) - ENHANCED FOR MULTIPLE CONNECTIONS

    private func startScan(service: String) {
        scanServiceUUID = CBUUID(string: service)

        guard let centralManager = centralManager, centralManager.state == .poweredOn else {
            sendEvent(["type": "error", "message": "Bluetooth not available for scanning"])
            return
        }

        centralManager.scanForPeripherals(
            withServices: [scanServiceUUID!],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        sendEvent(["type": "scan_started"])
        log("Scan started for service: \(service)")
    }

    private func stopScan() {
        centralManager?.stopScan()
        sendEvent(["type": "scan_stopped"])
        log("Scan stopped")
    }

    // ✅ ENHANCED: Connect to specific device
    private func connect(deviceId: String) {
        guard let peripheral = discoveredPeripherals[deviceId] else {
            log("Device not found for connection: \(deviceId)")
            sendEvent([
                          "type": "connectionFailed",
                          "deviceId": deviceId,
                          "message": "Device not found"
                      ])
            return
        }

        guard connectedPeripherals[deviceId] == nil else {
            log("Already connected to device: \(deviceId)")
            return
        }

        log("Connecting to device: \(deviceId)")
        sendEvent(["type": "connecting", "deviceId": deviceId])

        // Store peripheral before connection attempt
        connectedPeripherals[deviceId] = peripheral
        centralManager?.connect(peripheral, options: nil)
    }

    // ✅ ENHANCED: Disconnect specific device
    private func disconnect(deviceId: String) {
        guard let peripheral = connectedPeripherals[deviceId] else {
            log("No active connection to device: \(deviceId)")
            return
        }

        centralManager?.cancelPeripheralConnection(peripheral)
        connectedPeripherals.removeValue(forKey: deviceId)
        peripheralCharacteristics.removeValue(forKey: deviceId)

        sendEvent(["type": "disconnected", "deviceId": deviceId])
        log("Disconnected from device: \(deviceId)")
    }

    private func disconnectAll() {
        for (deviceId, peripheral) in connectedPeripherals {
            centralManager?.cancelPeripheralConnection(peripheral)
            sendEvent(["type": "disconnected", "deviceId": deviceId])
        }

        connectedPeripherals.removeAll()
        peripheralCharacteristics.removeAll()
        log("All devices disconnected")
    }

    // ✅ ENHANCED: Write to specific device's characteristic
    private func writeCharacteristic(deviceId: String, charUuid: String, value: Data) {
        guard let peripheral = connectedPeripherals[deviceId] else {
            log("No connected peripheral for device: \(deviceId)")
            sendEvent([
                          "type": "write_error",
                          "deviceId": deviceId,
                          "message": "Not connected"
                      ])
            return
        }

        guard let characteristics = peripheralCharacteristics[deviceId] else {
            log("No characteristics discovered for device: \(deviceId)")
            sendEvent([
                          "type": "write_error",
                          "deviceId": deviceId,
                          "message": "Characteristics not discovered"
                      ])
            return
        }

        // Find target characteristic
        guard let targetCharacteristic = characteristics.first(where: {
            $0.uuid.uuidString.uppercased() == charUuid.uppercased()
        })
        else {
            log("Characteristic not found: \(charUuid) for device: \(deviceId)")
            sendEvent([
                          "type": "write_error",
                          "deviceId": deviceId,
                          "message": "Characteristic not found"
                      ])
            return
        }

        peripheral.writeValue(value, for: targetCharacteristic, type: .withResponse)
        log("Writing to characteristic \(charUuid) for device \(deviceId)")
    }

    // ✅ NEW: MTU request implementation
    private func requestMtu(deviceId: String, mtu: Int) {
        // Note: iOS handles MTU negotiation automatically.
        // We can report the current MTU but cannot request a specific value like on Android.
        if let peripheral = connectedPeripherals[deviceId] {
            let effectiveMTU = peripheral.maximumWriteValueLength(for: .withoutResponse) + 3
            sendEvent([
                          "type": "mtu_changed",
                          "deviceId": deviceId,
                          "mtu": effectiveMTU
                      ])
            log("Reported MTU for device \(deviceId): \(effectiveMTU)")
        }
    }

    // MARK: - Helper Methods
    private func parseArguments(_ arguments: Any?, keys: [String]) throws -> [String: Any] {
        guard let args = arguments as? [String: Any] else {
            throw PluginError.invalidArguments("Arguments must be a dictionary")
        }

        for key in keys {
            if args[key] == nil {
                throw PluginError.invalidArguments("Missing required key: \(key)")
            }
        }

        return args
    }

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

    enum PluginError: Error {
        case invalidArguments(String)
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BlePeripheralPlugin: CBPeripheralManagerDelegate {

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let isOn = peripheral.state == .poweredOn
        log("Peripheral manager state updated: \(peripheral.state.rawValue)")
        sendEvent(["type": "bluetooth_state", "isOn": isOn])

        if peripheral.state == .poweredOn && peripheralService != nil {
            // Re-setup service if Bluetooth was restarted
            setupPeripheralService()
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            log("Failed to add service: \(error.localizedDescription)")
            sendEvent(["type": "error", "message": "Failed to add service: \(error.localizedDescription)"])
        } else {
            log("Service successfully added to peripheral")
        }
    }

    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            log("Failed to start advertising: \(error.localizedDescription)")
            sendEvent(["type": "error", "message": "Failed to start advertising: \(error.localizedDescription)"])
        } else {
            log("Peripheral started advertising successfully")
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribedCentrals.insert(central)
        sendEvent([
                      "type": "server_connected",
                      "deviceId": central.identifier.uuidString
                  ])
        log("Central subscribed: \(central.identifier.uuidString)")
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribedCentrals.remove(central)
        sendEvent([
                      "type": "server_disconnected",
                      "deviceId": central.identifier.uuidString
                  ])
        log("Central unsubscribed: \(central.identifier.uuidString)")
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                sendEvent([
                              "type": "rx",
                              "charUuid": request.characteristic.uuid.uuidString,
                              "value": value,
                              "deviceId": request.central.identifier.uuidString
                          ])
                log("Received write from \(request.central.identifier.uuidString)")
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Can retry sending notifications if previous attempt failed
        log("Peripheral manager ready to update subscribers")
    }
}

// MARK: - CBCentralManagerDelegate
extension BlePeripheralPlugin: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let isOn = central.state == .poweredOn
        log("Central manager state updated: \(central.state.rawValue)")
        sendEvent(["type": "bluetooth_state", "isOn": isOn])

        if central.state == .poweredOn && scanServiceUUID != nil {
            // Restart scan if it was active
            central.scanForPeripherals(
                withServices: [scanServiceUUID!],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let deviceId = peripheral.identifier.uuidString

        // Store discovered peripheral
        discoveredPeripherals[deviceId] = peripheral

        sendEvent([
                      "type": "scanResult",
                      "deviceId": deviceId,
                      "name": peripheral.name ?? "Unknown",
                      "rssi": RSSI.intValue
                  ])
        log("Discovered peripheral: \(deviceId)")
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let deviceId = peripheral.identifier.uuidString

        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID].compactMap {
            $0
        })

        sendEvent(["type": "connected", "deviceId": deviceId])
        log("Connected to peripheral: \(deviceId)")
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString

        connectedPeripherals.removeValue(forKey: deviceId)

        sendEvent([
                      "type": "connectionFailed",
                      "deviceId": deviceId,
                      "message": error?.localizedDescription ?? "Unknown error"
                  ])
        log("Failed to connect to peripheral: \(deviceId) - \(error?.localizedDescription ?? "Unknown error")")
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let deviceId = peripheral.identifier.uuidString

        connectedPeripherals.removeValue(forKey: deviceId)
        peripheralCharacteristics.removeValue(forKey: deviceId)

        sendEvent(["type": "disconnected", "deviceId": deviceId])
        log("Disconnected from peripheral: \(deviceId)")
    }
}

// MARK: - CBPeripheralDelegate
extension BlePeripheralPlugin: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let deviceId = peripheral.identifier.uuidString

        if let error = error {
            log("Service discovery failed for \(deviceId): \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else {
            return
        }

        for service in services {
            // Discover all characteristics for the service
            let characteristicUUIDs = [txUUID, rxUUID].compactMap {
                $0
            }
            peripheral.discoverCharacteristics(characteristicUUIDs, for: service)
        }

        log("Discovered services for peripheral: \(deviceId)")
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let deviceId = peripheral.identifier.uuidString

        if let error = error {
            log("Characteristic discovery failed for \(deviceId): \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else {
            return
        }

        // Store characteristics for this peripheral
        peripheralCharacteristics[deviceId] = characteristics

        // Enable notifications for TX characteristic
        for characteristic in characteristics {
            if characteristic.uuid == txUUID {
                peripheral.setNotifyValue(true, for: characteristic)
                log("Enabled notifications for TX characteristic on \(deviceId)")
            }
        }

        log("Discovered characteristics for peripheral: \(deviceId)")
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString

        if let error = error {
            log("Characteristic value update failed for \(deviceId): \(error.localizedDescription)")
            return
        }

        guard let value = characteristic.value else {
            return
        }

        sendEvent([
                      "type": "notification",
                      "deviceId": deviceId,
                      "charUuid": characteristic.uuid.uuidString,
                      "value": value
                  ])
        log("Received notification from \(deviceId)")
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString

        if let error = error {
            log("Write failed for \(deviceId): \(error.localizedDescription)")
            sendEvent([
                          "type": "write_error",
                          "deviceId": deviceId,
                          "message": error.localizedDescription
                      ])
        } else {
            log("Write successful for \(deviceId)")
            sendEvent([
                          "type": "write_result",
                          "deviceId": deviceId,
                          "charUuid": characteristic.uuid.uuidString,
                          "status": 0 // GATT_SUCCESS equivalent
                      ])
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let deviceId = peripheral.identifier.uuidString

        if let error = error {
            log("Notification state update failed for \(deviceId): \(error.localizedDescription)")
        } else {
            log("Notification state updated for \(deviceId): \(characteristic.isNotifying)")
        }
    }
}