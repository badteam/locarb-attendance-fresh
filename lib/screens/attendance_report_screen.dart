import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to   = DateTime.now();
  String? _branchId;

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

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    final branchesRef = FirebaseFirestore.instance.collection('branches').orderBy('name');

    // نبني الاستعلام حسب الفرع والتاريخ (يعتمد على الحقل localDay نصّيًا YYYY-MM-DD)
    Query<Map<String,dynamic>> q = FirebaseFirestore.instance
        .collection('attendance')
        .where('localDay', isGreaterThanOrEqualTo: _fmt(_from))
        .where('localDay', isLessThanOrEqualTo: _fmt(_to));

    if (_branchId != null && _branchId!.isNotEmpty) {
      q = q.where('branchId', isEqualTo: _branchId);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFrom,
                  icon: const Icon(Icons.date_range),
                  label: Text('من: ${_fmt(_from)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTo,
                  icon: const Icon(Icons.event),
                  label: Text('إلى: ${_fmt(_to)}'),
                ),
              ),
              const SizedBox(width: 8),
              StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
                stream: branchesRef.snapshots(),
                builder: (context, snap) {
                  final items = <DropdownMenuItem<String>>[
                    const DropdownMenuItem(value: '', child: Text('كل الفروع')),
                  ];
                  if (snap.hasData) {
                    for (final d in snap.data!.docs) {
                      final name = (d.data()['name'] ?? d.id).toString();
                      items.add(DropdownMenuItem(value: d.id, child: Text(name)));
                    }
                  }
                  return DropdownButton<String>(
                    value: _branchId ?? '',
                    items: items,
                    onChanged: (v) => setState(() => _branchId = (v ?? '').isEmpty ? null : v),
                  );
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
            stream: q.orderBy('at', descending: true).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('لا توجد سجلات في المدى المختار'));
              }

              // تجميع سريع حسب المستخدم
              final Map<String, Map<String, dynamic>> summary = {};
              for (final d in docs) {
                final m = d.data();
                final uid = (m['userId'] ?? '').toString();
                final typ = (m['type'] ?? 'in').toString();
                final day = (m['localDay'] ?? '').toString();

                summary.putIfAbsent(uid, () => {
                  'userId': uid,
                  'in': 0,
                  'out': 0,
                  'days': <String>{},
                });
                summary[uid]!['days'].add(day);
                summary[uid]![typ] = (summary[uid]![typ] as int) + 1;
              }

              return Column(
                children: [
                  // كارت خلاصة
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('إجمالي السجلات: ${docs.length}'),
                            Text('عدد الموظفين: ${summary.length}'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  // قائمة السجلات
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final m = docs[i].data();
                        final uid = (m['userId'] ?? '').toString();
                        final typ = (m['type'] ?? '').toString();
                        final day = (m['localDay'] ?? '').toString();
                        final branchId = (m['branchId'] ?? '').toString();
                        final lat = (m['lat'] ?? 0).toString();
                        final lng = (m['lng'] ?? 0).toString();

                        return ListTile(
                          leading: Icon(typ == 'in' ? Icons.login : Icons.logout),
                          title: Text('المستخدم: $uid'),
                          subtitle: Text('اليوم: $day • الفرع: $branchId\n($lat, $lng)'),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
