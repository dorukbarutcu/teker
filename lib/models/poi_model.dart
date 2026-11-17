import 'package:latlong2/latlong.dart';

class TekerPoi {
  final String id;
  final String name;
  final LatLng location;
  final double distanceMeters;
  final bool isRepairStation;
  final String openingHours;
  final Map<String, dynamic> rawTags;

  TekerPoi({
    required this.id,
    required this.name,
    required this.location,
    this.distanceMeters = 0.0,
    this.isRepairStation = false,
    this.openingHours = '',
    this.rawTags = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'lat': location.latitude,
      'lon': location.longitude,
      'distance': distanceMeters,
      'isRepair': isRepairStation,
    };
  }
}

class TekerCustomMarker {
  final String id;
  final String title;
  final String category;
  final LatLng location;
  final String note;
  final DateTime createdAt;

  TekerCustomMarker({
    required this.id,
    required this.title,
    required this.category,
    required this.location,
    this.note = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'lat': location.latitude,
      'lon': location.longitude,
      'note': note,
    };
  }
}
