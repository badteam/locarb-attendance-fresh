import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Option {
  final String id;
  final String name;
  const Option(this.id, this.name);
}

const kRoles = <String>[
  'employee',
  'supervisor',
  'branchManager',
  'admin',
];

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _tab = 'pending'; // pending | approved
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final branchesQ =
        FirebaseFirestore.instance.collection('branches').orderBy('name');
    final shiftsQ =
        FirebaseFirestore.instance.collection('shifts').orderBy('name');

    // users query + filter
    Query<Map<String, dynamic>> usersQ = FirebaseFirestore.instance
        .collection('users')
        .orderBy('fullName', descending: false);

    usersQ = usersQ.where('status', isEqualTo: _tab);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          // تبويبات بسيطة Pending/Approved
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pending', label: Text('Pending')),
                ButtonSegment(value: 'approved', label: Text('Approved')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط بحث
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name or email',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: branchesQ.snapshots(),
              builder: (context, bSnap) {
                final branches = (bSnap.data?.docs ?? [])
                    .map((d) => Option(d.id, (d.data()['name'] ?? d.id).toString()))
                    .toList();

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: shiftsQ.snapshots(),
                  builder: (context, sSnap) {
                    final shifts = (sSnap.data?.docs ?? [])
                        .map((d) => Option(d.id, (d.data()['name'] ?? d.id).toString()))
                        .toList();

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: usersQ.snapshots(),
                      builder: (context, uSnap) {
                        if (uSnap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (uSnap.hasError) {
                          return Center(child: Text('Error: ${uSnap.error}'));
                        }
                        var users = uSnap.data?.docs ?? [];

                        // فلترة البحث
                        if (_search.isNotEmpty) {
                          users = users.where((u) {
                            final m = u.data();
                            final name = (m['fullName'] ?? m['username'] ?? '').toString().toLowerCase();
                            final email = (m['email'] ?? '').toString().toLowerCase();
                            return name.contains(_search) || email.contains(_search);
                          }).toList();
                        }

                        if (users.isEmpty) {
                          return const Center(child: Text('No users'));
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                          itemCount: users.length,
                          itemBuilder: (_, i) {
                            final uDoc = users[i];
                            final u = uDoc.data();
                            return _UserCard(
                              uid: uDoc.id,
                              data: u,
                              branches: branches,
                              shifts: shifts,
                              tab: _tab,
                              onChanged: () => ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Saved'))),
                            );
                          },
                        );
                      },
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

/* -------------------------- User Card (compact) -------------------------- */

class _UserCard extends StatefulWidget {
  final String uid;
  final Map<String, dynamic> data;
  final List<Option> branches;
  final List<Option> shifts;
  final String tab; // pending | approved
  final VoidCallback onChanged;

  const _UserCard({
    required this.uid,
    required this.data,
    required this.branches,
    required this.shifts,
    required this.tab,
    required this.onChanged,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  bool _expanded = false;

  Future<void> _setUser(Map<String, dynamic> payload) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .set(payload, SetOptions(merge: true));
    widget.onChanged();
  }

  Future<void> _approveAs(String role) async {
    await _setUser({
      'status': 'approved',
      'role': role,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.data;
    final name = (m['fullName'] ?? m['username'] ?? widget.uid).toString();
    final email = (m['email'] ?? '').toString();
    final role = (m['role'] ?? 'employee').toString();
    final photoUrl = (m['photoUrl'] ?? '').toString();

    final branchId = (m['primaryBranchId'] ?? '').toString();
    final shiftId = (m['assignedShiftId'] ?? '').toString();

    final branchName = widget.branches.firstWhere(
      (o) => o.id == branchId,
      orElse: () => const Option('', 'No branch'),
    ).name;

    final shiftName = widget.shifts.firstWhere(
      (o) => o.id == shiftId,
      orElse: () => const Option('', 'No shift'),
    ).name;

    return Card(
      elevation: 0,
      child: ExpansionTile(
        initiallyExpanded: false,
        onExpansionChanged: (x) => setState(() => _expanded = x),
        leading: CircleAvatar(
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U') : null,
        ),
        title: Row(
          children: [
            Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            _rolePill(role),
            const SizedBox(width: 6),
            _statusPill((m['status'] ?? 'pending').toString()),
          ],
        ),
        subtitle: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),

        // زرار أكشنات صغير مرتب
        trailing: PopupMenuButton<String>(
          tooltip: 'Actions',
          onSelected: (key) async {
            switch (key) {
              case 'approve_employee':
                await _approveAs('employee');
                break;
              case 'approve_supervisor':
                await _approveAs('supervisor');
                break;
              case 'approve_manager':
                await _approveAs('branchManager');
                break;
              case 'approve_admin':
                await _approveAs('admin');
                break;
              case 'make_employee':
              case 'make_supervisor':
              case 'make_manager':
              case 'make_admin':
                final setRole = {
                  'make_employee': 'employee',
                  'make_supervisor': 'supervisor',
                  'make_manager': 'branchManager',
                  'make_admin': 'admin',
                }[key]!;
                await _setUser({'role': setRole, 'updatedAt': FieldValue.serverTimestamp()});
                break;
            }
          },
          itemBuilder: (ctx) => [
            if (widget.tab == 'pending') ...[
              const PopupMenuItem(value: 'approve_employee', child: Text('Approve as • Employee')),
              const PopupMenuItem(value: 'approve_supervisor', child: Text('Approve as • Supervisor')),
              const PopupMenuItem(value: 'approve_manager', child: Text('Approve as • Branch Manager')),
              const PopupMenuItem(value: 'approve_admin', child: Text('Approve as • Admin')),
              const PopupMenuDivider(),
            ],
            const PopupMenuItem(value: 'make_employee', child: Text('Set role: Employee')),
            const PopupMenuItem(value: 'make_supervisor', child: Text('Set role: Supervisor')),
            const PopupMenuItem(value: 'make_manager', child: Text('Set role: Branch Manager')),
            const PopupMenuItem(value: 'make_admin', child: Text('Set role: Admin')),
          ],
          child: const Icon(Icons.more_horiz),
        ),

        children: [
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _infoChip(Icons.storefront_outlined, branchName),
                      _infoChip(Icons.access_time, shiftName),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // سطر إعدادات سريعة: الفرع + الشفت + الدور
                  Row(
                    children: [
                      // Branch
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: branchId.isEmpty ? null : branchId,
                          decoration: const InputDecoration(
                            labelText: 'Branch',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('No branch')),
                            ...widget.branches.map(
                              (o) => DropdownMenuItem(value: o.id, child: Text(o.name)),
                            ),
                          ],
                          onChanged: (v) => _setUser({
                            if (v == null || v.isEmpty)
                              'primaryBranchId': FieldValue.delete()
                            else
                              'primaryBranchId': v,
                            'updatedAt': FieldValue.serverTimestamp(),
                          }),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Shift
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: shiftId.isEmpty ? null : shiftId,
                          decoration: const InputDecoration(
                            labelText: 'Shift',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('No shift')),
                            ...widget.shifts.map(
                              (o) => DropdownMenuItem(value: o.id, child: Text(o.name)),
                            ),
                          ],
                          onChanged: (v) => _setUser({
                            if (v == null || v.isEmpty)
                              'assignedShiftId': FieldValue.delete()
                            else
                              'assignedShiftId': v,
                            'updatedAt': FieldValue.serverTimestamp(),
                          }),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // اختيار الدور سريع
                  DropdownButtonFormField<String>(
                    value: kRoles.contains(role) ? role : 'employee',
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: kRoles
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (r) => _setUser({
                      'role': r,
                      'updatedAt': FieldValue.serverTimestamp(),
                    }),
                  ),

                  const SizedBox(height: 14),

                  // أزرار فرعية صغيرة (Payroll / Leave)
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => _EditPayrollDialog(uid: widget.uid, userName: name),
                        ),
                        child: const Text('Edit Payroll'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => showDialog(
                          context: context,
                          builder: (_) => _EditLeaveDialog(uid: widget.uid, userName: name),
                        ),
                        child: const Text('Leave'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final ok = status == 'approved';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ok
            ? Colors.green.withOpacity(.15)
            : Colors.orange.withOpacity(.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ok ? Icons.verified_user_outlined : Icons.hourglass_top_outlined, size: 14),
        const SizedBox(width: 4),
        Text(status, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  Widget _rolePill(String role) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.badge_outlined, size: 14),
        const SizedBox(width: 4),
        Text(role, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  Widget _infoChip(IconData ic, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, size: 14),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

/* ======================== Payroll Dialog (كما هو) ======================== */

class _EditPayrollDialog extends StatefulWidget {
  final String uid;
  final String userName;
  const _EditPayrollDialog({required this.uid, required this.userName});

  @override
  State<_EditPayrollDialog> createState() => _EditPayrollDialogState();
}

class _EditPayrollDialogState extends State<_EditPayrollDialog> {
  final _salary = TextEditingController();
  final _overtimeRate = TextEditingController();
  List<Map<String, dynamic>> _allowances = [];
  List<Map<String, dynamic>> _deductions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
    final m = doc.data() ?? {};
    _salary.text = ((m['salaryBase'] ?? 0) as num).toString();
    _overtimeRate.text = ((m['overtimeRate'] ?? 0) as num).toString();
    _allowances = List<Map<String, dynamic>>.from(m['allowances'] ?? []);
    _deductions = List<Map<String, dynamic>>.from(m['deductions'] ?? []);
    if (mounted) setState(() {});
  }

  void _addLine(List<Map<String, dynamic>> list) {
    list.add({'name': '', 'amount': 0});
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Payroll • ${widget.userName}'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _salary,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Base salary (monthly)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _overtimeRate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Overtime rate (per hour)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Allowances', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(onPressed: () => _addLine(_allowances), icon: const Icon(Icons.add)),
                ],
              ),
              ..._allowances.asMap().entries.map((e) {
                final i = e.key;
                final item = e.value;
                final nameC = TextEditingController(text: (item['name'] ?? '').toString());
                final amtC  = TextEditingController(text: (item['amount'] ?? 0).toString());
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameC,
                          decoration: const InputDecoration(hintText: 'Name'),
                          onChanged: (v) => item['name'] = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: amtC,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'Amount'),
                          onChanged: (v) => item['amount'] = num.tryParse(v) ?? 0,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _allowances.removeAt(i)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Deductions', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(onPressed: () => _addLine(_deductions), icon: const Icon(Icons.add)),
                ],
              ),
              ..._deductions.asMap().entries.map((e) {
                final i = e.key;
                final item = e.value;
                final nameC = TextEditingController(text: (item['name'] ?? '').toString());
                final amtC  = TextEditingController(text: (item['amount'] ?? 0).toString());
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameC,
                          decoration: const InputDecoration(hintText: 'Name'),
                          onChanged: (v) => item['name'] = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: amtC,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: 'Amount'),
                          onChanged: (v) => item['amount'] = num.tryParse(v) ?? 0,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _deductions.removeAt(i)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final payload = {
              'salaryBase': num.tryParse(_salary.text.trim()) ?? 0,
              'overtimeRate': num.tryParse(_overtimeRate.text.trim()) ?? 0,
              'allowances': _allowances
                  .where((e) => (e['name'] ?? '').toString().trim().isNotEmpty)
                  .map((e) => {'name': e['name'], 'amount': (e['amount'] ?? 0) as num})
                  .toList(),
              'deductions': _deductions
                  .where((e) => (e['name'] ?? '').toString().trim().isNotEmpty)
                  .map((e) => {'name': e['name'], 'amount': (e['amount'] ?? 0) as num})
                  .toList(),
              'updatedAt': FieldValue.serverTimestamp(),
            };
            await FirebaseFirestore.instance.collection('users').doc(widget.uid).set(
                  payload,
                  SetOptions(merge: true),
                );
            if (mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/* ======================== Leave Dialog (كما هو) ======================== */

class _EditLeaveDialog extends StatefulWidget {
  final String uid;
  final String userName;
  const _EditLeaveDialog({required this.uid, required this.userName});

  @override
  State<_EditLeaveDialog> createState() => _EditLeaveDialogState();
}

class _EditLeaveDialogState extends State<_EditLeaveDialog> {
  final _annual = TextEditingController();
  final _carried = TextEditingController();
  final _consumed = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
    final m = doc.data() ?? {};
    final leave = Map<String, dynamic>.from(m['leaveBalance'] ?? {});
    _annual.text = ((leave['annualAllocated'] ?? 0) as num).toString();
    _carried.text = ((leave['carried'] ?? 0) as num).toString();
    _consumed.text = ((leave['consumed'] ?? 0) as num).toString();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Leave balance • ${widget.userName}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _annual,   keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Annual allocated')),
            const SizedBox(height: 8),
            TextField(controller: _carried,  keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Carried over')),
            const SizedBox(height: 8),
            TextField(controller: _consumed, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Consumed (used)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final payload = {
              'leaveBalance': {
                'annualAllocated': num.tryParse(_annual.text.trim()) ?? 0,
                'carried': num.tryParse(_carried.text.trim()) ?? 0,
                'consumed': num.tryParse(_consumed.text.trim()) ?? 0,
              },
              'updatedAt': FieldValue.serverTimestamp(),
            };
            await FirebaseFirestore.instance.collection('users').doc(widget.uid).set(
                  payload,
                  SetOptions(merge: true),
                );
            if (mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
