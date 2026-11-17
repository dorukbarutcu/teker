import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import '../models/route_models.dart';

class GpxService {
  /// Cihazdan .gpx dosyası seçtirir ve NavigationRoute nesnesine dönüştürür
  static Future<NavigationRoute?> pickAndParseGpxFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx'],
      );

      if (files.isNotEmpty && files.first.path != null) {
        final file = File(files.first.path!);
        final content = await file.readAsString();
        return parseGpxString(content);
      }
    } catch (_) {}
    return null;
  }

  /// GPX XML içeriğini ayrıştırır
  static NavigationRoute? parseGpxString(String xmlString) {
    try {
      final document = XmlDocument.parse(xmlString);
      final trkpts = document.findAllElements('trkpt');

      if (trkpts.isEmpty) return null;

      final List<LatLng> latLngList = [];
      final List<RoutePointWithEle> pointWithEleList = [];

      double totalDistance = 0.0;
      double totalAscent = 0.0;
      double totalDescent = 0.0;
      const distanceCalc = Distance();

      LatLng? prevPoint;
      double? prevEle;

      for (var node in trkpts) {
        final latStr = node.getAttribute('lat');
        final lonStr = node.getAttribute('lon');
        if (latStr == null || lonStr == null) continue;

        final lat = double.parse(latStr);
        final lon = double.parse(lonStr);
        final eleNode = node.findElements('ele').firstOrNull;
        final ele = eleNode != null ? double.parse(eleNode.innerText) : 0.0;

        final currentPt = LatLng(lat, lon);
        latLngList.add(currentPt);
        pointWithEleList.add(RoutePointWithEle(point: currentPt, elevation: ele));

        if (prevPoint != null && prevEle != null) {
          final dist = distanceCalc.as(LengthUnit.Meter, prevPoint, currentPt);
          totalDistance += dist;

          final eleDiff = ele - prevEle;
          if (eleDiff > 0) {
            totalAscent += eleDiff;
          } else {
            totalDescent += eleDiff.abs();
          }
        }

        prevPoint = currentPt;
        prevEle = ele;
      }

      if (latLngList.isEmpty) return null;

      return NavigationRoute(
        coordinates: latLngList,
        coordinatesWithEle: pointWithEleList,
        totalDistanceMeters: totalDistance,
        totalDurationSeconds: totalDistance / 5.5, // ~20 km/s ortalama
        totalAscentMeters: totalAscent,
        totalDescentMeters: totalDescent,
        steps: [
          ManeuverStep(
            instruction: 'GPX Rotasını Takip Edin',
            streetName: 'Özel Bisiklet Parkuru',
            distanceMeters: totalDistance,
            durationSeconds: totalDistance / 5.5,
            type: 1,
          )
        ],
        isGpx: true,
      );
    } catch (_) {
      return null;
    }
  }
}
