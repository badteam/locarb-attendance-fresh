// lib/screens/absences_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/attendance_utils.dart';
import '../widgets/resolve_absence_dialog.dart';

class AbsencesScreen extends StatefulWidget {
  const AbsencesScreen({super.key});

  @override
  State<AbsencesScreen> createState() => _AbsencesScreenState();
}

class _AbsencesScreenState extends State<AbsencesScreen> {
  final fs = FirebaseFirestore.instance;

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  String _branchId = 'all';
  String _shiftId = 'all';
  String _status = 'anomalies'; // anomalies|all|absent|present|leave|weekend|holiday

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _branches = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _shifts = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    final br = await fs.collection('branches').orderBy('name').get();
    final sh = await fs.collection('shifts').orderBy('name').get();
    setState(() {
      _branches = br.docs;
      _shifts = sh.docs;
    });
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(context: context, initialDate: _from, firstDate: DateTime(2022), lastDate: DateTime(2100));
    if (d != null) setState(() => _from = DateTime(d.year, d.month, d.day));
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(context: context, initialDate: _to, firstDate: DateTime(2022), lastDate: DateTime(2100));
    if (d != null) setState(() => _to = DateTime(d.year, d.month, d.day, 23, 59, 59));
  }

  // يبني ملخصات للفترة للمستخدمين الموجودين حاليًا بحسب الفلاتر (خفيف مبدئيًا)
  Future<void> _buildSummariesForVisibleUsers() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // هنجلب المستخدمين بحسب الفروع/الشفت لو الفلاتر مش "all"
      Query<Map<String, dynamic>> uq = fs.collection('users').where('status', isEqualTo: 'approved');
      if (_branchId != 'all') uq = uq.where('primaryBranchId', isEqualTo: _branchId);
      if (_shiftId != 'all') uq = uq.where('assignedShiftId', isEqualTo: _shiftId);
      final users = await uq.get();
      final util = AttendanceUtils(fs);

      // حرس حدود بسيط (ما بين 1..62 يوم)
      final from = DateTime(_from.year, _from.month, _from.day);
      final to = DateTime(_to.year, _to.month, _to.day);
      int days = to.difference(from).inDays.abs() + 1;
      if (days > 62) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Range too large (max ~62 days).')));
        return;
      }

      for (final u in users.docs) {
        await util.ensureDailySummaryForRangeOne(uid: u.id, from: from, to: to);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Daily summaries built.')));
      setState(() {});
    } finally {
      setState(() => _busy = false);
    }
  }

  Query<Map<String, dynamic>> _query() {
    // نستخدم collectionGroup('users') داخل dailyAttendance
    // لازم يكون عند كل doc حقل 'date' (Timestamp) و 'day' (String)، وهو ما نكتبه في utils
    Query<Map<String, dynamic>> q = fs.collectionGroup('users')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(_from.year, _from.month, _from.day)))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(DateTime(_to.year, _to.month, _to.day, 23, 59, 59)))
        .orderBy('date', descending: true);

    if (_status != 'all' && _status != 'anomalies') {
      q = q.where('status', isEqualTo: _status);
    }
    if (_branchId != 'all') {
      q = q.where('branchId', isEqualTo: _branchId);
    }
    if (_shiftId != 'all') {
      q = q.where('shiftId', isEqualTo: _shiftId);
    }
    return q;
  }

  bool _matchesAnomaly(Map<String, dynamic> m) {
    if (_status != 'anomalies') return true; // لا نصفي هنا لو مش وضع anomalies
    final f = (m['flags'] ?? {}) as Map<String, dynamic>;
    final mi = (f['missingIn'] ?? false) == true;
    final mo = (f['missingOut'] ?? false) == true;
    final obi = (f['outBeforeIn'] ?? false) == true;
    return mi || mo || obi || (m['status'] == 'absent');
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'present': return Colors.green;
      case 'leave': return Colors.blue;
      case 'weekend': return Colors.grey;
      case 'holiday': return Colors.indigo;
      case 'absent': return Colors.red;
      default: return Colors.orange;
    }
  }

  String _branchName(String? id) {
    if (id == null || id.isEmpty) return '—';
    final found = _branches.firstWhere(
      (b) => b.id == id,
      orElse: () => DummyDoc('—'),
    );
    return found is DummyDoc ? '—' : ((found.data()['name'] ?? '').toString());
  }

  String _shiftName(String? id) {
    if (id == null || id.isEmpty) return '—';
    final found = _shifts.firstWhere(
      (s) => s.id == id,
      orElse: () => DummyDoc('—'),
    );
    return found is DummyDoc ? '—' : ((found.data()['name'] ?? '').toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Absences & Anomalies'),
        actions: [
          IconButton(
            tooltip: 'Build summaries',
            onPressed: _busy ? null : _buildSummariesForVisibleUsers,
            icon: const Icon(Icons.build),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(8, 10, 8, 6),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickFrom,
                    icon: const Icon(Icons.date_range),
                    label: Text('From: ${_from.year}-${_2(_from.month)}-${_2(_from.day)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickTo,
                    icon: const Icon(Icons.event),
                    label: Text('To: ${_to.year}-${_2(_to.month)}-${_2(_to.day)}'),
                  ),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _status,
                      items: const [
                        DropdownMenuItem(value: 'anomalies', child: Text('Anomalies only')),
                        DropdownMenuItem(value: 'all', child: Text('All statuses')),
                        DropdownMenuItem(value: 'absent', child: Text('Absent')),
                        DropdownMenuItem(value: 'present', child: Text('Present')),
                        DropdownMenuItem(value: 'leave', child: Text('Leave')),
                        DropdownMenuItem(value: 'weekend', child: Text('Weekend')),
                        DropdownMenuItem(value: 'holiday', child: Text('Holiday')),
                      ],
                      onChanged: (v) => setState(() => _status = v ?? 'anomalies'),
                    ),
                  ),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _branchId,
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All branches')),
                        ..._branches.map((b) => DropdownMenuItem(
                              value: b.id,
                              child: Text((b.data()['name'] ?? '').toString()),
                            )),
                      ],
                      onChanged: (v) => setState(() => _branchId = v ?? 'all'),
                    ),
                  ),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _shiftId,
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All shifts')),
                        ..._shifts.map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text((s.data()['name'] ?? '').toString()),
                            )),
                      ],
                      onChanged: (v) => setState(() => _shiftId = v ?? 'all'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query().snapshots(),
              builder: (context, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!s.hasData) return const Center(child: Text('No data'));
                final docs = s.data!.docs.where((d) => _matchesAnomaly(d.data())).toList();
                if (docs.isEmpty) return const Center(child: Text('Nothing to show with current filters.'));
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = docs[i].data();
                    final uid = (m['uid'] ?? '').toString();
                    final dayKey = (m['day'] ?? '').toString();
                    final status = (m['status'] ?? '').toString();
                    final f = (m['flags'] ?? {}) as Map<String, dynamic>;
                    final mi = (f['missingIn'] ?? false) == true;
                    final mo = (f['missingOut'] ?? false) == true;
                    final obi = (f['outBeforeIn'] ?? false) == true;
                    final brId = (m['branchId'] ?? '').toString();
                    final shId = (m['shiftId'] ?? '').toString();

                    return ListTile(
                      leading: CircleAvatar(backgroundColor: _statusColor(status)),
                      title: Text('$dayKey • $status'),
                      subtitle: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (mi) const Chip(label: Text('Missing IN')),
                          if (mo) const Chip(label: Text('Missing OUT')),
                          if (obi) const Chip(label: Text('OUT before IN')),
                          Chip(label: Text('Branch: ${_branchName(brId)}')),
                          Chip(label: Text('Shift: ${_shiftName(shId)}')),
                        ],
                      ),
                      trailing: FilledButton(
                        onPressed: () async {
                          final changed = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => ResolveAbsenceDialog(uid: uid, dayKey: dayKey),
                          );
                          if (changed == true && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated')));
                          }
                        },
                        child: const Text('Resolve'),
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

  String _2(int n) => n.toString().padLeft(2, '0');
}

// كائن بسيط لتجاوز البحث عندما لا نجد فرع/شيفت
class DummyDoc implements QueryDocumentSnapshot<Map<String, dynamic>> {
  DummyDoc(this._id);
  final String _id;
  @override noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override String get id => _id;
}
