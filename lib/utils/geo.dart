// lib/utils/geo.dart
import 'dart:async';
import 'dart:html' as html; // للويب فقط
import 'dart:math' as math;

class Geo {
  /// يحصل على إحداثيات المستخدم من المتصفح (Web).
  /// لو فشل/رفض الإذن يرجّع (0.0, 0.0).
  static Future<({double lat, double lng})> currentPosition({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final geo = html.window.navigator.geolocation;
    if (geo == null) {
      return (lat: 0.0, lng: 0.0);
    }

    final c = Completer<({double lat, double lng})>();
    final t = Timer(timeout, () {
      if (!c.isCompleted) c.complete((lat: 0.0, lng: 0.0));
    });

    geo.getCurrentPosition().then((pos) {
      final coords = pos.coords;
      final lat = (coords?.latitude ?? 0).toDouble();
      final lng = (coords?.longitude ?? 0).toDouble();
      if (!c.isCompleted) c.complete((lat: lat, lng: lng));
    }).catchError((_) {
      if (!c.isCompleted) c.complete((lat: 0.0, lng: 0.0));
    });

    final result = await c.future;
    t.cancel();
    return result;
    }

  /// مسافة هافرسين بالمتر بين نقطتين (lat/lng).
  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0; // نصف قطر الأرض بالمتر
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _deg2rad(double d) => d * (math.pi / 180.0);
}
