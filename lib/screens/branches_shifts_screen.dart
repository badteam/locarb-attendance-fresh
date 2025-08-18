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
      floatingActionButton: AnimatedBuilder(
        animation: _tab,
        builder: (context, _) {
          final isBranches = _tab.index == 0;
          return FloatingActionButton.extended(
            onPressed: () async {
              if (isBranches) {
                await _showBranchEditor(context);
              } else {
                await _showShiftEditor(context);
              }
            },
            icon: Icon(isBranches ? Icons.add_business : Icons.add_alarm),
            label: Text(isBranches ? 'Add branch' : 'Add shift'),
          );
        },
      ),
    );
  }
}

/* =============================== Branches =============================== */

class _BranchesTab extends StatelessWidget {
  const _BranchesTab();

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('branches').orderBy('name');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _ErrorBox('Error: ${snap.error}');
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No branches yet'));

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final name = (m['name'] ?? d.id).toString();
            final addr = (m['address'] ?? '').toString();
            final lat  = (m['lat'] ?? '').toString();
            final lng  = (m['lng'] ?? '').toString();
            final rad  = (m['radiusMeters'] ?? '').toString();

            return Card(
              child: ListTile(
                leading: const Icon(Icons.store),
                title: Text(name),
                subtitle: Text([
                  if (addr.isNotEmpty) addr,
                  if (lat.isNotEmpty && lng.isNotEmpty) '($lat, $lng)',
                  if (rad.isNotEmpty) 'radius: $rad m',
                ].join(' • ')),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CountChip(
                      query: FirebaseFirestore.instance
                          .collection('users')
                          .where('primaryBranchId', isEqualTo: d.id),
                      icon: Icons.people,
                      tooltip: 'Assigned employees',
                      onTap: () => _showBranchMembers(context,
                          branchId: d.id, branchName: name),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit branch',
                      onPressed: () => _showBranchEditor(context, docId: d.id, data: m),
                    ),
                  ],
                ),
                onTap: () => _showBranchMembers(context,
                    branchId: d.id, branchName: name),
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
  final name    = TextEditingController(text: (data?['name'] ?? '').toString());
  final address = TextEditingController(text: (data?['address'] ?? '').toString());
  final latCtrl = TextEditingController(text: (data?['lat'] ?? '').toString());
  final lngCtrl = TextEditingController(text: (data?['lng'] ?? '').toString());
  final radiusCtrl =
      TextEditingController(text: (data?['radiusMeters'] ?? '').toString());

