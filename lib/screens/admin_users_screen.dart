// lib/screens/users_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// ---- صلاحيات الأدوار (للاستخدام لاحقاً أيضاً) ----
class RolePermissions {
  static bool isAdmin(String? role) => role == 'admin';

  static const roleLabels = <String, String>{
    'admin': 'Admin',
    'branch_manager': 'Branch manager',
    'supervisor': 'Supervisor',
    'employee': 'Employee',
  };

  static const roleColors = <String, Color>{
    'admin': Color(0xFF1565C0),
    'branch_manager': Color(0xFF2E7D32),
    'supervisor': Color(0xFF6A1B9A),
    'employee': Color(0xFF616161),
  };
}

/// ---- شارة توضح الدور الحالي ----
class RoleBadge extends StatelessWidget {
  final String role;
  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final label = RolePermissions.roleLabels[role] ?? role;
    final color = RolePermissions.roleColors[role] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// ---- شاشة المستخدمين مع إدارة الأدوار ----
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String? _currentUserRole;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadMyRole();
  }

  Future<void> _loadMyRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance.doc('users/$uid').get();
    setState(() => _currentUserRole = (snap.data() ?? {})['role']?.toString() ?? 'employee');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .orderBy('fullName', descending: false)
        .snapshots();
  }

  Future<void> _updateRole(String userId, String newRole) async {
    await FirebaseFirestore.instance.doc('users/$userId').set(
      {'role': newRole},
      SetOptions(merge: true),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Role updated to ${RolePermissions.roleLabels[newRole]}')),
      );
    }
  }

  Future<void> _approveUser(String userId) async {
    await FirebaseFirestore.instance.doc('users/$userId').set(
      {'status': 'approved'},
      SetOptions(merge: true),
    );
  }

  Future<void> _markLeave(String userId) async {
    await FirebaseFirestore.instance.doc('users/$userId').set(
      {'status': 'left'},
      SetOptions(merge: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEditRoles = RolePermissions.isAdmin(_currentUserRole);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: _currentUserRole == null
                  ? const SizedBox(
                      height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : RoleBadge(role: _currentUserRole!),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط بحث بسيط
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              stream: _usersStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData) return const Center(child: Text('No users'));

                final docs = snap.data!.docs.where((d) {
                  final data = d.data();
                  final name = (data['fullName'] ?? data['username'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  if (_search.isEmpty) return true;
                  return name.contains(_search) || email.contains(_search);
                }).toList();

                if (docs.isEmpty) return const Center(child: Text('No results'));

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();
                    final uid = doc.id;

                    final fullName = (data['fullName'] ?? data['username'] ?? '—').toString();
                    final email = (data['email'] ?? '—').toString();
                    final role = (data['role'] ?? 'employee').toString();
                    final status = (data['status'] ?? 'pending').toString();
                    final branchName = (data['branchName'] ?? data['branchId'] ?? 'No branch').toString();
                    final shiftName = (data['shiftName'] ?? data['shiftId'] ?? '—').toString();

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // السطر العلوي: الاسم + شارة الدور + الحالة
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  child: Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : '?'),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(fullName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 2),
                                      Text(email,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                RoleBadge(role: role),
                                const SizedBox(width: 8),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: status == 'approved'
                                        ? Colors.green.withOpacity(.1)
                                        : status == 'left'
                                            ? Colors.red.withOpacity(.1)
                                            : Colors.orange.withOpacity(.1),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: status == 'approved'
                                          ? Colors.green[700]
                                          : status == 'left'
                                              ? Colors.red[700]
                                              : Colors.orange[800],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // السطر الثاني: الفرع + الشفت
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Chip(
                                  avatar: const Icon(Icons.store_mall_directory, size: 18),
                                  label: Text(branchName),
                                ),
                                Chip(
                                  avatar: const Icon(Icons.schedule, size: 18),
                                  label: Text(shiftName),
                                ),
                              ],
                            ),

                            const Divider(height: 24),

                            // السطر الثالث: أدوات الإدارة
                            Row(
                              children: [
                                // تغيير الدور (Admin فقط)
                                if (canEditRoles)
                                  Flexible(
                                    child: DropdownButtonFormField<String>(
                                      value: role,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'admin',
                                          child: Text('Admin'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'branch_manager',
                                          child: Text('Branch manager'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'supervisor',
                                          child: Text('Supervisor'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'employee',
                                          child: Text('Employee'),
                                        ),
                                      ],
                                      decoration: const InputDecoration(
                                        labelText: 'Role',
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (val) {
                                        if (val == null) return;
                                        _updateRole(uid, val);
                                      },
                                    ),
                                  ),

                                if (canEditRoles) const SizedBox(width: 12),

                                // زر الحالة: موافقة / Leave
                                Expanded(
                                  child: FilledButton.tonal(
                                    onPressed: () async {
                                      if (status == 'approved') {
                                        await _markLeave(uid);
                                      } else {
                                        await _approveUser(uid);
                                      }
                                    },
                                    child: Text(status == 'approved' ? 'Mark as leave' : 'Approve'),
                                  ),
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
          ),
        ],
      ),
    );
  }
}
