import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  /// Tabs: Approved / Pending
  String _statusTab = 'approved'; // 'approved' | 'pending'

  /// Filters
  String _roleFilter = 'all';         // all | employee | admin | supervisor | branch_manager
  String _branchFilterId = 'all';     // 'all' أو branchId
  String _shiftFilterId = 'all';      // 'all' أو shiftId

  /// Dropdown sources
  List<Map<String, String>> _branches = []; // [{id,name}]
  List<Map<String, String>> _shifts = [];   // [{id,name}]

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBranchesAndShifts();
  }

  Future<void> _loadBranchesAndShifts() async {
    final brSnap = await FirebaseFirestore.instance.collection('branches').get();
    final shSnap = await FirebaseFirestore.instance.collection('shifts').get();

    setState(() {
      _branches = [
        {'id': 'all', 'name': 'All branches'},
        for (final d in brSnap.docs)
          {'id': d.id, 'name': (d['name'] ?? d.id).toString()}
      ];
      _shifts = [
        {'id': 'all', 'name': 'All shifts'},
        for (final d in shSnap.docs)
          {'id': d.id, 'name': (d['name'] ?? d.id).toString()}
      ];
    });
  }

  Query<Map<String, dynamic>> _buildUsersQuery() {
    var q = FirebaseFirestore.instance.collection('users')
        .where('status', isEqualTo: _statusTab);

    // ترتيب بسيط
    q = q.orderBy('fullName', descending: false);

    return q;
  }

  Future<String> _safeNameFromId({
    required String collection,
    required String id,
    required String fallback,
  }) async {
    if (id.isEmpty) return fallback;
    try {
      final doc = await FirebaseFirestore.instance.collection(collection).doc(id).get();
      final data = doc.data() ?? {};
      final n = (data['name'] ?? '').toString();
      return n.isNotEmpty ? n : fallback;
    } catch (_) {
      return fallback;
    }
  }

  /// ====== تصدير CSV شهري مع الرواتب ======
  Future<void> exportUsersCsvMonthly({
    required Query<Map<String, dynamic>> usersQuery,
    required String roleFilter,
    required String branchFilterId,
    required String shiftFilterId,
    DateTime? monthStart,
  }) async {
    // 1) نطاق الشهر
    final now = DateTime.now();
    final start = monthStart ?? DateTime(now.year, now.month, 1);
    final end = DateTime(start.year, start.month + 1, 1)
        .subtract(const Duration(microseconds: 1));

    // 2) اجلب المستخدمين
    final snap = await usersQuery.get();
    var users = snap.docs;

    // 3) فلترة إضافية في الذاكرة
    users = users.where((u) {
      final m = u.data();
      final role     = (m['role'] ?? 'employee').toString();
      final branchId = (m['primaryBranchId'] ?? '').toString();
      final shiftId  = (m['assignedShiftId'] ?? '').toString();

      final roleOk   = roleFilter == 'all' || role == roleFilter;
      final branchOk = branchFilterId == 'all' || branchId == branchFilterId;
      final shiftOk  = shiftFilterId == 'all' || shiftId == shiftFilterId;

      // بحث نصّي بسيط على الاسم/الإيميل لو فيه كلمة في السيرش
      final q = _searchCtrl.text.trim().toLowerCase();
      final matchesSearch = q.isEmpty
          ? true
          : ((m['fullName'] ?? '').toString().toLowerCase().contains(q) ||
              (m['email'] ?? '').toString().toLowerCase().contains(q));

      return roleOk && branchOk && shiftOk && matchesSearch;
    }).toList();

    // 4) عناوين CSV
    final rows = <List<String>>[
      [
        'Name',
        'Email',
        'Role',
        'Status',
        'Branch',
        'Shift',
        'Base Salary',
        'Bonuses/Allowances (month)',
        'Deductions (month)',
        'Net Salary (month)',
        'UID',
        'Branch ID',
        'Shift ID',
        'Month',
      ]
    ];

    // 5) معالجة مستخدم -> صف في CSV
    Future<void> handleUser(QueryDocumentSnapshot<Map<String, dynamic>> u) async {
      final m = u.data();
      final uid         = u.id;
      final fullName    = (m['fullName'] ?? m['username'] ?? m['email'] ?? '').toString();
      final email       = (m['email'] ?? '').toString();
      final role        = (m['role'] ?? 'employee').toString();
      final status      = (m['status'] ?? 'pending').toString();
      final branchId    = (m['primaryBranchId'] ?? '').toString();
      final shiftId     = (m['assignedShiftId'] ?? '').toString();
      final baseSalary  = (m['baseSalary'] ?? 0).toDouble();

      final branchName = (m['branchName'] ?? '').toString().isNotEmpty
          ? m['branchName'].toString()
          : await _safeNameFromId(
              collection: 'branches',
              id: branchId,
              fallback: (branchId.isEmpty ? 'No branch' : branchId),
            );

      final shiftName = (m['shiftName'] ?? '').toString().isNotEmpty
          ? m['shiftName'].toString()
          : await _safeNameFromId(
              collection: 'shifts',
              id: shiftId,
              fallback: (shiftId.isEmpty ? 'No shift' : shiftId),
            );

      double bonuses = 0;
      double deductions = 0;

      try {
        final trxSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('payroll')
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
            .get();

        for (final d in trxSnap.docs) {
          final t = (d['type'] ?? '').toString().toLowerCase();
          final amount = (d['amount'] ?? 0).toDouble();
          if (t == 'bonus' || t == 'allowance') {
            bonuses += amount;
          } else if (t == 'deduction') {
            deductions += amount;
          }
        }
      } catch (_) {
        // تجاهل لو ما فيش كوليكشن/صلاحيات
      }

      final netSalary = (baseSalary + bonuses) - deductions;

      rows.add([
        fullName,
        email,
        role,
        status,
        branchName,
        shiftName,
        baseSalary.toStringAsFixed(2),
        bonuses.toStringAsFixed(2),
        deductions.toStringAsFixed(2),
        netSalary.toStringAsFixed(2),
        uid,
        branchId,
        shiftId,
        '${start.year}-${start.month.toString().padLeft(2, "0")}',
      ]);
    }

    await Future.wait(users.map(handleUser));

    // 6) CSV -> تنزيل
    final csv = const ListToCsvConverter().convert(rows);
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final fileName =
        'users_payroll_${_statusTab}_${start.year}-${start.month.toString().padLeft(2, "0")}.csv';

    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  // واجهة مبسّطة
  @override
  Widget build(BuildContext context) {
    final roleItems = const [
      DropdownMenuItem(value: 'all', child: Text('All roles')),
      DropdownMenuItem(value: 'employee', child: Text('Employee')),
      DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
      DropdownMenuItem(value: 'branch_manager', child: Text('Branch Manager')),
      DropdownMenuItem(value: 'admin', child: Text('Admin')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          // Tabs: Pending / Approved
          ToggleButtons(
            isSelected: [
              _statusTab == 'pending',
              _statusTab == 'approved',
            ],
            onPressed: (i) {
              setState(() {
                _statusTab = (i == 0) ? 'pending' : 'approved';
              });
            },
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('Pending'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('Approved'),
              ),
            ],
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // بحث + فلاتر + زر تصدير
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                // Search
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name or email',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                // Role
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    isDense: true,
                    value: _roleFilter,
                    items: roleItems,
                    onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Branch
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    isDense: true,
                    value: _branchFilterId,
                    items: _branches
                        .map((e) => DropdownMenuItem(
                              value: e['id'],
                              child: Text(e['name'] ?? e['id']!),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _branchFilterId = v ?? 'all'),
                    decoration: const InputDecoration(
                      labelText: 'Branch',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Shift
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    isDense: true,
                    value: _shiftFilterId,
                    items: _shifts
                        .map((e) => DropdownMenuItem(
                              value: e['id'],
                              child: Text(e['name'] ?? e['id']!),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _shiftFilterId = v ?? 'all'),
                    decoration: const InputDecoration(
                      labelText: 'Shift',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Export
                ElevatedButton(
                  onPressed: () async {
                    await exportUsersCsvMonthly(
                      usersQuery: _buildUsersQuery(),
                      roleFilter: _roleFilter,
                      branchFilterId: _branchFilterId,
                      shiftFilterId: _shiftFilterId,
                      // monthStart: DateTime(2025, 8, 1), // لو عايز شهر محدد
                    );
                  },
                  child: const Text('Export CSV (Excel)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          // قائمة المستخدمين
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildUsersQuery().snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var docs = snap.data?.docs ?? [];

                // فلترة إضافية بـ role/branch/shift/search
                docs = docs.where((u) {
                  final m = u.data();
                  final role     = (m['role'] ?? 'employee').toString();
                  final branchId = (m['primaryBranchId'] ?? '').toString();
                  final shiftId  = (m['assignedShiftId'] ?? '').toString();

                  final roleOk   = _roleFilter == 'all' || role == _roleFilter;
                  final branchOk = _branchFilterId == 'all' || branchId == _branchFilterId;
                  final shiftOk  = _shiftFilterId == 'all' || shiftId == _shiftFilterId;

                  final q = _searchCtrl.text.trim().toLowerCase();
                  final matchesSearch = q.isEmpty
                      ? true
                      : ((m['fullName'] ?? '').toString().toLowerCase().contains(q) ||
                          (m['email'] ?? '').toString().toLowerCase().contains(q));

                  return roleOk && branchOk && shiftOk && matchesSearch;
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('No users found'));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final name = (d['fullName'] ?? d['username'] ?? d['email'] ?? '').toString();
                    final email = (d['email'] ?? '').toString();
                    final role = (d['role'] ?? 'employee').toString();
                    final branch = (d['branchName'] ?? 'No branch').toString();
                    final shift = (d['shiftName'] ?? 'No shift').toString();

                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                      ),
                      title: Text(name),
                      subtitle: Text('$email  •  $role  •  $branch  •  $shift'),
                      trailing: Text(_statusTab),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
