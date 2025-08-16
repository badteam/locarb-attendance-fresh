import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class BranchesShiftsScreen extends StatefulWidget {
  const BranchesShiftsScreen({super.key});

  @override
  State<BranchesShiftsScreen> createState() => _BranchesShiftsScreenState();
}

class _BranchesShiftsScreenState extends State<BranchesShiftsScreen>
    with SingleTickerProviderStateMixin {
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
            Tab(icon: Icon(Icons.storefront), text: 'Branches'),
            Tab(icon: Icon(Icons.schedule), text: 'Shifts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _BranchesTab(),
          _ShiftsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (_tab.index == 0) {
            await _showBranchEditor(context);
          } else {
            await _showShiftEditor(context);
          }
        },
        icon: const Icon(Icons.add),
        label: Text(_tab.index == 0 ? 'Add branch' : 'Add shift'),
      ),
    );
  }
}

/* ------------------------------ Branches Tab ------------------------------ */

class _BranchesTab extends StatelessWidget {
  const _BranchesTab();

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('branches').orderBy('name');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final name = (m['name'] ?? d.id).toString();
            final addr = (m['address'] ?? '').toString();
            final lat = (m['lat'] ?? '').toString();
            final lng = (m['lng'] ?? '').toString();
            final radius = (m['radiusMeters'] ?? '').toString();

            return Card(
              child: ListTile(
                leading: const Icon(Icons.store),
                title: Text(name),
                subtitle: Text([
                  if (addr.isNotEmpty) addr,
                  if (lat.isNotEmpty && lng.isNotEmpty) '($lat, $lng)',
                  if (radius.isNotEmpty) 'radius: $radius m',
                ].join(' • ')),
                trailing: const Icon(Icons.edit),
                onTap: () => _showBranchEditor(context, docId: d.id, data: m),
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> _showBranchEditor(
  BuildContext context, {
  String? docId,
  Map<String, dynamic>? data,
}) async {
  final name = TextEditingController(text: (data?['name'] ?? '').toString());
  final address = TextEditingController(text: (data?['address'] ?? '').toString());
  final latCtrl = TextEditingController(text: (data?['lat'] ?? '').toString());
  final lngCtrl = TextEditingController(text: (data?['lng'] ?? '').toString());
  final radiusCtrl =
      TextEditingController(text: (data?['radiusMeters'] ?? '').toString());

  await showDialog(
    context: context,
    builder: (context) {
      Future<void> onSave() async {
        double? lat =
            latCtrl.text.trim().isEmpty ? null : double.tryParse(latCtrl.text.trim());
        double? lng =
            lngCtrl.text.trim().isEmpty ? null : double.tryParse(lngCtrl.text.trim());
        int? radius = radiusCtrl.text.trim().isEmpty
            ? null
            : int.tryParse(radiusCtrl.text.trim());

        final payload = <String, dynamic>{
          'name': name.text.trim(),
          'address': address.text.trim(),
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          if (radius != null) 'radiusMeters': radius,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        final col = FirebaseFirestore.instance.collection('branches');
        if (docId == null) {
          await col.add({
            ...payload,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          await col.doc(docId).set(payload, SetOptions(merge: true));
        }
        // ignore: use_build_context_synchronously
        Navigator.pop(context);
      }

      Future<void> onDelete() async {
        if (docId == null) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete branch?'),
            content: const Text('This action cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
              FilledButton.tonal(onPressed: () => Navigator.pop(_, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) {
          await FirebaseFirestore.instance.collection('branches').doc(docId).delete();
          // ignore: use_build_context_synchronously
          Navigator.pop(context);
        }
      }

      return AlertDialog(
        title: Text(docId == null ? 'Add branch' : 'Edit branch'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Latitude (e.g. 29.97)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: lngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Longitude (e.g. 31.25)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: radiusCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Allowed radius (meters)'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Note: Allow check-in from any branch is a USER flag (allowAnyBranch), not a branch setting.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          if (docId != null)
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(onPressed: onSave, child: const Text('Save')),
        ],
      );
    },
  );
}

/* -------------------------------- Shifts Tab -------------------------------- */

class _ShiftsTab extends StatelessWidget {
  const _ShiftsTab();

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('shifts').orderBy('name');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _ErrorBox(error: snap.error.toString());
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No shifts yet'));
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final name = (m['name'] ?? d.id).toString();
            final start = (m['start'] ?? '').toString(); // HH:mm
            final end = (m['end'] ?? '').toString();     // HH:mm
            return Card(
              child: ListTile(
                leading: const Icon(Icons.access_time),
                title: Text(name),
                subtitle: Text('Start: $start • End: $end'),
                trailing: const Icon(Icons.edit),
                onTap: () => _showShiftEditor(context, docId: d.id, data: m),
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> _showShiftEditor(
  BuildContext context, {
  String? docId,
  Map<String, dynamic>? data,
}) async {
  final name = TextEditingController(text: (data?['name'] ?? '').toString());
  final start = TextEditingController(text: (data?['start'] ?? '').toString()); // HH:mm
  final end = TextEditingController(text: (data?['end'] ?? '').toString());     // HH:mm

  await showDialog(
    context: context,
    builder: (context) {
      Future<void> onSave() async {
        final payload = <String, dynamic>{
          'name': name.text.trim(),
          'start': start.text.trim(),
          'end': end.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        final col = FirebaseFirestore.instance.collection('shifts');
        if (docId == null) {
          await col.add({
            ...payload,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          await col.doc(docId).set(payload, SetOptions(merge: true));
        }
        // ignore: use_build_context_synchronously
        Navigator.pop(context);
      }

      Future<void> onDelete() async {
        if (docId == null) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete shift?'),
            content: const Text('This action cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
              FilledButton.tonal(onPressed: () => Navigator.pop(_, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) {
          await FirebaseFirestore.instance.collection('shifts').doc(docId).delete();
          // ignore: use_build_context_synchronously
          Navigator.pop(context);
        }
      }

      return AlertDialog(
        title: Text(docId == null ? 'Add shift' : 'Edit shift'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(
                controller: start,
                decoration: const InputDecoration(labelText: 'Start (HH:mm)'),
                keyboardType: TextInputType.datetime,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: end,
                decoration: const InputDecoration(labelText: 'End (HH:mm)'),
                keyboardType: TextInputType.datetime,
              ),
            ],
          ),
        ),
        actions: [
          if (docId != null)
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(onPressed: onSave, child: const Text('Save')),
        ],
      );
    },
  );
}

/* -------------------------------- Utilities -------------------------------- */

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
          child: Text(error),
        ),
      ),
    );
  }
}
