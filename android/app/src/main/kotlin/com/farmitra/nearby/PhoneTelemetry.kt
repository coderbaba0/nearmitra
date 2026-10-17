package com.farmitra.nearby

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel

/** One foreground, explicitly approved snapshot; never starts background tracking. */
class PhoneTelemetry(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var dialog: AlertDialog? = null
    private var cancellation: CancellationSignal? = null
    private var timeout: Runnable? = null
    private val permissionCode = 7824

    fun request(peer: String, result: MethodChannel.Result) {
        if (pending != null) { result.error("BUSY", "A sensor sharing request is already open", null); return }
        if (activity.isFinishing || activity.isDestroyed || !activity.hasWindowFocus()) {
            result.error("FOREGROUND_REQUIRED", "Open NearMitra on the phone to approve sensor sharing", null); return
        }
        pending = result
        dialog = AlertDialog.Builder(activity)
            .setTitle("Nearby sensor request")
            .setMessage("$peer requests this phone's battery and location. Share a single reading?")
            .setPositiveButton("Battery + location") { _, _ -> requestLocationPermission() }
            .setNeutralButton("Battery only") { _, _ -> finish(snapshot().apply { put("location_status", "Location was not shared") }) }
            .setNegativeButton("Decline") { _, _ -> reject("Phone owner declined sensor sharing") }
            .setOnCancelListener { reject("Phone owner cancelled sensor sharing") }
            .show()
        timeout = Runnable { reject("Sensor sharing request timed out") }.also { handler.postDelayed(it, 35000) }
    }

    private fun requestLocationPermission() {
        if (activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), permissionCode)
        } else readLocation()
    }
    fun onPermissionsResult(code: Int): Boolean {
        if (code != permissionCode) return false
        if (pending != null) readLocation()
        return true
    }
    private fun snapshot(): MutableMap<String, Any> {
        val data = mutableMapOf<String, Any>()
        val battery = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (battery != null) {
            val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            if (level >= 0 && scale > 0) {
                val status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                val values = mutableMapOf<String, Any>("level" to level * 100.0 / scale,
                    "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL))
                if (battery.hasExtra(BatteryManager.EXTRA_TEMPERATURE)) values["temp"] = battery.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) / 10.0
                data["battery"] = values
            }
        }
        return data
    }
    @Suppress("MissingPermission")
    private fun readLocation() {
        val data = snapshot()
        if (activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            data["location_status"] = "Location permission was not granted"; finish(data); return
        }
        try {
            val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val providers = manager.getProviders(true)
            val provider = if (providers.contains(LocationManager.GPS_PROVIDER)) LocationManager.GPS_PROVIDER else providers.firstOrNull()
            if (provider == null) {data["location_status"] = "Enable location on the phone"; finish(data); return}
            fun accept(location: Location?) {
                if (pending == null) return
                if (location != null && SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos in 0..60_000_000_000L) {
                    data["gps"] = mapOf("lat" to location.latitude, "lng" to location.longitude,
                        "alt" to location.altitude, "accuracy" to location.accuracy.toDouble())
                } else data["location_status"] = "No recent location fix; try again outdoors"
                finish(data)
            }
            if (Build.VERSION.SDK_INT >= 30) {
                timeout?.let {handler.removeCallbacks(it)}
                cancellation = CancellationSignal()
                timeout = Runnable { cancellation?.cancel(); accept(null) }.also {handler.postDelayed(it, 8000)}
                manager.getCurrentLocation(provider, cancellation, activity.mainExecutor) { location -> accept(location) }
            } else accept(manager.getLastKnownLocation(provider))
        } catch (error: Exception) { data["location_status"] = error.message ?: "Location unavailable"; finish(data) }
    }
    private fun finish(data: Map<String, Any>) {
        val result = pending ?: return
        pending = null; timeout?.let {handler.removeCallbacks(it)}; cancellation?.cancel(); cancellation = null
        dialog?.dismiss(); dialog = null; result.success(data)
    }
    private fun reject(message: String) {
        val result = pending ?: return
        pending = null; timeout?.let {handler.removeCallbacks(it)}; cancellation?.cancel(); cancellation = null
        dialog?.dismiss(); dialog = null; result.error("SENSOR_SHARING", message, null)
    }
    fun close() { reject("Phone screen closed before sharing completed") }
}
