// lib/screens/absences_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/attendance_service.dart';

class AbsencesScreen extends StatefulWidget {
  const AbsencesScreen({super.key});

  @override
  State<AbsencesScreen> createState() => _AbsencesScreenState();
}

class _AbsencesScreenState extends State<AbsencesScreen> {
  final _svc = AttendanceService();

  // فلاتر
  DateTimeRange? _range;
  String _branchFilterId = 'all';
  String _shiftFilterId = 'all';
  String _typeFilter = 'exceptions'; // exceptions | absent | missing

  // كاش
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _branches = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _shifts = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _users = []; // approved فقط

  // النتائج
  bool _loading = false;
  List<_ExceptionRow> _rows = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );
    _loadRefs().then((_) => _loadData());
  }

  Future<void> _loadRefs() async {
    final fs = FirebaseFirestore.instance;
    final br = await fs.collection('branches').orderBy('name').get();
    final sh = await fs.collection('shifts').orderBy('name').get();
    final us = await fs.collection('users').where('status', isEqualTo: 'approved').orderBy('fullName').get();
    setState(() {
      _branches = br.docs;
      _shifts = sh.docs;
      _users = us.docs;
    });
  }

  Future<void> _loadData() async {
    if (_range == null) return;
    setState(() => _loading = true);

    final from = _range!.start;
    final to = _range!.end;

    final settings = await _svc.loadSettings();
    final weekend = settings.weekendDays;
    final holidays = settings.holidays;

    final days = _svc.daysRange(from, to);

    // فلترة المستخدمين حسب الفرع/الشفت لو مطلوب
    final filteredUsers = _users.where((u) {
      final m = u.data();
      if (_branchFilterId != 'all' && (m['primaryBranchId'] ?? '') != _branchFilterId) return false;
      if (_shiftFilterId != 'all' && (m['assignedShiftId'] ?? '') != _shiftFilterId) return false;
      return true;
    }).toList();

    final rows = <_ExceptionRow>[];

    // لوب بسيطة (افتراضيًا فرق صغير، لو الفريق كبير هنحتاج تحسين لاحقًا)
    for (final u in filteredUsers) {
      final uid = u.id;
      final m = u.data();
      final name = (m['fullName'] ?? m['username'] ?? m['email'] ?? '').toString();
      final brName = (m['branchName'] ?? '').toString();
      final shName = (m['shiftName'] ?? '').toString();

      for (final day in days) {
        final summary = await _svc.ensureDailySummary(
          uid: uid,
          date: day,
          weekendDays: weekend,
          holidays: holidays,
        );
        final status = (summary['status'] ?? '').toString();
        if (_typeFilter == 'absent') {
          if (status != 'absent') continue;
        } else if (_typeFilter == 'missing') {
          if (status != 'incomplete_in' && status != 'incomplete_out') continue;
        } else {
          // exceptions = absent + missing
          if (status != 'absent' && status != 'incomplete_in' && status != 'incomplete_out') continue;
        }

        rows.add(_ExceptionRow(
          uid: uid,
          userName: name,
          branchName: brName,
          shiftName: shName,
          date: day,
          status: status,
          note: (summary['note'] ?? '').toString(),
          proofUrl: (summary['proofUrl'] ?? '').toString(),
          missing: (summary['missing'] is List)
              ? (summary['missing'] as List).map((e) => e.toString()).toList()
              : const <String>[],
        ));
      }
    }

    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Absences & Missing IN/OUT'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          _filtersBar(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(child: Text('No exceptions for selected filters.'))
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _rowTile(_rows[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filtersBar() {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      elevation: .5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // التاريخ
            FilledButton.tonalIcon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2022),
                  lastDate: DateTime(2100),
                  initialDateRange: _range,
                );
                if (picked != null) setState(() => _range = picked);
              },
              icon: const Icon(Icons.date_range),
              label: Text(_range == null
                  ? 'Pick date range'
                  : '${_fmtD(_range!.start)} → ${_fmtD(_range!.end)}'),
            ),

            // نوع الحالات
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _typeFilter,
                items: const [
                  DropdownMenuItem(value: 'exceptions', child: Text('Absent + Missing')),
                  DropdownMenuItem(value: 'absent', child: Text('Absent only')),
                  DropdownMenuItem(value: 'missing', child: Text('Missing IN/OUT only')),
                ],
                onChanged: (v) => setState(() => _typeFilter = v ?? 'exceptions'),
              ),
            ),

            // فرع
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _branchFilterId,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All branches')),
                  ..._branches.map((b) => DropdownMenuItem(
                        value: b.id,
                        child: Text((b.data()['name'] ?? '').toString()),
                      )),
                ],
                onChanged: (v) => setState(() => _branchFilterId = v ?? 'all'),
              ),
            ),

            // شفت
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _shiftFilterId,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All shifts')),
                  ..._shifts.map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text((s.data()['name'] ?? '').toString()),
                      )),
                ],
                onChanged: (v) => setState(() => _shiftFilterId = v ?? 'all'),
              ),
            ),

            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _loading ? null : _loadData,
              icon: const Icon(Icons.search),
              label: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowTile(_ExceptionRow r) {
    final d = r.date;
    final dateStr = _fmtD(d);
    final badge = _badge(r.status);

    return ListTile(
      title: Text('${r.userName} • $dateStr'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            badge,
            if (r.branchName.isNotEmpty) Chip(label: Text('Branch: ${r.branchName}')),
            if (r.shiftName.isNotEmpty) Chip(label: Text('Shift: ${r.shiftName}')),
          ]),
          if (r.note.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Note: ${r.note}'),
          ),
          if (r.proofUrl.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Proof: ${r.proofUrl}', style: const TextStyle(decoration: TextDecoration.underline)),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _onAction(v, r),
        itemBuilder: (context) => [
          if (r.status == 'incomplete_in' || r.status == 'absent')
            const PopupMenuItem(value: 'fix_in', child: Text('Fix IN…')),
          if (r.status == 'incomplete_out' || r.status == 'absent')
            const PopupMenuItem(value: 'fix_out', child: Text('Fix OUT…')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'mark_present', child: Text('Mark Present')),
          const PopupMenuItem(value: 'mark_leave', child: Text('Mark Leave')),
          const PopupMenuItem(value: 'mark_absent', child: Text('Mark Absent')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'attach_proof', child: Text('Attach proof URL…')),
          const PopupMenuItem(value: 'reset_auto', child: Text('Reset to Auto')),
        ],
      ),
    );
  }

  Widget _badge(String status) {
    Color c;
    String t;
    switch (status) {
      case 'absent':
        c = Colors.red;
        t = 'Absent';
        break;
      case 'incomplete_in':
        c = Colors.orange;
        t = 'Missing IN';
        break;
      case 'incomplete_out':
        c = Colors.orange;
        t = 'Missing OUT';
        break;
      case 'present':
        c = Colors.green;
        t = 'Present';
        break;
      case 'leave':
        c = Colors.blue;
        t = 'Leave';
        break;
      case 'weekend':
        c = Colors.grey;
        t = 'Weekend';
        break;
      case 'holiday':
        c = Colors.grey;
        t = 'Holiday';
        break;
      default:
        c = Colors.black54;
        t = status;
    }
    return Chip(
      label: Text(t, style: const TextStyle(color: Colors.white)),
      backgroundColor: c,
    );
  }

  Future<void> _onAction(String action, _ExceptionRow r) async {
    final settings = await _svc.loadSettings();
    switch (action) {
      case 'fix_in':
        final picked = await _pickTime('Select IN time');
        if (picked != null) {
          await _svc.fixMissing(
            uid: r.uid,
            date: r.date,
            addIn: true,
            addOut: false,
            inTime: picked,
            outTime: null,
            branchId: null,
            shiftId: null,
            note: 'Fixed IN manually',
            proofUrl: r.proofUrl.isNotEmpty ? r.proofUrl : null,
            weekendDays: settings.weekendDays,
            holidays: settings.holidays,
          );
          await _loadData();
        }
        break;

      case 'fix_out':
        final picked2 = await _pickTime('Select OUT time');
        if (picked2 != null) {
          await _svc.fixMissing(
            uid: r.uid,
            date: r.date,
            addIn: false,
            addOut: true,
            inTime: null,
            outTime: picked2,
            branchId: null,
            shiftId: null,
            note: 'Fixed OUT manually',
            proofUrl: r.proofUrl.isNotEmpty ? r.proofUrl : null,
            weekendDays: settings.weekendDays,
            holidays: settings.holidays,
          );
          await _loadData();
        }
        break;

      case 'mark_present':
        await _svc.setManualStatus(uid: r.uid, date: r.date, status: 'present');
        await _loadData();
        break;

      case 'mark_leave':
        await _svc.setManualStatus(uid: r.uid, date: r.date, status: 'leave');
        await _loadData();
        break;

      case 'mark_absent':
        await _svc.setManualStatus(uid: r.uid, date: r.date, status: 'absent');
        await _loadData();
        break;

      case 'attach_proof':
        final url = await _askText('Attach proof URL', hint: 'https://… or gs://…');
        if (url != null && url.trim().isNotEmpty) {
          await _svc.setManualStatus(
            uid: r.uid,
            date: r.date,
            status: r.status, // نحافظ على نفس الحالة
            proofUrl: url.trim(),
          );
          await _loadData();
        }
        break;

      case 'reset_auto':
        // نحذف المصدر اليدوي → نخلي ensureDailySummary يبنيها تلقائيًا
        final key = _svc.dayKey(r.date);
        await FirebaseFirestore.instance
            .collection('dailyAttendance')
            .doc(key)
            .collection('users')
            .doc(r.uid)
            .set({'source': 'auto'}, SetOptions(merge: true));
        await _loadData();
        break;
    }
  }

  Future<TimeOfDay?> _pickTime(String title) async {
    final now = TimeOfDay.now();
    return showTimePicker(context: context, initialTime: now, helpText: title);
  }

  Future<String?> _askText(String title, {String? hint}) async {
    final c = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save')),
        ],
      ),
    );
  }

  String _fmtD(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _ExceptionRow {
  final String uid;
  final String userName;
  final String branchName;
  final String shiftName;
  final DateTime date;
  final String status;
  final String note;
  final String proofUrl;
  final List<String> missing;
  _ExceptionRow({
    required this.uid,
    required this.userName,
    required this.branchName,
    required this.shiftName,
    required this.date,
    required this.status,
    required this.note,
    required this.proofUrl,
    required this.missing,
  });
}
