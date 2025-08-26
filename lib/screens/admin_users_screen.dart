
// lib/screens/admin_users_screen.dart
// Improved version v2 — 2025-08-26

import 'dart:convert';
import 'dart:html' as html show Blob, Url, AnchorElement, document;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String get _statusTab => _tab.index == 0 ? 'pending' : 'approved';

  final _searchCtrl = TextEditingController();
  String _roleFilter = 'all';
  String _branchFilterId = 'all';
  String _shiftFilterId = 'all';

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _branches = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _shifts = [];
  final Map<String, String> _branchNames = {};
  final Map<String, String> _shiftNames = {};

  static const List<String> kRoles = [
    'all',
    'employee',
    'supervisor',
    'branch_manager',
    'admin',
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
    _loadRefs();
    _loadBranchNamesOnce();
    _loadShiftNamesOnce();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
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

  Query<Map<String, dynamic>> _usersQuery() {
    var q = FirebaseFirestore.instance
        .collection('users')
        .where('status', isEqualTo: _statusTab);
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
    final phone = (m['phone'] ?? '').toString().toLowerCase();
    final uid = (m['uid'] ?? '').toString().toLowerCase();

    final okSearch = q.isEmpty || name.contains(q) || email.contains(q) || phone.contains(q) || uid.contains(q);

    return okRole && okBr && okSh && okSearch;
  }

  Future<void> _exportUsersCsvPressed() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('CSV export works on Web builds only.'),
      ));
      return;
    }

    final qs = await _usersQuery().get();
    final users = qs.docs.where((d) => _matchesFilters(d.data())).toList();

    final rows = <List<String>>[
      [
        'ID',
        'Name',
        'Email',
        'Phone',
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
      final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? '').toString();
      final email = (m['email'] ?? '').toString();
      final phone = (m['phone'] ?? '').toString();
      final role = (m['role'] ?? 'employee').toString();

      final brName = (m['branchName'] ?? _branchLabelFor((m['primaryBranchId'] ?? m['branchId'] ?? '').toString())).toString();
      final shName = (m['shiftName'] ?? _shiftLabelFor((m['assignedShiftId'] ?? m['shiftId'] ?? '').toString())).toString();

      double _toNum(v) {
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
        return 0.0;
      }

      final base = _toNum(m['salaryBase']);
      final allow = _toNum(m['allowances']);
      final ded = _toNum(m['deductions']);
      final otAmount = _toNum(m['overtimeAmount']);
      final total = base + allow + otAmount - ded;

      String _fmt(num v) => v is int ? v.toString() : v.toStringAsFixed(2);

      rows.add([
        uid,
        name,
        email,
        phone,
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

    final csv = rows.map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(',')).join('\n');
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final now = DateTime.now();
    final fileName = 'users_${_statusTab}_${now.year}-${now.month}-${now.day}.csv';

    final a = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';
    html.document.body!.append(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV exported')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Users — v2 — 2025-08-26'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
          ],
          onTap: (_) => setState(() {}),
        ),
        actions: [
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
          _filtersBarUsers(),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _usersTab(),
                _usersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _usersTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usersQuery().snapshots(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = s.data?.docs.where((d) => _matchesFilters(d.data())).toList() ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No users found.'));
        }
        return ListView(
          children: docs.map((d) {
            final m = d.data();
            return ListTile(
              title: Text((m['fullName'] ?? m['name'] ?? 'Unnamed').toString()),
              subtitle: Text((m['email'] ?? '').toString()),
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
                  hintText: 'Search name, email, phone or UID',
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
          ],
        ),
      ),
    );
  }
}
