// lib/screens/admin_users_screen.dart
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
  // ====== Filters & search ======
  final _searchCtrl = TextEditingController();
  String _roleFilter = 'all';
  String _branchFilterId = 'all';
  String _shiftFilterId = 'all';

  // Static roles list (زد/قلّل حسب احتياجك)
  static const kRoles = <String>[
    'all',
    'admin',
    'manager', // مدير نظام عام
    'branch_manager',
    'supervisor',
    'employee',
  ];

  // ====== Caches for drop-downs ======
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadBranches() async {
    final snap =
        await FirebaseFirestore.instance.collection('branches').orderBy('name').get();
    return snap.docs;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadShifts() async {
    final snap =
        await FirebaseFirestore.instance.collection('shifts').orderBy('name').get();
    return snap.docs;
  }

  // Users stream (بنصفّي لاحقًا على الذاكرة عشان ما نركّب Composite Indexات كتير)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _usersStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .orderBy('fullName', descending: false)
        .snapshots()
        .map((s) => s.docs);
  }

  // ====== Export CSV ======
  Future<void> _exportUsersCsv(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    // فلترة على الذاكرة
    final filtered = docs.where((d) {
      final m = d.data();
      final role = (m['role'] ?? 'employee').toString();
      final brId = (m['primaryBranchId'] ?? '').toString();
      final shId = (m['assignedShiftId'] ?? '').toString();

      final search = _searchCtrl.text.trim().toLowerCase();
      final inSearch = search.isEmpty ||
          (m['fullName']?.toString().toLowerCase().contains(search) ?? false) ||
          (m['email']?.toString().toLowerCase().contains(search) ?? false);

      final okRole = _roleFilter == 'all' || _roleFilter == role;
      final okBr = _branchFilterId == 'all' || _branchFilterId == brId;
      final okSh = _shiftFilterId == 'all' || _shiftFilterId == shId;

      return inSearch && okRole && okBr && okSh;
    }).toList();

    final rows = <List<String>>[];
    rows.add([
      'UID',
      'FullName',
      'Email',
      'Role',
      'Status',
      'BranchId',
      'ShiftId',
      'SalaryBase',
      'AllowancesTotal',
      'DeductionsTotal',
      'Net',
      'UpdatedAt',
    ]);

    for (final d in filtered) {
      final m = d.data();

      final base = (m['salaryBase'] as num?) ?? 0;

      final allowTotal = ((m['allowances'] as List?) ?? [])
          .map((e) => (e as Map)['amount'] as num? ?? 0)
          .fold<num>(0, (s, e) => s + e);

      final dedTotal = ((m['deductions'] as List?) ?? [])
          .map((e) => (e as Map)['amount'] as num? ?? 0)
          .fold<num>(0, (s, e) => s + e);

      final net = base + allowTotal - dedTotal;

      rows.add([
        d.id,
        (m['fullName'] ?? m['username'] ?? '').toString(),
        (m['email'] ?? '').toString(),
        (m['role'] ?? 'employee').toString(),
        (m['status'] ?? 'pending').toString(),
        (m['primaryBranchId'] ?? '').toString(),
        (m['assignedShiftId'] ?? '').toString(),
        base.toString(),
        allowTotal.toString(),
        dedTotal.toString(),
        net.toString(),
        (m['updatedAt'] is Timestamp)
            ? (m['updatedAt'] as Timestamp).toDate().toIso8601String()
            : '',
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final now = DateTime.now();
    final fileName =
        'users_payroll_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.csv';

    final a = html.AnchorElement(href: url)..download = fileName;
    a.click();
    html.Url.revokeObjectUrl(url);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ====== Filters row ======
            Wrap(
              runSpacing: 8,
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 340,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name or email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                // Role
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    value: _roleFilter,
                    items: kRoles
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r == 'all' ? 'All roles' : r),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),

                // Branch
                FutureBuilder(
                  future: _loadBranches(),
                  builder: (context, snapshot) {
                    final items = <DropdownMenuItem<String>>[
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All branches'),
                      )
                    ];
                    if (snapshot.hasData) {
                      items.addAll(snapshot.data!
                          .map((d) => DropdownMenuItem(
                                value: d.id,
                                child: Text((d.data()['name'] ?? '').toString()),
                              )));
                    }
                    return SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: _branchFilterId,
                        items: items,
                        onChanged: (v) =>
                            setState(() => _branchFilterId = v ?? 'all'),
                        decoration: const InputDecoration(
                          labelText: 'Branch',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    );
                  },
                ),

                // Shift
                FutureBuilder(
                  future: _loadShifts(),
                  builder: (context, snapshot) {
                    final items = <DropdownMenuItem<String>>[
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All shifts'),
                      )
                    ];
                    if (snapshot.hasData) {
                      items.addAll(snapshot.data!
                          .map((d) => DropdownMenuItem(
                                value: d.id,
                                child: Text((d.data()['name'] ?? '').toString()),
                              )));
                    }
                    return SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: _shiftFilterId,
                        items: items,
                        onChanged: (v) =>
                            setState(() => _shiftFilterId = v ?? 'all'),
                        decoration: const InputDecoration(
                          labelText: 'Shift',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    );
                  },
                ),

                // Export
                StreamBuilder(
                  stream: _usersStream(),
                  builder: (context, snapshot) {
                    final can = snapshot.hasData && snapshot.data!.isNotEmpty;
                    return FilledButton.icon(
                      onPressed: can
                          ? () => _exportUsersCsv(snapshot.data!)
                          : null,
                      icon: const Icon(Icons.download),
                      label: const Text('Export CSV (Excel)'),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ====== Users list ======
            Expanded(
              child: StreamBuilder<
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                stream: _usersStream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  var docs = snap.data ?? [];

                  // Apply search & filters
                  final search = _searchCtrl.text.trim().toLowerCase();
                  docs = docs.where((d) {
                    final m = d.data();
                    final role = (m['role'] ?? 'employee').toString();
                    final brId = (m['primaryBranchId'] ?? '').toString();
                    final shId = (m['assignedShiftId'] ?? '').toString();

                    final inSearch = search.isEmpty ||
                        (m['fullName']?.toString().toLowerCase().contains(search) ??
                            false) ||
                        (m['email']?.toString().toLowerCase().contains(search) ??
                            false);

                    final okRole = _roleFilter == 'all' || _roleFilter == role;
                    final okBr =
                        _branchFilterId == 'all' || _branchFilterId == brId;
                    final okSh =
                        _shiftFilterId == 'all' || _shiftFilterId == shId;

                    return inSearch && okRole && okBr && okSh;
                  }).toList();

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        'No users found',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => Divider(color: cs.outline),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final m = d.data();
                      return _UserCard(
                        uid: d.id,
                        data: m,
                        loadBranches: _loadBranches,
                        loadShifts: _loadShifts,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// User Card + inline actions (assign branch/shift, allowAnyBranch, edit payroll)
// ===================================================================
class _UserCard extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> Function()
      loadBranches;
  final Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> Function()
      loadShifts;

  const _UserCard({
    required this.uid,
    required this.data,
    required this.loadBranches,
    required this.loadShifts,
  });

  Future<void> _assign({
    String? branchId,
    String? shiftId,
    bool? allowAnyBranch,
  }) async {
    final updates = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (branchId != null) updates['primaryBranchId'] = branchId;
    if (shiftId != null) updates['assignedShiftId'] = shiftId;
    if (allowAnyBranch != null) updates['allowAnyBranch'] = allowAnyBranch;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set(updates, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final name = (data['fullName'] ?? data['username'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final role = (data['role'] ?? 'employee').toString();
    final status = (data['status'] ?? 'pending').toString();
    final primaryBranchId = (data['primaryBranchId'] ?? '').toString();
    final assignedShiftId = (data['assignedShiftId'] ?? '').toString();
    final allowAnyBranch = (data['allowAnyBranch'] as bool?) ?? false;

    final cs = Theme.of(context).colorScheme;

    return ListTile(
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(email),
      trailing: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          // Role chip
          Chip(
            label: Text(role),
            avatar: const Icon(Icons.badge, size: 18),
          ),
          // Status chip
          Chip(
            label: Text(status),
            avatar: const Icon(Icons.verified, size: 18),
            backgroundColor:
                status == 'approved' ? cs.secondaryContainer : cs.surfaceVariant,
          ),
          // Edit payroll
          OutlinedButton.icon(
            onPressed: () async {
              final res = await showDialog(
                context: context,
                builder: (_) => _PayrollDialogInline(uid: uid, user: data),
              );
              if (res == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payroll updated')),
                );
              }
            },
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Edit Payroll'),
          ),
        ],
      ),
      // Assign row under title
      isThreeLine: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      subtitleTextStyle: Theme.of(context).textTheme.bodyMedium,
      dense: false,
      // Bottom controls (branch / shift / allowAnyBranch)
      // نستخدم Column عشان نظهر سطر تعيين واضح
      // ignore: prefer_const_constructors
      // (already set subtitle above; نبني أدوات أسفل)
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(email),
          const SizedBox(height: 8),
          Row(
            children: [
              // Branch selector
              FutureBuilder(
                future: loadBranches(),
                builder: (context, snapshot) {
                  final items = <DropdownMenuItem<String>>[
                    const DropdownMenuItem(
                      value: '',
                      child: Text('No branch'),
                    )
                  ];
                  if (snapshot.hasData) {
                    items.addAll(snapshot.data!
                        .map((d) => DropdownMenuItem(
                              value: d.id,
                              child: Text((d.data()['name'] ?? '').toString()),
                            )));
                  }
                  return SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      value: primaryBranchId,
                      items: items,
                      onChanged: (v) => _assign(branchId: v),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.store_outlined),
                        border: OutlineInputBorder(),
                        labelText: 'Branch',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),

              // Shift selector
              FutureBuilder(
                future: loadShifts(),
                builder: (context, snapshot) {
                  final items = <DropdownMenuItem<String>>[
                    const DropdownMenuItem(
                      value: '',
                      child: Text('No shift'),
                    )
                  ];
                  if (snapshot.hasData) {
                    items.addAll(snapshot.data!
                        .map((d) => DropdownMenuItem(
                              value: d.id,
                              child: Text((d.data()['name'] ?? '').toString()),
                            )));
                  }
                  return SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      value: assignedShiftId,
                      items: items,
                      onChanged: (v) => _assign(shiftId: v),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.schedule_outlined),
                        border: OutlineInputBorder(),
                        labelText: 'Shift',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),

              // Allow from any branch
              Row(
                children: [
                  const Text('Allow any branch'),
                  const SizedBox(width: 6),
                  Switch(
                    value: allowAnyBranch,
                    onChanged: (v) => _assign(allowAnyBranch: v),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===================================================================
// Inline Payroll Dialog (مدمج داخل نفس الملف)
// ===================================================================
class _PayrollDialogInline extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> user;
  const _PayrollDialogInline({required this.uid, required this.user});

  @override
  State<_PayrollDialogInline> createState() => _PayrollDialogInlineState();
}

class _PayrollDialogInlineState extends State<_PayrollDialogInline> {
  late final TextEditingController _baseCtrl;
  late final TextEditingController _otRateCtrl;

  final _allowNote = TextEditingController();
  final _allowAmount = TextEditingController();
  final _dedNote = TextEditingController();
  final _dedAmount = TextEditingController();

  List<Map<String, dynamic>> _allowances = [];
  List<Map<String, dynamic>> _deductions = [];

  num get base =>
      num.tryParse(_baseCtrl.text.trim()) ??
      (widget.user['salaryBase'] as num? ?? 0);

  num get otRate => num.tryParse(_otRateCtrl.text.trim()) ??
      (widget.user['leaveBalance']?['overtimeRate'] as num? ?? 0);

  num get allowTotal =>
      _allowances.fold<num>(0, (s, e) => s + ((e['amount'] as num?) ?? 0));
  num get dedTotal =>
      _deductions.fold<num>(0, (s, e) => s + ((e['amount'] as num?) ?? 0));
  num get net => base + allowTotal - dedTotal;

  @override
  void initState() {
    super.initState();
    _baseCtrl =
        TextEditingController(text: ((widget.user['salaryBase'] as num?) ?? 0).toString());
    _otRateCtrl = TextEditingController(
        text: ((widget.user['leaveBalance']?['overtimeRate'] as num?) ?? 0).toString());

    _allowances = (widget.user['allowances'] as List?)
            ?.cast<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];
    _deductions = (widget.user['deductions'] as List?)
            ?.cast<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        [];
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _otRateCtrl.dispose();
    _allowNote.dispose();
    _allowAmount.dispose();
    _dedNote.dispose();
    _dedAmount.dispose();
    super.dispose();
  }

  Future<void> _saveBasics() async {
    await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
      'salaryBase': num.tryParse(_baseCtrl.text.trim()) ?? 0,
      'leaveBalance': {
        ...(widget.user['leaveBalance'] as Map<String, dynamic>? ?? {}),
        'overtimeRate': num.tryParse(_otRateCtrl.text.trim()) ?? 0,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _addAllowance() async {
    final note = _allowNote.text.trim();
    final amt = num.tryParse(_allowAmount.text.trim());
    if (note.isEmpty || amt == null) return;

    final item = {'note': note, 'amount': amt, 'ts': FieldValue.serverTimestamp()};

    await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
      'allowances': FieldValue.arrayUnion([item]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() {
      _allowances.add({'note': note, 'amount': amt, 'ts': DateTime.now()});
      _allowNote.clear();
      _allowAmount.clear();
    });
  }

  Future<void> _addDeduction() async {
    final note = _dedNote.text.trim();
    final amt = num.tryParse(_dedAmount.text.trim());
    if (note.isEmpty || amt == null) return;

    final item = {'note': note, 'amount': amt, 'ts': FieldValue.serverTimestamp()};

    await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
      'deductions': FieldValue.arrayUnion([item]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() {
      _deductions.add({'note': note, 'amount': amt, 'ts': DateTime.now()});
      _dedNote.clear();
      _dedAmount.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Text('Edit Payroll',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _baseCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Base salary',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _otRateCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Overtime rate',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _section(
                        title: 'Allowances',
                        color: Colors.green.shade50,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _allowNote,
                                    decoration:
                                        const InputDecoration(labelText: 'Note'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: _allowAmount,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                        labelText: 'Amount'),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: _addAllowance,
                                )
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._allowances.map((e) => ListTile(
                                  dense: true,
                                  title: Text(e['note']?.toString() ?? ''),
                                  trailing:
                                      Text((e['amount'] ?? 0).toString()),
                                )),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _section(
                        title: 'Deductions',
                        color: Colors.red.shade50,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _dedNote,
                                    decoration:
                                        const InputDecoration(labelText: 'Note'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: _dedAmount,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                        labelText: 'Amount'),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: _addDeduction,
                                )
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._deductions.map((e) => ListTile(
                                  dense: true,
                                  title: Text(e['note']?.toString() ?? ''),
                                  trailing:
                                      Text((e['amount'] ?? 0).toString()),
                                )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Allowances: $allowTotal'),
                      Text('Deductions: $dedTotal'),
                      const SizedBox(height: 4),
                      Text('Net: $net',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saveBasics,
                      child: const Text('Save'),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section({required String title, required Widget child, Color? color}) {
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
