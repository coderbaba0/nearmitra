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
import android.location.LocationListener
import android.os.Bundle
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
    private val cancellations = mutableListOf<CancellationSignal>()
    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null
    private var generation = 0
    private var timeout: Runnable? = null
    private val permissionCode = 7824

    fun request(peer: String, result: MethodChannel.Result) {
        if (pending != null) { result.error("BUSY", "A sensor sharing request is already open", null); return }
        if (activity.isFinishing || activity.isDestroyed || !activity.hasWindowFocus()) {
            result.error("FOREGROUND_REQUIRED", "Open NearMitra on the phone to approve sensor sharing", null); return
        }
        pending = result
        generation++
        dialog = AlertDialog.Builder(activity)
            .setTitle("Nearby sensor request")
            .setMessage("$peer requests this phone's battery and location. Share a single reading?")
            .setPositiveButton("Battery + location") { _, _ -> requestLocationPermission() }
            .setNeutralButton("Battery only") { _, _ -> finish(snapshot().apply { put("location_status", "Location was not shared") }) }
            .setNegativeButton("Decline") { _, _ -> reject("Phone owner declined sensor sharing") }
            .setOnCancelListener { reject("Phone owner cancelled sensor sharing") }
            .show()
        timeout = Runnable { reject("Sensor sharing request timed out") }.also { handler.postDelayed(it, 60000) }
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
        val requestGeneration = generation
        val fine = activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine && activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            data["location_status"] = "Location permission was not granted"; finish(data); return
        }
        try {
            val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            locationManager = manager
            val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
                .filter { manager.isProviderEnabled(it) && (fine || it != LocationManager.GPS_PROVIDER) }
            if (providers.isEmpty()) { data["location_status"] = "Enable phone Location services; no permitted provider is available"; finish(data); return }
            fun recent(location: Location?): Boolean = location != null &&
                SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos in 0..60_000_000_000L
            fun accept(location: Location) {
                if (pending == null || generation != requestGeneration) return
                data["gps"] = mapOf("lat" to location.latitude, "lng" to location.longitude,
                    "alt" to location.altitude, "accuracy" to location.accuracy.toDouble())
                data["location_status"] = if (fine) "Phone location received" else "Approximate phone location received"
                finish(data)
            }
            val cached = providers.mapNotNull { provider ->
                try { manager.getLastKnownLocation(provider) } catch (_: Exception) { null }
            }.filter { recent(it) }.minByOrNull { if (it.hasAccuracy()) it.accuracy else Float.MAX_VALUE }
            if (cached != null) { accept(cached); return }
            timeout?.let { handler.removeCallbacks(it) }
            timeout = Runnable {
                if (pending != null && generation == requestGeneration) {
                    data["location_status"] = "Location allowed, but no fresh GPS/network fix arrived. Keep Location enabled and retry near a window or outdoors."
                    finish(data)
                }
            }.also { handler.postDelayed(it, 20000) }
            if (Build.VERSION.SDK_INT >= 30) {
                var started = 0
                for (provider in providers) {
                    try {
                        val signal = CancellationSignal(); cancellations.add(signal)
                        manager.getCurrentLocation(provider, signal, activity.mainExecutor) { location ->
                            if (recent(location)) accept(location!!)
                        }
                        started++
                    } catch (_: Exception) { /* Try the other permitted provider. */ }
                }
                if (started == 0) { data["location_status"] = "Phone location providers could not start; check Location settings"; finish(data) }
            } else {
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) { if (recent(location)) accept(location) }
                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                    @Deprecated("Legacy provider callback")
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                }
                locationListener = listener
                var started = 0
                for (provider in providers) {
                    try { manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper()); started++ }
                    catch (_: Exception) { }
                }
                if (started == 0) { data["location_status"] = "Phone location providers could not start"; finish(data) }
            }
        } catch (error: Exception) { data["location_status"] = error.message ?: "Location unavailable"; finish(data) }
    }
    private fun clearLocationRequest() {
        cancellations.forEach { it.cancel() }; cancellations.clear()
        locationListener?.let { listener -> try { locationManager?.removeUpdates(listener) } catch (_: Exception) {} }
        locationListener = null; locationManager = null
    }
    private fun finish(data: Map<String, Any>) {
        val result = pending ?: return
        pending = null; timeout?.let {handler.removeCallbacks(it)}; clearLocationRequest()
        dialog?.dismiss(); dialog = null; result.success(data)
    }
    private fun reject(message: String) {
        val result = pending ?: return
        pending = null; timeout?.let {handler.removeCallbacks(it)}; clearLocationRequest()
        dialog?.dismiss(); dialog = null; result.error("SENSOR_SHARING", message, null)
    }
    fun close() { reject("Phone screen closed before sharing completed") }
}
