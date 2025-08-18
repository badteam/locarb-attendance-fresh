import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// عنصر بسيط لعرض الخيارات (الفروع/الشفتات)
class Option {
  final String id;
  final String name;
  const Option(this.id, this.name);
}

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final branchesQ = FirebaseFirestore.instance.collection('branches').orderBy('name');
    final shiftsQ   = FirebaseFirestore.instance.collection('shifts').orderBy('name');
    final usersQ    = FirebaseFirestore.instance.collection('users').orderBy('fullName');

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                  final users = uSnap.data?.docs ?? [];
                  if (users.isEmpty) {
                    return const Center(child: Text('No users found'));
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final uDoc = users[i];
                      final u = uDoc.data();
                      final uid = uDoc.id;

                      final fullName = (u['fullName'] ?? u['username'] ?? uid).toString();
                      final email    = (u['email'] ?? '').toString();
                      final photoUrl = (u['photoUrl'] ?? '').toString();
                      final role     = (u['role'] ?? 'employee').toString();
                      final status   = (u['status'] ?? 'pending').toString();

                      final currentBranchId = (u['primaryBranchId'] ?? '').toString();
                      final currentShiftId  = (u['assignedShiftId'] ?? '').toString();

                      final currentBranch = branches.where((o) => o.id == currentBranchId).toList();
                      final currentShift  = shifts.where((o) => o.id == currentShiftId).toList();

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                          child: photoUrl.isEmpty
                              ? Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U')
                              : null,
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(fullName, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            _Chip(text: role, icon: Icons.badge_outlined),
                            const SizedBox(width: 6),
                            _Chip(
                              text: status,
                              icon: status == 'approved' ? Icons.verified_user_outlined : Icons.hourglass_top_outlined,
                              color: status == 'approved'
                                  ? Theme.of(context).colorScheme.secondaryContainer
                                  : Theme.of(context).colorScheme.surfaceVariant,
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),

                            // عرض الفرع والشفت الحاليين
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _InfoPill(
                                  icon: Icons.storefront_outlined,
                                  label: currentBranch.isNotEmpty ? currentBranch.first.name : 'No branch',
                                ),
                                _InfoPill(
                                  icon: Icons.access_time,
                                  label: currentShift.isNotEmpty ? currentShift.first.name : 'No shift',
                                ),
                              ],
                            ),
                          ],
                        ),

                        // أدوات التحكم
                        trailing: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // موافقة المستخدم
                              if (status != 'approved')
                                IconButton.filledTonal(
                                  tooltip: 'Approve user',
                                  icon: const Icon(Icons.check),
                                  onPressed: () async {
                                    await FirebaseFirestore.instance.collection('users').doc(uid).set({
                                      'status': 'approved',
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));
                                    _toast(context, 'User approved');
                                  },
                                ),

                              const SizedBox(width: 8),

                              // اختيار الفرع
                              DropdownButton<String>(
                                value: currentBranchId.isEmpty ? null : currentBranchId,
                                hint: const Text('Branch'),
                                items: [
                                  const DropdownMenuItem(value: '', child: Text('No branch')),
                                  ...branches.map((o) => DropdownMenuItem(value: o.id, child: Text(o.name))),
                                ],
                                onChanged: (val) async {
                                  await FirebaseFirestore.instance.collection('users').doc(uid).set({
                                    if (val == null || val.isEmpty)
                                      'primaryBranchId': FieldValue.delete()
                                    else
                                      'primaryBranchId': val,
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  }, SetOptions(merge: true));
                                  _toast(context, val == null || val.isEmpty ? 'Branch cleared' : 'Branch updated');
                                },
                              ),

                              const SizedBox(width: 8),

                              // اختيار الشفت
                              DropdownButton<String>(
                                value: currentShiftId.isEmpty ? null : currentShiftId,
                                hint: const Text('Shift'),
                                items: [
                                  const DropdownMenuItem(value: '', child: Text('No shift')),
                                  ...shifts.map((o) => DropdownMenuItem(value: o.id, child: Text(o.name))),
                                ],
                                onChanged: (val) async {
                                  await FirebaseFirestore.instance.collection('users').doc(uid).set({
                                    if (val == null || val.isEmpty)
                                      'assignedShiftId': FieldValue.delete()
                                    else
                                      'assignedShiftId': val,
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  }, SetOptions(merge: true));
                                  _toast(context, val == null || val.isEmpty ? 'Shift cleared' : 'Shift updated');
                                },
                              ),

                              const SizedBox(width: 8),

                              // Payroll
                              FilledButton.tonal(
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => _EditPayrollDialog(uid: uid, userName: fullName),
                                ),
                                child: const Text('Edit Payroll'),
                              ),

                              const SizedBox(width: 8),

                              // Leave
                              OutlinedButton(
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => _EditLeaveDialog(uid: uid, userName: fullName),
                                ),
                                child: const Text('Leave'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/* ============================= UI Helpers ============================== */

class _Chip extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color? color;
  const _Chip({required this.text, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/* ======================== Payroll Edit Dialog ========================= */

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

  Widget _moneyField(String hint, void Function(String) onChanged, String initial) {
    final c = TextEditingController(text: initial);
    return SizedBox(
      width: 130,
      child: TextField(
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: hint),
        onChanged: onChanged,
        controller: c,
      ),
    );
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

              // Allowances
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

              // Deductions
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

/* ======================== Leave Balance Dialog ======================== */

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
