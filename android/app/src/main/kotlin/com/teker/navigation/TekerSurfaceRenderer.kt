package com.teker.navigation

import android.content.Context
import android.graphics.*
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import androidx.car.app.AppManager
import androidx.car.app.CarContext
import androidx.car.app.SurfaceCallback
import androidx.car.app.SurfaceContainer
import java.io.File
import java.io.FileInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlin.math.*

class TekerSurfaceRenderer(
    private val carContext: CarContext
) : SurfaceCallback {

    private val tag = "TekerSurfaceRenderer"

    private var activeSurface: Surface? = null
    private var surfaceWidth = 800
    private var surfaceHeight = 480
    private var isRendering = false

    // Harita Kamera Durumu
    private var zoomLevel = 16.0
    private var panOffsetX = 0f
    private var panOffsetY = 0f
    private var isTrackingUser = true

    // Arka Plan Çizim İş Parçacığı
    private var renderThread: HandlerThread? = null
    private var renderHandler: Handler? = null

    // Karo İndirme ve Bellek Önbelleği
    private val tileExecutor = Executors.newFixedThreadPool(4)
    private val memoryTileCache = ConcurrentHashMap<String, Bitmap>()
    private val failedTiles = ConcurrentHashMap<String, Long>()

    // Çizim Nesneleri (Garbage Collector yükünü azaltmak için önceden tanımlı)
    private val bgPaint = Paint().apply { isAntiAlias = true }
    private val routePaint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.STROKE
        strokeWidth = 14f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        color = Color.parseColor("#00BCD4") // Cyan rota
    }
    private val climbPaint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.STROKE
        strokeWidth = 15f
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        color = Color.parseColor("#FF5722") // Dik yokuş turuncu
    }
    private val bikeMarkerPaint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.FILL
        color = Color.parseColor("#00E676") // Bisiklet Yeşil
    }
    private val bikeHeadingPaint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.FILL
        color = Color.WHITE
    }
    private val pulsePaint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.STROKE
        strokeWidth = 4f
        color = Color.parseColor("#8000E676")
    }
    private val textPaint = Paint().apply {
        isAntiAlias = true
        textSize = 28f
        typeface = Typeface.DEFAULT_BOLD
        color = Color.WHITE
        setShadowLayer(4f, 2f, 2f, Color.BLACK)
    }
    private val pinPaint = Paint().apply {
        isAntiAlias = true
        style = Paint.Style.FILL
    }

    private val dataListener = { requestRender() }

    fun start() {
        renderThread = HandlerThread("TekerRenderThread").apply { start() }
        renderHandler = Handler(renderThread!!.looper)
        TekerDataBridge.addChangeListener(dataListener)
    }

    fun stop() {
        TekerDataBridge.removeChangeListener(dataListener)
        isRendering = false
        renderThread?.quitSafely()
        renderThread = null
        renderHandler = null
        memoryTileCache.clear()
    }

    override fun onSurfaceAvailable(surfaceContainer: SurfaceContainer) {
        Log.d(tag, "onSurfaceAvailable: ${surfaceContainer.surface}")
        activeSurface = surfaceContainer.surface
        surfaceWidth = surfaceContainer.width.coerceAtLeast(400)
        surfaceHeight = surfaceContainer.height.coerceAtLeast(300)
        isRendering = true
        requestRender()
    }

    override fun onSurfaceDestroyed(surfaceContainer: SurfaceContainer) {
        Log.d(tag, "onSurfaceDestroyed")
        isRendering = false
        activeSurface = null
    }

    override fun onVisibleAreaChanged(visibleArea: Rect) {
        requestRender()
    }

    override fun onStableAreaChanged(stableArea: Rect) {
        requestRender()
    }

    override fun onScroll(distanceX: Float, distanceY: Float) {
        // Kullanıcı haritayı kaydırdığında merkezleme serbest bırakılır
        isTrackingUser = false
        panOffsetX -= distanceX
        panOffsetY -= distanceY
        requestRender()
    }

    override fun onScale(focusX: Float, focusY: Float, scaleFactor: Float) {
        if (scaleFactor > 1.0f) {
            zoomLevel = (zoomLevel + 0.15).coerceAtMost(19.0)
        } else if (scaleFactor < 1.0f) {
            zoomLevel = (zoomLevel - 0.15).coerceAtLeast(8.0)
        }
        requestRender()
    }

    fun zoomIn() {
        zoomLevel = (zoomLevel + 1.0).coerceAtMost(19.0)
        requestRender()
    }

    fun zoomOut() {
        zoomLevel = (zoomLevel - 1.0).coerceAtLeast(8.0)
        requestRender()
    }

    fun recenter() {
        isTrackingUser = true
        panOffsetX = 0f
        panOffsetY = 0f
        requestRender()
    }

    fun requestRender() {
        if (!isRendering || activeSurface == null) return
        renderHandler?.post {
            renderFrame()
        }
    }

    private fun renderFrame() {
        val surface = activeSurface ?: return
        if (!surface.isValid) return

        var canvas: Canvas? = null
        try {
            canvas = surface.lockCanvas(null)
            if (canvas != null) {
                drawScene(canvas)
            }
        } catch (e: Exception) {
            Log.e(tag, "Render hatası: ${e.message}")
        } finally {
            if (canvas != null) {
                try {
                    surface.unlockCanvasAndPost(canvas)
                } catch (e: Exception) {
                    Log.e(tag, "unlockCanvasAndPost hatası: ${e.message}")
                }
            }
        }
    }

    private fun drawScene(canvas: Canvas) {
        val isDark = carContext.isDarkMode
        val currentLat = TekerDataBridge.currentLat
        val currentLon = TekerDataBridge.currentLon
        val bearing = TekerDataBridge.currentBearing

        // 1. Arka planı temizle
        bgPaint.color = if (isDark) Color.parseColor("#121820") else Color.parseColor("#E8ECEF")
        canvas.drawRect(0f, 0f, surfaceWidth.toFloat(), surfaceHeight.toFloat(), bgPaint)

        // Merkez ekran koordinatı
        val centerX = surfaceWidth / 2f + (if (isTrackingUser) 0f else panOffsetX)
        val centerY = surfaceHeight / 2f + (if (isTrackingUser) 0f else panOffsetY)

        // Haritayı sürüş yönüne göre döndürmek için canvas pivot dönüşü
        canvas.save()
        if (isTrackingUser && bearing != 0f) {
            canvas.rotate(-bearing, centerX, centerY)
        }

        // 2. Harita Karolarını Çiz
        drawTiles(canvas, currentLat, currentLon, centerX, centerY, zoomLevel.toInt())

        // 3. Aktif Bisiklet Rotasını Çiz
        drawRoute(canvas, currentLat, currentLon, centerX, centerY)

        // 4. Şarj İstasyonları ve Bakım Noktalarını Çiz
        drawPois(canvas, currentLat, currentLon, centerX, centerY)

        // 5. Sesli Komut / Gemini ile Eklenen Özel Pinleri Çiz
        drawCustomMarkers(canvas, currentLat, currentLon, centerX, centerY)

        // 6. Bisiklet Sürücü İmlecini Çiz (Merkezde)
        drawUserCursor(canvas, centerX, centerY, if (isTrackingUser) 0f else bearing)

        canvas.restore()
    }

    private fun drawTiles(canvas: Canvas, centerLat: Double, centerLon: Double, centerX: Float, centerY: Float, z: Int) {
        val n = 1 shl z
        val centerTileX = (centerLon + 180.0) / 360.0 * n
        val latRad = Math.toRadians(centerLat)
        val centerTileY = (1.0 - asinh(tan(latRad)) / Math.PI) / 2.0 * n

        val baseTileX = floor(centerTileX).toInt()
        val baseTileY = floor(centerTileY).toInt()
        val tileSize = 256f

        // Ekranı dolduracak karo aralığı (-2 ile +2)
        for (dx in -2..2) {
            for (dy in -2..2) {
                val tx = (baseTileX + dx).coerceIn(0, n - 1)
                val ty = (baseTileY + dy).coerceIn(0, n - 1)

                val screenX = centerX + ((tx - centerTileX) * tileSize).toFloat()
                val screenY = centerY + ((ty - centerTileY) * tileSize).toFloat()

                val tileKey = "$z/$tx/$ty"
                val bitmap = memoryTileCache[tileKey]

                if (bitmap != null && !bitmap.isRecycled) {
                    canvas.drawBitmap(bitmap, screenX, screenY, null)
                } else {
                    // Karoyu yerel depodan oku veya arka planda çek
                    loadTileAsync(z, tx, ty, tileKey)
                    // Karo yüklenirken yer tutucu çizgi
                    val placeholderPaint = Paint().apply {
                        color = Color.parseColor("#1AFFFFFF")
                        style = Paint.Style.STROKE
                    }
                    canvas.drawRect(screenX, screenY, screenX + tileSize, screenY + tileSize, placeholderPaint)
                }
            }
        }
    }

    private fun loadTileAsync(z: Int, x: Int, y: Int, key: String) {
        val lastFail = failedTiles[key]
        if (lastFail != null && System.currentTimeMillis() - lastFail < 15000) return

        tileExecutor.execute {
            try {
                // 1. Önce Flutter Tile Caching dizinini kontrol et
                val cacheDir = File(carContext.cacheDir, "flutter_map_cache")
                val localFile = File(cacheDir, "$key.png")

                var bmp: Bitmap? = null
                if (localFile.exists()) {
                    bmp = BitmapFactory.decodeStream(FileInputStream(localFile))
                }

                // 2. Yerelde yoksa CyclOSM ağından indir
                if (bmp == null) {
                    val urlStr = "https://a.tile-cyclosm.openstreetmap.fr/cyclosm/$z/$x/$y.png"
                    val connection = URL(urlStr).openConnection() as HttpURLConnection
                    connection.setRequestProperty("User-Agent", "TekerBikeNav/1.0")
                    connection.connectTimeout = 4000
                    connection.readTimeout = 4000
                    connection.connect()

                    if (connection.responseCode == 200) {
                        bmp = BitmapFactory.decodeStream(connection.inputStream)
                    }
                }

                if (bmp != null) {
                    memoryTileCache[key] = bmp
                    requestRender()
                } else {
                    failedTiles[key] = System.currentTimeMillis()
                }
            } catch (e: Exception) {
                failedTiles[key] = System.currentTimeMillis()
            }
        }
    }

    private fun latLonToScreen(lat: Double, lon: Double, centerLat: Double, centerLon: Double, centerX: Float, centerY: Float): PointF {
        val n = 1 shl zoomLevel.toInt()
        val tileSize = 256.0

        val cx = (centerLon + 180.0) / 360.0 * n * tileSize
        val cyRad = Math.toRadians(centerLat)
        val cy = (1.0 - asinh(tan(cyRad)) / Math.PI) / 2.0 * n * tileSize

        val px = (lon + 180.0) / 360.0 * n * tileSize
        val pyRad = Math.toRadians(lat)
        val py = (1.0 - asinh(tan(pyRad)) / Math.PI) / 2.0 * n * tileSize

        val sx = (centerX + (px - cx)).toFloat()
        val sy = (centerY + (py - cy)).toFloat()
        return PointF(sx, sy)
    }

    private fun drawRoute(canvas: Canvas, centerLat: Double, centerLon: Double, centerX: Float, centerY: Float) {
        val points = synchronized(TekerDataBridge.routePoints) { TekerDataBridge.routePoints.toList() }
        if (points.size < 2) return

        for (i in 0 until points.size - 1) {
            val p1 = points[i]
            val p2 = points[i + 1]

            val s1 = latLonToScreen(p1.lat, p1.lon, centerLat, centerLon, centerX, centerY)
            val s2 = latLonToScreen(p2.lat, p2.lon, centerLat, centerLon, centerX, centerY)

            // Yokuş kontrolü: iki nokta arası eğim > %6 ise kırmızı/turuncu yokuş çizgisi
            val dist = hypot(p2.lon - p1.lon, p2.lat - p1.lat) * 111000.0
            val eleDiff = p2.elevation - p1.elevation
            val isSteepClimb = dist > 5 && (eleDiff / dist) > 0.06

            canvas.drawLine(s1.x, s1.y, s2.x, s2.y, if (isSteepClimb) climbPaint else routePaint)
        }
    }

    private fun drawPois(canvas: Canvas, centerLat: Double, centerLon: Double, centerX: Float, centerY: Float) {
        val pois = synchronized(TekerDataBridge.chargingStations) { TekerDataBridge.chargingStations.toList() }
        for (poi in pois) {
            val pos = latLonToScreen(poi.lat, poi.lon, centerLat, centerLon, centerX, centerY)
            
            // İstasyon Dairesi
            pinPaint.color = if (poi.isRepairStation) Color.parseColor("#FF9800") else Color.parseColor("#FFEB3B")
            canvas.drawCircle(pos.x, pos.y, 18f, pinPaint)

            // İç İkon
            pinPaint.color = Color.BLACK
            canvas.drawCircle(pos.x, pos.y, 8f, pinPaint)

            // Etiket
            canvas.drawText(poi.name, pos.x + 22f, pos.y + 10f, textPaint)
        }
    }

    private fun drawCustomMarkers(canvas: Canvas, centerLat: Double, centerLon: Double, centerX: Float, centerY: Float) {
        val markers = synchronized(TekerDataBridge.customMarkers) { TekerDataBridge.customMarkers.toList() }
        for (marker in markers) {
            val pos = latLonToScreen(marker.lat, marker.lon, centerLat, centerLon, centerX, centerY)

            // Gemini Sesli Pin (Mor)
            pinPaint.color = Color.parseColor("#9C27B0")
            canvas.drawCircle(pos.x, pos.y, 22f, pinPaint)

            pinPaint.color = Color.WHITE
            canvas.drawCircle(pos.x, pos.y, 10f, pinPaint)

            // Metin Etiketi
            canvas.drawText("★ ${marker.title}", pos.x + 26f, pos.y + 10f, textPaint)
        }
    }

    private fun drawUserCursor(canvas: Canvas, cx: Float, cy: Float, rotationDegrees: Float) {
        canvas.save()
        canvas.translate(cx, cy)
        canvas.rotate(rotationDegrees)

        // Pulsing Halka
        canvas.drawCircle(0f, 0f, 32f, pulsePaint)

        // Bisiklet Gövde Dairesi
        canvas.drawCircle(0f, 0f, 18f, bikeMarkerPaint)

        // Yön Gösteren Üçgen Ok
        val path = Path().apply {
            moveTo(0f, -24f)
            lineTo(-10f, 8f)
            lineTo(0f, 2f)
            lineTo(10f, 8f)
            close()
        }
        canvas.drawPath(path, bikeHeadingPaint)

        canvas.restore()
    }
}
