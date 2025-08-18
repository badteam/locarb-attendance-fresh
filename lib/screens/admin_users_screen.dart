import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// خيار عام لعرض العناصر في القوائم (Branches/Shifts)
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

                            // السطر الخاص بالفرع والشفت (عرض فقط هنا)
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

                        // أدوات التحكم (Approve / Branch dropdown / Shift dropdown)
                        trailing: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // زر الموافقة لو Pending
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

                              // اختيار الفرع (موجود سابقًا، بيساعدك تفضل شايفه)
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

                              // ✅ اختيار الشفت — الجديد
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
