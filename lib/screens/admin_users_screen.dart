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
  static const int _limit = 200;

  final Map<String, String> _shiftNameCache = {};
  Future<String> _shiftName(String? shiftId) async {
    final id = (shiftId ?? '').trim();
    if (id.isEmpty) return 'Unassigned';
    if (_shiftNameCache.containsKey(id)) return _shiftNameCache[id]!;
    try {
      final s = await FirebaseFirestore.instance.doc('shifts/$id').get();
      final m = s.data() ?? {};
      final name = (m['name'] ?? 'Unassigned').toString();
      _shiftNameCache[id] = name;
      return name;
    } catch (_) {
      _shiftNameCache[id] = 'Unassigned';
      return 'Unassigned';
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersCol = FirebaseFirestore.instance.collection('users');

    final stream = usersCol
        .orderBy('createdAt', descending: true)
        .limit(_limit)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Admin: Users')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search by name / username / email',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _statusFilter,
                  onChanged: (v) => setState(() => _statusFilter = v!),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All statuses')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'approved', child: Text('Approved')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  ],
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _roleFilter,
                  onChanged: (v) => setState(() => _roleFilter = v!),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All roles')),
                    DropdownMenuItem(value: 'employee', child: Text('Employee')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Failed to fetch users: ${snap.error}'),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snap.data?.docs ?? [];

                List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered = [];
                for (final d in docs) {
                  final m = d.data();
                  final role = (m['role'] ?? 'employee').toString().toLowerCase();
                  final status = (m['status'] ?? 'pending').toString().toLowerCase();
                  final uname = (m['username'] ?? '').toString().toLowerCase();
                  final full  = (m['fullName'] ?? '').toString().toLowerCase();
                  final email = (m['email'] ?? '').toString().toLowerCase();

                  bool ok = true;
                  if (_statusFilter != 'all' && status != _statusFilter) ok = false;
                  if (_roleFilter   != 'all' && role   != _roleFilter)   ok = false;
                  if (_query.isNotEmpty) {
                    final hit = uname.contains(_query) || full.contains(_query) || email.contains(_query);
                    if (!hit) ok = false;
                  }
                  if (ok) filtered.add(d);
                }

                if (filtered.isEmpty) {
                  return const Center(child: Text('No results match the current filters'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final m = d.data();

                    final uid   = (m['uid'] ?? d.id).toString();
                    final uname = (m['username'] ?? '').toString();
                    final full  = (m['fullName'] ?? '').toString();
                    final email = (m['email'] ?? '').toString();
                    final role  = (m['role'] ?? 'employee').toString();
                    final status= (m['status'] ?? 'pending').toString();
                    final branchName = (m['branchName'] ?? 'Unassigned').toString();
                    final shiftId = (m['shiftId'] ?? '').toString();
                    final canAny = (m['canCheckFromAnyBranch'] ?? false) == true;

                    return FutureBuilder<String>(
                      future: _shiftName(shiftId),
                      builder: (context, shiftSnap) {
                        final shiftName = shiftSnap.data ?? 'Unassigned';
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text(uname.isNotEmpty ? uname[0].toUpperCase() : '?'),
                          ),
                          title: Text(full.isNotEmpty ? full : uname),
                          subtitle: Text(
                            'Role: $role • Status: $status\n'
                            'Branch: $branchName • Shift: $shiftName\n'
                            'Any-branch: ${canAny ? 'Yes' : 'No'}\n'
                            '$email',
                          ),
                          isThreeLine: true,
                          trailing: _Actions(uid: uid, role: role, status: status, canAny: canAny),
                          onTap: () => _openAssignBranch(context, uid),
                          onLongPress: () => _openAssignShift(context, uid),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          const Text('* Showing first 200 users — add pagination later if needed.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _openAssignBranch(BuildContext context, String uid) async {
    final branches = await FirebaseFirestore.instance.collection('branches').orderBy('name').get();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) {
        String? selectedId;
        return AlertDialog(
          title: const Text('Assign Branch'),
          content: DropdownButtonFormField<String>(
            items: branches.docs.map((b) {
              final name = (b.data()['name'] ?? b.id).toString();
              return DropdownMenuItem(value: b.id, child: Text(name));
            }).toList(),
            onChanged: (v) => selectedId = v,
            decoration: const InputDecoration(labelText: 'Branch'),
          ),
          actions: [
            TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (selectedId == null) return;
                final doc = branches.docs.firstWhere((e) => e.id == selectedId);
                final name = (doc.data()['name'] ?? doc.id).toString();
                await AdminService.assignBranch(uid, selectedId!, name);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openAssignShift(BuildContext context, String uid) async {
    final shifts = await FirebaseFirestore.instance.collection('shifts').orderBy('name').get();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) {
        String? selectedId;
        return AlertDialog(
          title: const Text('Assign Shift'),
          content: DropdownButtonFormField<String>(
            items: shifts.docs.map((s) {
              final name = (s.data()['name'] ?? s.id).toString();
              final time = '${(s.data()['startTime'] ?? '')} → ${(s.data()['endTime'] ?? '')}';
              return DropdownMenuItem(value: s.id, child: Text('$name  ($time)'));
            }).toList(),
            onChanged: (v) => selectedId = v,
            decoration: const InputDecoration(labelText: 'Shift'),
          ),
          actions: [
            TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (selectedId == null) return;
                await FirebaseFirestore.instance.doc('users/$uid').update({'shiftId': selectedId});
                if (context.mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift assigned')));
              },
              child: const Text('Save'),
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
  final bool canAny;
  const _Actions({required this.uid, required this.role, required this.status, required this.canAny});

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.role == 'admin';
    final isPending = widget.status == 'pending';

    if (loading) {
      return const SizedBox(width: 140, height: 40, child: Center(child: CircularProgressIndicator()));
    }

    return Wrap(
      spacing: 6,
      children: [
        if (isPending)
          FilledButton(
            onPressed: () => _run(() => AdminService.approveUser(widget.uid)),
            child: const Text('Approve'),
          ),
        if (isPending)
          OutlinedButton(
            onPressed: () => _run(() => AdminService.rejectUser(widget.uid)),
            child: const Text('Reject'),
          ),
        if (!isAdmin)
          OutlinedButton(
            onPressed: () => _run(() => AdminService.makeAdmin(widget.uid)),
            child: const Text('Make Admin'),
          ),
        if (isAdmin)
          OutlinedButton(
            onPressed: () => _run(() => AdminService.makeEmployee(widget.uid)),
            child: const Text('Make Employee'),
          ),

        // Toggle "any-branch"
        if (!widget.canAny)
          OutlinedButton(
            onPressed: () => _run(() => FirebaseFirestore.instance.doc('users/${widget.uid}')
                .update({'canCheckFromAnyBranch': true})),
            child: const Text('Allow any branch'),
          ),
        if (widget.canAny)
          OutlinedButton(
            onPressed: () => _run(() => FirebaseFirestore.instance.doc('users/${widget.uid}')
                .update({'canCheckFromAnyBranch': false})),
            child: const Text('Restrict to assigned'),
          ),
      ],
    );
  }
}
