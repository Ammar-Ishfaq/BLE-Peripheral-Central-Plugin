package com.ammar.ble.ble_peripheral_plugin

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.*
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.*

import java.util.*

class BleBroadcastPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var ctx: Context
    private lateinit var m: MethodChannel
    private lateinit var e: EventChannel
    private var sink: EventChannel.EventSink? = null

    private var adapter: BluetoothAdapter? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var scanner: BluetoothLeScanner? = null
    private var advCallback: AdvertiseCallback? = null
    private var scanCallback: ScanCallback? = null
    private var logging = true
    private val serviceUuid = ParcelUuid(UUID.fromString("0000feed-0000-1000-8000-00805f9b34fb"))

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ctx = binding.applicationContext
        m = MethodChannel(binding.binaryMessenger, "ble_broadcast/methods")
        e = EventChannel(binding.binaryMessenger, "ble_broadcast/events")
        m.setMethodCallHandler(this)
        e.setStreamHandler(this)

        val mgr = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        adapter = mgr.adapter
        advertiser = adapter?.bluetoothLeAdvertiser
        scanner = adapter?.bluetoothLeScanner
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopAdvertising()
        stopScanning()
        m.setMethodCallHandler(null)
        e.setStreamHandler(null)
    }

    override fun onListen(args: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(args: Any?) { sink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {

            "startAdvertising" -> {
                val payload = call.argument<ByteArray>("payload")
                if (payload == null) {
                    result.error("ARG_ERROR", "payload is null", null)
                } else {
                    startAdvertising(payload)
                    result.success(null)
                }
            }

            "stopAdvertising" -> {
                stopAdvertising()
                result.success(null)
            }

            "startScanning" -> {
                startScanning()
                result.success(null)
            }

            "stopScanning" -> {
                stopScanning()
                result.success(null)
            }

            "isBluetoothOn" -> {
                result.success(adapter?.isEnabled ?: false)
            }

            "enableLogs" -> {
                logging = call.argument<Boolean>("enable") ?: true
                result.success(null)
            }

            else -> {
                result.notImplemented()
            }
        }
    }


    private fun log(s: String) { if (logging) Log.d("BLE_BROADCAST", s) }

    @SuppressLint("MissingPermission")
    private fun startAdvertising(payload: ByteArray) {
        stopAdvertising()
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false).build()
        val data = AdvertiseData.Builder()
            .addServiceUuid(serviceUuid)
            .addServiceData(serviceUuid, payload)
            .build()

        advCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(s: AdvertiseSettings?) = log("Advertising started")
            override fun onStartFailure(errorCode: Int) = log("Adv failed: $errorCode")
        }
        advertiser?.startAdvertising(settings, data, advCallback)
    }

    @SuppressLint("MissingPermission")
    private fun stopAdvertising() {
        advCallback?.let { advertiser?.stopAdvertising(it) }
        advCallback = null
    }

    @SuppressLint("MissingPermission")
    private fun startScanning() {
        stopScanning()
        val filter = ScanFilter.Builder().setServiceUuid(serviceUuid).build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanCallback = object : ScanCallback() {
            override fun onScanResult(type: Int, res: ScanResult) {
                res.scanRecord?.getServiceData(serviceUuid)?.let {
                    sink?.success(mapOf("type" to "advertisement", "deviceId" to res.device.address, "data" to it))
                }
            }
        }
        scanner?.startScan(listOf(filter), settings, scanCallback)
    }

    private fun stopScanning() {
        scanCallback?.let { scanner?.stopScan(it) }
        scanCallback = null
    }
}
