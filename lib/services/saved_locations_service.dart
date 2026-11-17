import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/saved_location_model.dart';

class SavedLocationsService {
  static const String _prefKey = 'teker_saved_shortcuts_v1';

  /// Kayıtlı tüm kısayol ve favori konumları getirir
  static Future<Map<String, SavedLocation>> loadSavedLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_prefKey);
    if (jsonStr == null) return {};

    try {
      final Map<String, dynamic> rawMap = jsonDecode(jsonStr);
      final Map<String, SavedLocation> result = {};
      rawMap.forEach((key, value) {
        result[key] = SavedLocation.fromJson(value);
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Belirtilen kısayol konumunu kaydeder (Ev, Okul, İş Yeri, Favori)
  static Future<void> saveLocation(SavedLocation location) async {
    final current = await loadSavedLocations();
    current[location.id] = location;

    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> rawMap = {};
    current.forEach((key, value) {
      rawMap[key] = value.toJson();
    });
    await prefs.setString(_prefKey, jsonEncode(rawMap));
  }

  /// Kısayol konumunu siler
  static Future<void> deleteLocation(String id) async {
    final current = await loadSavedLocations();
    current.remove(id);

    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> rawMap = {};
    current.forEach((key, value) {
      rawMap[key] = value.toJson();
    });
    await prefs.setString(_prefKey, jsonEncode(rawMap));
  }

  /// Sesli veya metin sorgusundan kısayol konumunu eşleştirir (Örn: "Ev", "Okul", "İş")
  static Future<SavedLocation?> matchShortcut(String query) async {
    final lower = query.toLowerCase();
    final current = await loadSavedLocations();

    if (lower.contains('ev') || lower.contains('home')) {
      return current['home'];
    }
    if (lower.contains('okul') || lower.contains('school') || lower.contains('üniversite')) {
      return current['school'];
    }
    if (lower.contains('iş') || lower.contains('work') || lower.contains('ofis')) {
      return current['work'];
    }
    if (lower.contains('favori') || lower.contains('fav')) {
      return current['favorite'];
    }

    return null;
  }
}
