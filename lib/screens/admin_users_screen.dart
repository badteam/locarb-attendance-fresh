// lib/screens/admin_users_screen.dart
import 'dart:convert';
import 'dart:html' as html show Blob, Url, AnchorElement, document;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  // ====== الإصدار ======
  static const String _versionLabel = 'Admin Users — v2.0 — 2025-08-27';

  // 0 = pending, 1 = approved
  late TabController _tab;
  String get _statusTab => _tab.index == 0 ? 'pending' : 'approved';

  // فلاتر وبحث
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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this); // شِلنا تبويب الغياب
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

  // ========== USERS QUERY/FILTERS ==========
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
    final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? '')
        .toString()
        .toLowerCase();
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
            .map((b) => _SelectItem(
                id: b.id, label: (b.data()['name'] ?? '').toString()))
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
            .map((s) => _SelectItem(
                id: s.id, label: (s.data()['name'] ?? '').toString()))
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
    final allow =
        TextEditingController(text: (m['allowances'] ?? 0).toString());
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
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder()),
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
        content: Text('CSV export works on Web builds only.'),
      ));
      return;
    }

    final qs = await _usersQuery().get();
    final users =
        qs.docs.where((d) => _matchesFilters(d.data())).toList();

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
      final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? m['email'] ?? '')
          .toString();
      final role = (m['role'] ?? 'employee').toString();

      final brName = (m['branchName'] ??
              _branchLabelFor((m['primaryBranchId'] ?? m['branchId'] ?? '').toString()))
          .toString();
      final shName = (m['shiftName'] ??
              _shiftLabelFor((m['assignedShiftId'] ?? m['shiftId'] ?? '').toString()))
          .toString();

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

  // ================== BUILD ==================
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
        actions: [
          // شارة الإصدار (لا تغيّر أي سلوك)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _versionLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          ),
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
                _usersTab(), // Pending
                _usersTab(), // Approved
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

        // نجمع حسب الفرع لعرض أنظف
        final byBranch =
            <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final d in docs) {
          final m = d.data();
          final brId = (m['primaryBranchId'] ?? m['branchId'] ?? '').toString();
          byBranch.putIfAbsent(brId, () => []).add(d);
        }

        return ListView(
          children: byBranch.entries.map((entry) {
            final title =
                entry.key.isEmpty ? 'No branch' : _branchLabelFor(entry.key);
            final list = entry.value;
            final shownCount = list.length; // بعد الفلاتر بالفعل
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
    final name =
        (data['fullName'] ?? data['name'] ?? data['username'] ?? '')
            .toString();
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
