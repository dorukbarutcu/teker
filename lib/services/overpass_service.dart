import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/poi_model.dart';

class OverpassService {
  static const String overpassUrl = 'https://overpass-api.de/api/interpreter';
  static const String userAgent = 'TekerBikeNav/1.0';

  /// Verilen merkez koordinat etrafındaki şarj istasyonlarını ve bakım noktalarını çeker
  static Future<List<TekerPoi>> fetchNearbyChargingAndRepairPoints({
    required LatLng center,
    double radiusMeters = 5000.0,
  }) async {
    final lat = center.latitude;
    final lon = center.longitude;

    // Overpass QL Sorgusu
    final query = '''
    [out:json][timeout:15];
    (
      node["amenity"="charging_station"](around:$radiusMeters,$lat,$lon);
      node["amenity"="bicycle_repair_station"](around:$radiusMeters,$lat,$lon);
      way["amenity"="charging_station"](around:$radiusMeters,$lat,$lon);
    );
    out center;
    ''';

    const distanceCalc = Distance();

    try {
      final response = await http.post(
        Uri.parse(overpassUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': userAgent,
        },
        body: 'data=${Uri.encodeQueryComponent(query)}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final elements = data['elements'] as List;
        final List<TekerPoi> results = [];

        for (var el in elements) {
          final double pLat = el['lat'] != null
              ? (el['lat'] as num).toDouble()
              : (el['center']?['lat'] as num?)?.toDouble() ?? 0.0;
          final double pLon = el['lon'] != null
              ? (el['lon'] as num).toDouble()
              : (el['center']?['lon'] as num?)?.toDouble() ?? 0.0;

          if (pLat == 0.0 && pLon == 0.0) continue;

          final tags = el['tags'] as Map<String, dynamic>? ?? {};
          final isRepair = tags['amenity'] == 'bicycle_repair_station';
          final name = tags['name'] ??
              (isRepair ? 'Bisiklet Bakım Noktası' : 'E-Bike Şarj İstasyonu');
          final hours = tags['opening_hours'] ?? '7/24 Açık';

          final poiLocation = LatLng(pLat, pLon);
          final dist = distanceCalc.as(LengthUnit.Meter, center, poiLocation);

          results.add(
            TekerPoi(
              id: el['id'].toString(),
              name: name,
              location: poiLocation,
              distanceMeters: dist,
              isRepairStation: isRepair,
              openingHours: hours,
              rawTags: tags,
            ),
          );
        }

        // Mesafeye göre artan sırada sırala
        results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
        return results;
      } else {
        return getMockPoiList(center);
      }
    } catch (e) {
      // Çevrimdışı veya hata durumunda mock POI'ler
      return getMockPoiList(center);
    }
  }

  static List<TekerPoi> getMockPoiList(LatLng center) {
    const distanceCalc = Distance();
    final p1 = LatLng(center.latitude + 0.008, center.longitude + 0.005);
    final p2 = LatLng(center.latitude - 0.006, center.longitude + 0.009);
    final p3 = LatLng(center.latitude + 0.012, center.longitude - 0.007);

    return [
      TekerPoi(
        id: 'mock_1',
        name: 'Marina E-Bike Hızlı Şarj Noktası',
        location: p1,
        distanceMeters: distanceCalc.as(LengthUnit.Meter, center, p1),
        isRepairStation: false,
        openingHours: '24 Saat',
      ),
      TekerPoi(
        id: 'mock_2',
        name: 'Sahil Bisiklet Tamir & Pompa İstasyonu',
        location: p2,
        distanceMeters: distanceCalc.as(LengthUnit.Meter, center, p2),
        isRepairStation: true,
        openingHours: '08:00 - 22:00',
      ),
      TekerPoi(
        id: 'mock_3',
        name: 'Park İçi E-Bike Şarj & Dinlenme',
        location: p3,
        distanceMeters: distanceCalc.as(LengthUnit.Meter, center, p3),
        isRepairStation: false,
        openingHours: '24 Saat',
      ),
    ];
  }
}
