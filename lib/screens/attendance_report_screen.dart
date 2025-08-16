import 'dart:typed_data';
import 'dart:html' as html;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../utils/export.dart';
import '../widgets/main_drawer.dart';

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

  Future<void> _exportExcel(Map<String, String> userNames) async {
    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('attendance')
          .where('localDay', isGreaterThanOrEqualTo: _fmtDay(_from))
          .where('localDay', isLessThanOrEqualTo: _fmtDay(_to))
          .orderBy('localDay', descending: false);

      final snap = await q.get();
      var docs = snap.docs;

      if (_branchId != null && _branchId!.isNotEmpty) {
        docs = docs.where((d) => (d.data()['branchId'] ?? '').toString() == _branchId).toList();
      }
      if (_shiftId != null && _shiftId!.isNotEmpty) {
        docs = docs.where((d) => (d.data()['shiftId'] ?? '').toString() == _shiftId).toList();
      }
      if (docs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No records to export for this range')));
        return;
      }

      // لو في مستخدمين مش موجودين في الخريطة، نجيب اسمهم
      final uidSet = <String>{};
      for (final d in docs) {
        final uid = (d.data()['userId'] ?? '').toString();
        if (uid.isNotEmpty) uidSet.add(uid);
      }
      final names = Map<String, String>.from(userNames);
      for (final uid in uidSet) {
        names.putIfAbsent(uid, () => uid); // fallback
      }

      final bytes = await Export.buildPivotExcelBytes(
        attendanceDocs: docs,
        from: _from,
        to: _to,
        userNames: names,
      );
      final filename = 'attendance_${_fmtDay(_from)}_${_fmtDay(_to)}.xlsx';

      if (kIsWeb) {
        final blob = html.Blob([Uint8List.fromList(bytes)]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)..download = filename;
        html.document.body!.children.add(anchor);
        anchor.click();
        html.document.body!.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel generated (mobile save/share later).')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('attendance')
        .where('localDay', isGreaterThanOrEqualTo: _fmtDay(_from))
        .where('localDay', isLessThanOrEqualTo: _fmtDay(_to))
        .orderBy('localDay', descending: true);

    final branchesRef = FirebaseFirestore.instance.collection('branches').orderBy('name');
    final shiftsRef = FirebaseFirestore.instance.collection('shifts').orderBy('name');
    final usersRef = FirebaseFirestore.instance.collection('users');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Reports'),
        actions: [
          Builder(
            builder: (context) {
              // نحتاج خريطة أسماء المستخدمين من StreamBuilder اللي تحت
              return IconButton(
                tooltip: 'Export Excel',
                onPressed: () async {
                  // هنجيب الخريطة من الـ InheritedElement (ببساطة: نعيد البناء ونستخدم setState؟)
                  // أسهل حل: نطلع SnackBar يطلب الانتظار لو الخريطة لسه ما اتبنتش.
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Scroll down slightly to ensure data loaded, then press Export again if needed.')),
                  );
                },
                icon: const Icon(Icons.file_download),
              );
            },
          ),
        ],
      ),
      drawer: const MainDrawer(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersRef.snapshots(),
        builder: (context, usersSnap) {
          // Build map: uid -> displayName
          final userNames = <String, String>{};
          if (usersSnap.hasData) {
            for (final u in usersSnap.data!.docs) {
              final m = u.data();
              final full = (m['fullName'] ?? '').toString();
              final uname = (m['username'] ?? '').toString();
              userNames[u.id] = full.isNotEmpty ? full : (uname.isNotEmpty ? uname : u.id);
            }
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: branchesRef.snapshots(),
            builder: (context, branchesSnap) {
              final branchNames = <String, String>{};
              if (branchesSnap.hasData) {
                for (final b in branchesSnap.data!.docs) {
                  final m = b.data();
                  branchNames[b.id] = (m['name'] ?? b.id).toString();
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Filters
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Wrap(
                      runSpacing: 8,
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                        // Branch filter dropdown
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: branchesRef.snapshots(),
                          builder: (context, snap) {
                            final items = <DropdownMenuItem<String>>[
                              const DropdownMenuItem(value: '', child: Text('All branches')),
                            ];
                            if (snap.hasData) {
                              for (final d in snap.data!.docs) {
                                final name = (d.data()['name'] ?? d.id).toString();
                                items.add(DropdownMenuItem(value: d.id, child: Text(name)));
                              }
                            }
                            return InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Branch',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _branchId ?? '',
                                  items: items,
                                  onChanged: (v) =>
                                      setState(() => _branchId = (v ?? '').isEmpty ? null : v),
                                ),
                              ),
                            );
                          },
                        ),
                        // Shift filter dropdown
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: shiftsRef.snapshots(),
                          builder: (context, snap) {
                            final items = <DropdownMenuItem<String>>[
                              const DropdownMenuItem(value: '', child: Text('All shifts')),
                            ];
                            if (snap.hasData) {
                              for (final d in snap.data!.docs) {
                                final name = (d.data()['name'] ?? d.id).toString();
                                items.add(DropdownMenuItem(value: d.id, child: Text(name)));
                              }
                            }
                            return InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Shift',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _shiftId ?? '',
                                  items: items,
                                  onChanged: (v) =>
                                      setState(() => _shiftId = (v ?? '').isEmpty ? null : v),
                                ),
                              ),
                            );
                          },
                        ),
                        // زر Export حقيقي يعتمد على userNames اللي نبنيها فوق
                        FilledButton.icon(
                          onPressed: () => _exportExcel(userNames),
                          icon: const Icon(Icons.file_download),
                          label: const Text('Export Excel'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Attendance stream
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: q.snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return _ErrorBox(error: snap.error.toString());
                        }
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        var docs = snap.data?.docs ?? [];

                        // client-side filters
                        if (_branchId != null && _branchId!.isNotEmpty) {
                          docs = docs
                              .where((d) => (d.data()['branchId'] ?? '').toString() == _branchId)
                              .toList();
                        }
                        if (_shiftId != null && _shiftId!.isNotEmpty) {
                          docs = docs
                              .where((d) => (d.data()['shiftId'] ?? '').toString() == _shiftId)
                              .toList();
                        }

                        if (docs.isEmpty) {
                          return const Center(child: Text('No records in the selected range'));
                        }

                        final uniqueUsers = <String>{};
                        for (final d in docs) {
                          uniqueUsers.add((d.data()['userId'] ?? '').toString());
                        }

                        final summary = Card(
                          elevation: 0,
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total records: ${docs.length}'),
                                Text('Employees: ${uniqueUsers.length}'),
                              ],
                            ),
                          ),
                        );

                        final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> byDay = {};
                        for (final d in docs) {
                          final day = (d.data()['localDay'] ?? '').toString();
                          byDay.putIfAbsent(day, () => []).add(d);
                        }
                        final orderedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: orderedDays.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) return summary;

                            final day = orderedDays[index - 1];
                            final items = byDay[day]!;

                            // sort by time asc
                            items.sort((a, b) {
                              final ta = (a.data()['at'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
                              final tb = (b.data()['at'] as Timestamp?)?.toDate().millisecondsSinceEpoch ?? 0;
                              return ta.compareTo(tb);
                            });

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                                  child: Text('Date: $day', style: Theme.of(context).textTheme.titleMedium),
                                ),
                                ...items.map((d) {
                                  final m = d.data();
                                  final uid = (m['userId'] ?? '').toString();
                                  final typ = (m['type'] ?? '').toString(); // in | out
                                  final branchId = (m['branchId'] ?? '').toString();
                                  final shiftId = (m['shiftId'] ?? '').toString();
                                  final lat = (m['lat'] ?? 0).toString();
                                  final lng = (m['lng'] ?? 0).toString();
                                  final at = m['at'] is Timestamp ? (m['at'] as Timestamp) : null;

                                  final userLabel = userNames[uid] ?? uid;
                                  final branchLabel = branchId.isEmpty ? '—' : (branchNames[branchId] ?? branchId);

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    elevation: 1.2,
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: typ == 'in' ? Colors.green.shade600 : Colors.red.shade600,
                                        child: Text(typ == 'in' ? 'IN' : 'OUT', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                      ),
                                      title: Text(userLabel),
                                      subtitle: Text('Branch: $branchLabel • Shift: $shiftId • Time: ${_fmtTime(at)}\n($lat, $lng)'),
                                    ),
                                  );
                                }),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

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
            'Query error:\n$error\n\nIf it mentions an index, pick "All branches" or create the index in Firestore > Indexes.',
          ),
        ),
      ),
    );
  }
}
