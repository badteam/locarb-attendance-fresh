// lib/screens/admin_users_screen.dart
import 'dart:convert';
import 'dart:html' as html show Blob, Url, AnchorElement, document;
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
  late TabController _tab; // 0=pending, 1=approved
  String get _statusTab => _tab.index == 0 ? 'pending' : 'approved';

  // فلاتر وبحث
  final _searchCtrl = TextEditingController();
  String _roleFilter = 'all';
  String _branchFilterId = 'all';
  String _shiftFilterId = 'all';

  // مرجع أسماء الفروع والشفتات
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _branches = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _shifts = [];

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
    _loadRefs();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefs() async {
    try {
      final br = await FirebaseFirestore.instance
          .collection('branches')
          .orderBy('name')
          .get();
      final sh = await FirebaseFirestore.instance
          .collection('shifts')
          .orderBy('name')
          .get();
      setState(() {
        _branches = br.docs;
        _shifts = sh.docs;
      });
    } catch (_) {}
  }

  // ========== HELPERS ==========
  String _branchNameById(String? id) {
    if (id == null || id.isEmpty) return 'No branch';
    for (final d in _branches) {
      if (d.id == id) return (d.data()['name'] ?? 'No branch').toString();
    }
    return 'No branch';
  }

  String _shiftNameById(String? id) {
    if (id == null || id.isEmpty) return 'No shift';
    for (final d in _shifts) {
      if (d.id == id) return (d.data()['name'] ?? 'No shift').toString();
    }
    return 'No shift';
  }

  Query<Map<String, dynamic>> _usersQuery() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('status', isEqualTo: _statusTab)
        .orderBy('fullName', descending: false);
  }

  bool _matchesFilters(Map<String, dynamic> m) {
    final role = (m['role'] ?? 'employee').toString();
    final branchId = (m['primaryBranchId'] ?? '').toString();
    final shiftId = (m['assignedShiftId'] ?? '').toString();

    final okRole = _roleFilter == 'all' || _roleFilter == role;
    final okBr = _branchFilterId == 'all' || _branchFilterId == branchId;
    final okSh = _shiftFilterId == 'all' || _shiftFilterId == shiftId;

    final q = _searchCtrl.text.trim().toLowerCase();
    final name = (m['fullName'] ?? m['username'] ?? '').toString().toLowerCase();
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

  Future<void> _changeStatus(String uid, String to) => _updateUser(uid, {'status': to});
  Future<void> _changeRole(String uid, String to) => _updateUser(uid, {'role': to});

  Future<void> _assignBranch(String uid) async {
    final chosen = await showDialog<String?>(
      context: context,
      builder: (_) => _SelectDialog(
        title: 'Assign Branch',
        items: _branches
            .map((b) => _SelectItem(id: b.id, label: (b.data()['name'] ?? '').toString()))
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _updateUser(uid, {
      'primaryBranchId': chosen,
      'branchName': _branchNameById(chosen),
    });
  }

  Future<void> _assignShift(String uid) async {
    final chosen = await showDialog<String?>(
      context: context,
      builder: (_) => _SelectDialog(
        title: 'Assign Shift',
        items: _shifts
            .map((s) => _SelectItem(id: s.id, label: (s.data()['name'] ?? '').toString()))
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _updateUser(uid, {
      'assignedShiftId': chosen,
      'shiftName': _shiftNameById(chosen),
    });
  }

  Future<void> _toggleAllowAnyBranch(String uid, bool v) =>
      _updateUser(uid, {'allowAnyBranch': v});

  Future<void> _editPayroll(String uid, Map<String, dynamic> user) async {
    await showDialog(
      context: context,
      builder: (_) => _PayrollDialog(uid: uid, initial: user),
    );
  }

  // ========== EXPORT CSV (مدمج) ==========
  String _csvEscape(String v) {
    // لفّ بين " واستبدل " بـ ""
    final s = v.replaceAll('"', '""');
    return '"$s"';
    // كده مش محتاجين dependency خارجية
  }

  Future<void> _exportCsvPressed() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('CSV export works on Web builds only.'),
      ));
      return;
    }

    final qs = await _usersQuery().get();
    final users = qs.docs.where((d) => _matchesFilters(d.data())).toList();

    // Header
    final rows = <List<String>>[
      [
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
        'Allowances (sum)',
        'Deductions (sum)',
        'OT Rate',
        'Allow Any Branch',
        'Created At',
        'Updated At',
      ],
    ];

    for (final d in users) {
      final m = d.data();

      final uid = d.id;
      final name = (m['fullName'] ?? m['username'] ?? '').toString();
      final email = (m['email'] ?? '').toString();
      final role = (m['role'] ?? 'employee').toString();
      final status = (m['status'] ?? 'pending').toString();

      final brId = (m['primaryBranchId'] ?? '').toString();
      final shId = (m['assignedShiftId'] ?? '').toString();
      final brName = (m['branchName'] ?? _branchNameById(brId)).toString();
      final shName = (m['shiftName'] ?? _shiftNameById(shId)).toString();

      final base = _toNum(m['salaryBase']);

      // allowances/deductions قد تكون رقم أو Array[{amount: num}]
      final sumAllow = _sumFlexible(m['allowances']);
      final sumDed = _sumFlexible(m['deductions']);

      // overtimeRate ممكن يبقى داخل leaveBalance أو مباشرة
      double ot = 0.0;
      if (m['overtimeRate'] is num) {
        ot = (m['overtimeRate'] as num).toDouble();
      } else if (m['leaveBalance'] is Map) {
        final lb = m['leaveBalance'] as Map;
        final v = lb['overtimeRate'];
        if (v is num) ot = v.toDouble();
      }

      final allowAny = (m['allowAnyBranch'] ?? false) == true ? 'true' : 'false';

      String createdAt = '';
      String updatedAt = '';
      if (m['createdAt'] is Timestamp) {
        createdAt = (m['createdAt'] as Timestamp).toDate().toIso8601String();
      }
      if (m['updatedAt'] is Timestamp) {
        updatedAt = (m['updatedAt'] as Timestamp).toDate().toIso8601String();
      }

      rows.add([
        uid,
        name,
        email,
        role,
        status,
        brName,
        brId,
        shName,
        shId,
        base.toStringAsFixed(2),
        sumAllow.toStringAsFixed(2),
        sumDed.toStringAsFixed(2),
        ot.toStringAsFixed(2),
        allowAny,
        createdAt,
        updatedAt,
      ]);
    }

    // حولّها CSV يدوي (escape لكل خلية)
    final csv = rows.map((r) => r.map(_csvEscape).join(',')).join('\n');
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final now = DateTime.now();
    final fileName =
        'users_${_statusTab}_role-${_roleFilter}_branch-${_branchFilterId}_shift-${_shiftFilterId}_${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}.csv';

    // Safari/m- web: لازم نضيف العنصر للـDOM ثم نضغط ثم نحذفه
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

  double _sumFlexible(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is List) {
      double s = 0;
      for (final x in v) {
        if (x is num) s += x.toDouble();
        if (x is Map && x['amount'] is num) s += (x['amount'] as num).toDouble();
      }
      return s;
    }
    return 0.0;
  }

  // ========== UI ==========
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [Tab(text: 'Pending'), Tab(text: 'Approved')],
          onTap: (_) => setState(() {}),
        ),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _exportCsvPressed,
            icon: const Icon(Icons.download),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _filtersBar(),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

                // نجمع حسب الفرع للوضوح
                final byBranch = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
                for (final d in docs) {
                  final m = d.data();
                  final brId = (m['primaryBranchId'] ?? '').toString();
                  byBranch.putIfAbsent(brId, () => []).add(d);
                }

                return ListView(
                  children: byBranch.entries.map((entry) {
                    final title = entry.key.isEmpty
                        ? 'No branch'
                        : _branchNameById(entry.key);
                    return ExpansionTile(
                      title: Text('$title — ${entry.value.length} user(s)'),
                      children: entry.value
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

  Widget _filtersBar() {
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
              onPressed: _exportCsvPressed,
              icon: const Icon(Icons.file_download),
              label: const Text('Export CSV'),
            ),
          ],
        ),
      ),
    );
  }
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
    final name = (data['fullName'] ?? data['username'] ?? '').toString();
    final email = (data['email'] ?? '').toString();
    final role = (data['role'] ?? 'employee').toString();
    final status = (data['status'] ?? 'pending').toString();

    final brName = (data['branchName'] ?? '').toString();
    final shName = (data['shiftName'] ?? '').toString();
    final allowAny = (data['allowAnyBranch'] ?? false) == true;

    final salaryBase = (data['salaryBase'] ?? 0).toString();
    final allowances = data['allowances'];
    final deductions = data['deductions'];
    final leave = (data['leaveBalance'] ?? {}) as Map<String, dynamic>;
    final overtimeRate = (leave['overtimeRate'] ?? data['overtimeRate'] ?? 0).toString();

    String allowancesTxt = '0';
    if (allowances is num) allowancesTxt = allowances.toString();
    if (allowances is List) {
      double s = 0;
      for (final x in allowances) {
        if (x is num) s += x.toDouble();
        if (x is Map && x['amount'] is num) s += (x['amount'] as num).toDouble();
      }
      allowancesTxt = s.toStringAsFixed(2);
    }

    String deductionsTxt = '0';
    if (deductions is num) deductionsTxt = deductions.toString();
    if (deductions is List) {
      double s = 0;
      for (final x in deductions) {
        if (x is num) s += x.toDouble();
        if (x is Map && x['amount'] is num) s += (x['amount'] as num).toDouble();
      }
      deductionsTxt = s.toStringAsFixed(2);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
        ),
        title: Text(name),
        // ✅ Subtitle واحد فقط
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
                Text('Base: $salaryBase'),
                Text('Allowances: $allowancesTxt'),
                Text('Deductions: $deductionsTxt'),
                Text('OT: $overtimeRate'),
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
                await onToggleAllowAnyBranch(uid, !allowAny);
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

