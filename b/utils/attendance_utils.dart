// lib/utils/attendance_utils.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class WeekendConfig {
  final Set<int> weekendDays; // 0=Sun ... 6=Sat
  final Set<String> holidays; // 'YYYY-MM-DD'
  const WeekendConfig({required this.weekendDays, required this.holidays});
}

class AttendanceUtils {
  AttendanceUtils(this.db);
  final FirebaseFirestore db;

  Future<WeekendConfig> loadWeekendConfig() async {
    try {
      final snap = await db.collection('settings').doc('global').get();
      final m = snap.data() ?? {};
      final wd = (m['weekendDays'] as List?)?.map((e) => (e as num).toInt()).toSet() ?? {5, 6}; // Fri, Sat
      final hd = (m['holidays'] as List?)?.map((e) => e.toString()).toSet() ?? <String>{};
      return WeekendConfig(weekendDays: wd, holidays: hd);
    } catch (_) {
      return const WeekendConfig(weekendDays: {5, 6}, holidays: {});
    }
  }

  /// يبني/يحدث ملخص يوم واحد لمستخدم.
  /// لو لقى doc موجود ومصدره manual، مش هيعدّل إلا لو force=true.
  Future<void> ensureDailySummaryForUserDay({
    required String uid,
    required DateTime dayUtc, // استخدم تاريخ اليوم (midnight) بتوقيتك/UTC
    bool force = false,
  }) async {
    final day = DateTime(dayUtc.year, dayUtc.month, dayUtc.day); // normalize
    final dayKey = _dayKey(day);
    final docRef = db.collection('dailyAttendance').doc(dayKey).collection('users').doc(uid);
    final exist = await docRef.get();

    if (exist.exists && (exist.data()?['source'] ?? 'auto') == 'manual' && !force) {
      return; // لا نلمسه لو اتعدّل يدويًا
    }

    // إعدادات الويك إند/العطلات
    final cfg = await loadWeekendConfig();
    final isHoliday = cfg.holidays.contains(dayKey);
    final isWeekend = cfg.weekendDays.contains(day.weekday % 7); // Sunday=7 => 0; نخليها 0..6

    // هل عنده طلب اجازة Approved يغطي اليوم؟ (اختياري—لو مش عندك, هتكون false)
    final approvedLeave = await _hasApprovedLeave(uid: uid, day: day);

    if (isHoliday) {
      await _writeSummary(docRef, {
        'uid': uid,
        'day': dayKey,
        'date': Timestamp.fromDate(day),
        'status': 'holiday',
        'workedHours': 0.0,
        'flags': _flags(),
        'source': 'auto',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    if (isWeekend) {
      await _writeSummary(docRef, {
        'uid': uid,
        'day': dayKey,
        'date': Timestamp.fromDate(day),
        'status': 'weekend',
        'workedHours': 0.0,
        'flags': _flags(),
        'source': 'auto',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }
    if (approvedLeave) {
      await _writeSummary(docRef, {
        'uid': uid,
        'day': dayKey,
        'date': Timestamp.fromDate(day),
        'status': 'leave',
        'workedHours': 0.0,
        'flags': _flags(),
        'source': 'auto',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    // لو يوم عمل عادي: شوف attendance logs
    final events = await _loadAttendanceForDay(uid: uid, day: day);
    if (events.isEmpty) {
      await _writeSummary(docRef, {
        'uid': uid,
        'day': dayKey,
        'date': Timestamp.fromDate(day),
        'status': 'absent',
        'workedHours': 0.0,
        'flags': _flags(missingIn: true, missingOut: true),
        'source': 'auto',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return;
    }

    // اكتشف الأنومالي: أول IN وآخر OUT
    DateTime? firstIn, lastOut;
    bool missingIn = true, missingOut = true, outBeforeIn = false;
    for (final e in events) {
      final t = (e['timestamp'] as Timestamp).toDate();
      final type = (e['type'] ?? '').toString().toLowerCase();
      if (type == 'in') {
        missingIn = false;
        if (firstIn == null || t.isBefore(firstIn!)) firstIn = t;
      } else if (type == 'out') {
        missingOut = false;
        if (lastOut == null || t.isAfter(lastOut!)) lastOut = t;
      }
    }
    if (firstIn != null && lastOut != null && lastOut!.isBefore(firstIn!)) {
      outBeforeIn = true;
    }
    final worked = (firstIn != null && lastOut != null)
        ? (lastOut!.difference(firstIn!).inMinutes / 60.0)
        : 0.0;

    await _writeSummary(docRef, {
      'uid': uid,
      'day': dayKey,
      'date': Timestamp.fromDate(day),
      'status': 'present',
      'workedHours': worked < 0 ? 0.0 : worked,
      'flags': _flags(missingIn: missingIn, missingOut: missingOut, outBeforeIn: outBeforeIn),
      'source': 'auto',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// يبني ملخصات لمدى زمني لمستخدم واحد
  Future<void> ensureDailySummaryForRangeOne({
    required String uid,
    required DateTime from,
    required DateTime to,
    bool force = false,
  }) async {
    var cur = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    int guard = 0;
    while (!cur.isAfter(end) && guard < 200) {
      await ensureDailySummaryForUserDay(uid: uid, dayUtc: cur, force: force);
      cur = cur.add(const Duration(days: 1));
      guard++;
    }
  }

  // =============== Privates ===============
  Future<bool> _hasApprovedLeave({required String uid, required DateTime day}) async {
    try {
      final from = DateTime(day.year, day.month, day.day);
      final to = from.add(const Duration(days: 1));
      final q = await db
          .collection('leaveRequests')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'approved')
          .where('start', isLessThan: Timestamp.fromDate(to))
          .where('end', isGreaterThan: Timestamp.fromDate(from))
          .limit(1)
          .get();
      return q.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> _loadAttendanceForDay({
    required String uid,
    required DateTime day,
  }) async {
    final start = Timestamp.fromDate(day);
    final end = Timestamp.fromDate(day.add(const Duration(days: 1)));
    final qs = await db
        .collection('attendance')
        .where('userId', isEqualTo: uid)
        .where('timestamp', isGreaterThanOrEqualTo: start)
        .where('timestamp', isLessThan: end)
        .orderBy('timestamp')
        .get();
    return qs.docs.map((d) => d.data()).toList();
  }

  Map<String, dynamic> _flags({bool missingIn = false, bool missingOut = false, bool outBeforeIn = false}) {
    return {
      'missingIn': missingIn,
      'missingOut': missingOut,
      'outBeforeIn': outBeforeIn,
      'outsideGeofence': false,
    };
  }

  Future<void> _writeSummary(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) {
    return ref.set(data, SetOptions(merge: true));
  }

  String _dayKey(DateTime d) => '${d.year}-${_2(d.month)}-${_2(d.day)}';
  String _2(int n) => n.toString().padLeft(2, '0');
}
