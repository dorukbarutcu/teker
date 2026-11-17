import 'package:latlong2/latlong.dart';

enum LocationShortcutType {
  home(id: 'home', label: 'Ev', iconName: 'home'),
  school(id: 'school', label: 'Okul', iconName: 'school'),
  work(id: 'work', label: 'İş Yeri', iconName: 'work'),
  favorite(id: 'favorite', label: 'Favori', iconName: 'star');

  final String id;
  final String label;
  final String iconName;

  const LocationShortcutType({
    required this.id,
    required this.label,
    required this.iconName,
  });
}

class SavedLocation {
  final String id; // 'home', 'school', 'work', 'favorite' veya özel id
  final String title;
  final String address;
  final LatLng location;
  final String iconType;

  SavedLocation({
    required this.id,
    required this.title,
    required this.address,
    required this.location,
    required this.iconType,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'address': address,
        'lat': location.latitude,
        'lon': location.longitude,
        'iconType': iconType,
      };

  factory SavedLocation.fromJson(Map<String, dynamic> json) => SavedLocation(
        id: json['id'],
        title: json['title'],
        address: json['address'] ?? '',
        location: LatLng(
          (json['lat'] as num).toDouble(),
          (json['lon'] as num).toDouble(),
        ),
        iconType: json['iconType'] ?? 'favorite',
      );
}
