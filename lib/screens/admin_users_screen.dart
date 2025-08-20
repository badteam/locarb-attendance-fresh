import 'dart:convert';
import 'dart:html' as html show Blob, Url, AnchorElement; // للويب فقط
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  // تبويب الحالة
  late TabController _tab;
  String get _statusTab => _tab.index == 0 ? 'pending' : 'approved';

  // بحث
  final _search = TextEditingController();

  // فلاتر
  static const List<String> kRoles = [
    'all',
    'employee',
    'supervisor',
    'branch_manager',
    'admin'
  ];
  String _roleFilter = 'all';
  String _branchFilterId = 'all';
  String _shiftFilterId = 'all';

  // بيانات فلاتر الفروع والشيفتات
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _branches = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _shifts = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    final bs = await FirebaseFirestore.instance
        .collection('branches')
        .orderBy('name')
        .get();
    final ss =
        await FirebaseFirestore.instance.collection('shifts').orderBy('name').get();
    setState(() {
      _branches = bs.docs;
      _shifts = ss.docs;
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _search.dispose();
    super.dispose();
  }

  // ============ Helpers ============

  String _branchNameById(String? id) {
    if (id == null || id.isEmpty) return 'No branch';
    final found = _branches.firstWhere(
      (e) => e.id == id,
      orElse: () => null as QueryDocumentSnapshot<Map<String, dynamic>>,
    );
    if (found == null) return 'No branch';
    return (found.data()['name'] ?? 'No branch').toString();
  }

  String _shiftNameById(String? id) {
    if (id == null || id.isEmpty) return 'No shift';
    final found = _shifts.firstWhere(
      (e) => e.id == id,
      orElse: () => null as QueryDocumentSnapshot<Map<String, dynamic>>,
    );
    if (found == null) return 'No shift';
    return (found.data()['name'] ?? 'No shift').toString();
  }

  Query<Map<String, dynamic>> _baseUsersQuery() {
    var q = FirebaseFirestore.instance.collection('users').where(
          'status',
          isEqualTo: _statusTab,
        );

    // فلترة role على مستوى الاستعلام ممكن لاحقًا؛ الآن هنفلتر بالذاكرة
    return q.orderBy('fullName', descending: false);
  }

  bool _matchesFilters(Map<String, dynamic> m) {
    final role = (m['role'] ?? 'employee').toString();
    final branchId = (m['primaryBranchId'] ?? '').toString();
    final shiftId = (m['assignedShiftId'] ?? '').toString();

    final roleOk = _roleFilter == 'all' || role == _roleFilter;
    final branchOk = _branchFilterId == 'all' || branchId == _branchFilterId;
    final shiftOk = _shiftFilterId == 'all' || shiftId == _shiftFilterId;

    // بحث
    final q = _search.text.trim().toLowerCase();
    final name = (m['fullName'] ?? m['username'] ?? '').toString().toLowerCase();
    final email = (m['email'] ?? '').toString().toLowerCase();
    final searchOk = q.isEmpty || name.contains(q) || email.contains(q);

    return roleOk && branchOk && shiftOk && searchOk;
  }

  // ============ Export CSV ============
  String _csvEscape(String v) {
    // بسيط: يلف الخلية بين "" ويستبدل " بـ ""
    final s = v.replaceAll('"', '""');
    return '"$s"';
  }

  Future<void> _exportCsv(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('CSV export supported on Web only for now.'),
      ));
      return;
    }

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
      'Base Salary',
      'Allowances',
      'Deductions',
      'Overtime Rate',
      'Allow Any Branch',
      'Created At',
      'Updated At',
    ]);

    for (final d in docs) {
      final m = d.data();
      final leave = (m['leaveBalance'] ?? {}) as Map<String, dynamic>;
      rows.add([
        d.id,
        (m['fullName'] ?? m['username'] ?? '').toString(),
        (m['email'] ?? '').toString(),
        (m['role'] ?? 'employee').toString(),
        (m['status'] ?? 'pending').toString(),
        (m['branchName'] ??
                _branchNameById((m['primaryBranchId'] ?? '').toString()))
            .toString(),
        (m['primaryBranchId'] ?? '').toString(),
        (m['shiftName'] ??
                _shiftNameById((m['assignedShiftId'] ?? '').toString()))
            .toString(),
        (m['assignedShiftId'] ?? '').toString(),
        (m['salaryBase'] ?? 0).toString(),
        (m['allowances'] ?? 0).toString(),
        (m['deductions'] ?? 0).toString(),
        (leave['overtimeRate'] ?? 0).toString(),
        ((m['allowAnyBranch'] ?? false) ? 'true' : 'false'),
        m['createdAt'] is Timestamp
            ? (m['createdAt'] as Timestamp).toDate().toIso8601String()
            : '',
        m['updatedAt'] is Timestamp
            ? (m['updatedAt'] as Timestamp).toDate().toIso8601String()
            : '',
      ].map((e) => _csvEscape(e)).toList());
    }

    final csv = rows.map((r) => r.join(',')).join('\n');
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final now = DateTime.now();
    final fileName =
    'users_${_statusTab}_role-${_roleFilter}_branch-${_branchFilterId}_shift-${_shiftFilterId}_${now.year}-${now.month.toString().padLeft(2,"0")}-${now.day.toString().padLeft(2,"0")}.csv';
      
    final a = html.AnchorElement(href: url)..setAttribute('download', fileName);
    a.click();
    html.Url.revokeObjectUrl(url);
  }

  // ============ Update helpers ============
  Future<void> _updateUser(String uid, Map<String, dynamic> data) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _assignBranch(String uid) async {
    final selected = await showDialog<String?>(
      context: context,
      builder: (_) => _SelectDialog(
        title: 'Assign Branch',
        items: _branches
            .map((e) => _SelectItem(id: e.id, label: e.data()['name'] ?? ''))
            .toList(),
      ),
    );
    if (selected == null) return;
    final name = _branchNameById(selected);
    await _updateUser(uid, {
      'primaryBranchId': selected,
      'branchName': name,
    });
  }

  Future<void> _assignShift(String uid) async {
    final selected = await showDialog<String?>(
      context: context,
      builder: (_) => _SelectDialog(
        title: 'Assign Shift',
        items:
            _shifts.map((e) => _SelectItem(id: e.id, label: e.data()['name'])).toList(),
      ),
    );
    if (selected == null) return;
    final name = _shiftNameById(selected);
    await _updateUser(uid, {
      'assignedShiftId': selected,
      'shiftName': name,
    });
  }

  Future<void> _toggleAllowAnyBranch(String uid, bool value) async {
    await _updateUser(uid, {'allowAnyBranch': value});
  }

  Future<void> _changeStatus(String uid, String to) async {
    await _updateUser(uid, {'status': to});
  }

  Future<void> _changeRole(String uid, String to) async {
    await _updateUser(uid, {'role': to});
  }

  Future<void> _editPayroll(String uid, Map<String, dynamic> m) async {
    await showDialog(
      context: context,
      builder: (_) => _PayrollDialog(
        uid: uid,
        initial: m,
      ),
    );
  }

  // ============ UI ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
          ],
          onTap: (_) => setState(() {}),
        ),
      ),
      body: Column(
        children: [
          // شريط البحث والفلاتر
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 240, maxWidth: 420),
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name or email',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                // Role
                _FilterDropdown<String>(
                  label: 'Role',
                  value: _roleFilter,
                  items: kRoles
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r == 'all' ? 'All roles' : r),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
                ),
                // Branch
                _FilterDropdown<String>(
                  label: 'Branch',
                  value: _branchFilterId,
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All branches'),
                    ),
                    ..._branches.map((b) => DropdownMenuItem(
                          value: b.id,
                          child: Text(b.data()['name'] ?? ''),
                        )),
                  ],
                  onChanged: (v) => setState(() => _branchFilterId = v ?? 'all'),
                ),
                // Shift
                _FilterDropdown<String>(
                  label: 'Shift',
                  value: _shiftFilterId,
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All shifts'),
                    ),
                    ..._shifts.map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.data()['name'] ?? ''),
                        )),
                  ],
                  onChanged: (v) => setState(() => _shiftFilterId = v ?? 'all'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () async {
                    final snap = await _baseUsersQuery().get();
                    final filtered =
                        snap.docs.where((d) => _matchesFilters(d.data())).toList();
                    await _exportCsv(filtered);
                  },
                  icon: const Icon(Icons.file_download),
                  label: const Text('Export CSV (Excel)'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _baseUsersQuery().snapshots(),
              builder: (context, s) {
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs =
                    s.data!.docs.where((d) => _matchesFilters(d.data())).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('No users found.'));
                }

                // نجمع حسب الفرع للعرض
                final byBranch = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
                for (final d in docs) {
                  final m = d.data();
                  final branchId = (m['primaryBranchId'] ?? '').toString();
                  byBranch.putIfAbsent(branchId, () => []).add(d);
                }

                return ListView(
                  children: byBranch.entries.map((e) {
                    final title = e.key.isEmpty
                        ? 'No branch'
                        : _branchNameById(e.key);
                    final count = e.value.length;
                    return _BranchGroup(
                      title: '$title  —  $count user(s)',
                      children: e.value
                          .map((d) => _UserCard(
                                uid: d.id,
                                data: d.data(),
                                onChangeStatus: _changeStatus,
                                onChangeRole: _changeRole,
                                onAssignBranch: _assignBranch,
                                onAssignShift: _assignShift,
                                onToggleAllowAnyBranch: _toggleAllowAnyBranch,
                                onEditPayroll: _editPayroll,
                              ))
                          .toList(),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ======= UI widgets =======

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _BranchGroup extends StatelessWidget {
  const _BranchGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title),
      children: children,
    );
  }
}

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
    final name = (data['fullName'] ?? data['username'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final role = (data['role'] ?? 'employee').toString();
    final status = (data['status'] ?? 'pending').toString();
    final branch = (data['branchName'] ??
            (data['primaryBranchId'] ?? '').toString().isEmpty
                ? 'No branch'
                : 'Branch')
        .toString();
    final shift = (data['shiftName'] ??
            (data['assignedShiftId'] ?? '').toString().isEmpty
                ? 'No shift'
                : 'Shift')
        .toString();
    final allowAny =
        (data['allowAnyBranch'] ?? false) == true;

    final salaryBase = (data['salaryBase'] ?? 0).toString();
    final allowances = (data['allowances'] ?? 0).toString();
    final deductions = (data['deductions'] ?? 0).toString();
    final leave = (data['leaveBalance'] ?? {}) as Map<String, dynamic>;
    final overtimeRate = (leave['overtimeRate'] ?? 0).toString();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?')),
        title: Text(name),
        // ✅ Subtitle واحد فقط (عشان ما يحصلش duplication)
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  avatar: const Icon(Icons.verified, size: 16),
                  label: Text(status),
                ),
                Chip(
                  avatar: const Icon(Icons.person, size: 16),
                  label: Text(role),
                ),
                Chip(
                  avatar: const Icon(Icons.store, size: 16),
                  label: Text(branch),
                ),
                Chip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  label: Text(shift),
                ),
                if (allowAny)
                  const Chip(
                    avatar: Icon(Icons.public, size: 16),
                    label: Text('Any branch'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              children: [
                Text('Base: $salaryBase'),
                Text('Allowances: $allowances'),
                Text('Deductions: $deductions'),
                Text('OT rate: $overtimeRate'),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'approve') {
              await onChangeStatus(uid, 'approved');
            } else if (v == 'pending') {
              await onChangeStatus(uid, 'pending');
            } else if (v == 'role_employee') {
              await onChangeRole(uid, 'employee');
            } else if (v == 'role_supervisor') {
              await onChangeRole(uid, 'supervisor');
            } else if (v == 'role_manager') {
              await onChangeRole(uid, 'branch_manager');
            } else if (v == 'role_admin') {
              await onChangeRole(uid, 'admin');
            } else if (v == 'assign_branch') {
              await onAssignBranch(uid);
            } else if (v == 'assign_shift') {
              await onAssignShift(uid);
            } else if (v == 'toggle_any') {
              await onToggleAllowAnyBranch(uid, !allowAny);
            } else if (v == 'edit_payroll') {
              await onEditPayroll(uid, data);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'approve', child: Text('Mark Approved')),
            const PopupMenuItem(value: 'pending', child: Text('Mark Pending')),
            const PopupMenuDivider(),
            const PopupMenuItem(
                value: 'role_employee', child: Text('Role: Employee')),
            const PopupMenuItem(
                value: 'role_supervisor', child: Text('Role: Supervisor')),
            const PopupMenuItem(
                value: 'role_manager', child: Text('Role: Branch Manager')),
            const PopupMenuItem(value: 'role_admin', child: Text('Role: Admin')),
            const PopupMenuDivider(),
            const PopupMenuItem(
                value: 'assign_branch', child: Text('Assign Branch')),
            const PopupMenuItem(
                value: 'assign_shift', child: Text('Assign Shift')),
            const PopupMenuItem(
                value: 'toggle_any', child: Text('Toggle Allow Any Branch')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'edit_payroll', child: Text('Edit Payroll')),
          ],
        ),
      ),
    );
  }
}