// ========== PAYROLL DIALOG ==========
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
  late final TextEditingController _ded;
  late final TextEditingController _ot;

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    final leave = (m['leaveBalance'] ?? {}) as Map<String, dynamic>;
    _base = TextEditingController(text: (m['salaryBase'] ?? 0).toString());
    _allow = TextEditingController(text: (m['allowances'] ?? 0).toString());
    _ded = TextEditingController(text: (m['deductions'] ?? 0).toString());
    _ot = TextEditingController(text: (leave['overtimeRate'] ?? m['overtimeRate'] ?? 0).toString());
  }

  @override
  void dispose() {
    _base.dispose();
    _allow.dispose();
    _ded.dispose();
    _ot.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final base = double.tryParse(_base.text.trim()) ?? 0;
    final allow = double.tryParse(_allow.text.trim()) ?? 0;
    final ded = double.tryParse(_ded.text.trim()) ?? 0;
    final ot = double.tryParse(_ot.text.trim()) ?? 0;

    await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
      'salaryBase': base,
      'allowances': allow,
      'deductions': ded,
      'leaveBalance': {
        ...(widget.initial['leaveBalance'] ?? <String, dynamic>{}),
        'overtimeRate': ot,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Payroll'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field('Base salary', _base),
            const SizedBox(height: 8),
            _field('Allowances (sum)', _allow),
            const SizedBox(height: 8),
            _field('Deductions (sum)', _ded),
            const SizedBox(height: 8),
            _field('Overtime rate', _ot),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _field(String label, TextEditingController c) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }
}
