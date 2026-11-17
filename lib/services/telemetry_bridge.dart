import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/route_models.dart';
import '../models/poi_model.dart';

class TelemetryBridge {
  static const MethodChannel _channel =
      MethodChannel('com.teker.navigation/telemetry');

  static Future<void> syncLocation({
    required LatLng position,
    required double bearing,
    required double speedKmh,
    required double altitudeMeters,
  }) async {
    try {
      await _channel.invokeMethod('updateLocation', {
        'lat': position.latitude,
        'lon': position.longitude,
        'bearing': bearing,
        'speed': speedKmh,
        'altitude': altitudeMeters,
      });
    } catch (_) {}
  }

  static Future<void> syncRoute(NavigationRoute route) async {
    try {
      final points = route.coordinatesWithEle.map((p) => {
            'lat': p.point.latitude,
            'lon': p.point.longitude,
            'ele': p.elevation,
          }).toList();

      await _channel.invokeMethod('setRoute', {'points': points});
    } catch (_) {}
  }

  static Future<void> syncManeuver(ManeuverStep step) async {
    try {
      await _channel.invokeMethod('updateManeuver', {
        'instruction': step.instruction,
        'streetName': step.streetName,
        'distanceMeters': step.distanceMeters,
        'type': step.type,
      });
    } catch (_) {}
  }

  static Future<void> syncTelemetry({
    required double speedKmh,
    required int batteryPct,
    required double remainingRangeKm,
    required double altitudeMeters,
    required double remainingDistanceMeters,
    required int remainingSeconds,
    required String assistMode,
  }) async {
    try {
      await _channel.invokeMethod('updateTelemetry', {
        'speedKmh': speedKmh,
        'batteryPct': batteryPct,
        'remainingRangeKm': remainingRangeKm,
        'altitudeMeters': altitudeMeters,
        'remainingDistanceMeters': remainingDistanceMeters,
        'remainingSeconds': remainingSeconds,
        'assistMode': assistMode,
      });
    } catch (_) {}
  }

  static Future<void> syncChargingStations(List<TekerPoi> stations) async {
    try {
      final list = stations.map((s) => s.toMap()).toList();
      await _channel.invokeMethod('setChargingStations', {'stations': list});
    } catch (_) {}
  }

  static Future<void> syncCustomMarker(TekerCustomMarker marker) async {
    try {
      await _channel.invokeMethod('addCustomMarker', marker.toMap());
    } catch (_) {}
  }

  static Future<void> clearCustomMarkers() async {
    try {
      await _channel.invokeMethod('clearCustomMarkers');
    } catch (_) {}
  }

  static Future<void> startForegroundService() async {
    try {
      await _channel.invokeMethod('startForegroundService');
    } catch (_) {}
  }

  static Future<void> stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } catch (_) {}
  }
}
