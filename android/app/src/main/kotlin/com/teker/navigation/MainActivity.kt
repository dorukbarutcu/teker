package com.teker.navigation

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val assistantChannelName = "com.teker.navigation/assistant"
    private val telemetryChannelName = "com.teker.navigation/telemetry"

    private var assistantChannel: MethodChannel? = null
    private var telemetryChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Asistan Kanalı
        assistantChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, assistantChannelName)
        TekerDataBridge.assistantChannel = assistantChannel

        // Telemetri ve Veri Senkronizasyon Kanalı
        telemetryChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, telemetryChannelName)
        TekerDataBridge.telemetryChannel = telemetryChannel

        telemetryChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateLocation" -> {
                    val lat = call.argument<Double>("lat") ?: 0.0
                    val lon = call.argument<Double>("lon") ?: 0.0
                    val bearing = (call.argument<Double>("bearing") ?: 0.0).toFloat()
                    val speed = call.argument<Double>("speed") ?: 0.0
                    val altitude = call.argument<Double>("altitude") ?: 0.0
                    TekerDataBridge.updateLocation(lat, lon, bearing, speed, altitude)
                    result.success(true)
                }
                "setRoute" -> {
                    val list = call.argument<List<Map<String, Any>>>("points") ?: emptyList()
                    val routePoints = list.map {
                        RoutePoint(
                            lat = (it["lat"] as? Number)?.toDouble() ?: 0.0,
                            lon = (it["lon"] as? Number)?.toDouble() ?: 0.0,
                            elevation = (it["ele"] as? Number)?.toDouble() ?: 0.0
                        )
                    }
                    TekerDataBridge.setRoute(routePoints)
                    result.success(true)
                }
                "updateManeuver" -> {
                    val instruction = call.argument<String>("instruction") ?: ""
                    val streetName = call.argument<String>("streetName") ?: ""
                    val distanceMeters = call.argument<Double>("distanceMeters") ?: 0.0
                    val type = call.argument<Int>("type") ?: 1
                    TekerDataBridge.updateManeuver(instruction, streetName, distanceMeters, type)
                    result.success(true)
                }
                "updateTelemetry" -> {
                    val speedKmh = call.argument<Double>("speedKmh") ?: 0.0
                    val batteryPct = call.argument<Int>("batteryPct") ?: 100
                    val remainingRangeKm = call.argument<Double>("remainingRangeKm") ?: 0.0
                    val altitudeMeters = call.argument<Double>("altitudeMeters") ?: 0.0
                    val remainingDistanceMeters = call.argument<Double>("remainingDistanceMeters") ?: 0.0
                    val remainingSeconds = call.argument<Int>("remainingSeconds") ?: 0
                    val assistMode = call.argument<String>("assistMode") ?: "Tour"
                    TekerDataBridge.updateTelemetry(
                        speedKmh, batteryPct, remainingRangeKm, altitudeMeters,
                        remainingDistanceMeters, remainingSeconds, assistMode
                    )
                    result.success(true)
                }
                "setChargingStations" -> {
                    val list = call.argument<List<Map<String, Any>>>("stations") ?: emptyList()
                    val pois = list.map {
                        ChargingStationPoi(
                            id = it["id"] as? String ?: "",
                            name = it["name"] as? String ?: "Şarj İstasyonu",
                            lat = (it["lat"] as? Number)?.toDouble() ?: 0.0,
                            lon = (it["lon"] as? Number)?.toDouble() ?: 0.0,
                            distanceMeters = (it["distance"] as? Number)?.toDouble() ?: 0.0,
                            isRepairStation = it["isRepair"] as? Boolean ?: false
                        )
                    }
                    TekerDataBridge.setChargingStations(pois)
                    result.success(true)
                }
                "addCustomMarker" -> {
                    val id = call.argument<String>("id") ?: System.currentTimeMillis().toString()
                    val title = call.argument<String>("title") ?: ""
                    val category = call.argument<String>("category") ?: ""
                    val lat = call.argument<Double>("lat") ?: 0.0
                    val lon = call.argument<Double>("lon") ?: 0.0
                    TekerDataBridge.addCustomMarker(CustomMarker(id, title, category, lat, lon))
                    result.success(true)
                }
                "clearCustomMarkers" -> {
                    TekerDataBridge.clearCustomMarkers()
                    result.success(true)
                }
                "startForegroundService" -> {
                    val fineGranted = androidx.core.content.ContextCompat.checkSelfPermission(
                        this, android.Manifest.permission.ACCESS_FINE_LOCATION
                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                    val coarseGranted = androidx.core.content.ContextCompat.checkSelfPermission(
                        this, android.Manifest.permission.ACCESS_COARSE_LOCATION
                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED

                    if (fineGranted || coarseGranted) {
                        try {
                            val intent = Intent(this, TekerLocationService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "stopForegroundService" -> {
                    stopService(Intent(this, TekerLocationService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Açılış intent'ini incele
        intent?.let { handleAppActionIntent(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAppActionIntent(intent)
    }

    private fun handleAppActionIntent(intent: Intent) {
        val action = intent.action ?: return
        val extras = intent.extras
        val data = intent.data

        val params = mutableMapOf<String, Any?>()
        if (data != null) {
            params["data_uri"] = data.toString()
            if (data.scheme == "geo") {
                params["geo_uri"] = data.toString()
            }
            data.queryParameterNames.forEach { name ->
                params[name] = data.getQueryParameter(name)
            }
        }
        if (extras != null) {
            for (key in extras.keySet()) {
                params[key] = extras.get(key)
            }
        }

        val actionType = extras?.getString("action_type")
            ?: data?.getQueryParameter("action_type")
            ?: action

        TekerDataBridge.dispatchAssistantIntent(actionType, params)
    }
}
