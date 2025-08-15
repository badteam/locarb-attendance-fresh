import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/geo.dart';

class AttendanceService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> checkInOut({required bool isCheckIn}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // 1) Read user to know branch & shift
    final userSnap = await _db.doc('users/$uid').get();
    final user = userSnap.data() ?? {};
    final branchId = (user['branchId'] ?? '').toString();
    final shiftId = (user['shiftId'] ?? '').toString();
    if (branchId.isEmpty) {
      throw Exception('No branch assigned to the user.');
    }

    // 2) Read branch geo radius
    final branchSnap = await _db.doc('branches/$branchId').get();
    if (!branchSnap.exists) {
      throw Exception('Branch not found.');
    }
    final b = branchSnap.data()!;
    final geo = (b['geo'] ?? {}) as Map<String, dynamic>;
    final centerLat = (geo['lat'] ?? 0).toDouble();
    final centerLng = (geo['lng'] ?? 0).toDouble();
    final radius = (geo['radiusMeters'] ?? 150).toDouble();

    // 3) Current position
    final pos = await Geo.currentPosition();
    if (pos.lat == 0.0 && pos.lng == 0.0) {
      throw Exception('Failed to get location. Please allow location access.');
    }

    // 4) Geofence check
    final dist = Geo.distanceMeters(pos.lat, pos.lng, centerLat, centerLng);
    if (dist > radius) {
      throw Exception('Outside branch radius (${dist.toStringAsFixed(0)} m / allowed $radius m).');
    }

    // 5) Write attendance record
    final now = DateTime.now();
    final dayKey = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';

    final doc = _db.collection('attendance').doc();
    await doc.set({
      'userId': uid,
      'branchId': branchId,
      'shiftId': shiftId,                 // ⬅️ NEW
      'type': isCheckIn ? 'in' : 'out',
      'at': FieldValue.serverTimestamp(),
      'localDay': dayKey,
      'lat': pos.lat,
      'lng': pos.lng,
      'distance': dist,
    });
  }
}
