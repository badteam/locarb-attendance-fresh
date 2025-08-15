import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class BranchesScreen extends StatelessWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance.collection('branches').orderBy('name');

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
                // زر إضافة فرع
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة فرع'),
                      onPressed: () => _openBranchDialog(context),
                    ),
                  ),
                );
              }
              final d = docs[i - 1];
              final data = d.data();
              final name = (data['name'] ?? d.id).toString();
              final code = (data['code'] ?? '').toString();
              final geo = (data['geo'] ?? {}) as Map<String, dynamic>;
              final lat = (geo['lat'] ?? 0).toString();
              final lng = (geo['lng'] ?? 0).toString();
              final rad = (geo['radiusMeters'] ?? 0).toString();

              return ListTile(
                leading: const Icon(Icons.store_mall_directory),
                title: Text('$name ($code)'),
                subtitle: Text('الموقع: $lat, $lng • نصف القطر: $rad م'),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton(
                      onPressed: () => _openBranchDialog(context, id: d.id, existing: data),
                      child: const Text('تعديل'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        final ok = await _confirm(context, 'حذف الفرع "$name"؟');
                        if (ok) await d.reference.delete();
                      },
                      child: const Text('حذف'),
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

  Future<void> _openBranchDialog(BuildContext context, {String? id, Map<String, dynamic>? existing}) async {
    final name = TextEditingController(text: (existing?['name'] ?? '').toString());
    final code = TextEditingController(text: (existing?['code'] ?? '').toString());
    final address = TextEditingController(text: (existing?['address'] ?? '').toString());
    final lat = TextEditingController(text: ((existing?['geo']?['lat']) ?? '').toString());
    final lng = TextEditingController(text: ((existing?['geo']?['lng']) ?? '').toString());
    final radius = TextEditingController(text: ((existing?['geo']?['radiusMeters']) ?? '150').toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(id == null ? 'إضافة فرع' : 'تعديل فرع'),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الفرع')),
                TextField(controller: code, decoration: const InputDecoration(labelText: 'كود الفرع')),
                TextField(controller: address, decoration: const InputDecoration(labelText: 'العنوان')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: lat, decoration: const InputDecoration(labelText: 'Latitude'), keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: lng, decoration: const InputDecoration(labelText: 'Longitude'), keyboardType: TextInputType.number)),
                ]),
                const SizedBox(height: 8),
                TextField(controller: radius, decoration: const InputDecoration(labelText: 'نصف القطر بالمتر'), keyboardType: TextInputType.number),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final data = {
                'name': name.text.trim(),
                'code': code.text.trim(),
                'address': address.text.trim(),
                'geo': {
                  'lat': double.tryParse(lat.text) ?? 0,
                  'lng': double.tryParse(lng.text) ?? 0,
                  'radiusMeters': double.tryParse(radius.text) ?? 150,
                },
                'updatedAt': FieldValue.serverTimestamp(),
              };
              final col = FirebaseFirestore.instance.collection('branches');
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
            child: Text(id == null ? 'حفظ' : 'تحديث'),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
        ],
      ),
    );
    return r == true;
  }
}
