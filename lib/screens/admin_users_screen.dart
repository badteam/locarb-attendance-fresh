import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/admin_service.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _statusFilter = 'all'; // all | pending | approved | rejected
  String _roleFilter = 'all';   // all | employee | admin
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance.collection('users');
    Query<Map<String, dynamic>> q = col.orderBy('createdAt', descending: true);

    if (_statusFilter != 'all') q = q.where('status', isEqualTo: _statusFilter);
    if (_roleFilter != 'all')   q = q.where('role',   isEqualTo: _roleFilter);

    return Scaffold(
      appBar: AppBar(title: const Text('لوحة الأدمن: المستخدمون')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'ابحث بالاسم أو اسم المستخدم',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _statusFilter,
                  onChanged: (v) => setState(() => _statusFilter = v!),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('كل الحالات')),
                    DropdownMenuItem(value: 'pending', child: Text('بانتظار الموافقة')),
                    DropdownMenuItem(value: 'approved', child: Text('موافق عليه')),
                    DropdownMenuItem(value: 'rejected', child: Text('مرفوض')),
                  ],
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _roleFilter,
                  onChanged: (v) => setState(() => _roleFilter = v!),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('كل الأدوار')),
                    DropdownMenuItem(value: 'employee', child: Text('موظف')),
                    DropdownMenuItem(value: 'admin', child: Text('أدمن')),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text('لا يوجد مستخدمون'));
                }
                var docs = snap.data!.docs;

                // بحث بسيط على الكلاينت
                if (_query.isNotEmpty) {
                  docs = docs.where((d) {
                    final m = d.data();
                    final uname = (m['username'] ?? '').toString().toLowerCase();
                    final full  = (m['fullName'] ?? '').toString().toLowerCase();
                    return uname.contains(_query.toLowerCase()) || full.contains(_query.toLowerCase());
                  }).toList();
                }

                if (docs.isEmpty) return const Center(child: Text('لا نتائج مطابقة'));

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
                    final branchName = (d['branchName'] ?? 'غير مُعيّن').toString();

                    return ListTile(
                      leading: CircleAvatar(child: Text(uname.isNotEmpty ? uname[0].toUpperCase() : '?')),
                      title: Text(full.isNotEmpty ? full : uname),
                      subtitle: Text('الدور: $role • الحالة: $status • الفرع: $branchName\n$email'),
                      isThreeLine: true,
                      trailing: _Actions(uid: uid, role: role, status: status),
                      onTap: () => _openAssignBranch(context, uid),
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

  Future<void> _openAssignBranch(BuildContext context, String uid) async {
    // قراءة الفروع لعرضها في قائمة اختيار
    final branches = await FirebaseFirestore.instance.collection('branches').get();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) {
        String? selectedId;
        return AlertDialog(
          title: const Text('تعيين فرع'),
          content: DropdownButtonFormField<String>(
            items: branches.docs.map((b) {
              final name = (b.data()['name'] ?? b.id).toString();
              return DropdownMenuItem(value: b.id, child: Text(name));
            }).toList(),
            onChanged: (v) => selectedId = v,
            decoration: const InputDecoration(labelText: 'اختر الفرع'),
          ),
          actions: [
            TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                if (selectedId == null) return;
                final doc = branches.docs.firstWhere((e) => e.id == selectedId);
                final name = (doc.data()['name'] ?? doc.id).toString();
                await AdminService.assignBranch(uid, selectedId!, name);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
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
      return const SizedBox(width: 100, height: 40, child: Center(child: CircularProgressIndicator()));
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
