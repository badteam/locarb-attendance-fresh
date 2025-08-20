// lib/widgets/resolve_absence_dialog.dart
// Dialog لتصحيح يوم حضور + رفع إثبات صورة (ويب)

import 'dart:html' as html; // Web only
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ResolveAbsenceDialog extends StatefulWidget {
  const ResolveAbsenceDialog({
    super.key,
    required this.uid,
    required this.dayKey, // 'YYYY-MM-DD'
  });

  final String uid;
  final String dayKey;

  @override
  State<ResolveAbsenceDialog> createState() => _ResolveAbsenceDialogState();
}

class _ResolveAbsenceDialogState extends State<ResolveAbsenceDialog> {
  final _note = TextEditingController();
  String _status = 'present'; // present|leave|absent|weekend
  TimeOfDay? _inTime;
  TimeOfDay? _outTime;
  String? _branchId;
  String? _shiftId;
  String? _proofUrl;
  bool _busy = false;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _branches = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _shifts = [];

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    final fs = FirebaseFirestore.instance;
    final br = await fs.collection('branches').orderBy('name').get();
    final sh = await fs.collection('shifts').orderBy('name').get();
    setState(() {
      _branches = br.docs;
      _shifts = sh.docs;
    });
  }

  Future<void> _pickAndUploadProof() async {
    final input = html.FileUploadInputElement()..accept = 'image/*';
    input.click();
    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;
    final file = input.files!.first;
    final ext = file.name.split('.').last;
    final path = 'proofs/${widget.uid}/${widget.dayKey}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final ref = FirebaseStorage.instance.ref(path);
    setState(() => _busy = true);
    try {
      final snap = await ref.putBlob(file);
      final url = await snap.ref.getDownloadURL();
      setState(() => _proofUrl = url);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final fs = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;
      final adminUid = auth.currentUser?.uid ?? 'system';

      final day = DateTime.parse(widget.dayKey); // YYYY-MM-DD
      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final summaryRef = fs.collection('dailyAttendance').doc(widget.dayKey).collection('users').doc(widget.uid);

      // إعداد payload للملخص
      final payload = <String, dynamic>{
        'uid': widget.uid,
        'day': widget.dayKey,
        'date': Timestamp.fromDate(dayStart),
        'status': _status,
        'workedHours': 0.0,
        'flags': {
          'missingIn': false,
          'missingOut': false,
          'outBeforeIn': false,
          'outsideGeofence': false,
        },
        'proof': _proofUrl == null
            ? null
            : {
                'url': _proofUrl,
                'note': _note.text.trim(),
                'uploadedBy': adminUid,
                'uploadedAt': FieldValue.serverTimestamp(),
              },
        'branchId': _branchId,
        'shiftId': _shiftId,
        'source': 'manual',
        'editedBy': adminUid,
        'editedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // لو Present ومعانا IN/OUT نحسب ساعات ونضيف سجلات manual
      if (_status == 'present' && _inTime != null && _outTime != null) {
        final inTs = DateTime(day.year, day.month, day.day, _inTime!.hour, _inTime!.minute);
        final outTs = DateTime(day.year, day.month, day.day, _outTime!.hour, _outTime!.minute);
        final worked = outTs.difference(inTs).inMinutes / 60.0;
        payload['workedHours'] = worked < 0 ? 0.0 : worked;

        // نضيف Logs manual (اختياري لكنه مفضل لتناسق التقارير)
        await fs.collection('attendance').add({
          'userId': widget.uid,
          'type': 'in',
          'timestamp': Timestamp.fromDate(inTs),
          'branchId': _branchId,
          'shiftId': _shiftId,
          'source': 'manual',
          'note': _note.text.trim().isEmpty ? 'Manual correction: IN' : _note.text.trim(),
          'createdBy': adminUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await fs.collection('attendance').add({
          'userId': widget.uid,
          'type': 'out',
          'timestamp': Timestamp.fromDate(outTs),
          'branchId': _branchId,
          'shiftId': _shiftId,
          'source': 'manual',
          'note': _note.text.trim().isEmpty ? 'Manual correction: OUT' : _note.text.trim(),
          'createdBy': adminUid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await summaryRef.set(payload, SetOptions(merge: true));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickIn() async {
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (t != null) setState(() => _inTime = t);
  }

  Future<void> _pickOut() async {
    final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
    if (t != null) setState(() => _outTime = t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Resolve • ${widget.dayKey}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // الحالة
              DropdownButtonFormField<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'present', child: Text('Present')),
                  DropdownMenuItem(value: 'leave', child: Text('Leave')),
                  DropdownMenuItem(value: 'absent', child: Text('Absent')),
                  DropdownMenuItem(value: 'weekend', child: Text('Weekend')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'present'),
                decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),

              // لو Present: IN/OUT + Branch/Shift
              if (_status == 'present') ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickIn,
                        icon: const Icon(Icons.login),
                        label: Text(_inTime == null ? 'Pick IN' : 'IN ${_inTime!.format(context)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickOut,
                        icon: const Icon(Icons.logout),
                        label: Text(_outTime == null ? 'Pick OUT' : 'OUT ${_outTime!.format(context)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _branchId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— Branch —')),
                    ..._branches.map((b) => DropdownMenuItem(value: b.id, child: Text((b.data()['name'] ?? '').toString()))),
                  ],
                  onChanged: (v) => setState(() => _branchId = v),
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Branch'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _shiftId,
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— Shift —')),
                    ..._shifts.map((s) => DropdownMenuItem(value: s.id, child: Text((s.data()['name'] ?? '').toString()))),
                  ],
                  onChanged: (v) => setState(() => _shiftId = v),
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Shift'),
                ),
                const SizedBox(height: 10),
              ],

              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickAndUploadProof,
                      icon: const Icon(Icons.attachment),
                      label: Text(_proofUrl == null ? 'Attach proof' : 'Proof attached'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
      ],
    );
  }
}
