import Flutter
import CoreBluetooth

public class BleBroadcastPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheralManager!
    private var sink: FlutterEventSink?
    private let serviceUUID = CBUUID(string: "0000FEED-0000-1000-8000-00805F9B34FB")
    private var logging = true

    public static func register(with registrar: FlutterPluginRegistrar) {
        let inst = BleBroadcastPlugin()
        inst.central = CBCentralManager(delegate: inst, queue: nil)
        inst.peripheral = CBPeripheralManager(delegate: inst, queue: nil)
        let m = FlutterMethodChannel(name: "ble_broadcast/methods", binaryMessenger: registrar.messenger())
        let e = FlutterEventChannel(name: "ble_broadcast/events", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(inst, channel: m)
        e.setStreamHandler(inst)
    }

    public func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events; return nil
    }
    public func onCancel(withArguments _: Any?) -> FlutterError? { sink = nil; return nil }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertising":
            if let args = call.arguments as? [String: Any],
               let bytes = args["payload"] as? FlutterStandardTypedData {
                startAdvertising(data: bytes.data)
            }
        case "stopAdvertising": stopAdvertising()
        case "startScanning": startScanning()
        case "stopScanning": stopScanning()
        case "isBluetoothOn":
            result(peripheral.state == .poweredOn || central.state == .poweredOn); return
        case "enableLogs":
            if let args = call.arguments as? [String: Any], let enable = args["enable"] as? Bool { logging = enable }
        default: result(FlutterMethodNotImplemented); return
        }
        result(nil)
    }

    private func log(_ msg: String) { if logging { print("[BLE_BROADCAST] \(msg)") } }

    private func startAdvertising(data: Data) {
        guard peripheral.state == .poweredOn else { return }
        peripheral.stopAdvertising()
        peripheral.startAdvertising([
                                        CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
                                        CBAdvertisementDataServiceDataKey: [serviceUUID: data]
                                    ])
        log("Advertising started")
    }

    private func stopAdvertising() {
        peripheral.stopAdvertising()
        log("Advertising stopped")
    }

    private func startScanning() {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
        log("Scan started")
    }

    private func stopScanning() {
        central.stopScan()
        log("Scan stopped")
    }
}

extension BleBroadcastPlugin: CBPeripheralManagerDelegate, CBCentralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        log("Peripheral state: \(peripheral.state.rawValue)")
    }
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("Central state: \(central.state.rawValue)")
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let data = serviceData[serviceUUID] {
            sink?(["type": "advertisement", "deviceId": peripheral.identifier.uuidString, "data": data])
        }
    }
}
