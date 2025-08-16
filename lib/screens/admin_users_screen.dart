import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _search = TextEditingController();
  String _roleFilter = 'all';     // all | admin | employee
  String _statusFilter = 'all';   // all | approved | pending | suspended

  Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream() {
    // بنبدأ بأبسط مسار ثم نفلتر كلينت سايد لو الدمج هيحتاج اندكس
    final ref = FirebaseFirestore.instance.collection('users').orderBy('fullName');
    return ref.snapshots();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roleItems = const [
      DropdownMenuItem(value: 'all', child: Text('All roles')),
      DropdownMenuItem(value: 'admin', child: Text('Admins')),
      DropdownMenuItem(value: 'employee', child: Text('Employees')),
    ];
    final statusItems = const [
      DropdownMenuItem(value: 'all', child: Text('All statuses')),
      DropdownMenuItem(value: 'approved', child: Text('Approved')),
      DropdownMenuItem(value: 'pending', child: Text('Pending')),
      DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Admin • Users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Search by name or username',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _roleFilter,
                    items: roleItems,
                    onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _statusFilter,
                    items: statusItems,
                    onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _usersStream(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _ErrorBox(error: snap.error.toString());
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data?.docs ?? [];

                // فلاتر بسيطة كلينت سايد
                String q = _search.text.trim().toLowerCase();
                bool matches(Map<String, dynamic> m) {
                  if (_roleFilter != 'all' && (m['role'] ?? 'employee') != _roleFilter) return false;
                  if (_statusFilter != 'all' && (m['status'] ?? 'pending') != _statusFilter) return false;
                  if (q.isEmpty) return true;
                  final name = (m['fullName'] ?? '').toString().toLowerCase();
                  final username = (m['username'] ?? '').toString().toLowerCase();
                  return name.contains(q) || username.contains(q);
                }

                final users = all.where((d) => matches(d.data())).toList();
                if (users.isEmpty) return const Center(child: Text('No users found'));

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = users[i];
                    final m = d.data();
                    final uid = d.id;
                    final fullName = (m['fullName'] ?? '').toString();
                    final username = (m['username'] ?? '').toString();
                    final email = (m['email'] ?? '').toString();
                    final role = (m['role'] ?? 'employee').toString(); // admin | employee
                    final status = (m['status'] ?? 'pending').toString(); // approved | pending | suspended
                    final branchId = (m['primaryBranchId'] ?? '').toString();
                    final photoUrl = (m['photoUrl'] ?? '').toString();

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                          child: photoUrl.isEmpty ? Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U') : null,
                        ),
                        title: Text(fullName.isNotEmpty ? fullName : username.isNotEmpty ? username : uid),
                        subtitle: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          future: branchId.isEmpty
                              ? null
                              : FirebaseFirestore.instance.doc('branches/$branchId').get(),
                          builder: (context, b) {
                            final bname = (b.data()?.data()?['name'] ?? branchId).toString();
                            return Text('Role: $role • Status: $status • Branch: ${branchId.isEmpty ? '—' : bname}\n$email');
                          },
                        ),
                        isThreeLine: true,
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            IconButton(
                              tooltip: 'Edit',
                              onPressed: () => _openEditUser(context, uid: uid, data: m),
                              icon: const Icon(Icons.edit),
                            ),
                            if (status != 'approved')
                              FilledButton.tonal(
                                onPressed: () => _updateUser(uid, {'status': 'approved'}),
                                child: const Text('Approve'),
                              ),
                            if (status != 'suspended')
                              TextButton(
                                onPressed: () => _updateUser(uid, {'status': 'suspended'}),
                                child: const Text('Suspend'),
                              ),
                            TextButton(
                              onPressed: () => _updateUser(uid, {
                                'role': role == 'admin' ? 'employee' : 'admin',
                              }),
                              child: Text(role == 'admin' ? 'Demote' : 'Promote'),
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

  Future<void> _updateUser(String uid, Map<String, dynamic> data) async {
    await FirebaseFirestore.instance.doc('users/$uid').set(data, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User updated')));
    }
  }

  Future<void> _openEditUser(
    BuildContext context, {
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    final fullName = TextEditingController(text: (data['fullName'] ?? '').toString());
    String branchId = (data['primaryBranchId'] ?? '').toString();
    bool allowAny = (data['allowAnyBranch'] ?? false) == true;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit user'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: fullName,
                    decoration: const InputDecoration(labelText: 'Full name'),
                  ),
                  const SizedBox(height: 12),
                  // اختيار الفرع من قائمة الفروع
                  FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    future: FirebaseFirestore.instance.collection('branches').orderBy('name').get(),
                    builder: (context, snap) {
                      final items = <DropdownMenuItem<String>>[
                        const DropdownMenuItem(value: '', child: Text('— No primary branch —')),
                      ];
                      if (snap.hasData) {
                        for (final d in snap.data!.docs) {
                          final name = (d.data()['name'] ?? d.id).toString();
                          items.add(DropdownMenuItem(value: d.id, child: Text(name)));
                        }
                      }
                      return InputDecorator(
                        decoration: const InputDecoration(labelText: 'Primary branch'),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: branchId,
                            items: items,
                            onChanged: (v) => setState(() => branchId = v ?? ''),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: allowAny,
                    onChanged: (v) => setState(() => allowAny = v ?? false),
                    title: const Text('Allow check-in from ANY branch'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Note: If enabled, employee can check-in/out from any branch (geofence still applies to the chosen branch at check time).',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              FilledButton(
                onPressed: () async {
                  await FirebaseFirestore.instance.doc('users/$uid').set({
                    'fullName': fullName.text.trim(),
                    'primaryBranchId': branchId,
                    'allowAnyBranch': allowAny,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(this.context)
                        .showSnackBar(const SnackBar(content: Text('Saved')));
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }
}

/* ------------------------------- Utilities ------------------------------- */

class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(error),
        ),
      ),
    );
  }
}
