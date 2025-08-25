// lib/screens/attendance_report_screen.dart
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:convert'; // للتصدير CSV

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../widgets/main_drawer.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({
    super.key,
    this.userId,
    this.userName,
    this.initialRange,
    this.branchId,
    this.shiftId,
    this.onlyExceptions = true,
    this.allowEditing = true,
  });

  final String? userId;
  final String? userName;
  final DateTimeRange? initialRange;
  final String? branchId;
  final String? shiftId;
  final bool onlyExceptions;
  final bool allowEditing;

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  late DateTime _from;
  late DateTime _to;
  String? _branchId;
  String? _shiftId;
  late bool _onlyEx;

  // caches
  final Map<String, Map<String, dynamic>> _usersCache = {};
  final Map<String, String> _userNames = {};
  final Map<String, String> _branchNames = {};
  final Map<String, String> _shiftNames  = {};

  @override
  void initState() {
    super.initState();
    _from = widget.initialRange?.start ?? DateTime.now().subtract(const Duration(days: 7));
    _to   = widget.initialRange?.end   ?? DateTime.now();
    _branchId = widget.branchId;
    _shiftId  = widget.shiftId;
    _onlyEx   = widget.onlyExceptions;
  }

  String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  DateTime _parseDay(String ymd) {
    final p = ymd.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }
  String _fmtTime(DateTime? dt) {
    if (dt == null) return '—';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  String _fmtHM(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _from = DateTime(d.year, d.month, d.day));
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _to = DateTime(d.year, d.month, d.day, 23, 59, 59));
  }

  Future<TimeOfDay?> _pickTime(String title) =>
      showTimePicker(context: context, helpText: title, initialTime: const TimeOfDay(hour: 9, minute: 0));

  // ======== كتابة IN/OUT + مسح absent ========
  Future<void> _setPunch({
    required String uid,
    required String localDay,   // YYYY-MM-DD
    required String type,       // "in" | "out"
    required DateTime at,
    required String userName,
    required String branchId,
    required String branchName,
    required String shiftId,
    required String shiftName,
  }) async {
    final col = FirebaseFirestore.instance.collection('attendance');

    final punchId  = '${uid}_${localDay}_$type';
    final absentId = '${uid}_${localDay}_absent';

    final batch = FirebaseFirestore.instance.batch();
    final punchRef  = col.doc(punchId);
    final absentRef = col.doc(absentId);

    batch.set(punchRef, {
      'userId': uid,
      'userName': userName,
      'localDay': localDay,
      'type': type,
      'at': Timestamp.fromDate(at),
      'branchId': branchId,
      'branchName': branchName,
      'shiftId': shiftId,
      'shiftName': shiftName,
      'source': 'manual',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.delete(absentRef); // لو موجود

    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved. Absent cleared (if existed).')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  // ======== تعليم اليوم Off/Sick/Leave ========
  Future<void> _setDayStatus({
    required String uid,
    required String localDay,
    required String statusType, // "off" | "sick" | "leave"
    required String userName,
    required String branchId,
    required String branchName,
    required String shiftId,
    required String shiftName,
  }) async {
    final col = FirebaseFirestore.instance.collection('attendance');
    final statusId = '${uid}_${localDay}_$statusType';
    final absentId = '${uid}_${localDay}_absent';

    final batch = FirebaseFirestore.instance.batch();
    batch.set(col.doc(statusId), {
      'userId': uid,
      'userName': userName,
      'localDay': localDay,
      'type': statusType,
      'branchId': branchId,
      'branchName': branchName,
      'shiftId': shiftId,
      'shiftName': shiftName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.delete(col.doc(absentId)); // نظافة

    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked as ${statusType.toUpperCase()}')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark day: $e')),
        );
      }
    }
  }

  // ======== Reset Auto: امسح حالات اليوم واترك IN/OUT ========
  Future<void> _resetDayAuto(String uid, String localDay) async {
    final col = FirebaseFirestore.instance.collection('attendance');
    final ids = [
      '${uid}_${localDay}_off',
      '${uid}_${localDay}_sick',
      '${uid}_${localDay}_leave',
      '${uid}_${localDay}_absent',
    ];
    final batch = FirebaseFirestore.instance.batch();
    for (final id in ids) {
      batch.delete(col.doc(id));
    }
    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Day reset to auto (kept IN/OUT).')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset failed: $e')),
        );
      }
    }
  }

  // ======== تصدير CSV من الملخصات ========
  Future<void> _exportCsvFromRows(List<_DaySummary> rows) async {
    final headers = [
      'Date','User','Branch','Shift','Status','IN','OUT',
      'Worked(HH:MM)','Scheduled(HH:MM)','OT(HH:MM)'
    ];
    final sb = StringBuffer();
    sb.writeln(headers.join(','));

    for (final r in rows) {
      final status = r.isOff ? 'Off'
        : r.isSick ? 'Sick'
        : r.isLeave ? 'Leave'
        : (r.hasIn && r.hasOut) ? 'Present'
        : (r.hasIn && !r.hasOut) ? 'Missing OUT'
        : (!r.hasIn && r.hasOut) ? 'Missing IN'
        : r.isAbsent ? 'Absent' : 'Absent';

      final worked = _fmtHM(r.workedMinutes);
      final scheduled = _fmtHM(r.scheduledMinutes);
      final ot = _fmtHM(r.overtimeMinutes);

      final row = [
        _fmtDay(r.date),
        r.userName.replaceAll(',', ' '),
        (r.branchName.isNotEmpty ? r.branchName : (_branchNames[r.branchId] ?? 'No branch')).replaceAll(',', ' '),
        (r.shiftName.isNotEmpty ? r.shiftName : (_shiftNames[r.shiftId] ?? 'No shift')).replaceAll(',', ' '),
        status,
        _fmtTime(r.inAt),
        _fmtTime(r.outAt),
        worked,
        scheduled,
        ot,
      ];
      sb.writeln(row.join(','));
    }

    final bytes = utf8.encode(sb.toString());
    final filename = 'attendance_${_fmtDay(_from)}_${_fmtDay(_to)}.csv';

    if (kIsWeb) {
      final blob = html.Blob([Uint8List.fromList(bytes)], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final a = html.AnchorElement(href: url)..download = filename;
      html.document.body!.children.add(a);
      a.click();
      html.document.body!.children.remove(a);
      html.Url.revokeObjectUrl(url);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV generated.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersRef    = FirebaseFirestore.instance.collection('users');
    final branchesRef = FirebaseFirestore.instance.collection('branches').orderBy('name');
    final shiftsRef   = FirebaseFirestore.instance.collection('shifts').orderBy('name');

    final q = FirebaseFirestore.instance
        .collection('attendance')
        .where('localDay', isGreaterThanOrEqualTo: _fmtDay(_from))
        .where('localDay', isLessThanOrEqualTo: _fmtDay(_to))
        .orderBy('localDay', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName ?? 'Attendance Reports'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: () async {
              // هنكوّن نفس rows المستخدمة في العرض ثم نصدّر
              final snap = await q.get();
              final computedRows = _computeRows(snap.docs);
              if (computedRows.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No records to export for this range')),
                );
                return;
              }
              await _exportCsvFromRows(computedRows);
            },
            icon: const Icon(Icons.file_download),
          ),
        ],
      ),
      drawer: const MainDrawer(),
      body: _MultiLoader(
        usersRef: usersRef,
        branchesRef: branchesRef,
        shiftsRef: shiftsRef,
        onUsers: (docs) {
          _userNames.clear();
          _usersCache.clear();
          for (final u in docs) {
            final m = u.data();
            final full = (m['fullName'] ?? m['name'] ?? '').toString();
            final uname = (m['username'] ?? '').toString();
            _userNames[u.id] = full.isNotEmpty ? full : (uname.isNotEmpty ? uname : u.id);
            _usersCache[u.id] = m;
          }
        },
        onBranches: (docs) {
          _branchNames.clear();
          for (final b in docs) {
            _branchNames[b.id] = (b.data()['name'] ?? b.id).toString();
          }
        },
        onShifts: (docs) {
          _shiftNames.clear();
          for (final s in docs) {
            _shiftNames[s.id] = (s.data()['name'] ?? s.id).toString();
          }
        },
        child: Column(
          children: [
            _filtersBar(branchesRef, shiftsRef),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: q.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) return _ErrorBox(error: snap.error.toString());
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final rows = _computeRows(snap.data?.docs ?? []);

                  if (rows.isEmpty) {
                    return const Center(child: Text('No records in the selected range'));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _rowTile(rows[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======== حساب الملخصات (with OT) ========
  List<_DaySummary> _computeRows(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // فلترة بالفرع/الشيفت + المستخدم
    final filtered = docs.where((d) {
      final m = d.data();
      if (widget.userId?.isNotEmpty == true && m['userId'] != widget.userId) return false;
      if (_branchId?.isNotEmpty == true && (m['branchId'] ?? '') != _branchId) return false;
      if (_shiftId?.isNotEmpty == true && (m['shiftId'] ?? '') != _shiftId) return false;
      return true;
    }).toList();

    // تجميع حسب (userId + localDay)
    final Map<String, _DaySummary> byUserDay = {};
    final Map<String, List<DateTime>> inTimes = {};
    final Map<String, List<DateTime>> outTimes = {};

    for (final d in filtered) {
      final m = d.data();
      final uid = (m['userId'] ?? '').toString();
      final day = (m['localDay'] ?? '').toString();
      if (uid.isEmpty || day.isEmpty) continue;

      final key = '$uid|$day';
      byUserDay.putIfAbsent(key, () {
        final u    = _usersCache[uid] ?? {};
        final bId  = (m['branchId'] ?? u['primaryBranchId'] ?? u['branchId'] ?? '').toString();
        final sId  = (m['shiftId']  ?? u['assignedShiftId'] ?? u['shiftId']  ?? '').toString();
        final bNm  = (m['branchName'] ?? u['branchName'] ?? _branchNames[bId] ?? '').toString();
        final sNm  = (m['shiftName']  ?? u['shiftName']  ?? _shiftNames[sId]  ?? '').toString();

        // سياسة العمل لكل موظف
        final wp = (u['workPolicy'] ?? {}) as Map<String, dynamic>;
        final workHours = (wp['workHoursPerDay'] is num)
            ? (wp['workHoursPerDay'] as num).toDouble()
            : 9.0;
        final weekendDays = (wp['weekendDays'] is List)
            ? (wp['weekendDays'] as List).map((e) => int.tryParse(e.toString()) ?? -1).where((e) => e >= 0).toList()
            : <int>[5, 6]; // افتراضي
        final holidays = (wp['holidays'] is List)
            ? (wp['holidays'] as List).map((e) => e.toString()).toSet()
            : <String>{};

        return _DaySummary(
          uid: uid,
          userName: _userNames[uid] ?? uid,
          localDay: day,
          date: _parseDay(day),
          branchId: bId,
          branchName: bNm,
          shiftId: sId,
          shiftName: sNm,
          workHoursPerDay: workHours,
          weekendDays: weekendDays,
          holidays: holidays,
        );
      });

      final typ = (m['type'] ?? '').toString();
      final at  = m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : null;

      if (typ == 'in' && at != null) {
        inTimes.putIfAbsent(key, () => []).add(at);
      } else if (typ == 'out' && at != null) {
        outTimes.putIfAbsent(key, () => []).add(at);
      } else if (typ == 'absent') {
        byUserDay[key]!.isAbsent = true;
      } else if (typ == 'off') {
        byUserDay[key]!.isOff = true;
      } else if (typ == 'sick') {
        byUserDay[key]!.isSick = true;
      } else if (typ == 'leave') {
        byUserDay[key]!.isLeave = true;
      }
    }

    // حساب العمل/الأوفر تايم
    for (final entry in byUserDay.entries) {
      final key = entry.key;
      final r = entry.value;

      // لو اليوم معلّم Off/Sick/Leave → تجميد الحسابات
      if (r.isOff || r.isSick || r.isLeave) {
        r.hasIn = r.hasOut = false;
        r.workedMinutes = 0;
        r.overtimeMinutes = 0;
        r.scheduledMinutes = 0;
        continue;
      }

      final ins = (inTimes[key] ?? [])..sort();
      final outs = (outTimes[key] ?? [])..sort();
      r.hasIn = ins.isNotEmpty;
      r.hasOut = outs.isNotEmpty;

      // قرن الأزواج: أقرب OUT لكل IN بالترتيب
      int i = 0, j = 0;
      int worked = 0;
      while (i < ins.length && j < outs.length) {
        final inT = ins[i];
        final outT = outs[j];
        if (outT.isBefore(inT)) { j++; continue; } // OUT قبل IN → تجاهله
        worked += outT.difference(inT).inMinutes;
        i++; j++;
      }
      r.workedMinutes = worked;

      final isWeekend = r.weekendDays.contains(r.date.weekday % 7); // نفس منطقك القديم
      final isHoliday = r.holidays.contains(r.localDay);
      final scheduled = (isWeekend || isHoliday)
          ? 0
          : (r.workHoursPerDay * 60).round();

      r.scheduledMinutes = scheduled;
      r.overtimeMinutes = (worked > scheduled) ? (worked - scheduled) : 0;

      // IN/OUT أحادية → Missing
      if (r.hasIn && !r.hasOut) r.missingOut = true;
      if (!r.hasIn && r.hasOut) r.missingIn  = true;

      // لو في أي IN/OUT نلغي غياب
      if (r.hasIn || r.hasOut) r.isAbsent = false;

      // أول قيم عرضية لـ IN/OUT
      r.inAt  = ins.isNotEmpty  ? ins.first  : null;
      r.outAt = outs.isNotEmpty ? outs.last  : null;
    }

    var rows = byUserDay.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (_onlyEx) {
      rows = rows.where((r) =>
        (r.isAbsent || r.missingIn || r.missingOut)
      ).toList();
    }
    return rows;
  }

  Widget _filtersBar(
    Query<Map<String, dynamic>> branchesRef,
    Query<Map<String, dynamic>> shiftsRef,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Wrap(
        runSpacing: 8,
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _pickFrom,
            icon: const Icon(Icons.date_range),
            label: Text('From: ${_fmtDay(_from)}'),
          ),
          OutlinedButton.icon(
            onPressed: _pickTo,
            icon: const Icon(Icons.event),
            label: Text('To: ${_fmtDay(_to)}'),
          ),
          // Branch
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: branchesRef.snapshots(),
            builder: (context, snap) {
              final items = <DropdownMenuItem<String>>[
                const DropdownMenuItem(value: '', child: Text('All branches')),
              ];
              if (snap.hasData) {
                for (final d in snap.data!.docs) {
                  _branchNames[d.id] = (d.data()['name'] ?? d.id).toString();
                  items.add(DropdownMenuItem(value: d.id, child: Text(_branchNames[d.id]!)));
                }
              }
              return InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Branch',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _branchId ?? '',
                    items: items,
                    onChanged: (v) => setState(() => _branchId = (v ?? '').isEmpty ? null : v),
                  ),
                ),
              );
            },
          ),
          // Shift
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: shiftsRef.snapshots(),
            builder: (context, snap) {
              final items = <DropdownMenuItem<String>>[
                const DropdownMenuItem(value: '', child: Text('All shifts')),
              ];
              if (snap.hasData) {
                for (final d in snap.data!.docs) {
                  _shiftNames[d.id] = (d.data()['name'] ?? d.id).toString();
                  items.add(DropdownMenuItem(value: d.id, child: Text(_shiftNames[d.id]!)));
                }
              }
              return InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Shift',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _shiftId ?? '',
                    items: items,
                    onChanged: (v) => setState(() => _shiftId = (v ?? '').isEmpty ? null : v),
                  ),
                ),
              );
            },
          ),
          // Only exceptions
          FilterChip(
            label: const Text('Only exceptions'),
            selected: _onlyEx,
            onSelected: (v) => setState(() => _onlyEx = v),
          ),
          // Export
          FilledButton.icon(
            onPressed: () async {
              final snap = await FirebaseFirestore.instance
                  .collection('attendance')
                  .where('localDay', isGreaterThanOrEqualTo: _fmtDay(_from))
                  .where('localDay', isLessThanOrEqualTo: _fmtDay(_to))
                  .orderBy('localDay', descending: true)
                  .get();
              final rows = _computeRows(snap.docs);
              if (rows.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No records to export for this range')),
                );
                return;
              }
              await _exportCsvFromRows(rows);
            },
            icon: const Icon(Icons.file_download),
            label: const Text('Export Excel'),
          ),
        ],
      ),
    );
  }

  Widget _rowTile(_DaySummary r) {
    // تحديد الحالة والعرض
    String status;
    Color color;

    if (r.isOff)   { status = 'Off';   color = Colors.grey;   }
    else if (r.isSick)  { status = 'Sick';  color = Colors.purple; }
    else if (r.isLeave) { status = 'Leave'; color = Colors.blue;   }
    else if (r.hasIn && r.hasOut) { status = 'Present';     color = Colors.green;  }
    else if (r.hasIn && !r.hasOut) { status = 'Missing OUT'; color = Colors.orange; }
    else if (!r.hasIn && r.hasOut) { status = 'Missing IN';  color = Colors.orange; }
    else if (r.isAbsent) { status = 'Absent'; color = Colors.red; }
    else { status = 'Absent'; color = Colors.red; }

    final displayBranch = r.branchName.isNotEmpty
        ? r.branchName
        : (_branchNames[r.branchId] ?? 'No branch');
    final displayShift = r.shiftName.isNotEmpty
        ? r.shiftName
        : (_shiftNames[r.shiftId] ?? 'No shift');

    final showOT = !(r.isOff || r.isSick || r.isLeave);
    final otChip = showOT ? Chip(label: Text('OT ${_fmtHM(r.overtimeMinutes)}')) : const SizedBox.shrink();

    return Card(
      child: ListTile(
        title: Text('${_fmtDay(r.date)} • ${r.userName}'),
        subtitle: Wrap(
          spacing: 8, runSpacing: 6, children: [
            Chip(label: Text(status), backgroundColor: color, labelStyle: const TextStyle(color: Colors.white)),
            Chip(label: Text('IN ${_fmtTime(r.inAt)}')),
            Chip(label: Text('OUT ${_fmtTime(r.outAt)}')),
            Chip(label: Text('Worked ${_fmtHM(r.workedMinutes)}')),
            Chip(label: Text('Sched ${_fmtHM(r.scheduledMinutes)}')),
            otChip,
            Chip(label: Text('Branch: $displayBranch')),
            Chip(label: Text('Shift: $displayShift')),
          ],
        ),
        trailing: widget.allowEditing ? PopupMenuButton<String>(
          onSelected: (v) async {
            final localDay = r.localDay;
            final userName = r.userName;
            final bId = r.branchId;
            final bName = displayBranch;
            final sId = r.shiftId;
            final sName = displayShift;

            if (v == 'fix_in' || v == 'edit_in') {
              final tod = await _pickTime(v == 'fix_in' ? 'Fix IN time' : 'Edit IN time');
              if (tod != null) {
                final when = DateTime(r.date.year, r.date.month, r.date.day, tod.hour, tod.minute);
                if (r.outAt != null && when.isAfter(r.outAt!)) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('IN cannot be after OUT')),
                    );
                  }
                  return;
                }
                await _setPunch(
                  uid: r.uid,
                  localDay: localDay,
                  type: 'in',
                  at: when,
                  userName: userName,
                  branchId: bId,
                  branchName: bName,
                  shiftId: sId,
                  shiftName: sName,
                );
                setState(() { r.setIn(when); r.isAbsent = false; });
              }
            }
            if (v == 'fix_out' || v == 'edit_out') {
              final tod = await _pickTime(v == 'fix_out' ? 'Fix OUT time' : 'Edit OUT time');
              if (tod != null) {
                final when = DateTime(r.date.year, r.date.month, r.date.day, tod.hour, tod.minute);
                if (r.inAt != null && when.isBefore(r.inAt!)) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('OUT cannot be before IN')),
                    );
                  }
                  return;
                }
                await _setPunch(
                  uid: r.uid,
                  localDay: localDay,
                  type: 'out',
                  at: when,
                  userName: userName,
                  branchId: bId,
                  branchName: bName,
                  shiftId: sId,
                  shiftName: sName,
                );
                setState(() { r.setOut(when); r.isAbsent = false; });
              }
            }
            if (v == 'mark_off' || v == 'mark_sick' || v == 'mark_leave') {
              final st = v == 'mark_off' ? 'off' : (v == 'mark_sick' ? 'sick' : 'leave');
              await _setDayStatus(
                uid: r.uid,
                localDay: localDay,
                statusType: st,
                userName: userName,
                branchId: bId,
                branchName: bName,
                shiftId: sId,
                shiftName: sName,
              );
            }
            if (v == 'reset_auto') {
              await _resetDayAuto(r.uid, localDay);
            }
          },
          itemBuilder: (_) => [
            if (!r.hasIn)  const PopupMenuItem(value: 'fix_in',  child: Text('Fix IN…')),
            if (!r.hasOut) const PopupMenuItem(value: 'fix_out', child: Text('Fix OUT…')),
            if (r.hasIn)   const PopupMenuItem(value: 'edit_in',  child: Text('Edit IN time…')),
            if (r.hasOut)  const PopupMenuItem(value: 'edit_out', child: Text('Edit OUT time…')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'mark_off',  child: Text('Mark day: Off')),
            const PopupMenuItem(value: 'mark_sick', child: Text('Mark day: Sick')),
            const PopupMenuItem(value: 'mark_leave',child: Text('Mark day: Leave')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'reset_auto', child: Text('Reset day (auto)')),
          ],
        ) : null,
      ),
    );
  }
}

