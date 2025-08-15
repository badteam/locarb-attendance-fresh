import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/admin_service.dart';

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usersRef = FirebaseFirestore.instance.collection('users');

    return Scaffold(
      appBar: AppBar(title: const Text('لوحة الأدمن: إدارة المستخدمين')),
      body: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream: usersRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('لا يوجد مستخدمون بعد'));
          }
          final docs = snap.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final uid = d['uid'] ?? docs[i].id;
              final uname = (d['username'] ?? '').toString();
              final full = (d['fullName'] ?? '').toString();
              final email = (d['email'] ?? '').toString();
              final role = (d['role'] ?? 'employee').toString();
              final status = (d['status'] ?? 'pending').toString();

              return ListTile(
                leading: CircleAvatar(child: Text(uname.isNotEmpty ? uname[0].toUpperCase() : '?')),
                title: Text(full.isNotEmpty ? full : uname),
                subtitle: Text('الدور: $role • الحالة: $status\n$email'),
                isThreeLine: true,
                trailing: _Actions(uid: uid, role: role, status: status),
              );
            },
          );
        },
      ),
    );
  }
}

class _Actions extends StatefulWidget {
  final String uid;
  final String role;
  final String status;
  const _Actions({required this.uid, required this.role, required this.status});

  @override
  State<_Actions> createState() => _ActionsState();
}

class _ActionsState extends State<_Actions> {
  bool loading = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => loading = true);
    try {
      await fn();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التحديث')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.role == 'admin';
    final isPending = widget.status == 'pending';

    if (loading) {
      return const SizedBox(width: 96, height: 40, child: Center(child: CircularProgressIndicator()));
    }

    return Wrap(
      spacing: 6,
      children: [
        if (isPending)
          FilledButton(
            onPressed: () => _run(() => AdminService.approveUser(widget.uid)),
            child: const Text('موافقة'),
          ),
        if (isPending)
          OutlinedButton(
            onPressed: () => _run(() => AdminService.rejectUser(widget.uid)),
            child: const Text('رفض'),
          ),
        if (!isAdmin)
          OutlinedButton(
            onPressed: () => _run(() => AdminService.makeAdmin(widget.uid)),
            child: const Text('ترقية لأدمن'),
          ),
        if (isAdmin)
          OutlinedButton(
            onPressed: () => _run(() => AdminService.makeEmployee(widget.uid)),
            child: const Text('إرجاع كموظف'),
          ),
      ],
    );
  }
}
