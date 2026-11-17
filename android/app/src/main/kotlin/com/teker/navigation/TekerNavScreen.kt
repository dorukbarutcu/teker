package com.teker.navigation

import android.text.SpannableString
import android.text.Spanned
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.*
import androidx.car.app.navigation.model.*
import androidx.core.graphics.drawable.IconCompat
import java.util.concurrent.TimeUnit

class TekerNavScreen(
    carContext: CarContext
) : Screen(carContext) {

    private val renderer = TekerSurfaceRenderer(carContext)
    private val dataListener = { invalidate() }

    init {
        carContext.getCarService(AppManager::class.java).setSurfaceCallback(renderer)
        renderer.start()
        TekerDataBridge.addChangeListener(dataListener)

        lifecycle.addObserver(object : androidx.lifecycle.DefaultLifecycleObserver {
            override fun onDestroy(owner: androidx.lifecycle.LifecycleOwner) {
                TekerDataBridge.removeChangeListener(dataListener)
                renderer.stop()
            }
        })
    }

    override fun onGetTemplate(): Template {
        val maneuver = TekerDataBridge.currentManeuver
        val telemetry = TekerDataBridge.telemetry

        // 1. Üst Dönüş Yönlendirme Kartı (RoutingInfo)
        val stepBuilder = Step.Builder(
            if (maneuver.instruction.isNotEmpty()) maneuver.instruction else "Rotayı Takip Edin"
        )
        if (maneuver.streetName.isNotEmpty()) {
            stepBuilder.setCue(maneuver.streetName)
        }

        val carIcon = CarIcon.Builder(
            IconCompat.createWithResource(carContext, android.R.drawable.ic_menu_directions)
        ).build()

        val maneuverBuilder = Maneuver.Builder(
            when (maneuver.type) {
                2 -> Maneuver.TYPE_TURN_NORMAL_LEFT
                3 -> Maneuver.TYPE_TURN_NORMAL_RIGHT
                4 -> Maneuver.TYPE_ROUNDABOUT_ENTER_AND_EXIT_CW
                else -> Maneuver.TYPE_STRAIGHT
            }
        ).setIcon(carIcon)

        stepBuilder.setManeuver(maneuverBuilder.build())

        val distance = Distance.create(
            (maneuver.distanceMeters / 1000.0).coerceAtLeast(0.05),
            Distance.UNIT_KILOMETERS
        )

        val routingInfo = RoutingInfo.Builder()
            .setCurrentStep(stepBuilder.build(), distance)
            .build()

        // 2. Alt Bilgi Çubuğu (TravelEstimate)
        val estDist = Distance.create(
            (telemetry.remainingDistanceMeters / 1000.0).coerceAtLeast(0.1),
            Distance.UNIT_KILOMETERS
        )
        val estSeconds = telemetry.remainingSeconds.coerceAtLeast(60).toLong()
        val estMinutes = TimeUnit.SECONDS.toMinutes(estSeconds)
        val estHours = estMinutes / 60
        val remainingMin = estMinutes % 60

        val timeString = if (estHours > 0) "${estHours} sa ${remainingMin} dk" else "$remainingMin dk"
        val batteryText = "Batarya: %${telemetry.batteryPct} (${telemetry.remainingRangeKm.toInt()} km)"
        val fullInfoText = "$timeString • ${String.format("%.1f", telemetry.remainingDistanceMeters / 1000.0)} km • $batteryText"

        val travelEstimate = TravelEstimate.Builder(
            estDist,
            DateTimeWithZone.create(
                System.currentTimeMillis() + (estSeconds * 1000),
                java.util.TimeZone.getDefault()
            )
        )
            .setTripText(CarText.Builder(fullInfoText).build())
            .build()

        // 3. Harita Üzerindeki Eylem Butonları (MapActionStrip)
        val mapActionStrip = ActionStrip.Builder()
            .addAction(
                Action.Builder()
                    .setTitle("+")
                    .setOnClickListener { renderer.zoomIn() }
                    .build()
            )
            .addAction(
                Action.Builder()
                    .setTitle("-")
                    .setOnClickListener { renderer.zoomOut() }
                    .build()
            )
            .addAction(
                Action.Builder()
                    .setTitle("⌖")
                    .setOnClickListener { renderer.recenter() }
                    .build()
            )
            .addAction(
                Action.Builder()
                    .setTitle("⚡ Şarj")
                    .setOnClickListener {
                        screenManager.push(TekerChargingStationsScreen(carContext))
                    }
                    .build()
            )
            .build()

        return NavigationTemplate.Builder()
            .setNavigationInfo(routingInfo)
            .setDestinationTravelEstimate(travelEstimate)
            .setMapActionStrip(mapActionStrip)
            .build()
    }
}

/**
 * Android Auto Üzerinde Yakındaki Şarj İstasyonlarını Listeleyen Ekran
 */
class TekerChargingStationsScreen(
    carContext: CarContext
) : Screen(carContext) {

    override fun onGetTemplate(): Template {
        val pois = synchronized(TekerDataBridge.chargingStations) {
            TekerDataBridge.chargingStations.take(6)
        }

        val itemListBuilder = ItemList.Builder()
            .setNoItemsMessage("Yakında şarj istasyonu bulunamadı")

        for (poi in pois) {
            val distKm = poi.distanceMeters / 1000.0
            val subText = "${String.format("%.1f", distKm)} km mesafede • E-Bike Uyumlu"

            itemListBuilder.addItem(
                Row.Builder()
                    .setTitle(poi.name)
                    .addText(subText)
                    .setOnClickListener {
                        TekerDataBridge.selectChargingWaypoint(poi)
                        screenManager.pop()
                    }
                    .build()
            )
        }

        return PlaceListNavigationTemplate.Builder()
            .setTitle("Yakındaki Şarj İstasyonları")
            .setItemList(itemListBuilder.build())
            .setHeaderAction(Action.BACK)
            .build()
    }
}
