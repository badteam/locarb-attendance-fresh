import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;

double _deg2rad(double deg) => deg * (math.pi / 180.0);

/// احسب المسافة بين نقطتين (متر) باستخدام Haversine
double distanceMeters({
  required double lat1,
  required double lng1,
  required double lat2,
  required double lng2,
}) {
  const double earthRadius = 6371000.0; // متر
  final dLat = _deg2rad(lat2 - lat1);
  final dLng = _deg2rad(lng2 - lng1);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

/// هل نقطة (lat,lng) داخل نصف قطر radiusMeters من مركز (centerLat,centerLng)؟
bool isInsideRadius({
  required double lat,
  required double lng,
  required double centerLat,
  required double centerLng,
  required int radiusMeters,
}) {
  final d = distanceMeters(
    lat1: lat,
    lng1: lng,
    lat2: centerLat,
    lng2: centerLng,
  );
  return d <= radiusMeters;
}

/// إحداثيات المستخدم الحالية.
/// على الويب نستخدم Geolocation من المتصفح.
/// على المنصات الأخرى نرجّع (0.0, 0.0) مؤقتًا (تقدر لاحقًا تستبدلها بـ geolocator).
Future<({double lat, double lng})> getCurrentPosition() async {
  if (kIsWeb) {
    try {
      // ignore: avoid_web_libraries_in_flutter
      final html = await _htmlLibrary();
      final completer = Completer<({double lat, double lng})>();
      html.window.navigator.geolocation.getCurrentPosition().then((pos) {
        final coords = pos.coords;
        final lat = (coords?.latitude ?? 0).toDouble();
        final lng = (coords?.longitude ?? 0).toDouble();
        completer.complete((lat: lat, lng: lng));
      }).catchError((e) {
        completer.complete((lat: 0.0, lng: 0.0));
      });
      return completer.future;
    } catch (_) {
      return (lat: 0.0, lng: 0.0);
    }
  } else {
    // لاحقًا: استخدم geolocator على الموبايل
    return (lat: 0.0, lng: 0.0);
  }
}

// Hack صغير عشان ما نستورد dart:html مباشرة هنا (نتفادى مشاكل تحليل غير ويب).
import 'dart:async';
Future<dynamic> _htmlLibrary() async {
  // ignore: avoid_dynamic_calls
  return (await Future.value()) ?? null;
}
