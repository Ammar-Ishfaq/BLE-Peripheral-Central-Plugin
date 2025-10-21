package com.ammar.ble.ble_peripheral_plugin

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.*
import java.util.concurrent.ConcurrentHashMap

class BlePeripheralPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val TAG = "BlePeripheralPlugin"
        private const val MAX_MTU = 512
        private var loggingEnabled = true
    }

    private fun logI(msg: String) {
        if (loggingEnabled) Log.i(TAG, msg)
    }

    private fun logW(msg: String) {
        if (loggingEnabled) Log.w(TAG, msg)
    }

    private fun logE(msg: String) {
        if (loggingEnabled) Log.e(TAG, msg)
    }

    // channels
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    // android context + managers
    private var appContext: Context? = null
    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var scanner: BluetoothLeScanner? = null

    // peripheral (server) state
    private var gattServer: BluetoothGattServer? = null
    private var serverServiceUuid: UUID? = null
    private var serverTxUuid: UUID? = null
    private var serverRxUuid: UUID? = null
    private var txCharacteristic: BluetoothGattCharacteristic? = null
    private var rxCharacteristic: BluetoothGattCharacteristic? = null
    private val subscribers = mutableSetOf<BluetoothDevice>()

    // ✅ ENHANCED: Multiple central connections support
    private val gattClients = ConcurrentHashMap<String, BluetoothGatt>()
    private val connectedDevices = ConcurrentHashMap<String, BluetoothDevice>()
    private val deviceCallbacks = ConcurrentHashMap<String, BluetoothGattCallback>()

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "ble_peripheral_plugin/methods")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "ble_peripheral_plugin/events")
        eventChannel.setStreamHandler(this)

        bluetoothManager =
            appContext?.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        scanner = bluetoothAdapter?.bluetoothLeScanner
        logI("Plugin attached with multiple connection support")
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        stopAll()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        logI("Plugin detached")
    }

    // EventChannel
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // MethodChannel - UPDATED FOR MULTIPLE CONNECTIONS
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "startPeripheral" -> {
                    val serviceUuid = call.argument<String>("serviceUuid")!!
                    val txUuid = call.argument<String>("txUuid")!!
                    val rxUuid = call.argument<String>("rxUuid")!!
                    startPeripheral(serviceUuid, txUuid, rxUuid)
                    result.success(null)
                }

                "stopPeripheral" -> {
                    stopPeripheral()
                    result.success(null)
                }

                "sendNotification" -> {
                    val charUuid = call.argument<String>("charUuid")!!
                    val value = call.argument<ByteArray>("value")!!
                    sendNotification(charUuid, value)
                    result.success(null)
                }

                "startScan" -> {
                    val serviceUuid = call.argument<String>("serviceUuid")!!
                    startScan(serviceUuid)
                    result.success(null)
                }

                "stopScan" -> {
                    stopScan()
                    result.success(null)
                }

                "connect" -> {
                    val deviceId = call.argument<String>("deviceId")
                    connect(deviceId)
                    result.success(null)
                }

                "disconnect" -> {
                    val deviceId = call.argument<String>("deviceId")
                    disconnect(deviceId)
                    result.success(null)
                }

                "disconnectAll" -> {
                    disconnectAll()
                    result.success(null)
                }

                "writeCharacteristic" -> {
                    val deviceId = call.argument<String>("deviceId")
                    val charUuid = call.argument<String>("charUuid")!!
                    val value = call.argument<ByteArray>("value")!!
                    writeCharacteristic(deviceId, charUuid, value)
                    result.success(null)
                }

                "requestMtu" -> {
                    val deviceId = call.argument<String>("deviceId")
                    val mtu = call.argument<Int>("mtu") ?: MAX_MTU
                    requestMtu(deviceId, mtu)
                    result.success(null)
                }

                "getConnectedDevices" -> {
                    val devices = getConnectedDevices()
                    result.success(devices)
                }

                "isDeviceConnected" -> {
                    val deviceId = call.argument<String>("deviceId")
                    val isConnected = isDeviceConnected(deviceId)
                    result.success(isConnected)
                }

                "enableLogs" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    loggingEnabled = enable
                    result.success(null)
                }

                "isBluetoothOn" -> {
                    val isOn = bluetoothAdapter?.isEnabled ?: false
                    result.success(isOn)
                }

                "stopAll" -> {
                    stopAll()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("PLUGIN_ERROR", t.message, null)
        }
    }

    private fun validateInitialization() {
        if (bluetoothManager == null)
            bluetoothManager =
                appContext?.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        if (bluetoothAdapter == null)
            bluetoothAdapter = bluetoothManager?.adapter
        if (advertiser == null)
            advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        if (scanner == null)
            scanner = bluetoothAdapter?.bluetoothLeScanner
    }

    // ---------- Peripheral (GATT Server + Advertiser) ----------
    // (Unchanged from original)
    private fun startPeripheral(serviceUuidStr: String, txUuidStr: String, rxUuidStr: String) {
        validateInitialization();
        stopPeripheral()
        serverServiceUuid = UUID.fromString(serviceUuidStr)
        serverTxUuid = UUID.fromString(txUuidStr)
        serverRxUuid = UUID.fromString(rxUuidStr)

        gattServer = bluetoothManager?.openGattServer(appContext, gattServerCallback)
        if (gattServer == null) {
            sendEvent(mapOf("type" to "error", "message" to "Cannot open GATT server"))
            return
        }

        val service =
            BluetoothGattService(serverServiceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        txCharacteristic = BluetoothGattCharacteristic(
            serverTxUuid,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )

        val cccd = BluetoothGattDescriptor(
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"),
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
        )
        txCharacteristic?.addDescriptor(cccd)

        rxCharacteristic = BluetoothGattCharacteristic(
            serverRxUuid,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )

        service.addCharacteristic(txCharacteristic)
        service.addCharacteristic(rxCharacteristic)
        gattServer?.addService(service)

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .build()

        val dataBuilder = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(serverServiceUuid!!))

        val data = dataBuilder.build()

        advertiser?.startAdvertising(settings, data, advertiseCallback)
        sendEvent(mapOf("type" to "peripheral_started"))
        logI("Peripheral started: $serviceUuidStr")
    }

    private fun stopPeripheral() {
        try {
            advertiser?.stopAdvertising(advertiseCallback)
        } catch (ignored: Exception) {
        }
        try {
            gattServer?.close()
        } catch (ignored: Exception) {
        }
        gattServer = null
        txCharacteristic = null
        rxCharacteristic = null
        subscribers.clear()
        serverServiceUuid = null
        serverTxUuid = null
        serverRxUuid = null
        sendEvent(mapOf("type" to "peripheral_stopped"))
    }

    private fun sendNotification(charUuidStr: String, value: ByteArray) {
        if (gattServer == null) {
            logW("No gatt server to notify")
            return
        }
        val charUuid = UUID.fromString(charUuidStr)
        val characteristic = txCharacteristic
        if (characteristic == null || characteristic.uuid != charUuid) {
            logW("TX characteristic mismatch or missing")
            return
        }

        characteristic.value = value
        synchronized(subscribers) {
            for (dev in subscribers) {
                try {
                    gattServer?.notifyCharacteristicChanged(dev, characteristic, false)
                } catch (t: Throwable) {
                    logW("Failed notify to ${dev.address}: ${t.message}")
                }
            }
        }
    }

    // GATT Server callback (peripheral) - UNCHANGED
    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            logI("Server connection state change: ${device.address} -> $newState")
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                sendEvent(
                    mapOf(
                        "type" to "server_connected",
                        "deviceId" to device.address,
                        "name" to (device.name ?: "")
                    )
                )
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                sendEvent(mapOf("type" to "server_disconnected", "deviceId" to device.address))
                synchronized(subscribers) { subscribers.remove(device) }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            logI("Write request on server char ${characteristic.uuid} from ${device.address}")
            sendEvent(
                mapOf(
                    "type" to "rx",
                    "charUuid" to characteristic.uuid.toString(),
                    "value" to value,
                    "deviceId" to device.address
                )
            )
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            logI("Descriptor write on server: ${descriptor.uuid} from ${device.address}")
            if (descriptor.uuid == UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")) {
                val enable = value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                if (enable) {
                    synchronized(subscribers) { subscribers.add(device) }
                } else {
                    synchronized(subscribers) { subscribers.remove(device) }
                }
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            super.onMtuChanged(device, mtu)
            logI("Server MTU changed: ${device.address} -> $mtu")
            sendEvent(mapOf("type" to "mtu_changed", "deviceId" to device.address, "mtu" to mtu))
        }
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            logI("Advertising started")
            sendEvent(mapOf("type" to "advertising_started"))
        }

        override fun onStartFailure(errorCode: Int) {
            logE("Advertising failed: $errorCode")
            sendEvent(mapOf("type" to "advertising_failed", "code" to errorCode))
        }
    }

    // ---------- ENHANCED: Multiple Central Connections ----------

    @SuppressLint("MissingPermission")
    private fun startScan(serviceUuidStr: String) {
        try {
            val filter = ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(UUID.fromString(serviceUuidStr)))
                .build()
//            val settings = ScanSettings.Builder()
//                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
//                .build()
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
                .setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE)
                .setNumOfMatches(ScanSettings.MATCH_NUM_MAX_ADVERTISEMENT)
                .build()

            if (scanner == null) scanner = bluetoothAdapter?.bluetoothLeScanner
            scanner?.startScan(listOf(filter), settings, scanCallback)
            sendEvent(mapOf("type" to "scan_started"))
        } catch (t: Throwable) {
            logE("startScan error: ${t.message}")
            sendEvent(mapOf("type" to "scan_error", "message" to t.message))
        }
    }

    private fun stopScan() {
        try {
            scanner?.stopScan(scanCallback)
            sendEvent(mapOf("type" to "scan_stopped"))
        } catch (t: Throwable) {
            logW("stopScan error: ${t.message}")
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val dev = result.device
            logI("Scan result: ${dev.address} name=${dev.name ?: ""} rssi=${result.rssi}")
            sendEvent(
                mapOf(
                    "type" to "scanResult",
                    "deviceId" to dev.address,
                    "name" to (dev.name ?: ""),
                    "rssi" to result.rssi
                )
            )
        }

        override fun onScanFailed(errorCode: Int) {
            logE("Scan failed: $errorCode")
            sendEvent(mapOf("type" to "scan_failed", "code" to errorCode))
        }
    }

    // ✅ ENHANCED: Connect to specific device (multiple connections supported)
    @SuppressLint("MissingPermission")
    private fun connect(deviceId: String?) {
        if (deviceId == null) {
            logE("Connect called with null deviceId")
            return
        }

        // Check if already connected or connecting
        if (gattClients.containsKey(deviceId)) {
            logW("Already connected or connecting to $deviceId")
            return
        }

        try {
            val device = bluetoothAdapter?.getRemoteDevice(deviceId)
            if (device == null) {
                logE("Device not found: $deviceId")
                sendEvent(
                    mapOf(
                        "type" to "connectionFailed",
                        "deviceId" to deviceId,
                        "status" to "device_not_found"
                    )
                )
                return
            }

            logI("Attempting connection to: $deviceId")

            // Create unique callback for this device
            val callback = createGattClientCallback(deviceId)
            deviceCallbacks[deviceId] = callback

            val gatt = device.connectGatt(appContext, false, callback)
            gattClients[deviceId] = gatt
            connectedDevices[deviceId] = device

            sendEvent(mapOf("type" to "connecting", "deviceId" to deviceId))

        } catch (t: Throwable) {
            logE("connect error for $deviceId: ${t.message}")
            sendEvent(
                mapOf(
                    "type" to "connectionFailed",
                    "deviceId" to deviceId,
                    "message" to t.message
                )
            )
            // Cleanup on failure
            gattClients.remove(deviceId)
            connectedDevices.remove(deviceId)
            deviceCallbacks.remove(deviceId)
        }
    }

    // ✅ ENHANCED: Disconnect specific device
    @SuppressLint("MissingPermission")
    private fun disconnect(deviceId: String?) {
        if (deviceId == null) {
            logW("Disconnect called with null deviceId")
            return
        }

        try {
            val gatt = gattClients[deviceId]
            if (gatt != null) {
                try {
                    if (gatt.connect()) { // Check if still connected
                        gatt.disconnect()
                    }
                } catch (e: Exception) {
                    logW("Error during disconnect: ${e.message}")
                } finally {
                    gatt.close()
                }
            }
            if (gatt != null) {
                gattClients.remove(deviceId)
                connectedDevices.remove(deviceId)
                deviceCallbacks.remove(deviceId)
                logI("Disconnected from: $deviceId")
                sendEvent(mapOf("type" to "disconnected", "deviceId" to deviceId))
            } else {
                logW("No active connection to disconnect: $deviceId")
            }
        } catch (t: Throwable) {
            logW("disconnect error for $deviceId: ${t.message}")
        }
    }

    // ✅ NEW: Disconnect all central connections
    private fun disconnectAll() {
        logI("Disconnecting all central connections")
        val deviceIds = gattClients.keys.toList() // Copy to avoid modification during iteration
        for (deviceId in deviceIds) {
            disconnect(deviceId)
        }
    }

    // ✅ ENHANCED: Write to specific device
    @SuppressLint("MissingPermission")
    private fun writeCharacteristic(deviceId: String?, charUuidStr: String, value: ByteArray) {
        if (deviceId == null) {
            logE("writeCharacteristic called with null deviceId")
            return
        }

        try {
            val gatt = gattClients[deviceId]
            if (gatt == null) {
                logW("No GATT client for device: $deviceId")
                sendEvent(
                    mapOf(
                        "type" to "write_error",
                        "deviceId" to deviceId,
                        "message" to "Not connected"
                    )
                )
                return
            }

            val charUuid = UUID.fromString(charUuidStr)
            val target = gatt.services?.firstOrNull { svc ->
                svc.getCharacteristic(charUuid) != null
            }?.getCharacteristic(charUuid)

            if (target == null) {
                logW("Target characteristic not found: $charUuidStr for $deviceId")
                sendEvent(
                    mapOf(
                        "type" to "write_error",
                        "deviceId" to deviceId,
                        "message" to "Characteristic not found"
                    )
                )
                return
            }

            target.value = value
            target.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            gatt.writeCharacteristic(target)
            logI("Writing to characteristic $charUuidStr for device $deviceId")

        } catch (t: Throwable) {
            logE("writeCharacteristic error for $deviceId: ${t.message}")
            sendEvent(
                mapOf(
                    "type" to "write_error",
                    "deviceId" to deviceId,
                    "message" to t.message
                )
            )
        }
    }

    // ✅ ENHANCED: Request MTU for specific device
    @SuppressLint("MissingPermission")
    private fun requestMtu(deviceId: String?, mtu: Int) {
        if (deviceId == null) {
            logE("requestMtu called with null deviceId")
            return
        }

        try {
            val gatt = gattClients[deviceId]
            if (gatt != null) {
                gatt.requestMtu(mtu)
                logI("Requesting MTU: $mtu for device: $deviceId")
            } else {
                logW("Cannot request MTU - GATT client not connected for: $deviceId")
            }
        } catch (t: Throwable) {
            logE("requestMtu error for $deviceId: ${t.message}")
        }
    }

    // ✅ NEW: Get list of connected devices
    private fun getConnectedDevices(): List<String> {
        return gattClients.keys.toList()
    }

    // ✅ NEW: Check if specific device is connected
    private fun isDeviceConnected(deviceId: String?): Boolean {
        return deviceId != null && gattClients.containsKey(deviceId)
    }

    // ✅ ENHANCED: Create device-specific GATT callback
    private fun createGattClientCallback(deviceId: String): BluetoothGattCallback {
        return object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                logI("Client connection state for $deviceId: $newState, status: $status")

                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        sendEvent(
                            mapOf(
                                "type" to "connected",
                                "deviceId" to deviceId
                            )
                        )
                        gatt.discoverServices()
                    } else {
                        sendEvent(
                            mapOf(
                                "type" to "connectionFailed",
                                "deviceId" to deviceId,
                                "status" to status.toString()
                            )
                        )
                        // Cleanup failed connection
                        gattClients.remove(deviceId)
                        connectedDevices.remove(deviceId)
                        deviceCallbacks.remove(deviceId)
                    }
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    sendEvent(
                        mapOf(
                            "type" to "disconnected",
                            "deviceId" to deviceId,
                            "status" to status.toString()
                        )
                    )
                    // Cleanup disconnected device
                    gattClients.remove(deviceId)
                    connectedDevices.remove(deviceId)
                    deviceCallbacks.remove(deviceId)
                    gatt.close()
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                logI("Services discovered for $deviceId, status: $status")

                if (status == BluetoothGatt.GATT_SUCCESS) {
                    try {
                        // Subscribe to all notify characteristics
                        gatt.services.forEach { svc ->
                            svc.characteristics.forEach { c ->
                                if (c.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
                                    gatt.setCharacteristicNotification(c, true)
                                    val desc = c.getDescriptor(
                                        UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
                                    )
                                    desc?.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                                    desc?.let { gatt.writeDescriptor(it) }
                                    logI("Subscribed to ${c.uuid} for $deviceId")
                                }
                            }
                        }
                    } catch (t: Throwable) {
                        logW("Service discover error for $deviceId: ${t.message}")
                    }
                } else {
                    logE("Service discovery failed for $deviceId: $status")
                }
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic
            ) {
                logI("Characteristic changed for $deviceId: ${characteristic.uuid}")
                sendEvent(
                    mapOf(
                        "type" to "notification",
                        "deviceId" to deviceId,
                        "charUuid" to characteristic.uuid.toString(),
                        "value" to characteristic.value
                    )
                )
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                logI("Characteristic write result for $deviceId: ${characteristic.uuid} status=$status")
                sendEvent(
                    mapOf(
                        "type" to "write_result",
                        "deviceId" to deviceId,
                        "charUuid" to characteristic.uuid.toString(),
                        "status" to status
                    )
                )
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                super.onMtuChanged(gatt, mtu, status)
                logI("Client MTU changed for $deviceId: $mtu, status: $status")
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    sendEvent(
                        mapOf(
                            "type" to "mtu_changed",
                            "deviceId" to deviceId,
                            "mtu" to mtu
                        )
                    )
                } else {
                    sendEvent(
                        mapOf(
                            "type" to "mtu_change_failed",
                            "deviceId" to deviceId,
                            "status" to status
                        )
                    )
                }
            }
        }
    }

    // ---------- helpers ----------
    private fun sendEvent(payload: Map<String, Any?>) {
        appContext?.let {
            if (it is android.app.Activity) {
                it.runOnUiThread {
                    try {
                        eventSink?.success(payload)
                    } catch (t: Throwable) {
                        logW("sendEvent error: ${t.message}")
                    }
                }
            } else {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    try {
                        eventSink?.success(payload)
                    } catch (t: Throwable) {
                        logW("sendEvent error: ${t.message}")
                    }
                }
            }
        }
    }

    private fun stopAll() {
        stopScan()
        disconnectAll()
        stopPeripheral()
    }
}