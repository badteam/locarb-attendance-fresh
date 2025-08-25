import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FixIdsScreen extends StatefulWidget {
  const FixIdsScreen({super.key});
  @override
  State<FixIdsScreen> createState() => _FixIdsScreenState();
}

class _FixIdsScreenState extends State<FixIdsScreen> {
  // نطاق التاريخ
  DateTime _from = DateTime(DateTime.now().year, 1, 1);
  DateTime _to   = DateTime.now();

  // خيارات
  bool _dryRun = true;                 // تحليل فقط
  bool _onlyNonDocId = true;           // صحّح فقط لو القيمة مش doc.id
  bool _includePunches = true;         // يشمل IN/OUT
  bool _includeStatuses = true;        // يشمل absent/off/sick/leave

  // حالة التنفيذ
  bool _running = false;
  int _scanned = 0, _would = 0, _updated = 0, _skipped = 0, _errors = 0;
  final _samples = <String>[];
  String _log = '';

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  bool _looksId(String s) => s.trim().length >= 16; // heuristic كفاية

  Future<void> _pick(DateTime init, bool from) async {
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2023,1,1), lastDate: DateTime(2100));
    if (d != null) setState(() => from ? _from = DateTime(d.year,d.month,d.day) : _to = DateTime(d.year,d.month,d.day));
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _scanned = _would = _updated = _skipped = _errors = 0;
      _samples.clear(); _log = '';
    });

    try {
      // 1) خرائط الماستر
      final shifts = await FirebaseFirestore.instance.collection('shifts').get();
      final branches = await FirebaseFirestore.instance.collection('branches').get();
      final users = await FirebaseFirestore.instance.collection('users').get();

      final shiftNameToId = {
        for (final d in shifts.docs) (d.data()['name'] ?? '').toString().trim().toLowerCase(): d.id
      };
      final shiftIdToName = {
        for (final d in shifts.docs) d.id : (d.data()['name'] ?? '').toString()
      };
      final branchNameToId = {
        for (final d in branches.docs) (d.data()['name'] ?? '').toString().trim().toLowerCase(): d.id
      };
      final branchIdToName = {
        for (final d in branches.docs) d.id : (d.data()['name'] ?? '').toString()
      };

      final userShiftId = <String,String>{};
      final userShiftName = <String,String>{};
      final userBranchId = <String,String>{};
      final userBranchName = <String,String>{};
      for (final u in users.docs) {
        final m = u.data();
        final sid = (m['assignedShiftId'] ?? m['shiftId'] ?? '').toString();
        final sname = (m['shiftName'] ?? '').toString();
        final bid = (m['primaryBranchId'] ?? m['branchId'] ?? '').toString();
        final bname = (m['branchName'] ?? '').toString();
        if (sid.isNotEmpty) userShiftId[u.id] = sid;
        if (sname.isNotEmpty) userShiftName[u.id] = sname;
        if (bid.isNotEmpty) userBranchId[u.id] = bid;
        if (bname.isNotEmpty) userBranchName[u.id] = bname;
      }

      // 2) استعلام attendance
      final from = _ymd(_from), to = _ymd(_to);
      final col = FirebaseFirestore.instance.collection('attendance');
      Query<Map<String, dynamic>> q = col
        .where('localDay', isGreaterThanOrEqualTo: from)
        .where('localDay', isLessThanOrEqualTo: to)
        .orderBy('localDay');

      DocumentSnapshot<Map<String,dynamic>>? cursor;
      while (true) {
        var page = q.limit(400);
        if (cursor != null) page = page.startAfterDocument(cursor);
        final snap = await page.get();
        if (snap.docs.isEmpty) break;
        cursor = snap.docs.last;

        WriteBatch? batch = _dryRun ? null : FirebaseFirestore.instance.batch();
        int ops = 0;

        for (final d in snap.docs) {
          final m = d.data(); _scanned++;

          final type = (m['type'] ?? '').toString().toLowerCase();
          final isPunch = type == 'in' || type == 'out';
          final isStatus = type == 'absent' || type == 'off' || type == 'sick' || type == 'leave';

          if ((isPunch && !_includePunches) || (isStatus && !_includeStatuses)) { _skipped++; continue; }

          final uid = (m['userId'] ?? m['userID'] ?? '').toString();

          String sid  = (m['shiftId'] ?? '').toString();
          String sname= (m['shiftName'] ?? '').toString();
          String bid  = (m['branchId'] ?? '').toString();
          String bname= (m['branchName'] ?? '').toString();

          // قرارات الإصلاح
          String? newSid, newSname, newBid, newBname;

          // shiftId
          final sidLooksId = _looksId(sid);
          final needFixSid = _onlyNonDocId ? !sidLooksId : (!sidLooksId || !shiftIdToName.containsKey(sid));
          if (needFixSid) {
            // 1) من اسم الشفت في السجل
            if (sname.isNotEmpty) {
              final key = sname.trim().toLowerCase();
              if (shiftNameToId.containsKey(key)) {
                newSid = shiftNameToId[key];
                newSname = shiftIdToName[newSid] ?? sname;
              }
            }
            // 2) من بيانات المستخدم
            newSid ??= userShiftId[uid];
            if (newSid != null && (newSname == null || newSname.isEmpty)) {
              newSname = shiftIdToName[newSid] ?? userShiftName[uid] ?? sname;
            }
          } else if (sname.isEmpty) {
            // عندنا id صحيح لكن الاسم فاضي
            newSid = sid;
            newSname = shiftIdToName[sid] ?? sname;
          }

          // branchId
          final bidLooksId = _looksId(bid);
          final needFixBid = _onlyNonDocId ? !bidLooksId : (!bidLooksId || !branchIdToName.containsKey(bid));
          if (needFixBid) {
            if (bname.isNotEmpty) {
              final key = bname.trim().toLowerCase();
              if (branchNameToId.containsKey(key)) {
                newBid = branchNameToId[key];
                newBname = branchIdToName[newBid] ?? bname;
              }
            }
            newBid ??= userBranchId[uid];
            if (newBid != null && (newBname == null || newBname.isEmpty)) {
              newBname = branchIdToName[newBid] ?? userBranchName[uid] ?? bname;
            }
          } else if (bname.isEmpty) {
            newBid = bid;
            newBname = branchIdToName[bid] ?? bname;
          }

          if (newSid == null && newSname == null && newBid == null && newBname == null) {
            _skipped++; continue;
          }

          _would++;
          if (_samples.length < 80) {
            _samples.add('${m['localDay'] ?? ''} • $uid • $type'
              ' | shiftId: ${sid.isEmpty ? '∅' : sid} -> ${newSid ?? sid}'
              ' | branchId: ${bid.isEmpty ? '∅' : bid} -> ${newBid ?? bid}');
          }

          if (!_dryRun) {
            final data = <String,dynamic>{};
            if (newSid != null)   data['shiftId'] = newSid;
            if (newSname != null) data['shiftName'] = newSname;
            if (newBid != null)   data['branchId'] = newBid;
            if (newBname != null) data['branchName'] = newBname;
            data['updatedAt'] = FieldValue.serverTimestamp();

            batch!.set(d.reference, data, SetOptions(merge: true));
            ops++;
            if (ops >= 400) {
              await batch.commit(); _updated += ops; ops = 0;
              batch = FirebaseFirestore.instance.batch();
            }
          }
        }

        if (!_dryRun && cursor != null) {
          await batch!.commit();
          _updated += ops;
        }

        setState(() {}); // تحديث العدادات
      }

      setState(()=> _log = 'Done. scanned=$_scanned, would=$_would, updated=$_updated, skipped=$_skipped, errors=$_errors');
    } catch (e, st) {
      _errors++;
      setState(()=> _log = 'ERROR: $e\n$st');
    } finally {
      setState(()=> _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin • Fix Legacy IDs'),
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
              FilterChip(
                label: const Text('فقط القيم غير doc.id'),
                selected: _onlyNonDocId,
                onSelected: _running ? null : (v)=>setState(()=>_onlyNonDocId = v),
              ),
              FilterChip(
                label: const Text('IN/OUT'),
                selected: _includePunches,
                onSelected: _running ? null : (v)=>setState(()=>_includePunches = v),
              ),
              FilterChip(
                label: const Text('absent/off/sick/leave'),
                selected: _includeStatuses,
                onSelected: _running ? null : (v)=>setState(()=>_includeStatuses = v),
              ),
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
              Chip(label: Text('Errors: $_errors')),
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
