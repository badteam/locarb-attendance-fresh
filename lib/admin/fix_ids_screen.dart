import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// شاشة أدمِن: تصحيح الـ IDs في مجموعة attendance
/// - تعتمد على: وجود مجموعتي shifts و branches فيهما name (لعمل lookup)
/// - تعمل على دفعات Batch (<= 400) وت paginate لتفادي حدود فايرستور
/// - فيها وضع "تحليل فقط" (Dry-run) يعرض أمثلة قبل التنفيذ

class FixIdsScreen extends StatefulWidget {
  const FixIdsScreen({super.key});

  @override
  State<FixIdsScreen> createState() => _FixIdsScreenState();
}

class _FixIdsScreenState extends State<FixIdsScreen> {
  // نطاق التاريخ (localDay)
  DateTime _from = DateTime(DateTime.now().year, 1, 1);
  DateTime _to   = DateTime.now();

  // خيارات
  bool _onlyWhenShiftIdNotDocId  = true;  // صحح فقط لو shiftId مش doc.id
  bool _onlyWhenBranchIdNotDocId = true;  // صحح فقط لو branchId مش doc.id
  bool _dryRun = true;                    // تحليل فقط ولا كتابة؟

  // حالة التنفيذ
  bool _running = false;
  int _scanned = 0;
  int _wouldChange = 0;
  int _updated = 0;
  int _skipped = 0;
  int _errors  = 0;

  final List<String> _samples = []; // أمثلة للتغييرات
  String _log = '';

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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

  bool _looksLikeDocId(String s) => s.trim().length >= 16; // heuristic كفاية لتمييز ids

