import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});
  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  String? _branchId;
  String? _shiftId;

  String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _from = DateTime(d.year, d.month, d.day));
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _to = DateTime(d.year, d.month, d.day));
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('attendance')
        .where('localDay', isGreaterThanOrEqualTo: _fmtDay(_from))
        .where('localDay', isLessThanOrEqualTo: _fmtDay(_to))
        .orderBy('localDay', descending: true);

    final branchesRef =
        FirebaseFirestore.instance.collection('branches').orderBy('name');
    final shiftsRef =
        FirebaseFirestore.instance.collection('shifts').orderBy('name');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance (Simple View)'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Wrap(
              runSpacing: 8,
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFrom,
                  icon: const Icon(Icons.date_range),
                  label: Text('From: ${_fmtDay(_from)}'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickTo,
                  icon: const Icon(Icons.event),
                  label: Text('To: ${_fmtDay(_to)}'),
                ),
                // Branch filter
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: branchesRef.snapshots(),
                  builder: (context, snap) {
                    final items = <DropdownMenuItem<String>>[
                      const DropdownMenuItem(
                          value: '', child: Text('All branches')),
                    ];
                    if (snap.hasData) {
                      for (final d in snap.data!.docs) {
                        final name = (d.data()['name'] ?? d.id).toString();
                        items.add(
                            DropdownMenuItem(value: d.id, child: Text(name)));
                      }
                    }
                    return InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Branch',
                          border: OutlineInputBorder(),
                          isDense: true),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _branchId ?? '',
                          items: items,
                          onChanged: (v) => setState(
                              () => _branchId = (v ?? '').isEmpty ? null : v),
                        ),
                      ),
                    );
                  },
                ),
                // Shift filter
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: shiftsRef.snapshots(),
                  builder: (context, snap) {
                    final items = <DropdownMenuItem<String>>[
                      const DropdownMenuItem(
                          value: '', child: Text('All shifts')),
                    ];
                    if (snap.hasData) {
                      for (final d in snap.data!.docs) {
                        final name = (d.data()['name'] ?? d.id).toString();
                        items.add(
                            DropdownMenuItem(value: d.id, child: Text(name)));
                      }
                    }
                    return InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Shift',
                          border: OutlineInputBorder(),
                          isDense: true),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _shiftId ?? '',
                          items: items,
                          onChanged: (v) => setState(
                              () => _shiftId = (v ?? '').isEmpty ? null : v),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                        'Query error: ${snap.error}\nTry removing filters or create index.'),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snap.data?.docs ?? [];

                // client-side filters to avoid composite index
                if (_branchId != null && _branchId!.isNotEmpty) {
                  docs = docs
                      .where((d) =>
                          (d.data()['branchId'] ?? '').toString() == _branchId)
                      .toList();
                }
                if (_shiftId != null && _shiftId!.isNotEmpty) {
                  docs = docs
                      .where((d) =>
                          (d.data()['shiftId'] ?? '').toString() == _shiftId)
                      .toList();
                }

                if (docs.isEmpty) {
                  return const Center(child: Text('No records'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final m = docs[i].data();
                    final typ = (m['type'] ?? '').toString(); // in | out
                    final day = (m['localDay'] ?? '').toString();
                    final at = m['at'] is Timestamp ? m['at'] as Timestamp : null;
                    final uid = (m['userId'] ?? '').toString();
                    final branchId = (m['branchId'] ?? '').toString();
                    final shiftId = (m['shiftId'] ?? '').toString();

                    return Card(
                      elevation: 1.2,
                      child: ListTile(
                        title: Text('$typ • $day • ${_fmtTime(at)}'),
                        subtitle: Text('User: $uid • Branch: $branchId • Shift: $shiftId'),
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