// ====== موديل اليوم الواحد ======
class _DaySummary {
  final String uid;
  final String userName;
  final String localDay;
  final DateTime date;
  final String branchId;
  final String branchName;
  final String shiftId;
  final String shiftName;

  // سياسة الموظف
  final double workHoursPerDay;
  final List<int> weekendDays; // 0..6 (أحد..سبت) مثل منطقك القديم
  final Set<String> holidays;  // YYYY-MM-DD

  bool hasIn = false;
  bool hasOut = false;
  bool missingIn = false;
  bool missingOut = false;
  bool isAbsent = false;
  bool isOff = false;
  bool isSick = false;
  bool isLeave = false;

  int workedMinutes = 0;
  int scheduledMinutes = 0;
  int overtimeMinutes = 0;

  DateTime? inAt;
  DateTime? outAt;

  _DaySummary({
    required this.uid,
    required this.userName,
    required this.localDay,
    required this.date,
    required this.branchId,
    required this.branchName,
    required this.shiftId,
    required this.shiftName,
    this.workHoursPerDay = 9.0,
    this.weekendDays = const [5,6],
    this.holidays = const {},
  });

  void setIn(DateTime? t) { hasIn = true; if (t != null) inAt = t; }
  void setOut(DateTime? t){ hasOut = true; if (t != null) outAt = t; }

  bool get isException => isAbsent || missingIn || missingOut;
}

// ====== Loader ======
class _MultiLoader extends StatelessWidget {
  const _MultiLoader({
    required this.usersRef,
    required this.branchesRef,
    required this.shiftsRef,
    required this.onUsers,
    required this.onBranches,
    required this.onShifts,
    required this.child,
  });

  final CollectionReference<Map<String, dynamic>> usersRef;
  final Query<Map<String, dynamic>> branchesRef;
  final Query<Map<String, dynamic>> shiftsRef;
  final void Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>) onUsers;
  final void Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>) onBranches;
  final void Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>) onShifts;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: usersRef.snapshots(),
      builder: (context, usersSnap) {
        if (usersSnap.hasData) onUsers(usersSnap.data!.docs);
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: branchesRef.snapshots(),
          builder: (context, brSnap) {
            if (brSnap.hasData) onBranches(brSnap.data!.docs);
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: shiftsRef.snapshots(),
              builder: (context, shSnap) {
                if (shSnap.hasData) onShifts(shSnap.data!.docs);
                return child;
              },
            );
          },
        );
      },
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Query error:\n$error\n\nIf an index is required, select "All branches/shifts" or create the suggested index in Firestore.',
          ),
        ),
      ),
    );
  }
}
