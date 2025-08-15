import 'package:cloud_firestore/cloud_firestore.dart';

class DBInit {
  static final _db = FirebaseFirestore.instance;

  /// ينشئ المستند الخاص بالمستخدم لو مش موجود
  static Future<void> ensureCurrentUserDoc({
    required String uid,
    required String username,
    required String? email,
    required String fullName,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    final snap = await userRef.get();

    if (!snap.exists) {
      await userRef.set({
        'uid': uid,
        'username': username,
        'email': email,
        'fullName': fullName.isEmpty ? username : fullName,
        'role': 'employee',         // الاعتماد: موافقة الأدمن لاحقًا
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// ينشئ وثائق/مجموعات أساسية لو مش موجودة
  static Future<void> ensureBaseCollections() async {
    // 1) companies
    await _ensureOnce('companies', {
      'name': 'LoCarb',
      'code': 'LOCARB',
      'currency': 'SAR',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2) branches
    await _ensureOnce('branches', {
      'name': 'Head Office',
      'code': 'HO',
      'address': 'Riyadh',
      'geo': {'lat': 24.7136, 'lng': 46.6753, 'radiusMeters': 150},
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 3) shifts (نموذج وردية أساسية)
    await _ensureOnce('shifts', {
      'name': 'Default Shift',
      'code': 'SHIFT_A',
      'start': '09:00',
      'end': '17:00',
      'breakMinutes': 60,
      'workingDays': [1,2,3,4,5], // الأحد-الخميس
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 4) attendance (علامة تهيئة فقط)
    await _ensureOnce('attendance', {
      'init': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 5) leaveRequests (علامة تهيئة)
    await _ensureOnce('leaveRequests', {
      'init': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 6) salaryRecords (علامة تهيئة)
    await _ensureOnce('salaryRecords', {
      'init': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// helper: لو الكوليكشن فاضي يضيف مستند افتراضي واحد
  static Future<void> _ensureOnce(String collection, Map<String, dynamic> doc) async {
    final q = await _db.collection(collection).limit(1).get();
    if (q.docs.isEmpty) {
      await _db.collection(collection).add(doc);
    }
  }
}
