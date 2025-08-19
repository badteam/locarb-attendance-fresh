// lib/screens/admin_users_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html; // للويب فقط
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/* =============================== ROLES =============================== */

const List<String> kRoles = [
  'employee',
  'supervisor',
  'branch_manager',
  'admin',
];

String roleLabel(String r) {
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

/* ========================= UTIL: Safe number ========================= */

double _numLike(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? 0.0;
  return 0.0;
}

Timestamp? _tsOrNull(dynamic v) {
  if (v is Timestamp) return v;
  return null;
}

/* ========================== ADMIN USERS PAGE ========================= */

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _statusTab = 'approved'; // or 'pending'
  final TextEditingController _searchCtrl = TextEditingController();
  String _roleFilter = 'all';
  String _branchFilterId = 'all';
  String _shiftFilterId = 'all';

  final Map<String, String> _branchNames = {'all': 'All branches'};
  final Map<String, String> _shiftNames = {'all': 'All shifts'};

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

  Future<void> _loadRefs() async {
    try {
      final br = await FirebaseFirestore.instance.collection('branches').get();
      for (final d in br.docs) {
        _branchNames[d.id] = (d['name'] ?? d.id).toString();
      }
    } catch (_) {}
    try {
      final sh = await FirebaseFirestore.instance.collection('shifts').get();
      for (final d in sh.docs) {
        _shiftNames[d.id] = (d['name'] ?? d.id).toString();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Query<Map<String, dynamic>> _buildUsersQuery() {
    var q = FirebaseFirestore.instance
        .collection('users')
        .where('status', isEqualTo: _statusTab)
        .orderBy('fullName', descending: false);
    return q;
  }

  Future<void> _setStatus(String uid, String status) async {
    await FirebaseFirestore.instance.doc('users/$uid').set(
      {'status': status, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> _setRole(String uid, String role) async {
    await FirebaseFirestore.instance.doc('users/$uid').set(
      {'role': role, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> _openPayrollDialog(String uid, Map<String, dynamic> userData) async {
    await showDialog(
      context: context,
      builder: (ctx) => PayrollDialog(uid: uid, userData: userData),
    );
  }

  Future<void> _exportCsvMonthly({DateTime? monthStart}) async {
    await exportUsersCsvMonthlyCompat(
      usersQuery: _buildUsersQuery(),
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
          // Filters
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              runSpacing: 12,
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search by name or email',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
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
                _FilterBox(
                  label: 'Branch',
                  child: DropdownButton<String>(
                    value: _branchFilterId,
                    items: branches
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _branchFilterId = v ?? 'all'),
                  ),
                ),
                _FilterBox(
                  label: 'Shift',
                  child: DropdownButton<String>(
                    value: _shiftFilterId,
                    items: shifts
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _shiftFilterId = v ?? 'all'),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _exportCsvMonthly(),
                  icon: const Icon(Icons.download),
                  label: const Text('Export CSV (Excel)'),
                ),
              ],
            ),
          ),
          const Divider(height: 0),
          // Users list
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

                final q = _searchCtrl.text.trim().toLowerCase();
                final docs = snap.data!.docs.where((d) {
                  final m = d.data();
                  final role = (m['role'] ?? 'employee').toString();
                  final brId = (m['primaryBranchId'] ?? '').toString();
                  final shId = (m['assignedShiftId'] ?? '').toString();
                  final roleOk = _roleFilter == 'all' || role == _roleFilter;
                  final brOk = _branchFilterId == 'all' || brId == _branchFilterId;
                  final shOk = _shiftFilterId == 'all' || shId == _shiftFilterId;
                  final matches = q.isEmpty
                      ? true
                      : ((m['fullName'] ?? '').toString().toLowerCase().contains(q) ||
                          (m['email'] ?? '').toString().toLowerCase().contains(q) ||
                          (m['username'] ?? '').toString().toLowerCase().contains(q));
                  return roleOk && brOk && shOk && matches;
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
                    final name = (m['fullName'] ?? m['username'] ?? m['email'] ?? '').toString();
                    final email = (m['email'] ?? '').toString();
                    final role = (m['role'] ?? 'employee').toString();
                    final status = (m['status'] ?? 'pending').toString();
                    final brId = (m['primaryBranchId'] ?? '').toString();
                    final shId = (m['assignedShiftId'] ?? '').toString();
                    final brName = (m['branchName'] ?? (_branchNames[brId] ?? (brId.isEmpty ? 'No branch' : brId))).toString();
                    final shName = (m['shiftName'] ?? (_shiftNames[shId] ?? (shId.isEmpty ? 'No shift' : shId))).toString();

                    return Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: Theme.of(context).textTheme.titleMedium),
                                      if (email.isNotEmpty)
                                        Text(email, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                Chip(
                                  avatar: Icon(
                                    status == 'approved' ? Icons.verified : Icons.hourglass_bottom,
                                    size: 18,
                                    color: status == 'approved' ? Colors.green : Colors.orange,
                                  ),
                                  label: Text(status),
                                  backgroundColor: status == 'approved' ? Colors.green.withOpacity(.12) : Colors.orange.withOpacity(.12),
                                  side: BorderSide.none,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: [
                                _InfoChip(icon: Icons.store, label: brName),
                                _InfoChip(icon: Icons.access_time, label: shName),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                OutlinedButton(
                                  onPressed: () {
                                    final next = status == 'approved' ? 'pending' : 'approved';
                                    _setStatus(u.id, next);
                                  },
                                  child: Text(status == 'approved' ? 'Mark Pending' : 'Approve'),
                                ),
                                const SizedBox(width: 12),
                                DropdownButton<String>(
                                  value: kRoles.contains(role) ? role : 'employee',
                                  items: kRoles.map((r) => DropdownMenuItem(value: r, child: Text(roleLabel(r)))).toList(),
                                  onChanged: (v) { if (v != null) _setRole(u.id, v); },
                                ),
                                const Spacer(),
                                OutlinedButton.icon(
                                  onPressed: () => _openPayrollDialog(u.id, m),
                                  icon: const Icon(Icons.payments),
                                  label: const Text('Edit Payroll'),
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
}

class _FilterBox extends StatelessWidget {
  final String label;
  final Widget child;
  const _FilterBox({required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withOpacity(.4)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label), side: BorderSide(color: Colors.grey.withOpacity(.25)));
  }
}

/* ============================= PAYROLL DIALOG ============================= */

class PayrollDialog extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> userData;
  const PayrollDialog({super.key, required this.uid, required this.userData});
  @override
  State<PayrollDialog> createState() => _PayrollDialogState();
}

class _PayrollDialogState extends State<PayrollDialog> {
  late final TextEditingController _baseSalaryCtrl;
  String _trxType = 'bonus'; // bonus | allowance | deduction
  final TextEditingController _amountCtrl = TextEditingController();
  DateTime _trxDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    // نقرأ من أي اسم محتمل للراتب الأساسي
    final base = _numLike(widget.userData['baseSalary']) +
        _numLike(widget.userData['base_salary']) +
        _numLike(widget.userData['salary']) +
        _numLike(widget.userData['monthlySalary']);
    _baseSalaryCtrl = TextEditingController(text: base == 0 ? '' : base.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _baseSalaryCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveBaseSalary() async {
    final v = _numLike(_baseSalaryCtrl.text);
    await FirebaseFirestore.instance.doc('users/${widget.uid}').set(
      {'baseSalary': v, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Base salary saved')));
      setState(() {});
    }
  }

  Future<void> _addTransaction() async {
    final amt = _numLike(_amountCtrl.text);
    if (amt == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount must be non-zero')));
      return;
    }
    await FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('payroll').add({
      'type': _trxType, // bonus | allowance | deduction
      'amount': amt,
      'date': Timestamp.fromDate(DateTime(_trxDate.year, _trxDate.month, _trxDate.day)),
      'createdAt': FieldValue.serverTimestamp(),
    });
    _amountCtrl.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction added')));
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // آخر 12 حركة
    final trxStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('payroll')
        .orderBy('date', descending: true)
        .limit(12)
        .snapshots();

    return AlertDialog(
      title: const Text('Payroll'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _baseSalaryCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Base salary', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _saveBaseSalary, child: const Text('Save')),
                ],
              ),
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerLeft, child: Text('Add transaction', style: Theme.of(context).textTheme.titleMedium)),
              const SizedBox(height: 8),
              Row(
                children: [
                  DropdownButton<String>(
                    value: _trxType,
                    items: const [
                      DropdownMenuItem(value: 'bonus', child: Text('Bonus')),
                      DropdownMenuItem(value: 'allowance', child: Text('Allowance')),
                      DropdownMenuItem(value: 'deduction', child: Text('Deduction')),
                    ],
                    onChanged: (v) => setState(() => _trxType = v ?? 'bonus'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _trxDate,
                        firstDate: DateTime(2020, 1, 1),
                        lastDate: DateTime(2100, 12, 31),
                      );
                      if (picked != null) setState(() => _trxDate = picked);
                    },
                    child: Text('${_trxDate.year}-${_trxDate.month.toString().padLeft(2, "0")}-${_trxDate.day.toString().padLeft(2, "0")}'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(onPressed: _addTransaction, icon: const Icon(Icons.add), label: const Text('Add')),
                ],
              ),
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerLeft, child: Text('Recent transactions', style: Theme.of(context).textTheme.titleMedium)),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: trxStream,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('No transactions'));
                  return Column(
                    children: docs.map((d) {
                      final m = d.data();
                      final t = (m['type'] ?? '').toString();
                      final a = _numLike(m['amount']);
                      final dt = _tsOrNull(m['date'])?.toDate() ?? _tsOrNull(m['createdAt'])?.toDate() ?? DateTime.now();
                      return ListTile(
                        dense: true,
                        title: Text('$t  •  ${a.toStringAsFixed(2)}'),
                        subtitle: Text('${dt.year}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}'),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async => d.reference.delete(),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

/* ======================== CSV EXPORT (COMPATIBLE) ======================== */

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
  final now = DateTime.now();
  final start = monthStart ?? DateTime(now.year, now.month, 1);
  final end = DateTime(start.year, start.month + 1, 1).subtract(const Duration(microseconds: 1));

  final snap = await usersQuery.get();
  var users = snap.docs;

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

  final rows = <List<String>>[
    [
      'Name','Email','Role','Status','Branch','Shift',
      'Base Salary','Bonuses/Allowances (month)','Deductions (month)','Net Salary (month)',
      'UID','Branch ID','Shift ID','Month',
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

    // 1) base salary من أي حقل شائع
    double baseSalary = 0;
    baseSalary += _numLike(m['baseSalary']);
    baseSalary += _numLike(m['base_salary']);
    baseSalary += _numLike(m['salary']);
    baseSalary += _numLike(m['monthlySalary']);

    // 2) مجاميع محفوظة مباشرة في مستند المستخدم (aliases كثيرة)
    double bonusesFixed = 0;
    for (final key in [
      'bonus','bonuses','bonusTotal','bonusesTotal',
      'allowance','allowances','allowanceTotal','allowancesTotal',
      'overtime','overtimeAmount'
    ]) {
      bonusesFixed += _numLike(m[key]);
    }

    double deductionsFixed = 0;
    for (final key in [
      'deduction','deductions','deductionTotal','deductionsTotal',
      'penalty','penalties','penaltiesTotal'
    ]) {
      deductionsFixed += _numLike(m[key]);
    }

    // 3) حركات شهرية من subcollection (تاريخ: date أو txnDate أو createdAt)
    double bonusesVar = 0, deductionsVar = 0;
    try {
      // هنجيب عدد معقول ونرشّح في الذاكرة لو ماقدرناش نستخدم where على كل الأسماء.
      final trx = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('payroll')
          .orderBy('date', descending: true)
          .limit(500)
          .get();

      final otherTrx = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('payroll')
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();

      final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>{}
        ..addAll(trx.docs) ..addAll(otherTrx.docs);

      for (final d in allDocs) {
        final mm = d.data();
        final t = (mm['type'] ?? '').toString().toLowerCase();
        final amount = _numLike(mm['amount']);
        final ts = _tsOrNull(mm['date']) ?? _tsOrNull(mm['txnDate']) ?? _tsOrNull(mm['createdAt']);
        final dt = ts?.toDate();
        if (dt == null) continue;
        if (dt.isBefore(start) || dt.isAfter(end)) continue;

        if (t == 'bonus' || t == 'allowance') {
          bonusesVar += amount;
        } else if (t == 'deduction') {
          deductionsVar += amount;
        }
      }
    } catch (_) {}

    final bonuses = bonusesFixed + bonusesVar;
    final deductions = deductionsFixed + deductionsVar;
    final net = (baseSalary + bonuses) - deductions;

    rows.add([
      name, email, role, stat, brNm, shNm,
      baseSalary.toStringAsFixed(2),
      bonuses.toStringAsFixed(2),
      deductions.toStringAsFixed(2),
      net.toStringAsFixed(2),
      uid, brId, shId,
      '${start.year}-${start.month.toString().padLeft(2, "0")}',
    ]);
  }

  if (!kIsWeb) return;
  final csv = const ListToCsvConverter().convert(rows);
  final bytes = utf8.encode(csv);
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final fileName = 'users_payroll_${statusTab}_${start.year}-${start.month.toString().padLeft(2, "0")}.csv';
  final a = html.AnchorElement(href: url)..setAttribute('download', fileName)..click();
  html.Url.revokeObjectUrl(url);
}
