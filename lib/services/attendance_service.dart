import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/geo.dart';

class AttendanceService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> checkInOut({required bool isCheckIn}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // اقرأ بيانات المستخدم لمعرفة الفرع المعيّن
    final userSnap = await _db.doc('users/$uid').get();
    final user = userSnap.data() ?? {};
    final branchId = (user['branchId'] ?? '').toString();
    if (branchId.isEmpty) {
      throw Exception('لم يتم تعيين فرع للمستخدم.');
    }

    // اقرأ بيانات الفرع (الموقع ونصف القطر)
    final branchSnap = await _db.doc('branches/$branchId').get();
    if (!branchSnap.exists) {
      throw Exception('لم يتم العثور على الفرع.');
    }
    final b = branchSnap.data()!;
    final geo = (b['geo'] ?? {}) as Map<String, dynamic>;
    final centerLat = (geo['lat'] ?? 0).toDouble();
    final centerLng = (geo['lng'] ?? 0).toDouble();
    final radius = (geo['radiusMeters'] ?? 150).toDouble();

    // موقع المستخدم الآن
    final pos = await Geo.currentPosition();
    if (pos.lat == 0 && pos.lng == 0) {
      throw Exception('فشل الحصول على الموقع. يُرجى السماح للموقع في المتصفح.');
    }

    // تحقق الجيوفنس
    final dist = Geo.distanceMeters(pos.lat, pos.lng, centerLat, centerLng);
    if (dist > radius) {
      throw Exception('خارج نطاق موقع الفرع (${dist.toStringAsFixed(0)} م / المسموح $radius م).');
    }

    // اكتب سجل حضور
    final now = DateTime.now();
    final dayKey = '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';

    final doc = _db.collection('attendance').doc(); // سجل منفصل لكل حركة
    await doc.set({
      'userId': uid,
      'branchId': branchId,
      'type': isCheckIn ? 'in' : 'out',
      'at': FieldValue.serverTimestamp(),
      'localDay': dayKey,
      'lat': pos.lat,
      'lng': pos.lng,
      'distance': dist, // للمراجعة
    });
  }
}
