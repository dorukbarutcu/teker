package com.teker.navigation

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

data class LatLng(val latitude: Double, val longitude: Double)

data class RoutePoint(
    val lat: Double,
    val lon: Double,
    val elevation: Double = 0.0
)

data class CustomMarker(
    val id: String,
    val title: String,
    val category: String,
    val lat: Double,
    val lon: Double
)

data class ChargingStationPoi(
    val id: String,
    val name: String,
    val lat: Double,
    val lon: Double,
    val distanceMeters: Double = 0.0,
    val isRepairStation: Boolean = false
)

data class ManeuverInfo(
    val instruction: String = "",
    val streetName: String = "",
    val distanceMeters: Double = 0.0,
    val type: Int = 1 // 1: straight, 2: left, 3: right, etc.
)

data class TelemetryData(
    val speedKmh: Double = 0.0,
    val batteryPct: Int = 100,
    val remainingRangeKm: Double = 50.0,
    val altitudeMeters: Double = 0.0,
    val remainingDistanceMeters: Double = 0.0,
    val remainingSeconds: Int = 0,
    val assistMode: String = "Tour"
)

object TekerDataBridge {
    private val mainHandler = Handler(Looper.getMainLooper())

    // Anlık Konum
    var currentLat: Double = 36.795 // Varsayılan Mersin Sahil
    var currentLon: Double = 34.618
    var currentBearing: Float = 0.0f
    var currentSpeedKmh: Double = 0.0
    var currentAltitude: Double = 5.0

    // Rota Bilgisi
    val routePoints = mutableListOf<RoutePoint>()
    val customMarkers = mutableListOf<CustomMarker>()
    val chargingStations = mutableListOf<ChargingStationPoi>()
    var currentManeuver = ManeuverInfo()
    var telemetry = TelemetryData()

    // Flutter Kanalları
    var assistantChannel: MethodChannel? = null
    var telemetryChannel: MethodChannel? = null

    // Dinleyiciler (Android Auto Surface & Ekran Yenileme)
    private val changeListeners = mutableListOf<() -> Unit>()

    fun addChangeListener(listener: () -> Unit) {
        synchronized(changeListeners) {
            changeListeners.add(listener)
        }
    }

    fun removeChangeListener(listener: () -> Unit) {
        synchronized(changeListeners) {
            changeListeners.remove(listener)
        }
    }

    fun notifyChanged() {
        mainHandler.post {
            synchronized(changeListeners) {
                changeListeners.forEach { it.invoke() }
            }
        }
    }

    fun updateLocation(lat: Double, lon: Double, bearing: Float, speedKmh: Double, altitude: Double) {
        currentLat = lat
        currentLon = lon
        currentBearing = bearing
        currentSpeedKmh = speedKmh
        currentAltitude = altitude
        notifyChanged()
    }

    fun setRoute(points: List<RoutePoint>) {
        synchronized(routePoints) {
            routePoints.clear()
            routePoints.addAll(points)
        }
        notifyChanged()
    }

    fun addCustomMarker(marker: CustomMarker) {
        synchronized(customMarkers) {
            customMarkers.removeAll { it.id == marker.id }
            customMarkers.add(marker)
        }
        notifyChanged()
    }

    fun clearCustomMarkers() {
        synchronized(customMarkers) {
            customMarkers.clear()
        }
        notifyChanged()
    }

    fun setChargingStations(list: List<ChargingStationPoi>) {
        synchronized(chargingStations) {
            chargingStations.clear()
            chargingStations.addAll(list)
        }
        notifyChanged()
    }

    fun updateManeuver(instruction: String, streetName: String, distanceMeters: Double, type: Int) {
        currentManeuver = ManeuverInfo(instruction, streetName, distanceMeters, type)
        notifyChanged()
    }

    fun updateTelemetry(speedKmh: Double, batteryPct: Int, remainingRangeKm: Double, altitudeMeters: Double, remainingDistanceMeters: Double, remainingSeconds: Int, assistMode: String) {
        telemetry = TelemetryData(
            speedKmh = speedKmh,
            batteryPct = batteryPct,
            remainingRangeKm = remainingRangeKm,
            altitudeMeters = altitudeMeters,
            remainingDistanceMeters = remainingDistanceMeters,
            remainingSeconds = remainingSeconds,
            assistMode = assistMode
        )
        notifyChanged()
    }

    fun dispatchAssistantIntent(action: String, params: Map<String, Any?>) {
        mainHandler.post {
            val payload = HashMap(params)
            payload["action"] = action
            assistantChannel?.invokeMethod("onAssistantCommand", payload)
        }
    }

    fun selectChargingWaypoint(station: ChargingStationPoi) {
        mainHandler.post {
            val map = mapOf(
                "action" to "addChargingWaypoint",
                "id" to station.id,
                "name" to station.name,
                "lat" to station.lat,
                "lon" to station.lon
            )
            assistantChannel?.invokeMethod("onAssistantCommand", map)
        }
    }
}
