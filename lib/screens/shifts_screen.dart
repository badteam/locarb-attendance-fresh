import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ShiftsScreen extends StatelessWidget {
  const ShiftsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance.collection('shifts').orderBy('name');

    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: col.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add shift'),
                      onPressed: () => _openShiftDialog(context),
                    ),
                  ),
                );
              }
              final d = docs[i - 1];
              final m = d.data();
              final name = (m['name'] ?? d.id).toString();
              final start = (m['startTime'] ?? '').toString();
              final end = (m['endTime'] ?? '').toString();
              final branchName = (m['branchName'] ?? 'Unassigned').toString();

              return ListTile(
                leading: const Icon(Icons.access_time_filled),
                title: Text(name),
                subtitle: Text('Time: $start → $end • Branch: $branchName'),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton(
                      onPressed: () => _openShiftDialog(context, id: d.id, existing: m),
                      child: const Text('Edit'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final ok = await _confirm(context, 'Delete shift "$name"?');
                        if (ok) await d.reference.delete();
                      },
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openShiftDialog(BuildContext context, {String? id, Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: (existing?['name'] ?? '').toString());
    final start = TextEditingController(text: (existing?['startTime'] ?? '08:00').toString());
    final end = TextEditingController(text: (existing?['endTime'] ?? '16:00').toString());
    String? selectedBranchId = (existing?['branchId'] ?? '').toString().isEmpty ? null : (existing?['branchId']).toString();
    String? selectedBranchName = (existing?['branchName'] ?? '').toString().isEmpty ? null : (existing?['branchName']).toString();

    final branches = await FirebaseFirestore.instance.collection('branches').orderBy('name').get();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(id == null ? 'Add shift' : 'Edit shift'),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Shift name')),

                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: start, decoration: const InputDecoration(labelText: 'Start (HH:mm)'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: end, decoration: const InputDecoration(labelText: 'End (HH:mm)'))),
                ]),

                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedBranchId,
                  items: [
                    for (final b in branches.docs)
                      DropdownMenuItem(
                        value: b.id,
                        child: Text((b.data()['name'] ?? b.id).toString()),
                      ),
                  ],
                  onChanged: (v) {
                    selectedBranchId = v;
                    if (v != null) {
                      final doc = branches.docs.firstWhere((e) => e.id == v);
                      selectedBranchName = (doc.data()['name'] ?? doc.id).toString();
                    } else {
                      selectedBranchName = null;
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Branch'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              final data = {
                'name': name.text.trim(),
                'startTime': start.text.trim(),
                'endTime': end.text.trim(),
                'branchId': selectedBranchId ?? '',
                'branchName': selectedBranchName ?? 'Unassigned',
                'updatedAt': FieldValue.serverTimestamp(),
              };
              final col = FirebaseFirestore.instance.collection('shifts');
              if (id == null) {
                await col.add({
                  ...data,
                  'createdAt': FieldValue.serverTimestamp(),
                });
              } else {
                await col.doc(id).set(data, SetOptions(merge: true));
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(id == null ? 'Save' : 'Update'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, String msg) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    return r == true;
  }
}
