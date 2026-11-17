import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/ebike_models.dart';
import '../models/poi_model.dart';
import '../models/route_models.dart';
import 'saved_locations_service.dart';
import 'ebike_calculator.dart';
import 'openroute_service.dart';
import 'overpass_service.dart';
import 'telemetry_bridge.dart';

class GeminiCommandService {
  static const String userAgent = "TekerBikeNav/1.0";

  static const MethodChannel _assistantChannel =
      MethodChannel('com.teker.navigation/assistant');

  final FlutterTts _tts = FlutterTts();

  // Callback Fonksiyonları (UI ve Harita ile Haberleşme)
  Function(TekerCustomMarker)? onMarkerAdded;
  Function()? onMarkersCleared;
  Function(NavigationRoute route, String destName)? onRouteCreated;
  Function(EbikeAssistMode mode)? onAssistModeChanged;
  Function(TekerPoi poi, bool asWaypoint)? onPoiSelected;

  // Anlık Durum Referansları
  LatLng currentPosition = const LatLng(36.795, 34.618); // Mersin Varsayılan
  EbikeProfile currentProfile = EbikeProfile();

  GeminiCommandService() {
    _initTts();
    _initChannelListener();
  }

  void _initTts() async {
    await _tts.setLanguage("tr-TR");
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  void _initChannelListener() {
    _assistantChannel.setMethodCallHandler((call) async {
      if (call.method == "onAssistantCommand") {
        final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
        await handleNativeAssistantIntent(args);
      }
    });
  }

  /// Android Gemini / Google Asistan App Actions & Deep Link Intentlerini Doğrudan İşler
  Future<void> handleNativeAssistantIntent(Map<dynamic, dynamic> args) async {
    final action = args['action']?.toString() ?? '';

    // 1. Android Auto veya Gemini'den gelen ara durak ekleme
    if (action == 'addChargingWaypoint') {
      final name = args['name']?.toString() ?? 'Şarj İstasyonu';
      final lat = (args['lat'] as num?)?.toDouble() ?? currentPosition.latitude;
      final lon = (args['lon'] as num?)?.toDouble() ?? currentPosition.longitude;
      final poi = TekerPoi(
        id: args['id']?.toString() ?? 'poi',
        name: name,
        location: LatLng(lat, lon),
      );
      onPoiSelected?.call(poi, true);
      await speak("$name rotaya ara durak olarak eklendi.");
      return;
    }

    // 2. geo: URI Yakalama (Gemini uygulamasından gelen harita yönlendirmesi)
    if (args.containsKey('geo_uri')) {
      final geoUri = args['geo_uri'].toString();
      await _handleGeoUri(geoUri);
      return;
    }

    // 3. actions.intent.CREATE_ROUTE (Gemini App: "Teker ile ... rotası oluştur")
    if (args.containsKey('destination') || action == 'CREATE_ROUTE') {
      final dest = args['destination']?.toString() ?? args['targetAddress']?.toString() ?? '';
      if (dest.isNotEmpty) {
        await executeFunctionCall('navigateToPlace', {
          'destinationName': dest,
          'profile': 'cycling-electric',
          'avoidHills': args['avoidHills'] == 'true' || args['avoid'] == 'hills',
        });
        return;
      }
    }

    // 4. actions.intent.GET_THING (Gemini App: "Teker'de en yakın şarj istasyonunu bul / işaretle")
    if (args.containsKey('query') || action == 'GET_THING') {
      final query = args['query']?.toString() ?? '';
      final category = args['category']?.toString() ?? '';
      final lower = query.toLowerCase();

      if (lower.contains('şarj') || category.contains('charging')) {
        await executeFunctionCall('findAndMarkNearestPoi', {
          'poiType': 'charging_station',
          'addAsWaypoint': lower.contains('ekle') || lower.contains('rota'),
        });
      } else if (lower.contains('tamir') || lower.contains('bakım') || lower.contains('pompa')) {
        await executeFunctionCall('findAndMarkNearestPoi', {
          'poiType': 'bicycle_repair_station',
          'addAsWaypoint': lower.contains('ekle'),
        });
      } else if (query.isNotEmpty) {
        await executeFunctionCall('markLocationOnMap', {
          'placeName': query,
          'category': category.isNotEmpty ? category : 'İlgi Noktası',
        });
      }
      return;
    }

    // 5. actions.intent.OPEN_APP_FEATURE (Gemini App: "Teker'de Turbo moda geç")
    if (args.containsKey('feature') || action == 'OPEN_APP_FEATURE') {
      final feature = (args['feature']?.toString() ?? '').toLowerCase();
      if (feature.contains('turbo')) {
        await executeFunctionCall('changeEbikeAssistMode', {'mode': 'Turbo'});
      } else if (feature.contains('sport')) {
        await executeFunctionCall('changeEbikeAssistMode', {'mode': 'Sport'});
      } else if (feature.contains('eco')) {
        await executeFunctionCall('changeEbikeAssistMode', {'mode': 'Eco'});
      } else if (feature.contains('tour')) {
        await executeFunctionCall('changeEbikeAssistMode', {'mode': 'Tour'});
      } else if (feature.contains('temizle') || feature.contains('clear')) {
        await executeFunctionCall('clearCustomMarkers', {});
      }
      return;
    }

    // 6. Serbest metin komutu
    final fallbackQuery = args['data_uri']?.toString() ?? args.toString();
    await processCommandWithGemini(fallbackQuery);
  }

  /// Gemini Android uygulamasından gelen geo: koordinat veya sorgu URI çözümleyici
  Future<void> _handleGeoUri(String uriString) async {
    try {
      final clean = uriString.replaceFirst('geo:', '');
      if (clean.contains('q=')) {
        final query = clean.split('q=').last;
        await executeFunctionCall('navigateToPlace', {
          'destinationName': Uri.decodeComponent(query),
          'profile': 'cycling-electric',
        });
      } else {
        final parts = clean.split('?').first.split(',');
        if (parts.length >= 2) {
          final lat = double.parse(parts[0].trim());
          final lon = double.parse(parts[1].trim());
          final dest = LatLng(lat, lon);
          final route = await OpenRouteService.getRoute(
            start: currentPosition,
            destination: dest,
            profile: 'cycling-electric',
          );
          if (route != null) {
            onRouteCreated?.call(route, "Hedef Konum");
            await TelemetryBridge.syncRoute(route);
            await speak("Hedef konuma rota oluşturuldu.");
          }
        }
      }
    } catch (_) {}
  }

  /// Doğrudan deterministik komut çözümleyici (Harici Gemini REST API gerektirmez)
  Future<String> processCommandWithGemini(String naturalLanguagePrompt) async {
    final lower = naturalLanguagePrompt.toLowerCase();

    // Destek Modu Değişimi
    if (lower.contains('turbo')) {
      return executeFunctionCall('changeEbikeAssistMode', {'mode': 'Turbo'});
    } else if (lower.contains('sport')) {
      return executeFunctionCall('changeEbikeAssistMode', {'mode': 'Sport'});
    } else if (lower.contains('eco')) {
      return executeFunctionCall('changeEbikeAssistMode', {'mode': 'Eco'});
    } else if (lower.contains('tour')) {
      return executeFunctionCall('changeEbikeAssistMode', {'mode': 'Tour'});
    }

    // Şarj ve Tamir Noktası
    if (lower.contains('şarj')) {
      return executeFunctionCall('findAndMarkNearestPoi', {
        'poiType': 'charging_station',
        'addAsWaypoint': lower.contains('ekle') || lower.contains('rota'),
      });
    } else if (lower.contains('tamir') || lower.contains('bakım') || lower.contains('pompa')) {
      return executeFunctionCall('findAndMarkNearestPoi', {
        'poiType': 'bicycle_repair_station',
        'addAsWaypoint': lower.contains('ekle'),
      });
    }

    // Pinleri Temizle
    if (lower.contains('temizle') || lower.contains('kaldır')) {
      return executeFunctionCall('clearCustomMarkers', {});
    }

    // Rota Oluşturma
    if (lower.contains('rota') || lower.contains('git') || lower.contains('sür') || lower.contains('yol')) {
      String dest = naturalLanguagePrompt
          .replaceAll(RegExp(r'(teker|ile|bana|bir|rota|çiz|oluştur|git|sür|navigasyon|başlat)', caseSensitive: false), '')
          .trim();
      if (dest.isEmpty) dest = "Mersin Marina";
      return executeFunctionCall('navigateToPlace', {
        'destinationName': dest,
        'profile': 'cycling-electric',
      });
    }

    // Yer İşaretleme
    String place = naturalLanguagePrompt
        .replaceAll(RegExp(r'(teker|de|da|en|yakın|bul|işaretle|göster)', caseSensitive: false), '')
        .trim();
    if (place.isEmpty) place = "Mersin Marina";
    return executeFunctionCall('markLocationOnMap', {
      'placeName': place,
      'category': 'Konum',
    });
  }

  Future<String> executeFunctionCall(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'markLocationOnMap':
        final placeName = args['placeName']?.toString() ?? 'Hedef';
        final category = args['category']?.toString() ?? 'Genel';
        final note = args['note']?.toString() ?? '';

        final target = await searchLocationNominatim(placeName);
        if (target != null) {
          final marker = TekerCustomMarker(
            id: 'marker_${DateTime.now().millisecondsSinceEpoch}',
            title: placeName,
            category: category,
            location: target,
            note: note,
          );
          onMarkerAdded?.call(marker);
          await TelemetryBridge.syncCustomMarker(marker);

          const distanceCalc = Distance();
          final distKm = distanceCalc.as(LengthUnit.Kilometer, currentPosition, target);
          final message = "$placeName haritada işaretlendi. Mesafe ${distKm.toStringAsFixed(1)} kilometre, bataryanızla rahatça ulaşabilirsiniz.";
          await speak(message);
          return message;
        } else {
          final message = "$placeName konumu haritada bulunamadı.";
          await speak(message);
          return message;
        }

      case 'navigateToPlace':
        final destName = args['destinationName']?.toString() ?? 'Hedef';
        final profile = args['profile']?.toString() ?? 'cycling-electric';
        final avoidHills = args['avoidHills'] == true;

        final shortcut = await SavedLocationsService.matchShortcut(destName);
        final LatLng? target = shortcut != null ? shortcut.location : await searchLocationNominatim(destName);
        final String displayName = shortcut != null ? shortcut.title : destName;

        if (target != null) {
          final route = await OpenRouteService.getRoute(
            start: currentPosition,
            destination: target,
            profile: profile,
            avoidHills: avoidHills,
          );
          if (route != null) {
            onRouteCreated?.call(route, displayName);
            await TelemetryBridge.syncRoute(route);

            final energyResult = EbikeCalculator.calculateRouteEnergy(
              distanceKm: route.totalDistanceKm,
              totalAscentMeters: route.totalAscentMeters,
              profile: currentProfile,
            );

            String msg = "$displayName için rota hazırlandı. Toplam mesafe ${route.totalDistanceKm.toStringAsFixed(1)} kilometre.";
            if (!energyResult.isSufficient) {
              msg += " Dikkat, varış için ${energyResult.deficitWh.toInt()} vat-saat ek enerjiye ihtiyacınız var. Şarj molası planlayın.";
            } else {
              msg += " Kalan bataryanız bu rota için fazlasıyla yeterli.";
            }
            await speak(msg);
            return msg;
          }
        }
        final failMsg = "$destName rotası oluşturulamadı.";
        await speak(failMsg);
        return failMsg;

      case 'findAndMarkNearestPoi':
        final poiType = args['poiType']?.toString() ?? 'charging_station';
        final addWaypoint = args['addAsWaypoint'] == true;

        final pois = await OverpassService.fetchNearbyChargingAndRepairPoints(
          center: currentPosition,
        );

        final filtered = pois.where((p) => poiType == 'bicycle_repair_station' ? p.isRepairStation : !p.isRepairStation).toList();
        if (filtered.isNotEmpty) {
          final nearest = filtered.first;
          onPoiSelected?.call(nearest, addWaypoint);
          final distKm = (nearest.distanceMeters / 1000.0).toStringAsFixed(1);
          final msg = "En yakın ${nearest.name} $distKm kilometre mesafede ${addWaypoint ? 'rotaya ara durak olarak eklendi' : 'işaretlendi'}.";
          await speak(msg);
          return msg;
        } else {
          const msg = "Yakında uygun şarj istasyonu veya bakım noktası bulunamadı.";
          await speak(msg);
          return msg;
        }

      case 'changeEbikeAssistMode':
        final modeStr = args['mode']?.toString() ?? 'Tour';
        final newMode = EbikeAssistMode.fromString(modeStr);
        currentProfile.assistMode = newMode;
        onAssistModeChanged?.call(newMode);
        final newRange = EbikeCalculator.calculateRemainingRangeKm(profile: currentProfile);
        final msg = "Destek modu ${newMode.displayName} olarak değiştirildi. Kalan menziliniz ${newRange.toInt()} kilometre.";
        await speak(msg);
        return msg;

      case 'clearCustomMarkers':
        onMarkersCleared?.call();
        await TelemetryBridge.clearCustomMarkers();
        const msg = "Haritada işaretlenen özel yerler temizlendi.";
        await speak(msg);
        return msg;

      default:
        const msg = "Komut anlaşılamadı.";
        await speak(msg);
        return msg;
    }
  }

  static Future<LatLng?> searchLocationNominatim(String query) async {
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&limit=1');
      final response = await http.get(url, headers: {'User-Agent': userAgent});

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          return LatLng(lat, lon);
        }
      }
    } catch (_) {}

    if (query.toLowerCase().contains('marina')) {
      return const LatLng(36.776, 34.582);
    }
    return const LatLng(36.795, 34.618);
  }

  Future<void> speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (_) {}
  }
}
