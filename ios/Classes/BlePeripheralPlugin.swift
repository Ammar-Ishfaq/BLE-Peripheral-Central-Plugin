import Flutter
import UIKit
import CoreBluetooth

public class BlePeripheralPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // Channels
    private var methodChannel: FlutterMethodChannel!
    private var eventChannel: FlutterEventChannel!
    private var eventSink: FlutterEventSink?

    // Peripheral (Server)
    private var peripheralManager: CBPeripheralManager!
    private var txCharacteristic: CBMutableCharacteristic?
    private var rxCharacteristic: CBMutableCharacteristic?
    private var serviceUUID: CBUUID!
    private var txUUID: CBUUID!
    private var rxUUID: CBUUID!
    private var subscribers = Set<CBCentral>()

    // Central (Client)
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals = [CBPeripheral]()
    private var connectedPeripherals = [CBPeripheral]()
    private var peripheralRX: CBCharacteristic?

    // Pending actions
    private var pendingPeripheralSetup: (service: String, tx: String, rx: String)?
    private var pendingScanUUID: CBUUID?

    // Flutter Plugin registration
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BlePeripheralPlugin()
        instance.methodChannel = FlutterMethodChannel(name: "ble_peripheral_plugin/methods", binaryMessenger: registrar.messenger())
        instance.eventChannel = FlutterEventChannel(name: "ble_peripheral_plugin/events", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)
        instance.eventChannel.setStreamHandler(instance)
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

    // MARK: - Method Call
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startPeripheral":
            guard let args = call.arguments as? [String: String],
                  let service = args["serviceUuid"],
                  let tx = args["txUuid"],
                  let rx = args["rxUuid"] else { return }
            startPeripheral(service: service, tx: tx, rx: rx)
            result(nil)

        case "stopPeripheral":
            stopPeripheral()
            result(nil)

        case "sendNotification":
            guard let args = call.arguments as? [String: Any],
                  let charUuid = args["charUuid"] as? String,
                  let value = args["value"] as? FlutterStandardTypedData else { return }
            sendNotification(charUuid: charUuid, value: value.data)
            result(nil)

        case "startScan":
            guard let args = call.arguments as? [String: String],
                  let service = args["serviceUuid"] else { return }
            startScan(service: service)
            result(nil)

        case "stopScan":
            stopScan()
            result(nil)

        case "connect":
            guard let args = call.arguments as? [String: String],
                  let deviceId = args["deviceId"] else { return }
            connect(deviceId: deviceId)
            result(nil)

        case "disconnect":
            disconnectAll()
            result(nil)

        case "writeCharacteristic":
            guard let args = call.arguments as? [String: Any],
                  let charUuid = args["charUuid"] as? String,
                  let value = args["value"] as? FlutterStandardTypedData else { return }
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

    // MARK: - Peripheral
    private func startPeripheral(service: String, tx: String, rx: String) {
        if peripheralManager?.state == .poweredOn {
            setupPeripheral(service: service, tx: tx, rx: rx)
        } else {
            pendingPeripheralSetup = (service, tx, rx)
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        }
    }

    private func setupPeripheral(service: String, tx: String, rx: String) {
        serviceUUID = CBUUID(string: service)
        txUUID = CBUUID(string: tx)
        rxUUID = CBUUID(string: rx)

        txCharacteristic = CBMutableCharacteristic(
            type: txUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )

        rxCharacteristic = CBMutableCharacteristic(
            type: rxUUID,
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )

        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [txCharacteristic!, rxCharacteristic!]

        peripheralManager.add(service)
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID!]])
        sendEvent(["type": "peripheral_started"])
    }

    private func stopPeripheral() {
        peripheralManager?.stopAdvertising()
        peripheralManager = nil
        subscribers.removeAll()
        sendEvent(["type": "peripheral_stopped"])
    }

    private func sendNotification(charUuid: String, value: Data) {
        guard let characteristic = txCharacteristic,
              charUuid.uppercased() == txUUID.uuidString else { return }
        peripheralManager.updateValue(value, for: characteristic, onSubscribedCentrals: Array(subscribers))
    }

    // MARK: - Central
    private func startScan(service: String) {
        let uuid = CBUUID(string: service)
        if centralManager?.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [uuid], options: nil)
            sendEvent(["type": "scan_started"])
        } else {
            pendingScanUUID = uuid
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    private func stopScan() {
        centralManager?.stopScan()
        sendEvent(["type": "scan_stopped"])
    }

    private func connect(deviceId: String) {
        if let peripheral = discoveredPeripherals.first(where: { $0.identifier.uuidString == deviceId }) {
            centralManager.connect(peripheral, options: nil)
        }
    }

    private func disconnectAll() {
        connectedPeripherals.forEach { centralManager.cancelPeripheralConnection($0) }
        connectedPeripherals.removeAll()
        sendEvent(["type": "disconnected"])
    }

    private func writeCharacteristic(charUuid: String, value: Data) {
        for peripheral in connectedPeripherals {
            if let rx = peripheralRX, rx.uuid.uuidString.uppercased() == charUuid.uppercased() {
                peripheral.writeValue(value, for: rx, type: .withResponse)
            }
        }
    }

    // MARK: - Event sending
    private func sendEvent(_ payload: [String: Any]) {
        DispatchQueue.main.async {
            self.eventSink?(payload)
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BlePeripheralPlugin: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn, let pending = pendingPeripheralSetup {
            setupPeripheral(service: pending.service, tx: pending.tx, rx: pending.rx)
            pendingPeripheralSetup = nil
        } else if peripheral.state != .poweredOn {
            sendEvent(["type": "peripheral_error", "message": "Bluetooth is not powered on"])
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        subscribers.insert(central)
        sendEvent(["type": "server_connected", "deviceId": central.identifier.uuidString])
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.remove(central)
        sendEvent(["type": "server_disconnected", "deviceId": central.identifier.uuidString])
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if let value = req.value {
                sendEvent(["type": "rx", "value": value, "deviceId": req.central.identifier.uuidString])
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }
}

// MARK: - CBCentralManagerDelegate & CBPeripheralDelegate
extension BlePeripheralPlugin: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, let uuid = pendingScanUUID {
            centralManager.scanForPeripherals(withServices: [uuid], options: nil)
            sendEvent(["type": "scan_started"])
            pendingScanUUID = nil
        } else if central.state != .poweredOn {
            sendEvent(["type": "scan_error", "message": "Bluetooth not powered on"])
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(peripheral) {
            discoveredPeripherals.append(peripheral)
        }
        sendEvent(["type": "scanResult", "deviceId": peripheral.identifier.uuidString, "name": peripheral.name ?? ""])
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
        connectedPeripherals.append(peripheral)
        sendEvent(["type": "connected", "deviceId": peripheral.identifier.uuidString])
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripherals.removeAll { $0 == peripheral }
        sendEvent(["type": "disconnected", "deviceId": peripheral.identifier.uuidString])
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([rxUUID, txUUID], for: service)
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
    }
    private var loggingEnabled = true

    private func log(_ message: String) {
        if loggingEnabled {
            print("[BlePeripheralPlugin] \(message)")
        }
    }

}
