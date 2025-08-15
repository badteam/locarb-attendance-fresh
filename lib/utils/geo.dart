import 'dart:async';
import 'dart:html' as html; // للويب فقط

class Geo {
  static Future<({double lat, double lng})> currentPosition() async {
    final c = Completer<({double lat, double lng})>();
    if (html.window.navigator.geolocation == null) {
      return (lat: 0, lng: 0); // فشل
    }
    html.window.navigator.geolocation!.getCurrentPosition()
      .then((pos) {
        final crd = pos.coords;
        c.complete((lat: crd?.latitude ?? 0, lng: crd?.longitude ?? 0));
      })
      .catchError((_) => c.complete((lat: 0, lng: 0)));
    return c.future;
  }

  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    // Haversine
    const R = 6371000; // m
    double dLat = _deg2rad(lat2 - lat1);
    double dLon = _deg2rad(lon2 - lon1);
    double a = 
      (Math.sin(dLat/2) * Math.sin(dLat/2)) +
      Math.cos(_deg2rad(lat1)) * Math.cos(_deg2rad(lat2)) *
      (Math.sin(dLon/2) * Math.sin(dLon/2));
    double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
  }
}

class Math {
  static double sin(double x) => html.window.math.sin(x);
  static double cos(double x) => html.window.math.cos(x);
  static double sqrt(num x) => html.window.math.sqrt(x.toDouble());
  static double atan2(num y, num x) => html.window.math.atan2(y.toDouble(), x.toDouble());
}

double _deg2rad(double d) => d * 3.141592653589793 / 180.0;