// ======= Select Dialog =======

class _SelectItem {
  final String id;
  final String label;
  _SelectItem({required this.id, required this.label});
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
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ======= Payroll Dialog =======

class _PayrollDialog extends StatefulWidget {
  const _PayrollDialog({required this.uid, required this.initial});
  final String uid;
  final Map<String, dynamic> initial;

  @override
  State<_PayrollDialog> createState() => _PayrollDialogState();
}

class _PayrollDialogState extends State<_PayrollDialog> {
  late final TextEditingController _base;
  late final TextEditingController _allow;
  late final TextEditingController _deduct;
  late final TextEditingController _ot;

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    final leave = (m['leaveBalance'] ?? {}) as Map<String, dynamic>;
    _base = TextEditingController(text: (m['salaryBase'] ?? 0).toString());
    _allow = TextEditingController(text: (m['allowances'] ?? 0).toString());
    _deduct = TextEditingController(text: (m['deductions'] ?? 0).toString());
    _ot = TextEditingController(text: (leave['overtimeRate'] ?? 0).toString());
  }

  @override
  void dispose() {
    _base.dispose();
    _allow.dispose();
    _deduct.dispose();
    _ot.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final base = double.tryParse(_base.text.trim()) ?? 0;
    final allow = double.tryParse(_allow.text.trim()) ?? 0;
    final deduct = double.tryParse(_deduct.text.trim()) ?? 0;
    final ot = double.tryParse(_ot.text.trim()) ?? 0;

    await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
      'salaryBase': base,
      'allowances': allow,
      'deductions': deduct,
      'updatedAt': FieldValue.serverTimestamp(),
      'leaveBalance': {
        ...(widget.initial['leaveBalance'] ?? <String, dynamic>{}),
        'overtimeRate': ot,
      },
    }, SetOptions(merge: true));

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Payroll'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _numField('Base Salary', _base),
            const SizedBox(height: 8),
            _numField('Allowances', _allow),
            const SizedBox(height: 8),
            _numField('Deductions', _deduct),
            const SizedBox(height: 8),
            _numField('Overtime Rate', _ot),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _numField(String label, TextEditingController c) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
