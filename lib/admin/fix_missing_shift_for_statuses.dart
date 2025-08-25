import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// تصلّح attendance التي type فيها: absent/off/sick/leave
/// لو ناقصها shiftId/shiftName (وكذلك branchId لو حبيت).
class FixMissingShiftForStatusesScreen extends StatefulWidget {
  const FixMissingShiftForStatusesScreen({super.key});
  @override
  State<FixMissingShiftForStatusesScreen> createState() => _FixMissingShiftForStatusesScreenState();
}

class _FixMissingShiftForStatusesScreenState extends State<FixMissingShiftForStatusesScreen> {
  DateTime _from = DateTime(DateTime.now().year, 1, 1);
  DateTime _to   = DateTime.now();
  bool _dryRun = true;
  bool _running = false;

  int _scanned = 0, _would = 0, _updated = 0, _skipped = 0;
  final _samples = <String>[];
  String _log = '';

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  Future<void> _pick(DateTime init, bool from) async {
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2023,1,1), lastDate: DateTime(2100));
    if (d != null) setState(() => from ? _from = DateTime(d.year,d.month,d.day) : _to = DateTime(d.year,d.month,d.day));
  }

  bool _looksId(String s) => s.trim().length >= 16;

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _scanned = _would = _updated = _skipped = 0;
      _samples.clear(); _log = '';
    });

    try {
      // 1) خرائط shifts و users
      final shifts = await FirebaseFirestore.instance.collection('shifts').get();
      final shiftNameToId = {
        for (final d in shifts.docs) (d.data()['name'] ?? '').toString().trim().toLowerCase(): d.id
      };
      final shiftIdToName = {
        for (final d in shifts.docs) d.id : (d.data()['name'] ?? '').toString()
      };

      final users = await FirebaseFirestore.instance.collection('users').get();
      final userToShiftId = <String,String>{};
      final userToShiftName = <String,String>{};
      for (final u in users.docs) {
        final m = u.data();
        final sid = (m['assignedShiftId'] ?? m['shiftId'] ?? '').toString();
        final sname = (m['shiftName'] ?? '').toString();
        if (sid.isNotEmpty) userToShiftId[u.id] = sid;
        if (sname.isNotEmpty) userToShiftName[u.id] = sname;
      }

      // 2) امشِ على attendance للstatuses فقط
      final from = _ymd(_from), to = _ymd(_to);
      final col = FirebaseFirestore.instance.collection('attendance');
      final types = {'absent','off','sick','leave'};

      Query<Map<String, dynamic>> q = col
        .where('localDay', isGreaterThanOrEqualTo: from)
        .where('localDay', isLessThanOrEqualTo: to)
        .orderBy('localDay');

      DocumentSnapshot<Map<String,dynamic>>? cursor;
      while (true) {
        var pageQ = q.limit(400);
        if (cursor != null) pageQ = pageQ.startAfterDocument(cursor);
        final snap = await pageQ.get();
        if (snap.docs.isEmpty) break;
        cursor = snap.docs.last;

        WriteBatch? batch = _dryRun ? null : FirebaseFirestore.instance.batch();
        int ops = 0;

        for (final d in snap.docs) {
          final m = d.data(); _scanned++;

          final typ = (m['type'] ?? '').toString().toLowerCase();
          if (!types.contains(typ)) { _skipped++; continue; }

          final uid = (m['userId'] ?? m['userID'] ?? '').toString();
          String sid = (m['shiftId'] ?? '').toString();
          String sname = (m['shiftName'] ?? '').toString();

          String? newSid, newSname;

          if (!_looksId(sid)) {
            // جرّب من user
            final fromUserSid = userToShiftId[uid];
            if (fromUserSid != null && fromUserSid.isNotEmpty) {
              newSid = fromUserSid;
              newSname = shiftIdToName[newSid] ?? userToShiftName[uid] ?? sname;
            } else if (sname.isNotEmpty) {
              // جرّب تحويل الاسم إلى id
              final k = sname.trim().toLowerCase();
              if (shiftNameToId.containsKey(k)) {
                newSid = shiftNameToId[k];
                newSname = shiftIdToName[newSid] ?? sname;
              }
            }
          } else if (sname.isEmpty) {
            // عندنا id بس الاسم فاضي
            newSid = sid;
            newSname = shiftIdToName[sid] ?? sname;
          }

          if (newSid == null && newSname == null) { _skipped++; continue; }

          _would++;
          if (_samples.length < 80) {
            _samples.add('${m['localDay'] ?? ''} • $uid • $typ  '
              'shiftId: ${sid.isEmpty ? '∅' : sid} -> ${newSid ?? sid}  |  '
              'shiftName: ${sname.isEmpty ? '∅' : sname} -> ${newSname ?? sname}');
          }

          if (!_dryRun) {
            final data = <String,dynamic>{};
            if (newSid != null) data['shiftId'] = newSid;
            if (newSname != null) data['shiftName'] = newSname;
            data['updatedAt'] = FieldValue.serverTimestamp();
            batch!.set(d.reference, data, SetOptions(merge: true));
            ops++;
            if (ops >= 400) { await batch.commit(); _updated += ops; ops = 0; batch = FirebaseFirestore.instance.batch(); }
          }
        }

        if (!_dryRun && cursor != null) {
          await batch!.commit(); _updated += ops;
        }
        setState(() {}); // تحديث العدادات على الشاشة
      }

      setState(()=> _log = 'Done. scanned=$_scanned, would=$_would, updated=$_updated, skipped=$_skipped');
    } catch (e, st) {
      setState(()=> _log = 'ERROR: $e\n$st');
    } finally {
      setState(()=> _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin • Fix Missing Shift for Statuses'),
        actions: [
          IconButton(
            tooltip: _dryRun ? 'وضع تنفيذ فعلي' : 'تحليل فقط',
            onPressed: _running ? null : () => setState(()=> _dryRun = !_dryRun),
            icon: Icon(_dryRun ? Icons.visibility : Icons.build),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: _running?null:()=>_pick(_from,true), icon: const Icon(Icons.date_range), label: Text('From: ${_ymd(_from)}')),
              OutlinedButton.icon(onPressed: _running?null:()=>_pick(_to,false),  icon: const Icon(Icons.event),      label: Text('To:   ${_ymd(_to)}')),
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: _running ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.play_arrow),
                label: Text(_dryRun ? 'تحليل (بدون تعديل)' : 'تشغيل التصحيح الآن'),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              Chip(label: Text('Scanned: $_scanned')),
              Chip(label: Text(_dryRun ? 'Would change: $_would' : 'Updated: $_updated')),
              Chip(label: Text('Skipped: $_skipped')),
            ]),
            const Divider(),
            const Text('أمثلة (أول 80):'),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
                child: _samples.isEmpty
                    ? const Center(child: Text('اضغط تشغيل لعرض أمثلة'))
                    : ListView.builder(
                        itemCount: _samples.length,
                        itemBuilder: (_, i) => ListTile(dense: true, leading: Text('${i+1}.'), title: Text(_samples[i])),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(_log, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
