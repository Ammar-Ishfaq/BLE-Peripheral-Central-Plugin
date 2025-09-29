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

class BlePeripheralPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "BlePeripheralPlugin"
        private const val MAX_MTU = 512
        private const val ADVERTISING_SERVICE_UUID = "12345678-1234-5678-1234-56789abc0000"
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

    // 🆕 BITCHAT advertising state
    private var isAdvertisingData = false
    private var isScanningAdvertisements = false
    private val advertisementScanner: BluetoothLeScanner? by lazy { bluetoothAdapter?.bluetoothLeScanner }

    // peripheral (server) state
    private var gattServer: BluetoothGattServer? = null
    private var serverServiceUuid: UUID? = null
    private var serverTxUuid: UUID? = null
    private var serverRxUuid: UUID? = null
    private var txCharacteristic: BluetoothGattCharacteristic? = null
    private var rxCharacteristic: BluetoothGattCharacteristic? = null
    private val subscribers = mutableSetOf<BluetoothDevice>()

    // central (client) state
    private var gattClient: BluetoothGatt? = null
    private var connectedDevice: BluetoothDevice? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "ble_peripheral_plugin/methods")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "ble_peripheral_plugin/events")
        eventChannel.setStreamHandler(this)

        bluetoothManager = appContext?.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter
        advertiser = bluetoothAdapter?.bluetoothLeAdvertiser
        scanner = bluetoothAdapter?.bluetoothLeScanner
        logI("Plugin attached")
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

    // MethodChannel
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                // 🆕 BITCHAT advertising methods
                "startAdvertisingData" -> {
                    val data = call.argument<String>("data")!!
                    startAdvertisingData(data)
                    result.success(null)
                }

                "stopAdvertisingData" -> {
                    stopAdvertisingData()
                    result.success(null)
                }

                "startScanForAdvertisements" -> {
                    startScanForAdvertisements()
                    result.success(null)
                }

                "stopScanForAdvertisements" -> {
                    stopScanForAdvertisements()
                    result.success(null)
                }

                // Existing methods
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
                    disconnect()
                    result.success(null)
                }

                "writeCharacteristic" -> {
                    val charUuid = call.argument<String>("charUuid")!!
                    val value = call.argument<ByteArray>("value")!!
                    writeCharacteristic(charUuid, value)
                    result.success(null)
                }

                "requestMtu" -> {
                    val mtu = call.argument<Int>("mtu") ?: MAX_MTU
                    requestMtu(mtu)
                    result.success(null)
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

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("PLUGIN_ERROR", t.message, null)
        }
    }

    // 🆕 BITCHAT: Start advertising data
    @SuppressLint("MissingPermission")
    private fun startAdvertisingData(data: String) {
        stopAdvertisingData() // Stop any existing advertising

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false) // 🎯 BITCHAT: No connections!
            .build()

        val advertiseData = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(UUID.fromString(ADVERTISING_SERVICE_UUID)))
            .addServiceData(
                ParcelUuid(UUID.fromString(ADVERTISING_SERVICE_UUID)),
                data.toByteArray(Charsets.UTF_8)
            )
            .build()

        advertiser?.startAdvertising(settings, advertiseData, object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                logI("✅ Advertising data started: ${data.take(20)}...")
                isAdvertisingData = true
                sendEvent(mapOf("type" to "advertising_started"))
            }

            override fun onStartFailure(errorCode: Int) {
                logE("❌ Advertising failed: $errorCode")
                sendEvent(mapOf("type" to "advertising_failed", "code" to errorCode))
            }
        })
    }

    // 🆕 BITCHAT: Stop advertising data
    @SuppressLint("MissingPermission")
    private fun stopAdvertisingData() {
        if (isAdvertisingData) {
            try {
                advertiser?.stopAdvertising(object : AdvertiseCallback() {})
                isAdvertisingData = false
                logI("🛑 Advertising data stopped")
            } catch (e: Exception) {
                logW("Stop advertising error: ${e.message}")
            }
        }
    }

    // 🆕 BITCHAT: Scan for advertisements
    @SuppressLint("MissingPermission")
    private fun startScanForAdvertisements() {
        try {
            val filters = listOf(
                ScanFilter.Builder()
                    .setServiceUuid(ParcelUuid(UUID.fromString(ADVERTISING_SERVICE_UUID)))
                    .build()
            )

            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .setReportDelay(0)
                .build()

            advertisementScanner?.startScan(filters, settings, advertisementScanCallback)
            isScanningAdvertisements = true
            logI("🔍 Scanning for advertisements started")
            sendEvent(mapOf("type" to "ad_scan_started"))

        } catch (t: Throwable) {
            logE("Start advertisement scan error: ${t.message}")
            sendEvent(mapOf("type" to "ad_scan_error", "message" to t.message))
        }
    }

    // 🆕 BITCHAT: Stop scanning advertisements
    @SuppressLint("MissingPermission")
    private fun stopScanForAdvertisements() {
        try {
            advertisementScanner?.stopScan(advertisementScanCallback)
            isScanningAdvertisements = false
            logI("🛑 Advertisement scanning stopped")
            sendEvent(mapOf("type" to "ad_scan_stopped"))
        } catch (t: Throwable) {
            logW("Stop advertisement scan error: ${t.message}")
        }
    }

    // 🆕 BITCHAT: Advertisement scan callback
    private val advertisementScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            try {
                val scanRecord = result.scanRecord
                val serviceData = scanRecord?.serviceData
                val serviceUuid = ParcelUuid(UUID.fromString(ADVERTISING_SERVICE_UUID))

                serviceData?.get(serviceUuid)?.let { data ->
                    val message = String(data, Charsets.UTF_8)
                    val deviceId = result.device.address
                    val rssi = result.rssi

                    logI("📨 Received advertisement from $deviceId: ${message.take(30)}...")

                    sendEvent(mapOf(
                        "type" to "advertisement_received",
                        "data" to message,
                        "deviceId" to deviceId,
                        "rssi" to rssi
                    ))
                }
            } catch (t: Throwable) {
                logE("Advertisement parse error: ${t.message}")
            }
        }

        override fun onScanFailed(errorCode: Int) {
            logE("Advertisement scan failed: $errorCode")
            sendEvent(mapOf("type" to "ad_scan_failed", "code" to errorCode))
        }
    }

    // ---------- Existing Peripheral Methods ----------
    private fun startPeripheral(serviceUuidStr: String, txUuidStr: String, rxUuidStr: String) {
        stopPeripheral()
        serverServiceUuid = UUID.fromString(serviceUuidStr)
        serverTxUuid = UUID.fromString(txUuidStr)
        serverRxUuid = UUID.fromString(rxUuidStr)

        gattServer = bluetoothManager?.openGattServer(appContext, gattServerCallback)
        if (gattServer == null) {
            sendEvent(mapOf("type" to "error", "message" to "Cannot open GATT server"))
            return
        }

        val service = BluetoothGattService(serverServiceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)

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

    // ... (rest of existing GATT server/client code remains the same)
    // GATT Server callback, Advertise callback, Scan callback, etc.

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

    @SuppressLint("MissingPermission")
    private fun startScan(serviceUuidStr: String) {
        try {
            val filter = ScanFilter.Builder()
                .setServiceUuid(ParcelUuid(UUID.fromString(serviceUuidStr)))
                .build()
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()

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
            logI("Scan result: ${dev.address} name=${dev.name ?: ""}")
            sendEvent(
                mapOf(
                    "type" to "scanResult",
                    "deviceId" to dev.address,
                    "name" to (dev.name ?: "")
                )
            )
        }

        override fun onScanFailed(errorCode: Int) {
            logE("Scan failed: $errorCode")
            sendEvent(mapOf("type" to "scan_failed", "code" to errorCode))
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(deviceId: String?) {
        if (deviceId == null) return
        try {
            val device = bluetoothAdapter?.getRemoteDevice(deviceId) ?: return
            connectedDevice = device
            gattClient = device.connectGatt(appContext, false, gattClientCallback)
        } catch (t: Throwable) {
            logE("connect error: ${t.message}")
            sendEvent(mapOf("type" to "connect_error", "message" to t.message))
        }
    }

    private fun disconnect() {
        try {
            gattClient?.disconnect()
            gattClient?.close()
        } catch (t: Throwable) {
            logW("disconnect error: ${t.message}")
        } finally {
            gattClient = null
            connectedDevice = null
            sendEvent(mapOf("type" to "disconnected"))
        }
    }

    private val gattClientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            logI("Client connection state: $newState")
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                sendEvent(mapOf("type" to "connected", "deviceId" to (gatt.device?.address ?: "")))
                gatt.discoverServices()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                sendEvent(
                    mapOf(
                        "type" to "disconnected",
                        "deviceId" to (gatt.device?.address ?: "")
                    )
                )
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            logI("Services discovered")
            try {
                gatt.services.forEach { svc ->
                    svc.characteristics.forEach { c ->
                        if (c.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
                            gatt.setCharacteristicNotification(c, true)
                            val desc =
                                c.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))
                            desc?.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                            desc?.let { gatt.writeDescriptor(it) }
                            logI("Subscribed to ${c.uuid}")
                        }
                    }
                }
                gattClient = gatt
            } catch (t: Throwable) {
                logW("Service discover error: ${t.message}")
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic
        ) {
            logI("Characteristic changed: ${characteristic.uuid}")
            sendEvent(
                mapOf(
                    "type" to "notification",
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
            logI("Characteristic write result: ${characteristic.uuid} status=$status")
            sendEvent(
                mapOf(
                    "type" to "write_result",
                    "charUuid" to characteristic.uuid.toString(),
                    "status" to status
                )
            )
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            super.onMtuChanged(gatt, mtu, status)
            logI("Client MTU changed: $mtu, status: $status")
            if (status == BluetoothGatt.GATT_SUCCESS) {
                sendEvent(
                    mapOf(
                        "type" to "mtu_changed",
                        "deviceId" to gatt.device.address,
                        "mtu" to mtu
                    )
                )
            } else {
                sendEvent(
                    mapOf(
                        "type" to "mtu_change_failed",
                        "deviceId" to gatt.device.address,
                        "status" to status
                    )
                )
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun writeCharacteristic(charUuidStr: String, value: ByteArray) {
        try {
            val charUuid = UUID.fromString(charUuidStr)
            val target =
                gattClient?.services?.firstOrNull { svc -> svc.getCharacteristic(charUuid) != null }
                    ?.getCharacteristic(charUuid)
            if (target == null) {
                logW("Target characteristic not found to write: $charUuidStr")
                sendEvent(mapOf("type" to "write_error", "message" to "Characteristic not found"))
                return
            }
            target.value = value
            target.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            gattClient?.writeCharacteristic(target)
        } catch (t: Throwable) {
            logE("writeCharacteristic error: ${t.message}")
            sendEvent(mapOf("type" to "write_error", "message" to t.message))
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestMtu(mtu: Int) {
        try {
            if (gattClient != null) {
                gattClient?.requestMtu(mtu)
                logI("Requesting MTU: $mtu")
            } else {
                logW("Cannot request MTU - GATT client not connected")
            }
        } catch (t: Throwable) {
            logE("requestMtu error: ${t.message}")
        }
    }

    // ---------- helpers ----------
    private fun sendEvent(payload: Map<String, Any?>) {
        appContext?.let {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try {
                    eventSink?.success(payload)
                } catch (t: Throwable) {
                    logW("sendEvent error: ${t.message}")
                }
            }
        }
    }

    private fun stopAll() {
        stopAdvertisingData()
        stopScanForAdvertisements()
        stopScan()
        disconnect()
        stopPeripheral()
    }
}