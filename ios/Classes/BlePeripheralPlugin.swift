import Flutter
import UIKit
import CoreBluetooth

public class BlePeripheralPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CBPeripheralManagerDelegate {
    var eventSink: FlutterEventSink?
    var peripheralManager: CBPeripheralManager?
    var characteristics = [CBMutableCharacteristic]()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "ble_peripheral_plugin", binaryMessenger: registrar.messenger())
        let instance = BlePeripheralPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        let eventChannel = FlutterEventChannel(name: "ble_peripheral_plugin/events", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertising":
            if let args = call.arguments as? [String: Any],
               let serviceUuid = args["serviceUuid"] as? String,
               let charUuids = args["characteristics"] as? [String] {
                startAdvertising(serviceUuid: serviceUuid, charUuids: charUuids)
            }
            result(nil)
        case "stopAdvertising":
            peripheralManager?.stopAdvertising()
            result(nil)
        case "sendNotification":
            if let args = call.arguments as? [String: Any],
               let charUuid = args["characteristic"] as? String,
               let value = args["value"] as? FlutterStandardTypedData {
                sendNotification(charUuid: charUuid, value: value.data)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startAdvertising(serviceUuid: String, charUuids: [String]) {
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)

        let serviceUUID = CBUUID(string: serviceUuid)
        let service = CBMutableService(type: serviceUUID, primary: true)

        characteristics.removeAll()
        for uuid in charUuids {
            let char = CBMutableCharacteristic(
                type: CBUUID(string: uuid),
                properties: [.read, .write, .notify],
                value: nil,
                permissions: [.readable, .writeable]
            )
            characteristics.append(char)
        }
        service.characteristics = characteristics
        peripheralManager?.add(service)

        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataLocalNameKey: "BLE-Peripheral"
        ])
    }

    private func sendNotification(charUuid: String, value: Data) {
        if let char = characteristics.first(where: { $0.uuid.uuidString == charUuid }) {
            peripheralManager?.updateValue(value, for: char, onSubscribedCentrals: nil)
        }
    }

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            eventSink?(["event": "powered_on"])
        } else {
            eventSink?(["event": "state_changed", "state": peripheral.state.rawValue])
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if let char = characteristics.first(where: { $0.uuid == request.characteristic.uuid }) {
            request.value = char.value
            peripheral.respond(to: request, withResult: .success)
            eventSink?(["event": "read", "char": char.uuid.uuidString])
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                eventSink?(["event": "write", "char": request.characteristic.uuid.uuidString, "value": [UInt8](value)])
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