  await showDialog(
    context: context,
    builder: (context) {
      Future<void> onSave() async {
        final lat = latCtrl.text.trim().isEmpty ? null : double.tryParse(latCtrl.text.trim());
        final lng = lngCtrl.text.trim().isEmpty ? null : double.tryParse(lngCtrl.text.trim());
        final rad = radiusCtrl.text.trim().isEmpty ? null : int.tryParse(radiusCtrl.text.trim());

        final payload = <String, dynamic>{
          'name': name.text.trim(),
          'address': address.text.trim(),
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          if (rad != null) 'radiusMeters': rad,
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
        if (context.mounted) Navigator.pop(context);
      }

      Future<void> onDelete() async {
        if (docId == null) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete branch?'),
            content: const Text('This action cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) {
          await FirebaseFirestore.instance.collection('branches').doc(docId).delete();
          if (context.mounted) Navigator.pop(context);
        }
      }

      return AlertDialog(
        title: Text(docId == null ? 'Add branch' : 'Edit branch'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name,    decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: address, decoration: const InputDecoration(labelText: 'Address')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Latitude (e.g. 24.71)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: lngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Longitude (e.g. 46.67)'),
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

/* ================================ Shifts ================================ */

class _ShiftsTab extends StatelessWidget {
  const _ShiftsTab();

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseFirestore.instance.collection('shifts').orderBy('name');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return _ErrorBox('Error: ${snap.error}');
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
            final name  = (m['name']  ?? d.id).toString();
            final start = (m['start'] ?? '').toString();
            final end   = (m['end']   ?? '').toString();

            return Card(
              child: ListTile(
                leading: const Icon(Icons.access_time),
                title: Text(name),
                subtitle: Text('Start: $start • End: $end'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CountChip(
                      query: FirebaseFirestore.instance
                          .collection('users')
                          .where('assignedShiftId', isEqualTo: d.id),
                      icon: Icons.person,
                      tooltip: 'Assigned employees',
                      onTap: () => _showShiftMembers(context,
                          shiftId: d.id, shiftName: name),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit shift',
                      onPressed: () => _showShiftEditor(context, docId: d.id, data: m),
                    ),
                  ],
                ),
                onTap: () => _showShiftMembers(context,
                    shiftId: d.id, shiftName: name),
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
  final name  = TextEditingController(text: (data?['name']  ?? '').toString());
  final start = TextEditingController(text: (data?['start'] ?? '').toString()); // HH:mm
  final end   = TextEditingController(text: (data?['end']   ?? '').toString()); // HH:mm

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
        if (context.mounted) Navigator.pop(context);
      }

      Future<void> onDelete() async {
        if (docId == null) return;
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete shift?'),
            content: const Text('This action cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) {
          await FirebaseFirestore.instance.collection('shifts').doc(docId).delete();
          if (context.mounted) Navigator.pop(context);
        }
      }

      return AlertDialog(
        title: Text(docId == null ? 'Add shift' : 'Edit shift'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name,  decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: start, decoration: const InputDecoration(labelText: 'Start (HH:mm)')),
              const SizedBox(height: 8),
              TextField(controller: end,   decoration: const InputDecoration(labelText: 'End (HH:mm)')),
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

/* ============================== Members UIs ============================= */

Future<void> _showShiftMembers(BuildContext context,
    {required String shiftId, String? shiftName}) async {
  // requires index: assignedShiftId ASC, fullName ASC
  final q = FirebaseFirestore.instance
      .collection('users')
      .where('assignedShiftId', isEqualTo: shiftId)
      .orderBy('fullName');

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) {
      return _MembersSheet(
        titleIcon: Icons.schedule,
        title: shiftName ?? 'Shift',
        subtitle: 'Assigned employees',
        query: q,
        assignBuilder: () => _AssignUsersDialog.shift(shiftId: shiftId, shiftName: shiftName ?? 'Shift'),
      );
    },
  );
}

Future<void> _showBranchMembers(BuildContext context,
    {required String branchId, String? branchName}) async {
  // requires index: primaryBranchId ASC, fullName ASC
  final q = FirebaseFirestore.instance
      .collection('users')
      .where('primaryBranchId', isEqualTo: branchId)
      .orderBy('fullName');

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) {
      return _MembersSheet(
        titleIcon: Icons.storefront,
        title: branchName ?? 'Branch',
        subtitle: 'Assigned employees',
        query: q,
        assignBuilder: () => _AssignUsersDialog.branch(branchId: branchId, branchName: branchName ?? 'Branch'),
      );
    },
  );
}

class _MembersSheet extends StatelessWidget {
  final IconData titleIcon;
  final String title;
  final String subtitle;
  final Query<Map<String, dynamic>> query;
  final Widget Function() assignBuilder;

  const _MembersSheet({
    required this.titleIcon,
    required this.title,
    required this.subtitle,
    required this.query,
    required this.assignBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 12, right: 12, top: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(titleIcon),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: FilledButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => assignBuilder()),
              icon: const Icon(Icons.person_add),
              label: const Text('Assign'),
            ),
          ),
          Flexible(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Error loading employees'),
                  );
                }
                if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                }
                final users = snap.data!.docs;
                if (users.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No employees assigned')),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = users[i].data();
                    final fullName = (m['fullName'] ?? '').toString();
                    final username = (m['username'] ?? '').toString();
                    final email    = (m['email']    ?? '').toString();
                    final photo    = (m['photoUrl'] ?? '').toString();
                    final display = fullName.isNotEmpty
                        ? fullName
                        : (username.isNotEmpty ? username : (email.isNotEmpty ? email : users[i].id));
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                        child: photo.isEmpty ? Text(display[0].toUpperCase()) : null,
                      ),
                      title: Text(display),
                      subtitle: Text(users[i].id),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/* ========================= Assign Users Dialog ========================== */

class _AssignUsersDialog extends StatefulWidget {
  final String? shiftId;
  final String? branchId;
  final String title;

  const _AssignUsersDialog._({
    this.shiftId,
    this.branchId,
    required this.title,
    super.key,
  });

  factory _AssignUsersDialog.shift({
    required String shiftId,
    required String shiftName,
  }) =>
      _AssignUsersDialog._(shiftId: shiftId, title: 'Assign to "$shiftName"');

  factory _AssignUsersDialog.branch({
    required String branchId,
    required String branchName,
  }) =>
      _AssignUsersDialog._(branchId: branchId, title: 'Assign to "$branchName"');

  @override
  State<_AssignUsersDialog> createState() => _AssignUsersDialogState();
}

class _AssignUsersDialogState extends State<_AssignUsersDialog> {
  String _search = '';
  final Map<String, bool> _selected = {};

  Query<Map<String, dynamic>> _baseQuery() {
    return FirebaseFirestore.instance.collection('users').orderBy('fullName');
  }

  Future<void> _apply() async {
    final batch = FirebaseFirestore.instance.batch();
    final usersCol = FirebaseFirestore.instance.collection('users');

    for (final e in _selected.entries) {
      final uid = e.key;
      final checked = e.value;
      final doc = usersCol.doc(uid);

      if (widget.shiftId != null) {
        batch.set(doc, {
          if (checked) 'assignedShiftId': widget.shiftId else 'assignedShiftId': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (widget.branchId != null) {
        batch.set(doc, {
          if (checked) 'primaryBranchId': widget.branchId else 'primaryBranchId': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    await batch.commit();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search…',
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _baseQuery().snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  var docs = snap.data!.docs;
                  if (_search.trim().isNotEmpty) {
                    final term = _search.toLowerCase();
                    docs = docs.where((d) {
                      final m = d.data();
                      final fullName = (m['fullName'] ?? '').toString().toLowerCase();
                      final username = (m['username'] ?? '').toString().toLowerCase();
                      final email    = (m['email']    ?? '').toString().toLowerCase();
                      final display  = fullName.isNotEmpty ? fullName : (username.isNotEmpty ? username : email);
                      return display.contains(term) || d.id.toLowerCase().contains(term);
                    }).toList();
                  }
                  if (docs.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No users found'),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final m = d.data();
                      final fullName = (m['fullName'] ?? '').toString();
                      final username = (m['username'] ?? '').toString();
                      final email    = (m['email']    ?? '').toString();
                      final photo    = (m['photoUrl'] ?? '').toString();
                      final display  = fullName.isNotEmpty ? fullName : (username.isNotEmpty ? username : (email.isNotEmpty ? email : d.id));

                      final initiallySelected = widget.shiftId != null
                          ? (m['assignedShiftId'] == widget.shiftId)
                          : (m['primaryBranchId'] == widget.branchId);

                      final checked = _selected[d.id] ?? initiallySelected;

                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) => setState(() => _selected[d.id] = v ?? false),
                        secondary: CircleAvatar(
                          backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                          child: photo.isEmpty ? Text(display[0].toUpperCase()) : null,
                        ),
                        title: Text(display),
                        subtitle: Text(d.id),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _apply, child: const Text('Save')),
      ],
    );
  }
}

/* ================================ UI Bits =============================== */

class _CountChip extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _CountChip({
    required this.query,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        final count = snap.hasData ? snap.data!.docs.length : 0;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsetsDirectional.only(end: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 4),
                Text('$count'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(message),
        ),
      ),
    );
  }
}
