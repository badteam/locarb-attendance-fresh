import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BranchesShiftsScreen extends StatefulWidget {
  const BranchesShiftsScreen({super.key});

  @override
  State<BranchesShiftsScreen> createState() => _BranchesShiftsScreenState();
}

class _BranchesShiftsScreenState extends State<BranchesShiftsScreen> {
  final _firestore = FirebaseFirestore.instance;

  // إضافة فرع جديد
  Future<void> _addBranch() async {
    final nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Branch'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Branch name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                await _firestore.collection('branches').add({
                  'name': nameController.text.trim(),
                  'createdAt': FieldValue.serverTimestamp(),
                  'employees': [],
                });
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // إضافة شفت جديد
  Future<void> _addShift() async {
    final nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Shift'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Shift name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                await _firestore.collection('shifts').add({
                  'name': nameController.text.trim(),
                  'createdAt': FieldValue.serverTimestamp(),
                  'employees': [],
                });
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // تعيين موظفين داخل فرع أو شفت
  Future<void> _assignEmployees(String collection, String docId) async {
    final employeesSnap = await _firestore.collection('users').get();
    final employees = employeesSnap.docs;

    List<String> selected = [];

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Assign Employees to $collection'),
          content: SizedBox(
            width: 300,
            height: 400,
            child: ListView(
              children: employees.map((e) {
                final id = e.id;
                final email = e['email'] ?? 'no-email';
                final isSelected = selected.contains(id);
                return CheckboxListTile(
                  title: Text(email),
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        selected.add(id);
                      } else {
                        selected.remove(id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await _firestore.collection(collection).doc(docId).update({
                  'employees': selected,
                });
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // عرض الموظفين داخل فرع أو شفت
  void _showEmployees(List<dynamic> employeeIds) async {
    if (employeeIds.isEmpty) {
      showDialog(
        context: context,
        builder: (_) => const AlertDialog(
          title: Text('Employees'),
          content: Text('No employees assigned.'),
        ),
      );
      return;
    }

    final snap = await _firestore
        .collection('users')
        .where(FieldPath.documentId, whereIn: employeeIds)
        .get();

    final employees = snap.docs;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Employees'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView(
            children: employees.map((e) {
              final email = e['email'] ?? 'no-email';
              return ListTile(title: Text(email));
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String collection, VoidCallback onAdd) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection(collection).orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return ListTile(title: Text('No $title found'));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...snap.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final name = data['name'] ?? 'Unnamed';
              final employees = List<String>.from(data['employees'] ?? []);
              return Card(
                child: ListTile(
                  title: Text(name),
                  subtitle: Text('Employees: ${employees.length}'),
                  onTap: () => _showEmployees(employees),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_add),
                    onPressed: () => _assignEmployees(collection, doc.id),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text('Add $title'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Branches & Shifts')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection('Branches', 'branches', _addBranch),
            const SizedBox(height: 24),
            _buildSection('Shifts', 'shifts', _addShift),
          ],
        ),
      ),
    );
  }
}
