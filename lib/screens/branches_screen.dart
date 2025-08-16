import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/main_drawer.dart';

class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});

  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Branches & Shifts'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.store_outlined), text: 'Branches'),
            Tab(icon: Icon(Icons.access_time), text: 'Shifts'),
          ],
        ),
      ),
      drawer: const MainDrawer(),
      body: TabBarView(
        controller: _tab,
        children: const [
          _BranchesTab(),
          _ShiftsTab(),
        ],
      ),
    );
  }
}

/* -------------------- Branches Tab -------------------- */

class _BranchesTab extends StatelessWidget {
  const _BranchesTab();

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance.collection('branches').orderBy('name');

    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _ErrorBox(error: snap.error.toString());
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No branches yet'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i];
              final m = d.data();
              final name = (m['name'] ?? d.id).toString();
              final address = (m['address'] ?? '').toString();
              final allowAll = (m['allowAllBranches'] ?? false) == true;

              return Card(
                elevation: 1.2,
                child: ListTile(
                  leading: const Icon(Icons.store_mall_directory),
                  title: Text(name),
                  subtitle: Text(address.isEmpty ? 'No address' : address),
                  trailing: allowAll
                      ? const Chip(label: Text('Open for all'), visualDensity: VisualDensity.compact)
                      : null,
                  onTap: () => _editBranchDialog(context, d.id, m),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add branch'),
        onPressed: () => _addBranchDialog(context),
      ),
    );
  }

  Future<void> _addBranchDialog(BuildContext context) async {
    final name = TextEditingController();
    final address = TextEditingController();
    bool allowAll = false;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New branch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow check-in from any branch'),
              value: allowAll,
              onChanged: (v) => allowAll = v ?? false,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await FirebaseFirestore.instance.collection('branches').add({
                'name': name.text.trim(),
                'address': address.text.trim(),
                'allowAllBranches': allowAll,
                'createdAt': FieldValue.serverTimestamp(),
              });
              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editBranchDialog(BuildContext context, String id, Map<String, dynamic> data) async {
    final name = TextEditingController(text: (data['name'] ?? '').toString());
    final address = TextEditingController(text: (data['address'] ?? '').toString());
    bool allowAll = (data['allowAllBranches'] ?? false) == true;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit branch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (context, setState) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow check-in from any branch'),
                value: allowAll,
                onChanged: (v) => setState(() => allowAll = v ?? false),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('branches').doc(id).delete();
              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await FirebaseFirestore.instance.collection('branches').doc(id).set({
                'name': name.text.trim(),
                'address': address.text.trim(),
                'allowAllBranches': allowAll,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/* -------------------- Shifts Tab -------------------- */

class _ShiftsTab extends StatelessWidget {
  const _ShiftsTab();

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance.collection('shifts').orderBy('name');

    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return _ErrorBox(error: snap.error.toString());
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('No shifts yet'));

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i];
              final m = d.data();
              final name = (m['name'] ?? d.id).toString();
              final start = (m['start'] ?? '').toString(); // HH:mm
              final end = (m['end'] ?? '').toString();     // HH:mm
              final grace = (m['graceMinutes'] ?? 0).toString();
              final branchId = (m['branchId'] ?? '').toString();

              return Card(
                elevation: 1.2,
                child: ListTile(
                  leading: const Icon(Icons.access_time),
                  title: Text(name),
                  subtitle: Text('Time: $start - $end • Grace: $grace min\nBranch: ${branchId.isEmpty ? "Any" : branchId}'),
                  isThreeLine: true,
                  onTap: () => _editShiftDialog(context, d.id, m),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add shift'),
        onPressed: () => _addShiftDialog(context),
      ),
    );
  }

  Future<void> _addShiftDialog(BuildContext context) async {
    final name = TextEditingController();
    final start = TextEditingController(); // بصيغة HH:mm
    final end = TextEditingController();
    final grace = TextEditingController(text: '10'); // دقائق سماح
    final branchId = TextEditingController(); // اختياري: ربط الشفت بفرع

    TimeOfDay? _pickTime(TimeOfDay? init) => init;

    Future<void> pickStart() async {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (t != null) start.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    Future<void> pickEnd() async {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (t != null) end.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New shift'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: start, decoration: const InputDecoration(labelText: 'Start (HH:mm)'))),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(onPressed: pickStart, icon: const Icon(Icons.access_time), label: const Text('Pick')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: end, decoration: const InputDecoration(labelText: 'End (HH:mm)'))),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(onPressed: pickEnd, icon: const Icon(Icons.access_time), label: const Text('Pick')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: grace,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Grace minutes'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: branchId,
                decoration: const InputDecoration(
                  labelText: 'Branch ID (optional)',
                  helperText: 'Leave empty to allow this shift in any branch',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty || start.text.trim().isEmpty || end.text.trim().isEmpty) return;
              final gm = int.tryParse(grace.text.trim()) ?? 0;
              await FirebaseFirestore.instance.collection('shifts').add({
                'name': name.text.trim(),
                'start': start.text.trim(),
                'end': end.text.trim(),
                'graceMinutes': gm,
                'branchId': branchId.text.trim(), // ممكن يكون فاضي
                'createdAt': FieldValue.serverTimestamp(),
              });
              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editShiftDialog(BuildContext context, String id, Map<String, dynamic> data) async {
    final name = TextEditingController(text: (data['name'] ?? '').toString());
    final start = TextEditingController(text: (data['start'] ?? '').toString());
    final end = TextEditingController(text: (data['end'] ?? '').toString());
    final grace = TextEditingController(text: (data['graceMinutes'] ?? 0).toString());
    final branchId = TextEditingController(text: (data['branchId'] ?? '').toString());

    Future<void> pickStart() async {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (t != null) start.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    Future<void> pickEnd() async {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (t != null) end.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit shift'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: start, decoration: const InputDecoration(labelText: 'Start (HH:mm)'))),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(onPressed: pickStart, icon: const Icon(Icons.access_time), label: const Text('Pick')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: end, decoration: const InputDecoration(labelText: 'End (HH:mm)'))),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(onPressed: pickEnd, icon: const Icon(Icons.access_time), label: const Text('Pick')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: grace,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Grace minutes'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: branchId,
                decoration: const InputDecoration(
                  labelText: 'Branch ID (optional)',
                  helperText: 'Leave empty to allow this shift in any branch',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('shifts').doc(id).delete();
              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty || start.text.trim().isEmpty || end.text.trim().isEmpty) return;
              final gm = int.tryParse(grace.text.trim()) ?? 0;
              await FirebaseFirestore.instance.collection('shifts').doc(id).set({
                'name': name.text.trim(),
                'start': start.text.trim(),
                'end': end.text.trim(),
                'graceMinutes': gm,
                'branchId': branchId.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/* -------------------- Helpers -------------------- */

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
          child: Text(
            'Query error:\n$error',
          ),
        ),
      ),
    );
  }
}
