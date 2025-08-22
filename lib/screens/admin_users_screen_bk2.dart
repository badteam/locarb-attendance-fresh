// lib/screens/admin_users_screen.dart
import 'dart:convert';
import 'dart:html' as html show Blob, Url, AnchorElement, document;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// ملاحظة: مفيش AttendanceService هنا. تبويب الغياب هيقرأ مباشرة من attendance.

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab; // 0=pending, 1=approved, 2=absences
  String get _statusTab =>
      _tab.index == 0 ? 'pending' : _tab.index == 1 ? 'approved' : 'approved';

  // فلاتر وبحث (للتبويبين الأولين)
  final _searchCtrl = TextEditingController();
  String _roleFilter = 'all';
  String _branchFilterId = 'all';
  String _shiftFilterId = 'all';

  // مرجع أسماء الفروع/الشفتات
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _branches = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _shifts = [];
  final Map<String, String> _branchNames = {}; // {branchId: branchName}
  final Map<String, String> _shiftNames = {};  // {shiftId: shiftName}

  static const List<String> kRoles = [
    'all',
    'employee',
    'supervisor',
    'branch_manager',
    'admin',
  ];

  // ======= حالة تبويب Absences (كلها داخل نفس الشاشة) =======
  DateTimeRange? _range;
  String _absBranchFilterId = 'all';
  String _absShiftFilterId = 'all';
  final _absSearchCtrl = TextEditingController();
  bool _absLoading = false;
  List<_AbsRow> _absRows = [];

  // مستخدمين Approved (لتجميع أسماء/فروع سريعة لو احتجنا)
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _usersApproved = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      setState(() {});
      if (_tab.index == 2) {
        _ensureAbsencesInit();
      }
    });
    _loadRefs();
    _loadBranchNamesOnce();
    _loadShiftNamesOnce();

    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _absSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefs() async {
    final fs = FirebaseFirestore.instance;
    final br = await fs.collection('branches').orderBy('name').get();
    final sh = await fs.collection('shifts').orderBy('name').get();
    setState(() {
      _branches = br.docs;
      _shifts = sh.docs;
    });
  }

  Future<void> _loadBranchNamesOnce() async {
    if (_branchNames.isNotEmpty) return;
    final qs = await FirebaseFirestore.instance.collection('branches').get();
    for (final d in qs.docs) {
      _branchNames[d.id] = (d.data()['name'] ?? '').toString();
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadShiftNamesOnce() async {
    if (_shiftNames.isNotEmpty) return;
    final qs = await FirebaseFirestore.instance.collection('shifts').get();
    for (final d in qs.docs) {
      _shiftNames[d.id] = (d.data()['name'] ?? '').toString();
    }
    if (mounted) setState(() {});
  }

  String _branchLabelFor(String? id) {
    if (id == null || id.isEmpty) return 'No branch';
    return _branchNames[id] ?? 'No branch';
  }

  String _shiftLabelFor(String? id) {
    if (id == null || id.isEmpty) return 'No shift';
    return _shiftNames[id] ?? 'No shift';
  }

  // ========== USERS QUERY/FILTERS ==========
  Query<Map<String, dynamic>> _usersQuery() {
    var q = FirebaseFirestore.instance.collection('users').where('status',
        isEqualTo: _statusTab); // pending/approved
    return q.orderBy('fullName', descending: false);
  }

  bool _matchesFilters(Map<String, dynamic> m) {
    final role = (m['role'] ?? 'employee').toString();
    final branchId = (m['primaryBranchId'] ?? m['branchId'] ?? '').toString();
    final shiftId = (m['assignedShiftId'] ?? m['shiftId'] ?? '').toString();

    final okRole = _roleFilter == 'all' || _roleFilter == role;
    final okBr = _branchFilterId == 'all' || _branchFilterId == branchId;
    final okSh = _shiftFilterId == 'all' || _shiftFilterId == shiftId;

    final q = _searchCtrl.text.trim().toLowerCase();
    final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? '').toString().toLowerCase();
    final email = (m['email'] ?? '').toString().toLowerCase();
    final okSearch = q.isEmpty || name.contains(q) || email.contains(q);

    return okRole && okBr && okSh && okSearch;
  }

  // ========== MUTATIONS ==========
  Future<void> _updateUser(String uid, Map<String, dynamic> data) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _changeStatus(String uid, String to) =>
      _updateUser(uid, {'status': to});
  Future<void> _changeRole(String uid, String to) =>
      _updateUser(uid, {'role': to});

  Future<void> _assignBranch(String uid) async {
    final chosen = await showDialog<String?>(
      context: context,
      builder: (_) => _SelectDialog(
        title: 'Assign Branch',
        items: _branches
            .map((b) =>
                _SelectItem(id: b.id, label: (b.data()['name'] ?? '').toString()))
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _updateUser(uid, {
      'primaryBranchId': chosen,
      'branchId': chosen,
      'branchName': _branchLabelFor(chosen),
    });
  }

  Future<void> _assignShift(String uid) async {
    final chosen = await showDialog<String?>(
      context: context,
      builder: (_) => _SelectDialog(
        title: 'Assign Shift',
        items: _shifts
            .map((s) =>
                _SelectItem(id: s.id, label: (s.data()['name'] ?? '').toString()))
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _updateUser(uid, {
      'assignedShiftId': chosen,
      'shiftId': chosen,
      'shiftName': _shiftLabelFor(chosen),
    });
  }

  Future<void> _toggleAllowAnyBranch(String uid, bool v) =>
      _updateUser(uid, {'allowAnyBranch': v});

  Future<void> _editPayrollBasic(String uid, Map<String, dynamic> user) async {
    final m = user;
    final base = TextEditingController(text: (m['salaryBase'] ?? 0).toString());
    final allow = TextEditingController(text: (m['allowances'] ?? 0).toString());
    final ded = TextEditingController(text: (m['deductions'] ?? 0).toString());
    final otAmt =
        TextEditingController(text: (m['overtimeAmount'] ?? 0).toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Payroll (basic)'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Base salary', base),
              const SizedBox(height: 8),
              _field('Allowances (sum)', allow),
              const SizedBox(height: 8),
              _field('Deductions (sum)', ded),
              const SizedBox(height: 8),
              _field('Overtime amount (month)', otAmt),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              final b = double.tryParse(base.text.trim()) ?? 0;
              final a = double.tryParse(allow.text.trim()) ?? 0;
              final d = double.tryParse(ded.text.trim()) ?? 0;
              final o = double.tryParse(otAmt.text.trim()) ?? 0;
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .set({
                'salaryBase': b,
                'allowances': a,
                'deductions': d,
                'overtimeAmount': o,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }

  // ========== EXPORT CSV (users) ==========
  String _csvEscape(String v) {
    final s = v.replaceAll('"', '""');
    return '"$s"';
  }

  Future<void> _exportUsersCsvPressed() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('CSV export works on Web builds only.')),
      );
      return;
    }

    final qs = await _usersQuery().get();
    final users = qs.docs.where((d) => _matchesFilters(d.data())).toList();

    final rows = <List<String>>[
      [
        'ID',
        'Name',
        'Role',
        'Branch name',
        'Shift name',
        'Base salary',
        'Allowance',
        'Deduction',
        'Overtime amount',
        'Total salary',
      ],
    ];

    for (final d in users) {
      final m = d.data();
      final uid = d.id;
      final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? m['email'] ?? '').toString();
      final role = (m['role'] ?? 'employee').toString();

      final brName = (m['branchName'] ?? _branchLabelFor(
        (m['primaryBranchId'] ?? m['branchId'] ?? '').toString(),
      )).toString();
      final shName = (m['shiftName'] ?? _shiftLabelFor(
        (m['assignedShiftId'] ?? m['shiftId'] ?? '').toString(),
      )).toString();

      final base = _toNum(m['salaryBase']);
      final allow = _toNum(m['allowances']);
      final ded = _toNum(m['deductions']);
      final otAmount = _toNum(m['overtimeAmount']);

      final total = base + allow + otAmount - ded;

      rows.add([
        uid,
        name,
        role,
        brName,
        shName,
        _fmt(base),
        _fmt(allow),
        _fmt(ded),
        _fmt(otAmount),
        _fmt(total),
      ]);
    }

    final csv = rows.map((r) => r.map(_csvEscape).join(',')).join('\n');
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final now = DateTime.now();
    final fileName =
        'users_${_statusTab}_role-${_roleFilter}_branch-${_branchFilterId}_shift-${_shiftFilterId}_${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}.csv';

    final a = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';
    html.document.body!.append(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('CSV exported')));
    }
  }

  double _toNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }

  String _fmt(num v) => v is int ? v.toString() : v.toStringAsFixed(2);

  // ================== ABSENCES (داخل نفس الشاشة) ==================
  Future<void> _ensureAbsencesInit() async {
    if (_usersApproved.isEmpty) {
      final us = await FirebaseFirestore.instance
          .collection('users')
          .where('status', isEqualTo: 'approved')
          .orderBy('fullName')
          .get();
      _usersApproved = us.docs;
    }
    await _loadAbsencesData();
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _parseLocalDay(dynamic localDay, dynamic at) {
    if (localDay is String) {
      final parts = localDay.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]) ?? 1970;
        final m = int.tryParse(parts[1]) ?? 1;
        final d = int.tryParse(parts[2]) ?? 1;
        return DateTime(y, m, d);
      }
    }
    if (at is Timestamp) {
      final dt = at.toDate();
      return DateTime(dt.year, dt.month, dt.day);
    }
    return null;
  }

  Future<void> _loadAbsencesData() async {
    if (_range == null) return;
    setState(() => _absLoading = true);

    try {
      final fromStr = _dayKey(_range!.start);
      final toStr = _dayKey(_range!.end);

      final qs = await FirebaseFirestore.instance
          .collection('attendance')
          .where('type', isEqualTo: 'absent')
          .where('localDay', isGreaterThanOrEqualTo: fromStr)
          .where('localDay', isLessThanOrEqualTo: toStr)
          .get();

      final filtered = <_AbsRow>[];
      final q = _absSearchCtrl.text.trim().toLowerCase();

      for (final d in qs.docs) {
        final m = d.data();
        final branchId = (m['branchId'] ?? '').toString();
        final shiftId = (m['shiftId'] ?? '').toString();
        if (_absBranchFilterId != 'all' && branchId != _absBranchFilterId) continue;
        if (_absShiftFilterId != 'all' && shiftId != _absShiftFilterId) continue;

        final localDay = (m['localDay'] ?? '').toString();
        final date = _parseLocalDay(localDay, m['at']);
        if (date == null) continue;

        final userId = (m['userId'] ?? '').toString();
        final userName = (m['userName'] ?? '').toString();
        final branchName = (m['branchName'] ?? _branchLabelFor(branchId)).toString();
        final shiftName = (m['shiftName'] ?? _shiftLabelFor(shiftId)).toString();

        final hay = '$userId $userName $branchName $localDay'.toLowerCase();
        if (q.isNotEmpty && !hay.contains(q)) continue;

        filtered.add(_AbsRow(
          docId: d.id,
          userId: userId,
          userName: userName,
          branchId: branchId,
          branchName: branchName,
          shiftId: shiftId,
          shiftName: shiftName,
          date: date,
          localDay: localDay,
        ));
      }

      filtered.sort((a, b) {
        final c = b.date.compareTo(a.date);
        if (c != 0) return c;
        final c2 = a.branchName.compareTo(b.branchName);
        if (c2 != 0) return c2;
        return a.userId.compareTo(b.userId);
      });

      setState(() {
        _absRows = filtered;
        _absLoading = false;
      });
    } catch (e) {
      setState(() => _absLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load absences failed: $e')),
      );
    }
  }

  Future<void> _absMarkPresent(_AbsRow r) async {
    // يحوّل الغياب لحضور (IN/OUT) ويمسح سجل الغياب
    final d = r.date;
    final inAt = DateTime(d.year, d.month, d.day, 9, 0);
    final outAt = DateTime(d.year, d.month, d.day, 17, 0);

    final inRef = FirebaseFirestore.instance
        .collection('attendance')
        .doc('${r.userId}_${r.localDay}_in');
    final outRef = FirebaseFirestore.instance
        .collection('attendance')
        .doc('${r.userId}_${r.localDay}_out');
    final absRef = FirebaseFirestore.instance
        .collection('attendance')
        .doc(r.docId);

    final batch = FirebaseFirestore.instance.batch();

    batch.set(inRef, {
      'userId': r.userId,
      'userName': r.userName,
      'branchId': r.branchId,
      'branchName': r.branchName,
      'shiftId': r.shiftId,
      'localDay': r.localDay,
      'type': 'in',
      'at': Timestamp.fromDate(inAt),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(outRef, {
      'userId': r.userId,
      'userName': r.userName,
      'branchId': r.branchId,
      'branchName': r.branchName,
      'shiftId': r.shiftId,
      'localDay': r.localDay,
      'type': 'out',
      'at': Timestamp.fromDate(outAt),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.delete(absRef);

    await batch.commit();
    await _loadAbsencesData();
  }

  Future<void> _absDelete(_AbsRow r) async {
    await FirebaseFirestore.instance
        .collection('attendance')
        .doc(r.docId)
        .delete();
    await _loadAbsencesData();
  }

  // ================== BUILD ==================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users & Absences'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Absences'),
          ],
          onTap: (_) => setState(() {}),
        ),
        actions: [
          if (_tab.index != 2)
            IconButton(
              tooltip: 'Export CSV',
              onPressed: _exportUsersCsvPressed,
              icon: const Icon(Icons.download),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_tab.index != 2) _filtersBarUsers(),
          if (_tab.index != 2) const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _usersTab(),       // Pending
                _usersTab(),       // Approved
                _absencesTab(),    // Absences (في نفس الشاشة)
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ======== USERS TABS ========
  Widget _usersTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usersQuery().snapshots(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs =
            s.data?.docs.where((d) => _matchesFilters(d.data())).toList() ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No users found.'));
        }

        // نجمع حسب الفرع
        final byBranch =
            <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final d in docs) {
          final m = d.data();
          final brId = (m['primaryBranchId'] ?? m['branchId'] ?? '').toString();
          byBranch.putIfAbsent(brId, () => []).add(d);
        }

        return ListView(
          children: byBranch.entries.map((entry) {
            final title = entry.key.isEmpty
                ? 'No branch'
                : _branchLabelFor(entry.key);
            final list = entry.value;
            final shownCount = list.length;
            return ExpansionTile(
              title: Text('$title — $shownCount user(s)'),
              children: list
                  .map((d) => _UserCard(
                        uid: d.id,
                        data: d.data(),
                        onChangeStatus: _changeStatus,
                        onChangeRole: _changeRole,
                        onAssignBranch: _assignBranch,
                        onAssignShift: _assignShift,
                        onToggleAllowAnyBranch: _toggleAllowAnyBranch,
                        onEditPayroll: _editPayrollBasic,
                      ))
                  .toList(),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _filtersBarUsers() {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      elevation: .5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name or email',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _roleFilter,
                items: kRoles
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r == 'all' ? 'All roles' : r),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
              ),
            ),
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
              onPressed: _exportUsersCsvPressed,
              icon: const Icon(Icons.file_download),
              label: const Text('Export CSV'),
            ),
          ],
        ),
      ),
    );
  }

  // ======== ABSENCES TAB (داخل نفس الشاشة) ========
  Widget _absencesTab() {
    return Column(
      children: [
        _filtersBarAbsences(),
        const Divider(height: 1),
        Expanded(
          child: _absLoading
              ? const Center(child: CircularProgressIndicator())
              : _absRows.isEmpty
                  ? const Center(child: Text('No absences for selected filters.'))
                  : ListView.separated(
                      itemCount: _absRows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _absRowTile(_absRows[i]),
                    ),
        ),
      ],
    );
  }

  Widget _filtersBarAbsences() {
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
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _absBranchFilterId,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All branches')),
                  ..._branches.map((b) => DropdownMenuItem(
                        value: b.id,
                        child: Text((b.data()['name'] ?? '').toString()),
                      )),
                ],
                onChanged: (v) => setState(() => _absBranchFilterId = v ?? 'all'),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _absShiftFilterId,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All shifts')),
                  ..._shifts.map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text((s.data()['name'] ?? '').toString()),
                      )),
                ],
                onChanged: (v) => setState(() => _absShiftFilterId = v ?? 'all'),
              ),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                controller: _absSearchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search (name / code / branch)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _absLoading ? null : _loadAbsencesData,
              icon: const Icon(Icons.search),
              label: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _absRowTile(_AbsRow r) {
    final dateStr = _fmtD(r.date);
    return ListTile(
      title: Text('${r.userName.isEmpty ? r.userId : r.userName} • $dateStr'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            Chip(
              label: const Text('Absent', style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
            ),
            if (r.userId.isNotEmpty) Chip(label: Text('Code: ${r.userId}')),
            if (r.branchName.isNotEmpty) Chip(label: Text('Branch: ${r.branchName}')),
            if (r.shiftName.isNotEmpty) Chip(label: Text('Shift: ${r.shiftName}')),
          ]),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'present':
              await _absMarkPresent(r);
              break;
            case 'delete':
              await _absDelete(r);
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'present', child: Text('Mark Present (create IN/OUT)')),
          PopupMenuItem(value: 'delete', child: Text('Delete absence')),
        ],
      ),
    );
  }

  String _fmtD(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ========== USER CARD ==========
class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.uid,
    required this.data,
    required this.onChangeStatus,
    required this.onChangeRole,
    required this.onAssignBranch,
    required this.onAssignShift,
    required this.onToggleAllowAnyBranch,
    required this.onEditPayroll,
  });

  final String uid;
  final Map<String, dynamic> data;

  final Future<void> Function(String uid, String to) onChangeStatus;
  final Future<void> Function(String uid, String to) onChangeRole;
  final Future<void> Function(String uid) onAssignBranch;
  final Future<void> Function(String uid) onAssignShift;
  final Future<void> Function(String uid, bool v) onToggleAllowAnyBranch;
  final Future<void> Function(String uid, Map<String, dynamic> m) onEditPayroll;

  @override
  Widget build(BuildContext context) {
    final name = (data['fullName'] ?? data['name'] ?? data['username'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final role = (data['role'] ?? 'employee').toString();
    final status = (data['status'] ?? 'pending').toString();

    final brName = (data['branchName'] ?? '').toString();
    final shName = (data['shiftName'] ?? '').toString();
    final allowAny = (data['allowAnyBranch'] ?? false) == true;

    final base = (data['salaryBase'] ?? 0);
    final allow = (data['allowances'] ?? 0);
    final ded = (data['deductions'] ?? 0);
    final otAmt = (data['overtimeAmount'] ?? 0);

    String _numTxt(dynamic v) {
      if (v is num) return v is int ? v.toString() : v.toStringAsFixed(2);
      final d = double.tryParse(v.toString()) ?? 0;
      return d.toStringAsFixed(2);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
        ),
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Chip(label: Text('Status: $status'), avatar: const Icon(Icons.verified, size: 16)),
                Chip(label: Text('Role: $role'), avatar: const Icon(Icons.badge, size: 16)),
                Chip(label: Text('Branch: ${brName.isEmpty ? '—' : brName}'), avatar: const Icon(Icons.store, size: 16)),
                Chip(label: Text('Shift: ${shName.isEmpty ? '—' : shName}'), avatar: const Icon(Icons.schedule, size: 16)),
                if (allowAny) const Chip(label: Text('Any branch'), avatar: Icon(Icons.public, size: 16)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              children: [
                Text('Base: ${_numTxt(base)}'),
                Text('Allowances: ${_numTxt(allow)}'),
                Text('Deductions: ${_numTxt(ded)}'),
                Text('OT amount: ${_numTxt(otAmt)}'),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'approve':
                await onChangeStatus(uid, 'approved');
                break;
              case 'pending':
                await onChangeStatus(uid, 'pending');
                break;
              case 'role_employee':
                await onChangeRole(uid, 'employee');
                break;
              case 'role_supervisor':
                await onChangeRole(uid, 'supervisor');
                break;
              case 'role_manager':
                await onChangeRole(uid, 'branch_manager');
                break;
              case 'role_admin':
                await onChangeRole(uid, 'admin');
                break;
              case 'assign_branch':
                await onAssignBranch(uid);
                break;
              case 'assign_shift':
                await onAssignShift(uid);
                break;
              case 'toggle_any':
                await onToggleAllowAnyBranch(uid, !(data['allowAnyBranch'] == true));
                break;
              case 'edit_payroll':
                await onEditPayroll(uid, data);
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'approve', child: Text('Mark Approved')),
            PopupMenuItem(value: 'pending', child: Text('Mark Pending')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'role_employee', child: Text('Role: Employee')),
            PopupMenuItem(value: 'role_supervisor', child: Text('Role: Supervisor')),
            PopupMenuItem(value: 'role_manager', child: Text('Role: Branch Manager')),
            PopupMenuItem(value: 'role_admin', child: Text('Role: Admin')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'assign_branch', child: Text('Assign Branch')),
            PopupMenuItem(value: 'assign_shift', child: Text('Assign Shift')),
            PopupMenuItem(value: 'toggle_any', child: Text('Toggle Allow Any Branch')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'edit_payroll', child: Text('Edit Payroll')),
          ],
        ),
      ),
    );
  }
}

// ========== SELECT DIALOG ==========
class _SelectItem {
  final String id;
  final String label;
  const _SelectItem({required this.id, required this.label});
}

class _SelectDialog extends StatefulWidget {
  const _SelectDialog({required this.title, required this.items});
  final String title;
  final List<_SelectItem> items;

  @override
  State<_SelectDialog> createState() => _SelectDialogState();
}

class _SelectDialogState extends State<_SelectDialog> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: DropdownButtonFormField<String>(
        value: _selected,
        items: widget.items
            .map((e) => DropdownMenuItem(value: e.id, child: Text(e.label)))
            .toList(),
        onChanged: (v) => setState(() => _selected = v),
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ====== Absences model ======
class _AbsRow {
  final String docId;
  final String userId;
  final String userName;
  final String branchId;
  final String branchName;
  final String shiftId;
  final String shiftName;
  final DateTime date;
  final String localDay;

  _AbsRow({
    required this.docId,
    required this.userId,
    required this.userName,
    required this.branchId,
    required this.branchName,
    required this.shiftId,
    required this.shiftName,
    required this.date,
    required this.localDay,
  });
}
