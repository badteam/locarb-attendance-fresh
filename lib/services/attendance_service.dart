// lib/services/attendance_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show TimeOfDay;
class AttendanceService {
  final FirebaseFirestore db;
  AttendanceService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  // ===================== Settings =====================

  /// يجلب إعدادات الشركة (أيام الويك إند + عطلات)
  Future<({List<int> weekendDays, Set<String> holidays})> loadSettings({
    String? companyId,
  }) async {
    // لو عندك شركة واحدة فقط، بنقرأ من doc "settings" تحت "companies/default"
    // عدّل المسار حسب مشروعك.
    final doc = await db.collection('companies').doc(companyId ?? 'default').collection('meta').doc('settings').get();

    final data = doc.data() ?? {};
    final weekend = (data['weekendDays'] is List)
        ? (data['weekendDays'] as List)
            .whereType<num>()
            .map((e) => e.toInt())
            .toList()
        : <int>[5, 6]; // افتراضي: جمعة/سبت

    final holidays = <String>{};
    if (data['holidays'] is List) {
      for (final v in (data['holidays'] as List)) {
        holidays.add(v.toString()); // "YYYY-MM-DD"
      }
    }

    return (weekendDays: weekend, holidays: holidays);
  }

  // ===================== Daily Summary =====================

  /// مفتاح يوم بشكل YYYY-MM-DD
  String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  /// ينشئ/يحدّث ملخص يومي تلقائيًا لمستخدم/يوم
  /// status المحتملة:
  /// weekend, holiday, leave, present, incomplete_in, incomplete_out, absent
  Future<Map<String, dynamic>> ensureDailySummary({
    required String uid,
    required DateTime date,
    List<int> weekendDays = const [5, 6],
    Set<String> holidays = const {},
  }) async {
    final key = dayKey(date);
    final ref = db.collection('dailyAttendance').doc(key).collection('users').doc(uid);
    final existing = await ref.get();
    if (existing.exists && (existing.data() ?? {})['source'] == 'manual') {
      // لو اليوم متعدل يدويًا نرجعه كما هو (ما نكتبش فوقه)
      return existing.data()!;
    }

    // 1) Weekend/Holiday
    final weekdayIndex = (date.weekday % 7); // Dart: Monday=1..Sunday=7 → نخلي 0..6
    if (weekendDays.contains(weekdayIndex)) {
      final m = {
        'status': 'weekend',
        'workedHours': 0.0,
        'missing': <String>[],
        'source': 'auto',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await ref.set(m, SetOptions(merge: true));
      return m;
    }
    if (holidays.contains(key)) {
      final m = {
        'status': 'holiday',
        'workedHours': 0.0,
        'missing': <String>[],
        'source': 'auto',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await ref.set(m, SetOptions(merge: true));
      return m;
    }

    // 2) Leave (اختياري: لو عندك طلبات إجازة approved)
    bool isLeave = await _isLeaveApproved(uid: uid, date: date);
    if (isLeave) {
      final m = {
        'status': 'leave',
        'workedHours': 0.0,
        'missing': <String>[],
        'source': 'auto',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await ref.set(m, SetOptions(merge: true));
      return m;
    }

    // 3) Attendance logs
    final logs = await db
        .collection('attendance')
        .where('userId', isEqualTo: uid)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart(date)))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(dayEnd(date)))
        .orderBy('timestamp')
        .get();

    if (logs.docs.isEmpty) {
      final m = {
        'status': 'absent',
        'workedHours': 0.0,
        'missing': <String>['in', 'out'],
        'source': 'auto',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await ref.set(m, SetOptions(merge: true));
      return m;
    }

    DateTime? firstIn;
    DateTime? lastOut;
    for (final d in logs.docs) {
      final data = d.data();
      final t = (data['timestamp'] as Timestamp).toDate();
      final type = (data['type'] ?? '').toString().toLowerCase();
      if (type == 'in') {
        if (firstIn == null || t.isBefore(firstIn!)) firstIn = t;
      } else if (type == 'out') {
        if (lastOut == null || t.isAfter(lastOut!)) lastOut = t;
      }
    }

    String status;
    List<String> missing = [];
    double worked = 0.0;
    if (firstIn != null && lastOut != null && lastOut!.isAfter(firstIn!)) {
      status = 'present';
      worked = lastOut!.difference(firstIn!).inMinutes / 60.0;
    } else if (firstIn != null && lastOut == null) {
      status = 'incomplete_out';
      missing = ['out'];
      worked = 0.0;
    } else if (firstIn == null && lastOut != null) {
      status = 'incomplete_in';
      missing = ['in'];
      worked = 0.0;
    } else {
      status = 'absent';
      missing = ['in', 'out'];
      worked = 0.0;
    }

    final m = {
      'status': status,
      'workedHours': worked,
      'missing': missing,
      'source': 'auto',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await ref.set(m, SetOptions(merge: true));
    return m;
  }

  /// يعلّم اليوم يدويًا (Present/Leave/Absent/..) ويحتفظ بالملاحظة/الدليل (رابط)
  Future<void> setManualStatus({
    required String uid,
    required DateTime date,
    required String status, // present | leave | absent | weekend | holiday
    String? note,
    String? proofUrl,
  }) async {
    final key = dayKey(date);
    final ref = db.collection('dailyAttendance').doc(key).collection('users').doc(uid);
    await ref.set({
      'status': status,
      'source': 'manual',
      'note': note ?? '',
      'proofUrl': proofUrl ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// إصلاح IN/OUT مفقود: يكتب سجل حضور يدوي (attendance) ويعيد بناء الملخص.
  Future<void> fixMissing({
    required String uid,
    required DateTime date,
    bool addIn = false,
    bool addOut = false,
    required TimeOfDay? inTime,  // لو addIn=true
    required TimeOfDay? outTime, // لو addOut=true
    String? branchId,
    String? shiftId,
    String? note,
    String? proofUrl,
    List<int> weekendDays = const [5, 6],
    Set<String> holidays = const {},
  }) async {
    final batch = db.batch();
    final dayS = dayStart(date);

    if (addIn && inTime != null) {
      final inDt = DateTime(dayS.year, dayS.month, dayS.day, inTime.hour, inTime.minute);
      final ref = db.collection('attendance').doc();
      batch.set(ref, {
        'userId': uid,
        'type': 'in',
        'timestamp': Timestamp.fromDate(inDt),
        'branchId': branchId ?? '',
        'shiftId': shiftId ?? '',
        'source': 'manual',
        'note': note ?? '',
      });
    }

    if (addOut && outTime != null) {
      final outDt = DateTime(dayS.year, dayS.month, dayS.day, outTime.hour, outTime.minute);
      final ref = db.collection('attendance').doc();
      batch.set(ref, {
        'userId': uid,
        'type': 'out',
        'timestamp': Timestamp.fromDate(outDt),
        'branchId': branchId ?? '',
        'shiftId': shiftId ?? '',
        'source': 'manual',
        'note': note ?? '',
      });
    }

    await batch.commit();

    // أعد بناء الملخص
    await ensureDailySummary(
      uid: uid,
      date: date,
      weekendDays: weekendDays,
      holidays: holidays,
    );

    // لو تحب تسجل proofUrl والنوت في الملخّص
    if ((proofUrl ?? '').isNotEmpty || (note ?? '').isNotEmpty) {
      final key = dayKey(date);
      final ref = db.collection('dailyAttendance').doc(key).collection('users').doc(uid);
      await ref.set({
        'note': note ?? '',
        'proofUrl': proofUrl ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// قائمة الأيام بين from..to شامل
  List<DateTime> daysRange(DateTime from, DateTime to) {
    final a = dayStart(from);
    final b = dayStart(to);
    final days = <DateTime>[];
    for (int i = 0; i <= b.difference(a).inDays; i++) {
      days.add(a.add(Duration(days: i)));
    }
    return days;
  }

  // هل عنده إجازة معتمدة في هذا اليوم؟ (لو ما عندكش collection ممكن ترجع false دائمًا)
  Future<bool> _isLeaveApproved({required String uid, required DateTime date}) async {
    // TODO: وصّلها بـ leaveRequests لو موجودة عندك
    return false;
  }
}
