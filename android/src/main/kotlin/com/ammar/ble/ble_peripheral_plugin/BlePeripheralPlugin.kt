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

class BlePeripheralPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val TAG = "BlePeripheralPlugin"
        private const val MAX_MTU = 512 // Set your desired MTU size
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

    // central (client) state
    private var gattClient: BluetoothGatt? = null
    private var connectedDevice: BluetoothDevice? = null

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
                "isBluetoothOn" -> {
                    val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
                    val enabled = bluetoothAdapter?.isEnabled == true
                    result.success(enabled)
                }
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

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("PLUGIN_ERROR", t.message, null)
        }
    }

    // ---------- Peripheral (GATT Server + Advertiser) ----------

    private fun startPeripheral(serviceUuidStr: String, txUuidStr: String, rxUuidStr: String) {
        stopPeripheral() // cleanup if any
        serverServiceUuid = UUID.fromString(serviceUuidStr)
        serverTxUuid = UUID.fromString(txUuidStr)
        serverRxUuid = UUID.fromString(rxUuidStr)

        // open GATT server
        gattServer = bluetoothManager?.openGattServer(appContext, gattServerCallback)
        if (gattServer == null) {
            sendEvent(mapOf("type" to "error", "message" to "Cannot open GATT server"))
            return
        }

        // create service and characteristics
        val service =
            BluetoothGattService(serverServiceUuid, BluetoothGattService.SERVICE_TYPE_PRIMARY)

        txCharacteristic = BluetoothGattCharacteristic(
            serverTxUuid,
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        // CCCD for notifications
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

        // start advertising
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .build()

        val dataBuilder = AdvertiseData.Builder()
            .setIncludeDeviceName(false) // keep advertisement small to avoid ADVERTISE_FAILED_DATA_TOO_LARGE
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
        // notify all subscribers we tracked via descriptor writes
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

    // GATT Server callback (peripheral)
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
            // send to Flutter as rx
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

        // Remove the problematic onMtuChanged method or fix its signature
        // The correct signature for onMtuChanged in BluetoothGattServerCallback is:
        // override fun onMtuChanged(device: BluetoothDevice, mtu: Int) { ... }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            super.onMtuChanged(device, mtu)
            logI("Server MTU changed: ${device.address} -> $mtu")
            setMtu(device, mtu)
        }
    }

    // Add this method to handle MTU changes in peripheral mode
    private fun setMtu(device: BluetoothDevice, mtu: Int) {
        // For peripheral mode, we need to handle MTU in the server callback
        logI("MTU changed for ${device.address}: $mtu")
        sendEvent(mapOf("type" to "mtu_changed", "deviceId" to device.address, "mtu" to mtu))
    }

    // Add this method to request MTU
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

    // Advertise callback
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

    // ---------- Central (scanner + gatt client) ----------

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
            // autoConnect = false
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
                // discover services
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
            // subscribe to notified characteristic if matches serverTxUuid
            try {
                // find characteristic in discovered services
                val targetCharUuid =
                    serverTxUuid // if connecting to our own server this may be set; otherwise user should use known UUIDs
                // subscribe to all characteristics that are notify-capable for demo
                gatt.services.forEach { svc ->
                    svc.characteristics.forEach { c ->
                        if (c.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) {
                            // enable notification locally
                            gatt.setCharacteristicNotification(c, true)
                            // write descriptor to enable on remote
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

        // Remove the problematic onConnectionStateChange method with wrong signature
        // The correct signature is already implemented above

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
                // fallback: use a Handler if appContext is not Activity
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
        disconnect()
        stopPeripheral()
    }
}