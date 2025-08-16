import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/main_drawer.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  @override
  Widget build(BuildContext context) {
    final usersRef = FirebaseFirestore.instance.collection('users').orderBy('fullName');
    final branchesRef = FirebaseFirestore.instance.collection('branches').orderBy('name');

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      drawer: const MainDrawer(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: branchesRef.snapshots(),
        builder: (context, branchesSnap) {
          // Build a map: branchId -> name
          final branchNames = <String, String>{};
          if (branchesSnap.hasData) {
            for (final d in branchesSnap.data!.docs) {
              final m = d.data();
              branchNames[d.id] = (m['name'] ?? d.id).toString();
            }
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: usersRef.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return _ErrorBox(error: snap.error.toString());
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No users'));
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final m = d.data();

                  final fullName = (m['fullName'] ?? '').toString();
                  final username = (m['username'] ?? '').toString();
                  final email = (m['email'] ?? '').toString();
                  final role = (m['role'] ?? 'employee').toString();
                  final status = (m['status'] ?? 'pending').toString();

                  final primaryBranchId = (m['primaryBranchId'] ?? '').toString();
                  final primaryBranchName = primaryBranchId.isEmpty
                      ? '—'
                      : (branchNames[primaryBranchId] ?? primaryBranchId);

                  final allowAny = (m['allowAnyBranch'] ?? false) == true;

                  return Card(
                    elevation: 1.2,
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          fullName.isNotEmpty
                              ? fullName.characters.first.toUpperCase()
                              : (username.isNotEmpty ? username.characters.first.toUpperCase() : '?'),
                        ),
                      ),
                      title: Text(fullName.isNotEmpty ? fullName : (username.isNotEmpty ? username : d.id)),
                      subtitle: Text([
                        email.isNotEmpty ? email : '(no email)',
                        'Role: $role • Status: $status',
                        'Primary branch: $primaryBranchName',
                        'Allow any branch: ${allowAny ? "Yes" : "No"}',
                      ].join('\n')),
                      isThreeLine: true,
                      trailing: const Icon(Icons.edit),
                      onTap: () => _editUserDialog(context, d.id, m, branchNames),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editUserDialog(
    BuildContext context,
    String uid,
    Map<String, dynamic> data,
    Map<String, String> branchNames,
  ) async {
    final fullName = TextEditingController(text: (data['fullName'] ?? '').toString());
    final username = TextEditingController(text: (data['username'] ?? '').toString());
    final email = TextEditingController(text: (data['email'] ?? '').toString());
    final role = TextEditingController(text: (data['role'] ?? 'employee').toString());
    final status = TextEditingController(text: (data['status'] ?? 'pending').toString());
    String primaryBranchId = (data['primaryBranchId'] ?? '').toString();
    bool allowAnyBranch = (data['allowAnyBranch'] ?? false) == true;

    // Branch dropdown items
    final branchItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('— No primary branch —')),
      ...branchNames.entries.map(
        (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
      ),
    ];

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit user'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: fullName, decoration: const InputDecoration(labelText: 'Full name')),
                const SizedBox(height: 8),
                TextField(controller: username, decoration: const InputDecoration(labelText: 'Username')),
                const SizedBox(height: 8),
                TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 8),
                TextField(controller: role, decoration: const InputDecoration(labelText: 'Role (admin/manager/employee)')),
                const SizedBox(height: 8),
                TextField(controller: status, decoration: const InputDecoration(labelText: 'Status (approved/pending/disabled)')),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Primary branch',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: primaryBranchId,
                      items: branchItems,
                      onChanged: (v) => setState(() => primaryBranchId = v ?? ''),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow check-in from ANY branch'),
                  value: allowAnyBranch,
                  onChanged: (v) => setState(() => allowAnyBranch = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            FilledButton(
              onPressed: () async {
                await FirebaseFirestore.instance.collection('users').doc(uid).set({
                  'fullName': fullName.text.trim(),
                  'username': username.text.trim(),
                  'email': email.text.trim(),
                  'role': role.text.trim().isEmpty ? 'employee' : role.text.trim(),
                  'status': status.text.trim().isEmpty ? 'approved' : status.text.trim(),
                  'primaryBranchId': primaryBranchId,
                  'allowAnyBranch': allowAnyBranch,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                // ignore: use_build_context_synchronously
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

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
          child: Text('Error:\n$error'),
        ),
      ),
    );
  }
}
