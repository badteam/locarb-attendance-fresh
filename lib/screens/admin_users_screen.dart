// lib/screens/admin_user_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String? _myRole;
  bool _loadingRole = true;

  // أدوار النظام
  static const List<String> kRoles = [
    'admin',
    'branch_manager',
    'supervisor',
    'employee',
  ];

  // تسميات لطيفة للأدوار
  static const Map<String, String> kRoleLabels = {
    'admin': 'Admin',
    'branch_manager': 'Branch Manager',
    'supervisor': 'Supervisor',
    'employee': 'Employee',
  };

  // ألوان للبادج حسب الدور
  static Color roleColor(String role, BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    switch (role) {
      case 'admin':
        return cs.primary;
      case 'branch_manager':
        return Colors.teal;
      case 'supervisor':
        return Colors.indigo;
      default:
        return cs.secondary;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMyRole();
  }

  Future<void> _loadMyRole() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _myRole = 'employee';
          _loadingRole = false;
        });
        return;
      }
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _myRole = (snap.data() ?? const {})['role']?.toString() ?? 'employee';
    } catch (_) {
      _myRole = 'employee';
    } finally {
      if (mounted) {
        setState(() {
          _loadingRole = false;
        });
      }
    }
  }

  bool get _isAdmin => _myRole == 'admin';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
      ),
      body: _loadingRole
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('fullName', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Error: ${snap.error}'),
                  );
                }
                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty) {
                  return const Center(child: Text('No users yet.'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final data = docs[i].data();
                    final uid = docs[i].id;

                    final name =
                        (data['fullName'] ?? data['username'] ?? '—').toString();
                    final email = (data['email'] ?? '').toString();
                    final role = (data['role'] ?? 'employee').toString();
                    final status = (data['status'] ?? 'pending').toString();

                    final branchName =
                        (data['branchName'] ?? 'No branch').toString();
                    final shiftName = (data['shiftName'] ?? '—').toString();

                    return Card(
                      elevation: 0.6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: cs.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // الاسم والإيميل
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  child: Text(
                                    (name.isNotEmpty ? name[0] : '?')
                                        .toUpperCase(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        email,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Badge الدور
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: roleColor(role, context)
                                        .withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: roleColor(role, context)
                                          .withOpacity(0.35),
                                    ),
                                  ),
                                  child: Text(
                                    kRoleLabels[role] ?? role,
                                    style: TextStyle(
                                      color: roleColor(role, context),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Chips: الفرع – الشفت – الحالة
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  avatar:
                                      const Icon(Icons.store, size: 18),
                                  label: Text(branchName),
                                  backgroundColor:
                                      cs.secondaryContainer.withOpacity(.3),
                                ),
                                Chip(
                                  avatar:
                                      const Icon(Icons.schedule, size: 18),
                                  label: Text(shiftName),
                                  backgroundColor:
                                      cs.tertiaryContainer.withOpacity(.25),
                                ),
                                Chip(
                                  avatar: Icon(
                                    status == 'approved'
                                        ? Icons.verified
                                        : Icons.hourglass_bottom,
                                    size: 18,
                                    color: status == 'approved'
                                        ? Colors.green
                                        : cs.onSurfaceVariant,
                                  ),
                                  label: Text(status),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // لو أنا Admin أظهر Dropdown لتغيير الدور
                            if (_isAdmin) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: kRoles.contains(role)
                                          ? role
                                          : 'employee',
                                      decoration: const InputDecoration(
                                        labelText: 'Role',
                                        border: OutlineInputBorder(),
                                      ),
                                      items: kRoles
                                          .map(
                                            (r) => DropdownMenuItem(
                                              value: r,
                                              child: Text(
                                                  kRoleLabels[r] ?? r),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (val) async {
                                        if (val == null) return;
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(uid)
                                            .update({'role': val});
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Role updated to ${kRoleLabels[val] ?? val}'),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],

                            // الأزرار السفلية
                            Row(
                              children: [
                                // Approve / Pending toggle
                                FilledButton.tonal(
                                  onPressed: () async {
                                    final newStatus = status == 'approved'
                                        ? 'pending'
                                        : 'approved';
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .update({'status': newStatus});
                                  },
                                  child: Text(
                                    status == 'approved'
                                        ? 'Mark Pending'
                                        : 'Approve',
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Edit Payroll
                                OutlinedButton(
                                  onPressed: () {
                                    // لو عندك شاشة رواتب، وجّه لها هنا
                                    // Navigator.pushNamed(context, '/payroll', arguments: uid);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text('Payroll editor (coming soon)'),
                                      ),
                                    );
                                  },
                                  child: const Text('Edit Payroll'),
                                ),
                                const Spacer(),

                                // Leave
                                TextButton(
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Confirm'),
                                            content: const Text(
                                                'Mark this user as left?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('Yes'),
                                              ),
                                            ],
                                          ),
                                        ) ??
                                        false;
                                    if (!ok) return;
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .update({'status': 'left'});
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                  child: const Text('Leave'),
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
    );
  }
}
