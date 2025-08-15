import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/geo.dart';

class AttendanceService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> checkInOut({required bool isCheckIn}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // 1) Read user to know branch/shift and "any-branch" capability
    final userSnap = await _db.doc('users/$uid').get();
    final user = userSnap.data() ?? {};
    final assignedBranchId = (user['branchId'] ?? '').toString();
    final shiftId = (user['shiftId'] ?? '').toString();
    final canAny = (user['canCheckFromAnyBranch'] ?? false) == true;

    if (!canAny && assignedBranchId.isEmpty) {
      throw Exception('No branch assigned to the user.');
    }

    // 2) Current position
    final pos = await Geo.currentPosition();
    if (pos.lat == 0.0 && pos.lng == 0.0) {
      throw Exception('Failed to get location. Please allow location access.');
    }

    String usedBranchId = assignedBranchId;
    double centerLat = 0, centerLng = 0, radius = 0;

    if (canAny) {
      // 3A) Find nearest branch within its radius
      final branches = await _db.collection('branches').get();
      double bestDist = double.infinity;
      String bestId = '';
      double bestLat = 0, bestLng = 0, bestRad = 0;

      for (final b in branches.docs) {
        final data = b.data();
        final geo = (data['geo'] ?? {}) as Map<String, dynamic>;
        final lat = (geo['lat'] ?? 0).toDouble();
        final lng = (geo['lng'] ?? 0).toDouble();
        final rad = (geo['radiusMeters'] ?? 150).toDouble();
        if (lat == 0 || lng == 0) continue;

        final d = Geo.distanceMeters(pos.lat, pos.lng, lat, lng);
        if (d <= rad && d < bestDist) {
          bestDist = d;
          bestId = b.id;
          bestLat = lat;
          bestLng = lng;
          bestRad = rad;
        }
      }

      if (bestId.isEmpty) {
        throw Exception('You are not within any branch geofence.');
      }

      usedBranchId = bestId;
      centerLat = bestLat;
      centerLng = bestLng;
      radius = bestRad;
    } else {
      // 3B) Use assigned branch geofence
      final branchSnap = await _db.doc('branches/$assignedBranchId').get();
      if (!branchSnap.exists) {
        throw Exception('Branch not found.');
      }
      final b = branchSnap.data()!;
      final geo = (b['geo'] ?? {}) as Map<String, dynamic>;
      centerLat = (geo['lat'] ?? 0).toDouble();
      centerLng = (geo['lng'] ?? 0).toDouble();
      radius = (geo['radiusMeters'] ?? 150).toDouble();

      final d = Geo.distanceMeters(pos.lat, pos.lng, centerLat, centerLng);
      if (d > radius) {
        throw Exception('Outside assigned branch radius '
            '(${d.toStringAsFixed(0)} m / allowed $radius m).');
      }
    }

    // 4) Write attendance record
    final now = DateTime.now();
    final dayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final doc = _db.collection('attendance').doc();
    await doc.set({
      'userId': uid,
      'branchId': usedBranchId,   // ← actual branch used (assigned or nearest)
      'shiftId': shiftId,
      'type': isCheckIn ? 'in' : 'out',
      'at': FieldValue.serverTimestamp(),
      'localDay': dayKey,
      'lat': pos.lat,
      'lng': pos.lng,
      // distance: بنحسبها فقط في حالة الفرع المعيّن، والآن ليست مطلوبة لنجاح العملية
    });
  }
}