  Future<void> _runFix({required bool commit}) async {
    if (_running) return;
    setState(() {
      _running = true;
      _dryRun = !commit;
      _scanned = _wouldChange = _updated = _skipped = _errors = 0;
      _samples.clear();
      _log = '';
    });

    try {
      // 1) ابني خرائط الاسم -> id من shifts/branches
      final shifts = await FirebaseFirestore.instance.collection('shifts').get();
      final branches = await FirebaseFirestore.instance.collection('branches').get();

      final Map<String, String> shiftIdByName = {
        for (final d in shifts.docs)
          ((d.data()['name'] ?? '').toString().trim().toLowerCase()): d.id
      };
      final Map<String, String> branchIdByName = {
        for (final d in branches.docs)
          ((d.data()['name'] ?? '').toString().trim().toLowerCase()): d.id
      };

      // 2) امشِ على attendance بالصفحات
      final col = FirebaseFirestore.instance.collection('attendance');
      final String fromStr = _ymd(_from);
      final String toStr   = _ymd(_to);

      Query<Map<String, dynamic>> q = col
          .where('localDay', isGreaterThanOrEqualTo: fromStr)
          .where('localDay', isLessThanOrEqualTo: toStr)
          .orderBy('localDay'); // مفروض يعمل بدون index مركّب

      DocumentSnapshot<Map<String, dynamic>>? cursor;
      int pages = 0;

      while (true) {
        var pageQ = q.limit(400);
        if (cursor != null) pageQ = pageQ.startAfterDocument(cursor);

        final snap = await pageQ.get();
        if (snap.docs.isEmpty) break;
        pages++;
        cursor = snap.docs.last;

        // Batch لكل صفحة
        WriteBatch? batch = commit ? FirebaseFirestore.instance.batch() : null;
        int opsInBatch = 0;

        for (final d in snap.docs) {
          _scanned++;

          final m = d.data();
          String sid  = (m['shiftId'] ?? '').toString();
          String sname= (m['shiftName'] ?? '').toString();
          String bid  = (m['branchId'] ?? '').toString();
          String bname= (m['branchName'] ?? '').toString();

          final bool sidLooksId = _looksLikeDocId(sid);
          final bool bidLooksId = _looksLikeDocId(bid);

          String? newSid;
          String? newBid;

          // قرر هل محتاج تصحيح للـ shiftId
          final needFixSid = _onlyWhenShiftIdNotDocId ? !sidLooksId : (!sidLooksId || !shiftIdByName.values.contains(sid));
          if (needFixSid) {
            final key = sname.trim().toLowerCase();
            if (key.isNotEmpty && shiftIdByName.containsKey(key)) {
              newSid = shiftIdByName[key];
            }
          }

          // قرر هل محتاج تصحيح للـ branchId
          final needFixBid = _onlyWhenBranchIdNotDocId ? !bidLooksId : (!bidLooksId || !branchIdByName.values.contains(bid));
          if (needFixBid) {
            final key = bname.trim().toLowerCase();
            if (key.isNotEmpty && branchIdByName.containsKey(key)) {
              newBid = branchIdByName[key];
            }
          }

          if (newSid == null && newBid == null) {
            _skipped++;
            continue;
          }

          _wouldChange++;

          if (_samples.length < 80) {
            _samples.add(
              '${m['localDay'] ?? ''} • ${m['userId'] ?? ''}  '
              'shiftId: ${sid.isEmpty ? '∅' : sid} -> ${newSid ?? sid}  |  '
              'branchId: ${bid.isEmpty ? '∅' : bid} -> ${newBid ?? bid}');
          }

          if (commit) {
            final data = <String, dynamic>{};
            if (newSid != null) data['shiftId'] = newSid;
            if (newBid != null) data['branchId'] = newBid;
            data['updatedAt'] = FieldValue.serverTimestamp();

            batch!.set(d.reference, data, SetOptions(merge: true));
            opsInBatch++;

            // حرّك batch لو قرب من الحد
            if (opsInBatch >= 400) {
              await batch.commit();
              _updated += opsInBatch;
              opsInBatch = 0;
              batch = FirebaseFirestore.instance.batch();
            }
          }
        }

        // commit المتبقي في الصفحة
        if (commit && opsInBatch > 0 && batch != null) {
          await batch.commit();
          _updated += opsInBatch;
        }

        setState(() {}); // تحديث العدادات في الـ UI
      }

      _log = 'Done. pages=$pages, scanned=$_scanned, wouldChange=$_wouldChange, '
             'updated=$_updated, skipped=$_skipped';
    } catch (e, st) {
      _errors++;
      _log = 'ERROR: $e\n$st';
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final btnText = _dryRun ? 'تحليل (بدون تعديل)' : 'تشغيل التصحيح الآن';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin • Fix Attendance IDs'),
        actions: [
          IconButton(
            tooltip: _dryRun ? 'سيدو تنفيذ (Dry-run)' : 'وضع تنفيذ فعلي',
            onPressed: _running ? null : () => setState(() => _dryRun = !_dryRun),
            icon: Icon(_dryRun ? Icons.visibility : Icons.build),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8, runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _running ? null : _pickFrom,
                  icon: const Icon(Icons.date_range),
                  label: Text('From: ${_ymd(_from)}'),
                ),
                OutlinedButton.icon(
                  onPressed: _running ? null : _pickTo,
                  icon: const Icon(Icons.event),
                  label: Text('To: ${_ymd(_to)}'),
                ),
                FilterChip(
                  label: const Text('صحح shiftId فقط لو مش doc.id'),
                  selected: _onlyWhenShiftIdNotDocId,
                  onSelected: _running ? null : (v) => setState(() => _onlyWhenShiftIdNotDocId = v),
                ),
                FilterChip(
                  label: const Text('صحح branchId فقط لو مش doc.id'),
                  selected: _onlyWhenBranchIdNotDocId,
                  onSelected: _running ? null : (v) => setState(() => _onlyWhenBranchIdNotDocId = v),
                ),
                FilledButton.icon(
                  onPressed: _running ? null : () async {
                    if (_dryRun) {
                      await _runFix(commit: false);
                    } else {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('تأكيد'),
                          content: const Text('سيتم تعديل السجلات في Firestore. متأكد؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، نفّذ')),
                          ],
                        ),
                      );
                      if (ok == true) await _runFix(commit: true);
                    }
                  },
                  icon: _running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
                  label: Text(btnText),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 12, children: [
              _Stat('Scanned', _scanned),
              _Stat(_dryRun ? 'Would change' : 'Updated', _dryRun ? _wouldChange : _updated),
              _Stat('Skipped', _skipped),
              _Stat('Errors', _errors),
            ]),
            const Divider(),
            const Text('Examples / Preview (أول 80 تغيير):'),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _samples.isEmpty
                    ? const Center(child: Text('لا توجد أمثلة بعد. اضغط "تحليل" أولاً.'))
                    : ListView.builder(
                        itemCount: _samples.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          leading: Text('${i + 1}.'),
                          title: Text(_samples[i]),
                        ),
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

class _Stat extends StatelessWidget {
  final String title;
  final int value;
  const _Stat(this.title, this.value);

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$title: $value'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    );
  }
}
