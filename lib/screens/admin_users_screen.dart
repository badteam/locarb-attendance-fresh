// lib/screens/admin_users_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html; // يُستخدم للتحميل على الويب فقط
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// أدوار النظام (لا نغيّر في الداتابيز: نقرأ الموجود فقط)
const List<String> kRoles = [
  'employee',
  'supervisor',
  'branch_manager',
  'admin',
];

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  // تبويب الحالة
  String _statusTab = 'approved'; // or 'pending'

  // فلاتر
  final TextEditingController _searchCtrl = TextEditingController();
  String _roleFilter = 'all';
  String _branchFilterId = 'all';
  String _shiftFilterId = 'all';

  // بيانات الفروع/الشفتات (id=>name) لعرض القوائم فقط
  final Map<String, String> _branchNames = {'all': 'All branches'};
  final Map<String, String> _shiftNames = {'all': 'All shifts'};

  // تحميل الفروع والشفتات مرة واحدة
  Future<void> _loadRefs() async {
    // branches
    try {
      final br = await FirebaseFirestore.instance.collection('branches').get();
      for (final d in br.docs) {
        final name = (d['name'] ?? d.id).toString();
        _branchNames[d.id] = name;
      }
    } catch (_) {}
    // shifts
    try {
      final sh = await FirebaseFirestore.instance.collection('shifts').get();
      for (final d in sh.docs) {
        final name = (d['name'] ?? d.id).toString();
        _shiftNames[d.id] = name;
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// استعلام المستخدمين الأساسي حسب الحالة
  Query<Map<String, dynamic>> _buildUsersQuery() {
    var q = FirebaseFirestore.instance.collection('users')
      .where('status', isEqualTo: _statusTab);
    // ترتيب اختياري
    q = q.orderBy('fullName', descending: false);
    return q;
  }

  /// تغيير الحالة Pending/Approved
  Future<void> _setStatus(String uid, String status) async {
    await FirebaseFirestore.instance.doc('users/$uid').set(
      {'status': status, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// تغيير الدور
  Future<void> _setRole(String uid, String role) async {
    await FirebaseFirestore.instance.doc('users/$uid').set(
      {'role': role, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  /// تصدير CSV شهري – لا يغير أي schema
  Future<void> _exportCsvMonthly({
    DateTime? monthStart,
  }) async {
    final usersQuery = _buildUsersQuery();
    await exportUsersCsvMonthlyCompat(
      usersQuery: usersQuery,
      roleFilter: _roleFilter,
      branchFilterId: _branchFilterId,
      shiftFilterId: _shiftFilterId,
      monthStart: monthStart,
      statusTab: _statusTab,
      searchText: _searchCtrl.text,
      branchNames: _branchNames,
      shiftNames: _shiftNames,
    );
  }

  // واجهة
  @override
  Widget build(BuildContext context) {
    final branches = _branchNames.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    final shifts = _shiftNames.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          // سوئتش بين Pending/Approved
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pending', label: Text('Pending')),
                ButtonSegment(value: 'approved', label: Text('Approved')),
              ],
              selected: {_statusTab},
              onSelectionChanged: (s) => setState(() => _statusTab = s.first),
              showSelectedIcon: false,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // شريط الفلاتر
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              runSpacing: 12,
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // بحث
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search by name or email',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),

                // Role
                _FilterBox(
                  label: 'Role',
                  child: DropdownButton<String>(
                    value: _roleFilter,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All roles')),
                      DropdownMenuItem(value: 'employee', child: Text('Employee')),
                      DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                      DropdownMenuItem(value: 'branch_manager', child: Text('Branch manager')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    ],
                    onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
                  ),
                ),

                // Branch
                _FilterBox(
                  label: 'Branch',
                  child: DropdownButton<String>(
                    value: _branchFilterId,
                    items: branches
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _branchFilterId = v ?? 'all'),
                  ),
                ),

                // Shift
                _FilterBox(
                  label: 'Shift',
                  child: DropdownButton<String>(
                    value: _shiftFilterId,
                    items: shifts
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _shiftFilterId = v ?? 'all'),
                  ),
                ),

                // Export
                FilledButton.icon(
                  onPressed: () => _exportCsvMonthly(),
                  icon: const Icon(Icons.download),
                  label: const Text('Export CSV (Excel)'),
                ),
              ],
            ),
          ),
          const Divider(height: 0),

          // قائمة المستخدمين
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildUsersQuery().snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData) {
                  return const Center(child: Text('No data'));
                }

                // فلترة في الذاكرة حسب الفلاتر والبحث
                final q = _searchCtrl.text.trim().toLowerCase();
                final docs = snap.data!.docs.where((d) {
                  final m = d.data();

                  final role = (m['role'] ?? 'employee').toString();
                  final brId = (m['primaryBranchId'] ?? '').toString();
                  final shId = (m['assignedShiftId'] ?? '').toString();

                  final roleOk = _roleFilter == 'all' || role == _roleFilter;
                  final brOk = _branchFilterId == 'all' || brId == _branchFilterId;
                  final shOk = _shiftFilterId == 'all' || shId == _shiftFilterId;

                  final matchesSearch = q.isEmpty
                      ? true
                      : ((m['fullName'] ?? '').toString().toLowerCase().contains(q) ||
                          (m['email'] ?? '').toString().toLowerCase().contains(q) ||
                          (m['username'] ?? '').toString().toLowerCase().contains(q));

                  return roleOk && brOk && shOk && matchesSearch;
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('No users match these filters.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final u = docs[i];
                    final m = u.data();

                    final name =
                        (m['fullName'] ?? m['username'] ?? m['email'] ?? '').toString();
                    final email = (m['email'] ?? '').toString();
                    final role = (m['role'] ?? 'employee').toString();
                    final status = (m['status'] ?? 'pending').toString();

                    final brId = (m['primaryBranchId'] ?? '').toString();
                    final shId = (m['assignedShiftId'] ?? '').toString();

                    final brName =
                        (m['branchName'] ?? (_branchNames[brId] ?? (brId.isEmpty ? 'No branch' : brId))).toString();
                    final shName =
                        (m['shiftName'] ?? (_shiftNames[shId] ?? (shId.isEmpty ? 'No shift' : shId))).toString();

                    return Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // السطر العلوي: الاسم + الإيميل + شارات
                            Row(
                              children: [
                                CircleAvatar(
                                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          style: Theme.of(context).textTheme.titleMedium),
                                      if (email.isNotEmpty)
                                        Text(email,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                // حالة المستخدم
                                _StatusChip(status: status),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // معلومات الفرع والشفت
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _InfoChip(icon: Icons.store, label: brName),
                                _InfoChip(icon: Icons.access_time, label: shName),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // أكشنز: تغيير الحالة + الدور
                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: () {
                                    final next =
                                        status == 'approved' ? 'pending' : 'approved';
                                    _setStatus(u.id, next);
                                  },
                                  child: Text(status == 'approved'
                                      ? 'Mark Pending'
                                      : 'Approve'),
                                ),
                                const SizedBox(width: 12),
                                // اختيار الدور
                                DropdownButton<String>(
                                  value: kRoles.contains(role) ? role : 'employee',
                                  items: kRoles
                                      .map((r) => DropdownMenuItem(
                                            value: r,
                                            child: Text(_roleLabel(r)),
                                          ))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) _setRole(u.id, v);
                                  },
                                ),
                                const Spacer(),
                                // زر راتب (اختياري – مجرد placeholder)
                                OutlinedButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Payroll dialog is not implemented here – محفوظ كما هو.'),
                                      ),
                                    );
                                  },
                                  child: const Text('Edit Payroll'),
                                ),
                              ],
                            ),
                          ],
                        ),
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

  String _roleLabel(String r) {
    switch (r) {
      case 'admin':
        return 'Admin';
      case 'supervisor':
        return 'Supervisor';
      case 'branch_manager':
        return 'Branch manager';
      default:
        return 'Employee';
    }
  }
}

