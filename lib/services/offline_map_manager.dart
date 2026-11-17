import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadedRegion {
  final String id;
  final String name;
  final String detailLevel; // 'city' (10-16) veya 'region' (7-13)
  final int minZoom;
  final int maxZoom;
  final int totalTiles;
  final double sizeMb;
  final DateTime downloadedAt;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  DownloadedRegion({
    required this.id,
    required this.name,
    required this.detailLevel,
    required this.minZoom,
    required this.maxZoom,
    required this.totalTiles,
    required this.sizeMb,
    required this.downloadedAt,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'detailLevel': detailLevel,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
        'totalTiles': totalTiles,
        'sizeMb': sizeMb,
        'downloadedAt': downloadedAt.toIso8601String(),
        'minLat': minLat,
        'maxLat': maxLat,
        'minLon': minLon,
        'maxLon': maxLon,
      };

  factory DownloadedRegion.fromJson(Map<String, dynamic> json) =>
      DownloadedRegion(
        id: json['id'],
        name: json['name'],
        detailLevel: json['detailLevel'],
        minZoom: json['minZoom'],
        maxZoom: json['maxZoom'],
        totalTiles: json['totalTiles'],
        sizeMb: (json['sizeMb'] as num).toDouble(),
        downloadedAt: DateTime.parse(json['downloadedAt']),
        minLat: (json['minLat'] as num).toDouble(),
        maxLat: (json['maxLat'] as num).toDouble(),
        minLon: (json['minLon'] as num).toDouble(),
        maxLon: (json['maxLon'] as num).toDouble(),
      );
}

class BoundarySearchResult {
  final String displayName;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final List<List<LatLng>> polygonRings;

  BoundarySearchResult({
    required this.displayName,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.polygonRings,
  });
}

class OfflineMapManager {
  static const String userAgent = 'TekerBikeNav/1.0';
  static const String prefKey = 'teker_downloaded_regions_v1';

  static bool isPaused = false;
  static bool isCancelled = false;

  /// Nominatim üzerinden poligon ve sınır kutusu (bounding box) arar
  static Future<BoundarySearchResult?> searchAdministrativeBoundary(
      String query) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?format=json&polygon_geojson=1&q=${Uri.encodeComponent(query)}&limit=1',
      );
      final response = await http.get(url, headers: {'User-Agent': userAgent});

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        if (data.isEmpty) return null;

        final item = data[0];
        final bbox = item['boundingbox'] as List; // [minLat, maxLat, minLon, maxLon]
        final double minLat = double.parse(bbox[0]);
        final double maxLat = double.parse(bbox[1]);
        final double minLon = double.parse(bbox[2]);
        final double maxLon = double.parse(bbox[3]);

        final geoJson = item['geojson'];
        final List<List<LatLng>> rings = [];

        if (geoJson != null && geoJson['type'] == 'Polygon') {
          final coordinates = geoJson['coordinates'] as List;
          for (var ring in coordinates) {
            final List<LatLng> ringPts = [];
            for (var pt in ring) {
              ringPts.add(LatLng(
                (pt[1] as num).toDouble(),
                (pt[0] as num).toDouble(),
              ));
            }
            rings.add(ringPts);
          }
        } else if (geoJson != null && geoJson['type'] == 'MultiPolygon') {
          final multiCoords = geoJson['coordinates'] as List;
          for (var poly in multiCoords) {
            for (var ring in poly) {
              final List<LatLng> ringPts = [];
              for (var pt in ring) {
                ringPts.add(LatLng(
                  (pt[1] as num).toDouble(),
                  (pt[0] as num).toDouble(),
                ));
              }
              rings.add(ringPts);
            }
          }
        }

        return BoundarySearchResult(
          displayName: item['display_name'] ?? query,
          minLat: minLat,
          maxLat: maxLat,
          minLon: minLon,
          maxLon: maxLon,
          polygonRings: rings,
        );
      }
    } catch (_) {}
    return null;
  }

  static double _asinh(double x) => log(x + sqrt(x * x + 1.0));

  /// Seçili alan ve zoom aralığına göre toplam karo sayısını ve tahmini MB boyutunu hesaplar
  static Map<String, dynamic> estimateTilesAndSize({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required int minZoom,
    required int maxZoom,
  }) {
    int totalTiles = 0;

    for (int z = minZoom; z <= maxZoom; z++) {
      final n = 1 << z;
      final x1 = (((minLon + 180.0) / 360.0) * n).floor().clamp(0, n - 1);
      final x2 = (((maxLon + 180.0) / 360.0) * n).floor().clamp(0, n - 1);

      final y1 = ((1.0 - _asinh(tan(maxLat * pi / 180.0)) / pi) / 2.0 * n)
          .floor()
          .clamp(0, n - 1);
      final y2 = ((1.0 - _asinh(tan(minLat * pi / 180.0)) / pi) / 2.0 * n)
          .floor()
          .clamp(0, n - 1);

      final countX = (x2 - x1).abs() + 1;
      final countY = (y2 - y1).abs() + 1;
      totalTiles += (countX * countY);
    }

    // CyclOSM karosu ortalama 22 - 28 KB
    final double estimatedMb = (totalTiles * 0.025);

    return {
      'totalTiles': totalTiles,
      'estimatedMb': double.parse(estimatedMb.toStringAsFixed(1)),
    };
  }

  /// Karoları yerel önbellek dizinine indirir (Hem Flutter hem Android Auto ortak okur)
  static Future<void> downloadRegionTiles({
    required String regionName,
    required String detailLevel,
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required int minZoom,
    required int maxZoom,
    required Function(double progress, int downloadedCount, int totalCount)
        onProgress,
  }) async {
    isPaused = false;
    isCancelled = false;

    // Ortak Önbellek Dizini
    final cacheDir = await getSharedTileCacheDir();
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    // İndirilecek karo listesini derle
    final List<Map<String, int>> tileList = [];
    for (int z = minZoom; z <= maxZoom; z++) {
      final n = 1 << z;
      final x1 = (((minLon + 180.0) / 360.0) * n).floor().clamp(0, n - 1);
      final x2 = (((maxLon + 180.0) / 360.0) * n).floor().clamp(0, n - 1);

      final y1 = ((1.0 - _asinh(tan(maxLat * pi / 180.0)) / pi) / 2.0 * n)
          .floor()
          .clamp(0, n - 1);
      final y2 = ((1.0 - _asinh(tan(minLat * pi / 180.0)) / pi) / 2.0 * n)
          .floor()
          .clamp(0, n - 1);

      final minX = min(x1, x2);
      final maxX = max(x1, x2);
      final minY = min(y1, y2);
      final maxY = max(y1, y2);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tileList.add({'z': z, 'x': x, 'y': y});
        }
      }
    }

    final totalCount = tileList.length;
    int downloadedCount = 0;
    int totalBytes = 0;

    final client = http.Client();

    for (var tile in tileList) {
      if (isCancelled) break;

      while (isPaused) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (isCancelled) break;
      }

      final z = tile['z']!;
      final x = tile['x']!;
      final y = tile['y']!;

      final file = File('${cacheDir.path}/$z/$x/$y.png');
      if (file.existsSync()) {
        downloadedCount++;
        totalBytes += file.lengthSync();
        onProgress(downloadedCount / totalCount, downloadedCount, totalCount);
        continue;
      }

      file.parent.createSync(recursive: true);

      try {
        final url = Uri.parse(
          'https://a.tile-cyclosm.openstreetmap.fr/cyclosm/$z/$x/$y.png',
        );
        final res = await client.get(url, headers: {'User-Agent': userAgent});

        if (res.statusCode == 200) {
          await file.writeAsBytes(res.bodyBytes);
          totalBytes += res.bodyBytes.length;
        }
      } catch (_) {}

      downloadedCount++;
      onProgress(downloadedCount / totalCount, downloadedCount, totalCount);

      // Sunucu kısıtlamasına takılmamak için kısa gecikme
      await Future.delayed(const Duration(milliseconds: 25));
    }

    client.close();

    if (!isCancelled && downloadedCount > 0) {
      final region = DownloadedRegion(
        id: 'reg_${DateTime.now().millisecondsSinceEpoch}',
        name: regionName,
        detailLevel: detailLevel,
        minZoom: minZoom,
        maxZoom: maxZoom,
        totalTiles: downloadedCount,
        sizeMb: double.parse((totalBytes / (1024 * 1024)).toStringAsFixed(1)),
        downloadedAt: DateTime.now(),
        minLat: minLat,
        maxLat: maxLat,
        minLon: minLon,
        maxLon: maxLon,
      );
      await saveRegionToPrefs(region);
    }
  }

  static Future<Directory> getSharedTileCacheDir() async {
    final tempDir = await getTemporaryDirectory();
    return Directory('${tempDir.parent.path}/cache/flutter_map_cache');
  }

  static Future<List<DownloadedRegion>> getSavedRegions() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(prefKey);
    if (jsonStr == null) return [];

    try {
      final List list = jsonDecode(jsonStr);
      return list.map((e) => DownloadedRegion.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveRegionToPrefs(DownloadedRegion region) async {
    final current = await getSavedRegions();
    current.removeWhere((r) => r.id == region.id);
    current.insert(0, region);

    final prefs = await SharedPreferences.getInstance();
    final jsonList = current.map((r) => r.toJson()).toList();
    await prefs.setString(prefKey, jsonEncode(jsonList));
  }

  static Future<void> deleteRegion(DownloadedRegion region) async {
    final current = await getSavedRegions();
    current.removeWhere((r) => r.id == region.id);

    final prefs = await SharedPreferences.getInstance();
    final jsonList = current.map((r) => r.toJson()).toList();
    await prefs.setString(prefKey, jsonEncode(jsonList));
  }
}
