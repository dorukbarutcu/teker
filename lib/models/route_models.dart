import 'package:latlong2/latlong.dart';

class RoutePointWithEle {
  final LatLng point;
  final double elevation;

  RoutePointWithEle({
    required this.point,
    required this.elevation,
  });
}

class ManeuverStep {
  final String instruction;
  final String streetName;
  final double distanceMeters;
  final double durationSeconds;
  final int type; // 1: straight, 2: left, 3: right, 4: roundabout

  ManeuverStep({
    required this.instruction,
    required this.streetName,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.type,
  });
}

class NavigationRoute {
  final List<LatLng> coordinates;
  final List<RoutePointWithEle> coordinatesWithEle;
  final double totalDistanceMeters;
  final double totalDurationSeconds;
  final double totalAscentMeters;
  final double totalDescentMeters;
  final List<ManeuverStep> steps;
  final bool isGpx;

  NavigationRoute({
    required this.coordinates,
    required this.coordinatesWithEle,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.totalAscentMeters,
    required this.totalDescentMeters,
    required this.steps,
    this.isGpx = false,
  });

  double get totalDistanceKm => totalDistanceMeters / 1000.0;
}
