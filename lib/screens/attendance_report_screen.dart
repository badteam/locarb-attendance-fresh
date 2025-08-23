// lib/screens/attendance_report_screen.dart
import 'dart:typed_data';
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// لو مش محتاج التصدير حالياً، تقدر تشيل import + كل ما يخص _exportExcel
import '../utils/export.dart';
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

  // ========= أهم جزء: الحفظ + حذف أي absent =========
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
    final docId = '${uid}_${localDay}_$type';

    // 1) سجل IN/OUT بنفس الـ schema
    await col.doc(docId).set({
      'userId': uid,
      'userName': userName,
      'localDay': localDay,
      'type': type,
      'at': Timestamp.fromDate(at),
      'branchId': branchId,
      'branchName': branchName,
      'shiftId': shiftId,
      'shiftName': shiftName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2) امسح أي مستند غياب لنفس اليوم/الموظف
    final abs = await col
        .where('userId', isEqualTo: uid)
        .where('localDay', isEqualTo: localDay)
        .where('type', isEqualTo: 'absent')
        .get();
    for (final d in abs.docs) {
      await d.reference.delete();
    }
  }

  // (اختياري) تصدير اكسل
  Future<void> _exportExcel() async {
    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('attendance')
          .where('localDay', isGreaterThanOrEqualTo: _fmtDay(_from))
          .where('localDay', isLessThanOrEqualTo: _fmtDay(_to))
          .orderBy('localDay', descending: false);

      final snap = await q.get();
      var docs = snap.docs;

      if (widget.userId?.isNotEmpty == true) {
        docs = docs.where((d) => (d.data()['userId'] ?? '') == widget.userId).toList();
      }
      if (_branchId?.isNotEmpty == true) {
        docs = docs.where((d) => (d.data()['branchId'] ?? '') == _branchId).toList();
      }
      if (_shiftId?.isNotEmpty == true) {
        docs = docs.where((d) => (d.data()['shiftId'] ?? '') == _shiftId).toList();
      }
      if (docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No records to export for this range')));
        return;
      }

      final uidSet = <String>{};
      for (final d in docs) {
        final uid = (d.data()['userId'] ?? '').toString();
        if (uid.isNotEmpty) uidSet.add(uid);
      }
      final names = Map<String, String>.from(_userNames);
      for (final uid in uidSet) {
        names.putIfAbsent(uid, () => uid);
      }

      final bytes = await Export.buildPivotExcelBytes(
        attendanceDocs: docs,
        from: _from,
        to: _to,
        userNames: names,
      );
      final filename = 'attendance_${_fmtDay(_from)}_${_fmtDay(_to)}.xlsx';

      if (kIsWeb) {
        final blob = html.Blob([Uint8List.fromList(bytes)]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final a = html.AnchorElement(href: url)..download = filename;
        html.document.body!.children.add(a);
        a.click();
        html.document.body!.children.remove(a);
        html.Url.revokeObjectUrl(url);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel generated.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
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
        .orderBy('localDay', descending: true); // نجيب in/out/absent

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName ?? 'Attendance Reports'),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            onPressed: _exportExcel,
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

                  final docs = snap.data?.docs ?? [];

                  // فلترة بسيطة
                  final filtered = docs.where((d) {
                    final m = d.data();
                    if (widget.userId?.isNotEmpty == true && m['userId'] != widget.userId) return false;
                    if (_branchId?.isNotEmpty == true && m['branchId'] != _branchId) return false;
                    if (_shiftId?.isNotEmpty == true && m['shiftId'] != _shiftId) return false;
                    return true;
                  }).toList();

                  // ====== تجميع حسب (userId + localDay) ======
                  final Map<String, _DaySummary> byUserDay = {};
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

                      return _DaySummary(
                        uid: uid,
                        userName: _userNames[uid] ?? uid,
                        localDay: day,
                        date: _parseDay(day),
                        branchId: bId,
                        branchName: bNm,
                        shiftId: sId,
                        shiftName: sNm,
                      );
                    });

                    final typ = (m['type'] ?? '').toString();
                    final at  = m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : null;

                    if (typ == 'in')  byUserDay[key]!.setIn(at);
                    if (typ == 'out') byUserDay[key]!.setOut(at);
                    if (typ == 'absent') byUserDay[key]!.isAbsent = true;
                  }

                  // لو فيه IN/OUT اعتبره ليس غياب
                  for (final r in byUserDay.values) {
                    if (r.hasIn || r.hasOut) r.isAbsent = false;
                  }

                  var rows = byUserDay.values.toList()..sort((a, b) => b.date.compareTo(a.date));
                  if (_onlyEx) rows = rows.where((r) => r.isException).toList();

                  if (rows.isEmpty) return const Center(child: Text('No records in the selected range'));
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
            onPressed: _exportExcel,
            icon: const Icon(Icons.file_download),
            label: const Text('Export Excel'),
          ),
        ],
      ),
    );
  }

  Widget _rowTile(_DaySummary r) {
    String status;
    Color color;
    if (r.hasIn && r.hasOut) { status = 'Present';     color = Colors.green;  }
    else if (r.hasIn && !r.hasOut) { status = 'Missing OUT'; color = Colors.orange; }
    else if (!r.hasIn && r.hasOut) { status = 'Missing IN';  color = Colors.orange; }
    else if (r.isAbsent) { status = 'Absent'; color = Colors.red; }
    else { status = 'Absent'; color = Colors.red; }

    final displayBranch = r.branchName.isNotEmpty
        ? r.branchName
        : (_branchNames[r.branchId] ?? (_usersCache[r.uid]?['branchName'] ?? 'No branch')).toString();
    final displayShift = r.shiftName.isNotEmpty
        ? r.shiftName
        : (_shiftNames[r.shiftId] ?? (_usersCache[r.uid]?['shiftName'] ?? 'No shift')).toString();

    return Card(
      child: ListTile(
        title: Text('${_fmtDay(r.date)} • ${_userNames[r.uid] ?? r.uid}'),
        subtitle: Wrap(
          spacing: 8, runSpacing: 6, children: [
            Chip(label: Text(status), backgroundColor: color, labelStyle: const TextStyle(color: Colors.white)),
            Chip(label: Text('IN ${_fmtTime(r.inAt)}')),
            Chip(label: Text('OUT ${_fmtTime(r.outAt)}')),
            Chip(label: Text('Branch: $displayBranch')),
            Chip(label: Text('Shift: $displayShift')),
          ],
        ),
        trailing: widget.allowEditing ? PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'fix_in' || v == 'edit_in') {
              final tod = await _pickTime(v == 'fix_in' ? 'Fix IN time' : 'Edit IN time');
              if (tod != null) {
                final when = DateTime(r.date.year, r.date.month, r.date.day, tod.hour, tod.minute);
                await _setPunch(
                  uid: r.uid,
                  localDay: r.localDay,
                  type: 'in',
                  at: when,
                  userName: _userNames[r.uid] ?? r.uid,
                  branchId: r.branchId,
                  branchName: displayBranch,
                  shiftId: r.shiftId,
                  shiftName: displayShift,
                );
                setState(() { r.setIn(when); r.isAbsent = false; });
              }
            }
            if (v == 'fix_out' || v == 'edit_out') {
              final tod = await _pickTime(v == 'fix_out' ? 'Fix OUT time' : 'Edit OUT time');
              if (tod != null) {
                final when = DateTime(r.date.year, r.date.month, r.date.day, tod.hour, tod.minute);
                await _setPunch(
                  uid: r.uid,
                  localDay: r.localDay,
                  type: 'out',
                  at: when,
                  userName: _userNames[r.uid] ?? r.uid,
                  branchId: r.branchId,
                  branchName: displayBranch,
                  shiftId: r.shiftId,
                  shiftName: displayShift,
                );
                setState(() { r.setOut(when); r.isAbsent = false; });
              }
            }
          },
          itemBuilder: (_) => [
            if (!r.hasIn)  const PopupMenuItem(value: 'fix_in',  child: Text('Fix IN…')),
            if (!r.hasOut) const PopupMenuItem(value: 'fix_out', child: Text('Fix OUT…')),
            if (r.hasIn)   const PopupMenuItem(value: 'edit_in',  child: Text('Edit IN time…')),
            if (r.hasOut)  const PopupMenuItem(value: 'edit_out', child: Text('Edit OUT time…')),
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

  bool hasIn = false;
  bool hasOut = false;
  bool isAbsent = false;
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
  });

  void setIn(DateTime? t) { hasIn = true; if (t != null) inAt = t; }
  void setOut(DateTime? t){ hasOut = true; if (t != null) outAt = t; }
  bool get isException => !(hasIn && hasOut) || isAbsent;
}

// ====== Loader لتجميع الـ Streams ======
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
            'Query error:\n$error\n\nIf an index is required, select "All branches" or create the index in Firestore.',
          ),
        ),
      ),
    );
  }
}