/// صندوق فلتر صغير
class _FilterBox extends StatelessWidget {
  final String label;
  final Widget child;
  const _FilterBox({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withOpacity(.4)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// شارة الحالة
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final ok = status == 'approved';
    return Chip(
      avatar: Icon(ok ? Icons.verified : Icons.hourglass_bottom,
          size: 18, color: ok ? Colors.green : Colors.orange),
      label: Text(status),
      backgroundColor: ok ? Colors.green.withOpacity(.12) : Colors.orange.withOpacity(.12),
      side: BorderSide.none,
    );
  }
}

/// شارة معلومات
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      side: BorderSide(color: Colors.grey.withOpacity(.25)),
    );
  }
}

/* -------------------------------------------------------------------------- */
/* -------------------  CSV Export (متوافق مع الموجود)  ---------------------- */
/* -------------------------------------------------------------------------- */

Future<void> exportUsersCsvMonthlyCompat({
  required Query<Map<String, dynamic>> usersQuery,
  required String roleFilter,
  required String branchFilterId,
  required String shiftFilterId,
  required String statusTab,
  required String searchText,
  required Map<String, String> branchNames,
  required Map<String, String> shiftNames,
  DateTime? monthStart,
}) async {
  // نطاق الشهر
  final now = DateTime.now();
  final start = monthStart ?? DateTime(now.year, now.month, 1);
  final end = DateTime(start.year, start.month + 1, 1)
      .subtract(const Duration(microseconds: 1));

  // اجلب المستخدمين
  final snap = await usersQuery.get();
  var users = snap.docs;

  // فلترة في الذاكرة (لا تغيّر الداتابيز)
  final q = searchText.trim().toLowerCase();
  users = users.where((u) {
    final m = u.data();
    final role = (m['role'] ?? 'employee').toString();
    final brId = (m['primaryBranchId'] ?? '').toString();
    final shId = (m['assignedShiftId'] ?? '').toString();

    final roleOk = roleFilter == 'all' || role == roleFilter;
    final brOk = branchFilterId == 'all' || brId == branchFilterId;
    final shOk = shiftFilterId == 'all' || shId == shiftFilterId;

    final matches = q.isEmpty
        ? true
        : ((m['fullName'] ?? '').toString().toLowerCase().contains(q) ||
            (m['email'] ?? '').toString().toLowerCase().contains(q) ||
            (m['username'] ?? '').toString().toLowerCase().contains(q));

    return roleOk && brOk && shOk && matches;
  }).toList();

  // رؤوس CSV — UID في آخر عمود
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
    ],
  ];

  for (final u in users) {
    final m = u.data();

    final uid   = u.id;
    final name  = (m['fullName'] ?? m['username'] ?? m['email'] ?? '').toString();
    final email = (m['email'] ?? '').toString();
    final role  = (m['role'] ?? 'employee').toString();
    final stat  = (m['status'] ?? 'pending').toString();

    final brId  = (m['primaryBranchId'] ?? '').toString();
    final shId  = (m['assignedShiftId'] ?? '').toString();

    final brNm  = (m['branchName'] ?? (branchNames[brId] ?? (brId.isEmpty ? 'No branch' : brId))).toString();
    final shNm  = (m['shiftName']  ?? (shiftNames[shId]  ?? (shId.isEmpty ? 'No shift'  : shId ))).toString();

    final baseSalary = (m['baseSalary'] ?? 0).toDouble();

    // نجمع معاملات الشهر (اختياري)
    double bonuses = 0;
    double deductions = 0;
    try {
      final trx = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('payroll')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      for (final d in trx.docs) {
        final t = (d['type'] ?? '').toString().toLowerCase();
        final amt = (d['amount'] ?? 0).toDouble();
        if (t == 'bonus' || t == 'allowance') {
          bonuses += amt;
        } else if (t == 'deduction') {
          deductions += amt;
        }
      }
    } catch (_) {
      // تجاهل لو مفيش صلاحية/كوليكشن
    }

    final net = (baseSalary + bonuses) - deductions;

    rows.add([
      name,
      email,
      role,
      stat,
      brNm,
      shNm,
      baseSalary.toStringAsFixed(2),
      bonuses.toStringAsFixed(2),
      deductions.toStringAsFixed(2),
      net.toStringAsFixed(2),
      uid,     // UID آخر عمود
      brId,
      shId,
      '${start.year}-${start.month.toString().padLeft(2, "0")}',
    ]);
  }

  // أنشئ الملف ونزّله (ويب فقط)
  if (!kIsWeb) {
    // على الموبايل: ممكن ترفعه لـ Storage أو تحفظه محلي – خارج نطاقنا هنا
    return;
  }
  final csv = const ListToCsvConverter().convert(rows);
  final bytes = utf8.encode(csv);
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final fileName =
      'users_payroll_${statusTab}_${start.year}-${start.month.toString().padLeft(2, "0")}.csv';

  final a = html.AnchorElement(href: url)..setAttribute('download', fileName)..click();
  html.Url.revokeObjectUrl(url);
}
