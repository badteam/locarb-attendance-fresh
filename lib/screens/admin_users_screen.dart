// lib/screens/admin_users_screen.dart
import 'dart:convert';
import 'dart:html' as html; // لتنزيل CSV على الويب

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/* ======================= Top-level roles & labels ======================= */

const List<String> kRoles = [
  'admin',
  'branch_manager',
  'supervisor',
  'employee',
];

const Map<String, String> kRoleLabels = {
  'admin': 'Admin',
  'branch_manager': 'Branch Manager',
  'supervisor': 'Supervisor',
  'employee': 'Employee',
};

/* =============================== Screen ================================= */

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  // تبويب الحالة
  String _statusTab = 'pending'; // pending | approved
  // بحث
  String _search = '';
  // فلاتر
  String _roleFilter = 'all';     // all | {role}
  String _branchFilterId = 'all'; // all | {branchId}
  String _shiftFilterId = 'all';  // all | {shiftId}

  // دوري الحالي (لإظهار/إخفاء صلاحيات)
  String? _myRole;
  bool _loadingMyRole = true;

  @override
  void initState() {
    super.initState();
    _loadMyRole();
  }

  Future<void> _loadMyRole() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        _myRole = 'employee';
      } else {
        final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        _myRole = (snap.data() ?? const {})['role']?.toString() ?? 'employee';
      }
    } catch (_) {
      _myRole = 'employee';
    } finally {
      if (mounted) setState(() => _loadingMyRole = false);
    }
  }

  bool get _isAdmin => _myRole == 'admin';

  Color _roleColor(String role, BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    switch (role) {
      case 'admin':
        return cs.primary;
      case 'branch_manager':
        return Colors.teal;
      case 'supervisor':
        return Colors.indigo;
      default:
        return cs.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchesQ = FirebaseFirestore.instance.collection('branches').orderBy('name');
    final shiftsQ   = FirebaseFirestore.instance.collection('shifts').orderBy('name');

    // users query by status
    Query<Map<String, dynamic>> usersQ = FirebaseFirestore.instance
        .collection('users')
        .where('status', isEqualTo: _statusTab)
        .orderBy('fullName');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          // تبويب حالة: Pending/Approved
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pending', label: Text('Pending')),
                ButtonSegment(value: 'approved', label: Text('Approved')),
              ],
              selected: {_statusTab},
              onSelectionChanged: (s) => setState(() => _statusTab = s.first),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loadingMyRole
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // شريط البحث
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name or email',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                  ),
                ),

                // فلاتر: الدور + الفرع + الشفت + زر التصدير
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: branchesQ.snapshots(),
                  builder: (context, bSnap) {
                    final branches = (bSnap.data?.docs ?? []);
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: shiftsQ.snapshots(),
                      builder: (context, sSnap) {
                        final shifts = (sSnap.data?.docs ?? []);

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // Role filter
                              SizedBox(
                                width: 220,
                                child: DropdownButtonFormField<String>(
                                  value: _roleFilter,
                                  decoration: const InputDecoration(
                                    labelText: 'Role',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('All roles')),
                                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                                    DropdownMenuItem(value: 'branch_manager', child: Text('Branch Manager')),
                                    DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                                    DropdownMenuItem(value: 'employee', child: Text('Employee')),
                                  ],
                                  onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
                                ),
                              ),

                              // Branch filter
                              SizedBox(
                                width: 260,
                                child: DropdownButtonFormField<String>(
                                  value: _branchFilterId,
                                  decoration: const InputDecoration(
                                    labelText: 'Branch',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    const DropdownMenuItem(value: 'all', child: Text('All branches')),
                                    ...branches.map((d) => DropdownMenuItem(
                                          value: d.id,
                                          child: Text((d['name'] ?? d.id).toString()),
                                        )),
                                  ],
                                  onChanged: (v) => setState(() => _branchFilterId = v ?? 'all'),
                                ),
                              ),

                              // Shift filter
                              SizedBox(
                                width: 240,
                                child: DropdownButtonFormField<String>(
                                  value: _shiftFilterId,
                                  decoration: const InputDecoration(
                                    labelText: 'Shift',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    const DropdownMenuItem(value: 'all', child: Text('All shifts')),
                                    ...shifts.map((d) => DropdownMenuItem(
                                          value: d.id,
                                          child: Text((d['name'] ?? d.id).toString()),
                                        )),
                                  ],
                                  onChanged: (v) => setState(() => _shiftFilterId = v ?? 'all'),
                                ),
                              ),

                              // Export CSV button
                              FilledButton.icon(
                                onPressed: () async {
                                  await _exportCsvWithFilters(
                                    usersQ: usersQ,
                                    roleFilter: _roleFilter,
                                    branchFilterId: _branchFilterId,
                                    shiftFilterId: _shiftFilterId,
                                  );
                                },
                                icon: const Icon(Icons.download),
                                label: const Text('Export CSV (Excel)'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),

                // القائمة
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: usersQ.snapshots(),
                    builder: (context, uSnap) {
                      if (uSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (uSnap.hasError) {
                        return Center(child: Text('Error: ${uSnap.error}'));
                      }
                      var users = uSnap.data?.docs ?? [];

                      // تطبيق فلاتر البحث والدور والفرع والشفت
                      users = users.where((u) {
                        final m = u.data();
                        final fullName = (m['fullName'] ?? m['username'] ?? '').toString().toLowerCase();
                        final email    = (m['email'] ?? '').toString().toLowerCase();
                        final role     = (m['role'] ?? 'employee').toString();
                        final branchId = (m['primaryBranchId'] ?? '').toString();
                        final shiftId  = (m['assignedShiftId'] ?? '').toString();

                        final searchOk = _search.isEmpty || fullName.contains(_search) || email.contains(_search);
                        final roleOk   = _roleFilter == 'all' || role == _roleFilter;
                        final branchOk = _branchFilterId == 'all' || branchId == _branchFilterId;
                        final shiftOk  = _shiftFilterId == 'all' || shiftId == _shiftFilterId;

                        return searchOk && roleOk && branchOk && shiftOk;
                      }).toList();

                      if (users.isEmpty) {
                        return const Center(child: Text('No users match filters.'));
                      }

                      // تجميع حسب الفرع
                      final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> grouped = {};
                      for (final u in users) {
                        final m = u.data();
                        final branchName = (m['branchName'] ?? '').toString();
                        final key = branchName.isEmpty ? '— No branch —' : branchName;
                        grouped.putIfAbsent(key, () => []).add(u);
                      }

                      final groups = grouped.keys.toList()..sort();

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                        itemCount: groups.length,
                        itemBuilder: (_, gi) {
                          final gName = groups[gi];
                          final gUsers = grouped[gName]!;
                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ExpansionTile(
                              title: Text('$gName  •  ${gUsers.length} user(s)'),
                              children: gUsers.map((uDoc) {
                                final data = uDoc.data();
                                return _UserCard(
                                  uid: uDoc.id,
                                  data: data,
                                  isAdmin: _isAdmin,
                                  roleColor: _roleColor,
                                  onChanged: () => ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(content: Text('Saved'))),
                                );
                              }).toList(),
                            ),
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

  Future<void> _exportCsvWithFilters({
    required Query<Map<String, dynamic>> usersQ,
    required String roleFilter,
    required String branchFilterId,
    required String shiftFilterId,
  }) async {
    // Snapshot واحد حسب حالة التبويب + نطبق الفلاتر في الذاكرة
    final snap = await usersQ.get();
    var users = snap.docs;

    users = users.where((u) {
      final m = u.data();
      final role     = (m['role'] ?? 'employee').toString();
      final branchId = (m['primaryBranchId'] ?? '').toString();
      final shiftId  = (m['assignedShiftId'] ?? '').toString();

      final roleOk   = roleFilter == 'all' || role == roleFilter;
      final branchOk = branchFilterId == 'all' || branchId == branchFilterId;
      final shiftOk  = shiftFilterId == 'all' || shiftId == shiftFilterId;

      return roleOk && branchOk && shiftOk;
    }).toList();

    // تجهيز CSV
    final rows = <List<String>>[];
    rows.add([
      'UID',
      'Full Name',
      'Email',
      'Role',
      'Status',
      'Branch Name',
      'Branch ID',
      'Shift Name',
      'Shift ID',
      'Created At',
      'Updated At',
    ]);

    for (final u in users) {
      final m = u.data();
      rows.add([
        u.id,
        (m['fullName'] ?? m['username'] ?? '').toString(),
        (m['email'] ?? '').toString(),
        (m['role'] ?? 'employee').toString(),
        (m['status'] ?? 'pending').toString(),
        (m['branchName'] ?? '').toString(),
        (m['primaryBranchId'] ?? '').toString(),
        (m['shiftName'] ?? '').toString(),
        (m['assignedShiftId'] ?? '').toString(),
        (m['createdAt'] is Timestamp) ? (m['createdAt'] as Timestamp).toDate().toIso8601String() : '',
        (m['updatedAt'] is Timestamp) ? (m['updatedAt'] as Timestamp).toDate().toIso8601String() : '',
      ]);
    }

    // إلى CSV (Excel-compatible)
    final csv = const ListToCsvConverter().convert(rows);
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final dt = DateTime.now();
    final br = branchFilterId == 'all' ? 'ALL' : branchFilterId;
    final sh = shiftFilterId == 'all' ? 'ALL' : shiftFilterId;

    // ✅ هنا كانت المشكلة: استخدم أسماء المتغيرات الصحيحة
    final fileName =
        'users_${_statusTab}_role-$roleFilter_branch-$branchFilterId_shift-$shiftFilterId_${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}.csv';
    
    
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();

    html.Url.revokeObjectUrl(url);
  }
}

/* -------------------------- User Card (compact) -------------------------- */

class _UserCard extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  final bool isAdmin;
  final Color Function(String role, BuildContext ctx) roleColor;
  final VoidCallback onChanged;

  const _UserCard({
    required this.uid,
    required this.data,
    required this.isAdmin,
    required this.roleColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final name   = (data['fullName'] ?? data['username'] ?? '—').toString();
    final email  = (data['email'] ?? '').toString();
    final role0  = (data['role'] ?? 'employee').toString();
    final role   = kRoles.contains(role0) ? role0 : 'employee';
    final status = (data['status'] ?? 'pending').toString();

    final branchName = (data['branchName'] ?? 'No branch').toString();
    final shiftName  = (data['shiftName'] ?? '—').toString();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  child: Text((name.isNotEmpty ? name[0] : '?').toUpperCase()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                // role badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: roleColor(role, context).withOpacity(.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: roleColor(role, context).withOpacity(.35)),
                  ),
                  child: Text(
                    kRoleLabels[role] ?? role,
                    style: TextStyle(
                      color: roleColor(role, context),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.store, size: 18),
                  label: Text(branchName),
                  backgroundColor: cs.secondaryContainer.withOpacity(.3),
                ),
                Chip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(shiftName),
                  backgroundColor: cs.tertiaryContainer.withOpacity(.25),
                ),
                Chip(
                  avatar: Icon(
                    status == 'approved' ? Icons.verified : Icons.hourglass_bottom,
                    size: 18,
                    color: status == 'approved' ? Colors.green : cs.onSurfaceVariant,
                  ),
                  label: Text(status),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Actions row
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: () async {
                    final newStatus = status == 'approved' ? 'pending' : 'approved';
                    await FirebaseFirestore.instance.collection('users').doc(uid).update({
                      'status': newStatus,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    onChanged();
                  },
                  child: Text(status == 'approved' ? 'Mark Pending' : 'Approve'),
                ),
                const SizedBox(width: 8),

                OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payroll editor (coming soon)')),
                    );
                  },
                  child: const Text('Edit Payroll'),
                ),
                const Spacer(),

                // تغيير الدور يظهر للأدمن فقط
                if (isAdmin)
                  DropdownButton<String>(
                    value: role,
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'branch_manager', child: Text('Branch Manager')),
                      DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                      DropdownMenuItem(value: 'employee', child: Text('Employee')),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      await FirebaseFirestore.instance.collection('users').doc(uid).update({
                        'role': v,
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                      onChanged();
                    },
                  ),

                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Confirm'),
                            content: const Text('Mark this user as left?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                            ],
                          ),
                        ) ??
                        false;
                    if (!ok) return;
                    await FirebaseFirestore.instance.collection('users').doc(uid).update({
                      'status': 'left',
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    onChanged();
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Leave'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/* --------------------------- CSV Converter --------------------------- */

class ListToCsvConverter {
  const ListToCsvConverter();

  String convert(List<List<dynamic>> rows,
      {String fieldDelimiter = ',', String eol = '\n'}) {
    final sb = StringBuffer();
    for (final row in rows) {
      for (int i = 0; i < row.length; i++) {
        var cell = row[i]?.toString() ?? '';
        // لفّ الحقول اللي فيها فواصل أو سطور داخل علامات اقتباس
        if (cell.contains(fieldDelimiter) || cell.contains('\n') || cell.contains('"')) {
          cell = '"${cell.replaceAll('"', '""')}"';
        }
        sb.write(cell);
        if (i != row.length - 1) sb.write(fieldDelimiter);
      }
      sb.write(eol);
    }
    return sb.toString();
  }
}
