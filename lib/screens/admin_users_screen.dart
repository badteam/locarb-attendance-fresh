// lib/screens/admin_users_screen.dart
import 'dart:convert';
import 'dart:html' as html show Blob, Url, AnchorElement, document;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab; // 0=pending, 1=approved, 2=absences
  String get _statusTab =>
      _tab.index == 0 ? 'pending' : _tab.index == 1 ? 'approved' : 'approved';

  // ====== فلاتر وبحث (للتبويبين الأولين) ======
  final _searchCtrl = TextEditingController();
  String _roleFilter = 'all';
  String _branchFilterId = 'all';
  String _shiftFilterId = 'all';

  // مرجع أسماء الفروع/الشفتات
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _branches = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _shifts = [];
  final Map<String, String> _branchNames = {}; // {branchId: branchName}
  final Map<String, String> _shiftNames = {}; // {shiftId: shiftName}

  static const List<String> kRoles = [
    'all',
    'employee',
    'supervisor',
    'branch_manager',
    'admin',
  ];

  // ======= حالة تبويب Absences (Cards + Detail) =======
  DateTimeRange? _range;
  String _absBranchFilterId = 'all';
  String _absShiftFilterId = 'all';
  final _absSearchCtrl = TextEditingController();
  bool _absLoading = false;

  // كروت الموظفين المجمّعة
  List<_AbsAgg> _absCards = [];

  // users approved
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _usersApproved = [];

  // إعدادات ويك إند/عطلات (لتوليد غياب تلقائي اختياريًا)
  final Set<int> _weekendDays = {6, 7}; // سبت/أحد
  final Set<String> _holidays = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() {
      setState(() {});
      if (_tab.index == 2) _ensureAbsencesInit();
    });
    _loadRefs();
    _loadBranchNamesOnce();
    _loadShiftNamesOnce();

    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _absSearchCtrl.dispose();
    super.dispose();
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

  Future<void> _loadBranchNamesOnce() async {
    if (_branchNames.isNotEmpty) return;
    final qs = await FirebaseFirestore.instance.collection('branches').get();
    for (final d in qs.docs) {
      _branchNames[d.id] = (d.data()['name'] ?? '').toString();
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadShiftNamesOnce() async {
    if (_shiftNames.isNotEmpty) return;
    final qs = await FirebaseFirestore.instance.collection('shifts').get();
    for (final d in qs.docs) {
      _shiftNames[d.id] = (d.data()['name'] ?? '').toString();
    }
    if (mounted) setState(() {});
  }

  String _branchLabelFor(String? id) {
    if (id == null || id.isEmpty) return 'No branch';
    return _branchNames[id] ?? 'No branch';
  }

  String _shiftLabelFor(String? id) {
    if (id == null || id.isEmpty) return 'No shift';
    return _shiftNames[id] ?? 'No shift';
  }

  // ========== USERS QUERY/FILTERS ==========
  Query<Map<String, dynamic>> _usersQuery() {
    var q = FirebaseFirestore.instance
        .collection('users')
        .where('status', isEqualTo: _statusTab);
    return q.orderBy('fullName', descending: false);
  }

  bool _matchesFilters(Map<String, dynamic> m) {
    final role = (m['role'] ?? 'employee').toString();
    final branchId = (m['primaryBranchId'] ?? m['branchId'] ?? '').toString();
    final shiftId = (m['assignedShiftId'] ?? m['shiftId'] ?? '').toString();

    final okRole = _roleFilter == 'all' || _roleFilter == role;
    final okBr = _branchFilterId == 'all' || _branchFilterId == branchId;
    final okSh = _shiftFilterId == 'all' || _shiftFilterId == shiftId;

    final q = _searchCtrl.text.trim().toLowerCase();
    final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? '')
        .toString()
        .toLowerCase();
    final email = (m['email'] ?? '').toString().toLowerCase();
    final okSearch = q.isEmpty || name.contains(q) || email.contains(q);

    return okRole && okBr && okSh && okSearch;
  }

  // ========== MUTATIONS ==========
  Future<void> _updateUser(String uid, Map<String, dynamic> data) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _changeStatus(String uid, String to) =>
      _updateUser(uid, {'status': to});
  Future<void> _changeRole(String uid, String to) =>
      _updateUser(uid, {'role': to});

  Future<void> _assignBranch(String uid) async {
    final chosen = await showDialog<String?>(
      context: context,
      builder: (_) => _SelectDialog(
        title: 'Assign Branch',
        items: _branches
            .map((b) =>
                _SelectItem(id: b.id, label: (b.data()['name'] ?? '').toString()))
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _updateUser(uid, {
      'primaryBranchId': chosen,
      'branchId': chosen,
      'branchName': _branchLabelFor(chosen),
    });
  }

  Future<void> _assignShift(String uid) async {
    final chosen = await showDialog<String?>(
      context: context,
      builder: (_) => _SelectDialog(
        title: 'Assign Shift',
        items: _shifts
            .map((s) =>
                _SelectItem(id: s.id, label: (s.data()['name'] ?? '').toString()))
            .toList(),
      ),
    );
    if (chosen == null) return;
    await _updateUser(uid, {
      'assignedShiftId': chosen,
      'shiftId': chosen,
      'shiftName': _shiftLabelFor(chosen),
    });
  }

  Future<void> _toggleAllowAnyBranch(String uid, bool v) =>
      _updateUser(uid, {'allowAnyBranch': v});

  Future<void> _editPayrollBasic(String uid, Map<String, dynamic> user) async {
    final m = user;
    final base = TextEditingController(text: (m['salaryBase'] ?? 0).toString());
    final allow =
        TextEditingController(text: (m['allowances'] ?? 0).toString());
    final ded = TextEditingController(text: (m['deductions'] ?? 0).toString());
    final otAmt =
        TextEditingController(text: (m['overtimeAmount'] ?? 0).toString());

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Payroll (basic)'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Base salary', base),
              const SizedBox(height: 8),
              _field('Allowances (sum)', allow),
              const SizedBox(height: 8),
              _field('Deductions (sum)', ded),
              const SizedBox(height: 8),
              _field('Overtime amount (month)', otAmt),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              final b = double.tryParse(base.text.trim()) ?? 0;
              final a = double.tryParse(allow.text.trim()) ?? 0;
              final d = double.tryParse(ded.text.trim()) ?? 0;
              final o = double.tryParse(otAmt.text.trim()) ?? 0;
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .set({
                'salaryBase': b,
                'allowances': a,
                'deductions': d,
                'overtimeAmount': o,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c) {
    return TextField(
      controller: c,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder()),
    );
  }

  // ========== EXPORT CSV (users) ==========
  String _csvEscape(String v) {
    final s = v.replaceAll('"', '""');
    return '"$s"';
  }

  Future<void> _exportUsersCsvPressed() async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('CSV export works on Web builds only.'),
      ));
      return;
    }

    final qs = await _usersQuery().get();
    final users =
        qs.docs.where((d) => _matchesFilters(d.data())).toList();

    final rows = <List<String>>[
      [
        'ID',
        'Name',
        'Role',
        'Branch name',
        'Shift name',
        'Base salary',
        'Allowance',
        'Deduction',
        'Overtime amount',
        'Total salary',
      ],
    ];

    for (final d in users) {
      final m = d.data();
      final uid = d.id;
      final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? m['email'] ?? '')
          .toString();
      final role = (m['role'] ?? 'employee').toString();

      final brName = (m['branchName'] ??
              _branchLabelFor((m['primaryBranchId'] ?? m['branchId'] ?? '').toString()))
          .toString();
      final shName = (m['shiftName'] ??
              _shiftLabelFor((m['assignedShiftId'] ?? m['shiftId'] ?? '').toString()))
          .toString();

      final base = _toNum(m['salaryBase']);
      final allow = _toNum(m['allowances']);
      final ded = _toNum(m['deductions']);
      final otAmount = _toNum(m['overtimeAmount']);

      final total = base + allow + otAmount - ded;

      rows.add([
        uid,
        name,
        role,
        brName,
        shName,
        _fmt(base),
        _fmt(allow),
        _fmt(ded),
        _fmt(otAmount),
        _fmt(total),
      ]);
    }

    final csv = rows.map((r) => r.map(_csvEscape).join(',')).join('\n');
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final now = DateTime.now();
    final fileName =
        'users_${_statusTab}_role-${_roleFilter}_branch-${_branchFilterId}_shift-${_shiftFilterId}_${now.year}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}.csv';

    final a = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..style.display = 'none';
    html.document.body!.append(a);
    a.click();
    a.remove();
    html.Url.revokeObjectUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('CSV exported')));
    }
  }

  double _toNum(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }

  String _fmt(num v) => v is int ? v.toString() : v.toStringAsFixed(2);

  // ================== ABSENCES (Cards + Detail) ==================
  Future<void> _ensureAbsencesInit() async {
    if (_usersApproved.isEmpty) {
      final us = await FirebaseFirestore.instance
          .collection('users')
          .where('status', isEqualTo: 'approved')
          .orderBy('fullName')
          .get();
      _usersApproved = us.docs;
    }
    await _loadAbsencesData();
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadAbsencesData() async {
    if (_range == null) return;
    setState(() => _absLoading = true);

    try {
      final fromStr = _dayKey(_range!.start);
      final toStr = _dayKey(_range!.end);

      // هنجلب كل الأيام للفترة ونفلتر محليًا حسب النوع
      final qs = await FirebaseFirestore.instance
          .collection('attendance')
          .where('localDay', isGreaterThanOrEqualTo: fromStr)
          .where('localDay', isLessThanOrEqualTo: toStr)
          .orderBy('localDay')
          .get();

      final Map<String, Map<String, Map<String, dynamic>>> perUser = {};

      for (final d in qs.docs) {
        final m = d.data();
        final userId = (m['userId'] ?? '').toString();
        if (userId.isEmpty) continue;

        final branchId = (m['branchId'] ?? '').toString();
        final shiftId = (m['shiftId'] ?? '').toString();

        if (_absBranchFilterId != 'all' && branchId != _absBranchFilterId) {
          continue;
        }
        if (_absShiftFilterId != 'all' && shiftId != _absShiftFilterId) {
          continue;
        }

        final localDay = (m['localDay'] ?? '').toString();
        if (localDay.isEmpty) continue;

        perUser.putIfAbsent(userId, () => {});
        perUser[userId]!.putIfAbsent(localDay, () {
          return {
            'hasIn': false,
            'hasOut': false,
            'isAbsent': false,
            'userName': (m['userName'] ?? '').toString(),
            'branchId': branchId,
            'branchName': (m['branchName'] ?? _branchLabelFor(branchId)).toString(),
            'shiftId': shiftId,
            'shiftName': (m['shiftName'] ?? _shiftLabelFor(shiftId)).toString(),
          };
        });

        final t = (m['type'] ?? '').toString();
        if (t == 'in') perUser[userId]![localDay]!['hasIn'] = true;
        if (t == 'out') perUser[userId]![localDay]!['hasOut'] = true;
        if (t == 'absent') perUser[userId]![localDay]!['isAbsent'] = true;
      }

      final List<_AbsAgg> cards = [];
      final searchTxt = _absSearchCtrl.text.trim().toLowerCase();

      perUser.forEach((uid, daysMap) {
        if (daysMap.isEmpty) return;

        final any = daysMap.values.first;
        final userName = (any['userName'] ?? '').toString();
        final branchId = (any['branchId'] ?? '').toString();
        final branchName =
            (any['branchName'] ?? _branchLabelFor(branchId)).toString();
        final shiftId = (any['shiftId'] ?? '').toString();
        final shiftName =
            (any['shiftName'] ?? _shiftLabelFor(shiftId)).toString();

        int absent = 0, missIn = 0, missOut = 0;

        daysMap.forEach((_, v) {
          final hasIn = v['hasIn'] == true;
          final hasOut = v['hasOut'] == true;
          final isAbs = v['isAbsent'] == true;

          if (hasIn && hasOut) {
            // present — مفيش مشكلة
          } else if (hasIn && !hasOut) {
            missOut++;
          } else if (!hasIn && hasOut) {
            missIn++;
          } else if (isAbs) {
            absent++;
          }
        });

        final hay = '$uid $userName $branchName $shiftName'.toLowerCase();
        if (searchTxt.isNotEmpty && !hay.contains(searchTxt)) return;
        if (absent == 0 && missIn == 0 && missOut == 0) return;

        cards.add(_AbsAgg(
          uid: uid,
          userName: userName,
          branchId: branchId,
          branchName: branchName,
          shiftId: shiftId,
          shiftName: shiftName,
        )
          ..absent = absent
          ..missingIn = missIn
          ..missingOut = missOut);
      });

      cards.sort((a, b) {
        final ca = (b.absent + b.missingIn + b.missingOut)
            .compareTo(a.absent + a.missingIn + a.missingOut);
        if (ca != 0) return ca;
        return (a.userName).compareTo(b.userName);
      });

      setState(() {
        _absCards = cards;
        _absLoading = false;
      });
    } catch (e) {
      setState(() => _absLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Load absences failed: $e')),
      );
    }
  }

  // فتح تفاصيل موظف
  Future<void> _openUserExceptions(_AbsAgg a) async {
    if (_range == null) return;

    final fromStr = _dayKey(_range!.start);
    final toStr = _dayKey(_range!.end);

    final qs = await FirebaseFirestore.instance
        .collection('attendance')
        .where('localDay', isGreaterThanOrEqualTo: fromStr)
        .where('localDay', isLessThanOrEqualTo: toStr)
        .orderBy('localDay')
        .get();

    final Map<String, Map<String, dynamic>> days = {};

    for (final d in qs.docs) {
      final m = d.data();
      if ((m['userId'] ?? '').toString() != a.uid) continue;

      final localDay = (m['localDay'] ?? '').toString();
      if (localDay.isEmpty) continue;

      days.putIfAbsent(localDay, () => {
            'hasIn': false,
            'hasOut': false,
            'isAbsent': false,
            'inAt': null,
            'outAt': null,
          });

      final t = (m['type'] ?? '').toString();
      if (t == 'in') {
        days[localDay]!['hasIn'] = true;
        final ts = m['at'];
        if (ts is Timestamp) days[localDay]!['inAt'] = ts.toDate();
      }
      if (t == 'out') {
        days[localDay]!['hasOut'] = true;
        final ts = m['at'];
        if (ts is Timestamp) days[localDay]!['outAt'] = ts.toDate();
      }
      if (t == 'absent') {
        days[localDay]!['isAbsent'] = true;
      }
    }

    final details = <_AbsDetailRow>[];
    days.forEach((ld, v) {
      final parts = ld.split('-');
      final y = int.tryParse(parts.elementAt(0)) ?? 1970;
      final mo = int.tryParse(parts.elementAt(1)) ?? 1;
      final da = int.tryParse(parts.elementAt(2)) ?? 1;
      final date = DateTime(y, mo, da);

      details.add(_AbsDetailRow(
        uid: a.uid,
        userName: a.userName,
        branchName: a.branchName,
        shiftName: a.shiftName,
        date: date,
        localDay: ld,
        hasIn: v['hasIn'] == true,
        hasOut: v['hasOut'] == true,
        isAbsent: v['isAbsent'] == true,
        inAt: v['inAt'] is DateTime ? v['inAt'] as DateTime : null,
        outAt: v['outAt'] is DateTime ? v['outAt'] as DateTime : null,
      ));
    });

    details.sort((x, y) => y.date.compareTo(x.date));

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (context, ctrl) => Scaffold(
          appBar:
              AppBar(title: Text(a.userName.isEmpty ? a.uid : a.userName)),
          body: ListView.builder(
            controller: ctrl,
            itemCount: details.length,
            itemBuilder: (_, i) => _detailTile(details[i]),
          ),
        ),
      ),
    );

    await _loadAbsencesData();
  }

  // ======== وقت مخصص: Pickers + دمج التاريخ بالوقت ========
  Future<TimeOfDay?> _pickTime(BuildContext context, {required String title}) async {
    return showTimePicker(
      context: context,
      helpText: title,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    // ملاحظة: ممكن تستخدم intl لو عايز تنسيق 12/24 أو Locale
  }

  DateTime _combineDateTime(DateTime date, TimeOfDay tod) {
    return DateTime(date.year, date.month, date.day, tod.hour, tod.minute);
  }

  // إضافة IN/OUT — تقبل وقت مخصّص (إن وُجد) + حذف absent
  Future<void> _addPunch(
    _AbsDetailRow r, {
    bool addIn = false,
    bool addOut = false,
    DateTime? inAtOverride,
    DateTime? outAtOverride,
  }) async {
    final defaultIn  = DateTime(r.date.year, r.date.month, r.date.day, 9, 0);
    final defaultOut = DateTime(r.date.year, r.date.month, r.date.day, 17, 0);

    final inAt  = inAtOverride  ?? defaultIn;
    final outAt = outAtOverride ?? defaultOut;

    final col = FirebaseFirestore.instance.collection('attendance');
    final batch = FirebaseFirestore.instance.batch();

    if (addIn) {
      batch.set(
        col.doc('${r.uid}_${r.localDay}_in'),
        {
          'userId': r.uid,
          'userName': r.userName,
          'branchName': r.branchName,
          'shiftName': r.shiftName,
          'localDay': r.localDay,
          'type': 'in',
          'at': Timestamp.fromDate(inAt),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    if (addOut) {
      batch.set(
        col.doc('${r.uid}_${r.localDay}_out'),
        {
          'userId': r.uid,
          'userName': r.userName,
          'branchName': r.branchName,
          'shiftName': r.shiftName,
          'localDay': r.localDay,
          'type': 'out',
          'at': Timestamp.fromDate(outAt),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    // احذف مستند الغياب (لو موجود)
    try {
      await col.doc('${r.uid}_${r.localDay}_absent').delete();
    } catch (_) {}
  }

  Future<void> _markPresentDay(_AbsDetailRow r) async {
    await _addPunch(r, addIn: true, addOut: true);
    await _deleteAbsentDoc(r, silent: true);
  }

  Future<void> _deleteAbsentDoc(_AbsDetailRow r, {bool silent = false}) async {
    final id = '${r.uid}_${r.localDay}_absent';
    final ref = FirebaseFirestore.instance.collection('attendance').doc(id);
    final snap = await ref.get();
    if (snap.exists) await ref.delete();
    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Absence deleted')));
    }
  }

  // Backfill
  Future<void> _backfillAllAbsencesForRange() async {
    if (_range == null) return;
    setState(() => _absLoading = true);

    try {
      final users = await _getApprovedUsersFiltered();
      for (final u in users) {
        final uid = u.id;
        await _backfillAbsents(
          uid: uid,
          from: DateTime(_range!.start.year, _range!.start.month, _range!.start.day),
          to: DateTime(_range!.end.year, _range!.end.month, _range!.end.day),
          weekendDays: _weekendDays,
          holidays: _holidays,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backfill completed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backfill failed: $e')),
        );
      }
    } finally {
      await _loadAbsencesData();
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _getApprovedUsersFiltered() async {
    var q = FirebaseFirestore.instance
        .collection('users')
        .where('status', isEqualTo: 'approved');
    final qs = await q.get();
    final list = qs.docs.where((d) {
      final m = d.data();
      final br = (m['primaryBranchId'] ?? m['branchId'] ?? '').toString();
      final sh = (m['assignedShiftId'] ?? m['shiftId'] ?? '').toString();
      if (_absBranchFilterId != 'all' && br != _absBranchFilterId) return false;
      if (_absShiftFilterId != 'all' && sh != _absShiftFilterId) return false;
      return true;
    }).toList();
    return list;
  }

  Future<void> _backfillAbsents({
    required String uid,
    required DateTime from,
    required DateTime to,
    required Set<int> weekendDays,
    required Set<String> holidays,
  }) async {
    final col = FirebaseFirestore.instance.collection('attendance');

    for (var d = DateTime(from.year, from.month, from.day);
        !d.isAfter(to);
        d = d.add(const Duration(days: 1))) {
      final dayKey = _dayKey(d);

      final isWeekend = weekendDays.contains(d.weekday);
      final isHoliday = holidays.contains(dayKey);
      if (isWeekend || isHoliday) continue;

      final qs = await col
          .where('userId', isEqualTo: uid)
          .where('localDay', isEqualTo: dayKey)
          .get();

      final hasInOrOut = qs.docs.any((x) {
        final t = (x['type'] ?? '').toString();
        return t == 'in' || t == 'out';
      });
      final hasAbsent = qs.docs.any((x) => (x['type'] ?? '') == 'absent');

      if (!hasInOrOut && !hasAbsent) {
        await col.doc('${uid}_${dayKey}_absent').set({
          'userId': uid,
          'localDay': dayKey,
          'type': 'absent',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  // ================== BUILD ==================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users & Absences'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Absences'),
          ],
          onTap: (_) => setState(() {}),
        ),
        actions: [
          if (_tab.index != 2)
            IconButton(
              tooltip: 'Export CSV',
              onPressed: _exportUsersCsvPressed,
              icon: const Icon(Icons.download),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          if (_tab.index != 2) _filtersBarUsers(),
          if (_tab.index != 2) const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _usersTab(),
                _usersTab(),
                _absencesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ======== USERS TABS ========
  Widget _usersTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _usersQuery().snapshots(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs =
            s.data?.docs.where((d) => _matchesFilters(d.data())).toList() ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No users found.'));
        }

        final byBranch =
            <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final d in docs) {
          final m = d.data();
          final brId = (m['primaryBranchId'] ?? m['branchId'] ?? '').toString();
          byBranch.putIfAbsent(brId, () => []).add(d);
        }

        return ListView(
          children: byBranch.entries.map((entry) {
            final title =
                entry.key.isEmpty ? 'No branch' : _branchLabelFor(entry.key);
            final list = entry.value;
            final shownCount = list.length;
            return ExpansionTile(
              title: Text('$title — $shownCount user(s)'),
              children: list
                  .map((d) => _UserCard(
                        uid: d.id,
                        data: d.data(),
                        onChangeStatus: _changeStatus,
                        onChangeRole: _changeRole,
                        onAssignBranch: _assignBranch,
                        onAssignShift: _assignShift,
                        onToggleAllowAnyBranch: _toggleAllowAnyBranch,
                        onEditPayroll: _editPayrollBasic,
                      ))
                  .toList(),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _filtersBarUsers() {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      elevation: .5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name or email',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _roleFilter,
                items: kRoles
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r == 'all' ? 'All roles' : r),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _branchFilterId,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All branches')),
                  ..._branches.map((b) => DropdownMenuItem(
                        value: b.id,
                        child: Text((b.data()['name'] ?? '').toString()),
                      )),
                ],
                onChanged: (v) => setState(() => _branchFilterId = v ?? 'all'),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _shiftFilterId,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All shifts')),
                  ..._shifts.map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text((s.data()['name'] ?? '').toString()),
                      )),
                ],
                onChanged: (v) => setState(() => _shiftFilterId = v ?? 'all'),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _exportUsersCsvPressed,
              icon: const Icon(Icons.file_download),
              label: const Text('Export CSV'),
            ),
          ],
        ),
      ),
    );
  }

  // ======== ABSENCES TAB (Cards + Detail) ========
  Widget _absencesTab() {
    final isWide = MediaQuery.of(context).size.width > 900;
    return Column(
      children: [
        _filtersBarAbsences(),
        const Divider(height: 1),
        Expanded(
          child: _absLoading
              ? const Center(child: CircularProgressIndicator())
              : _absCards.isEmpty
                  ? const Center(child: Text('No exceptions for selected filters.'))
                  : Padding(
                      padding: const EdgeInsets.all(8),
                      child: isWide
                          ? GridView.count(
                              crossAxisCount: 3,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 3.4,
                              children: _absCards.map(_userAggCard).toList(),
                            )
                          : ListView.separated(
                              itemCount: _absCards.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => _userAggCard(_absCards[i]),
                            ),
                    ),
        ),
      ],
    );
  }

  Widget _filtersBarAbsences() {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      elevation: .5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2022),
                  lastDate: DateTime(2100),
                  initialDateRange: _range,
                );
                if (picked != null) setState(() => _range = picked);
              },
              icon: const Icon(Icons.date_range),
              label: Text(_range == null
                  ? 'Pick date range'
                  : '${_fmtD(_range!.start)} → ${_fmtD(_range!.end)}'),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _absBranchFilterId,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All branches')),
                  ..._branches.map((b) => DropdownMenuItem(
                        value: b.id,
                        child: Text((b.data()['name'] ?? '').toString()),
                      )),
                ],
                onChanged: (v) => setState(() => _absBranchFilterId = v ?? 'all'),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _absShiftFilterId,
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All shifts')),
                  ..._shifts.map((s) => DropdownMenuItem(
                        value: s.id,
                        child: Text((s.data()['name'] ?? '').toString()),
                      )),
                ],
                onChanged: (v) => setState(() => _absShiftFilterId = v ?? 'all'),
              ),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                controller: _absSearchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search (name / code / branch / shift)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _absLoading ? null : _loadAbsencesData,
              icon: const Icon(Icons.search),
              label: const Text('Apply'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _absLoading
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Backfill absences'),
                          content: const Text(
                              'سيتم إنشاء سجلات غياب لأي يوم عمل بلا IN/OUT في الفترة المختارة. هل تريد المتابعة؟'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Proceed')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await _backfillAllAbsencesForRange();
                      }
                    },
              icon: const Icon(Icons.build),
              label: const Text('Backfill absences'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userAggCard(_AbsAgg a) {
    final total = a.absent + a.missingIn + a.missingOut;
    return Card(
      child: ListTile(
        title: Text(a.userName.isEmpty ? a.uid : a.userName),
        subtitle: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            Chip(label: Text('Code: ${a.uid}')),
            if (a.branchName.isNotEmpty) Chip(label: Text('Branch: ${a.branchName}')),
            if (a.shiftName.isNotEmpty) Chip(label: Text('Shift: ${a.shiftName}')),
            Chip(
              label: Text('Absent: ${a.absent}'),
              backgroundColor: Colors.red,
              labelStyle: const TextStyle(color: Colors.white),
            ),
            Chip(
              label: Text('Missing IN: ${a.missingIn}'),
              backgroundColor: Colors.orange,
              labelStyle: const TextStyle(color: Colors.white),
            ),
            Chip(
              label: Text('Missing OUT: ${a.missingOut}'),
              backgroundColor: Colors.orange,
              labelStyle: const TextStyle(color: Colors.white),
            ),
            Chip(label: Text('Total: $total')),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openUserExceptions(a),
      ),
    );
  }

  Widget _detailTile(_AbsDetailRow r) {
    // لون الحالة العامة
    Color statusColor;
    String statusText = r.status;
    switch (r.status) {
      case 'absent':
        statusColor = Colors.red;
        break;
      case 'incomplete_in':
      case 'incomplete_out':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = Colors.green;
        statusText = 'Present';
    }

    final inChip = r.hasIn && r.inAt != null
        ? Chip(label: Text('IN ${_fmtTime(r.inAt!)}'))
        : const Chip(
            label: Text('Missing IN'),
            backgroundColor: Colors.orange,
            labelStyle: TextStyle(color: Colors.white),
          );

    final outChip = r.hasOut && r.outAt != null
        ? Chip(label: Text('OUT ${_fmtTime(r.outAt!)}'))
        : const Chip(
            label: Text('Missing OUT'),
            backgroundColor: Colors.orange,
            labelStyle: TextStyle(color: Colors.white),
          );

    return ListTile(
      title: Text(_fmtD(r.date)),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          Chip(
            label: Text(statusText),
            backgroundColor: statusColor,
            labelStyle: const TextStyle(color: Colors.white),
          ),
          inChip,
          outChip,
          Chip(label: Text('Branch: ${r.branchName}')),
          Chip(label: Text('Shift: ${r.shiftName}')),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'fix_in': {
              final tod = await _pickTime(context, title: 'اختر وقت الدخول (IN)');
              if (tod != null) {
                final when = _combineDateTime(r.date, tod);
                await _addPunch(r, addIn: true, inAtOverride: when);
                // تحديث محلي فوري
                r.hasIn = true;
                r.inAt = when;
                r.isAbsent = false;
                setState(() {});
              }
              break;
            }
            case 'fix_out': {
              final tod = await _pickTime(context, title: 'اختر وقت الخروج (OUT)');
              if (tod != null) {
                final when = _combineDateTime(r.date, tod);
                await _addPunch(r, addOut: true, outAtOverride: when);
                r.hasOut = true;
                r.outAt = when;
                r.isAbsent = false;
                setState(() {});
              }
              break;
            }
            case 'mark_present':
              await _markPresentDay(r);
              // تحديث محلي
              r.hasIn = true;
              r.hasOut = true;
              r.inAt ??= DateTime(r.date.year, r.date.month, r.date.day, 9, 0);
              r.outAt ??= DateTime(r.date.year, r.date.month, r.date.day, 17, 0);
              r.isAbsent = false;
              setState(() {});
              break;
            case 'delete_absent':
              await _deleteAbsentDoc(r);
              r.isAbsent = false;
              setState(() {});
              break;
          }
        },
        itemBuilder: (context) => [
          if (!r.hasIn)
            const PopupMenuItem(value: 'fix_in', child: Text('Fix IN (اختر الوقت)')),
          if (!r.hasOut)
            const PopupMenuItem(value: 'fix_out', child: Text('Fix OUT (اختر الوقت)')),
          const PopupMenuItem(value: 'mark_present', child: Text('Mark Present (create IN/OUT)')),
          if (r.isAbsent)
            const PopupMenuItem(value: 'delete_absent', child: Text('Delete absence')),
        ],
      ),
    );
  }

  String _fmtD(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

// ========== USER CARD ==========
class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.uid,
    required this.data,
    required this.onChangeStatus,
    required this.onChangeRole,
    required this.onAssignBranch,
    required this.onAssignShift,
    required this.onToggleAllowAnyBranch,
    required this.onEditPayroll,
  });

  final String uid;
  final Map<String, dynamic> data;

  final Future<void> Function(String uid, String to) onChangeStatus;
  final Future<void> Function(String uid, String to) onChangeRole;
  final Future<void> Function(String uid) onAssignBranch;
  final Future<void> Function(String uid) onAssignShift;
  final Future<void> Function(String uid, bool v) onToggleAllowAnyBranch;
  final Future<void> Function(String uid, Map<String, dynamic> m) onEditPayroll;

  @override
  Widget build(BuildContext context) {
    final name =
        (data['fullName'] ?? data['name'] ?? data['username'] ?? '')
            .toString();
    final email = (data['email'] ?? '').toString();
    final role = (data['role'] ?? 'employee').toString();
    final status = (data['status'] ?? 'pending').toString();

    final brName = (data['branchName'] ?? '').toString();
    final shName = (data['shiftName'] ?? '').toString();
    final allowAny = (data['allowAnyBranch'] ?? false) == true;

    final base = (data['salaryBase'] ?? 0);
    final allow = (data['allowances'] ?? 0);
    final ded = (data['deductions'] ?? 0);
    final otAmt = (data['overtimeAmount'] ?? 0);

    String _numTxt(dynamic v) {
      if (v is num) return v is int ? v.toString() : v.toStringAsFixed(2);
      final d = double.tryParse(v.toString()) ?? 0;
      return d.toStringAsFixed(2);
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
        ),
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                Chip(label: Text('Status: $status'), avatar: const Icon(Icons.verified, size: 16)),
                Chip(label: Text('Role: $role'), avatar: const Icon(Icons.badge, size: 16)),
                Chip(label: Text('Branch: ${brName.isEmpty ? '—' : brName}'), avatar: const Icon(Icons.store, size: 16)),
                Chip(label: Text('Shift: ${shName.isEmpty ? '—' : shName}'), avatar: const Icon(Icons.schedule, size: 16)),
                if (allowAny) const Chip(label: Text('Any branch'), avatar: Icon(Icons.public, size: 16)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              children: [
                Text('Base: ${_numTxt(base)}'),
                Text('Allowances: ${_numTxt(allow)}'),
                Text('Deductions: ${_numTxt(ded)}'),
                Text('OT amount: ${_numTxt(otAmt)}'),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'approve':
                await onChangeStatus(uid, 'approved');
                break;
              case 'pending':
                await onChangeStatus(uid, 'pending');
                break;
              case 'role_employee':
                await onChangeRole(uid, 'employee');
                break;
              case 'role_supervisor':
                await onChangeRole(uid, 'supervisor');
                break;
              case 'role_manager':
                await onChangeRole(uid, 'branch_manager');
                break;
              case 'role_admin':
                await onChangeRole(uid, 'admin');
                break;
              case 'assign_branch':
                await onAssignBranch(uid);
                break;
              case 'assign_shift':
                await onAssignShift(uid);
                break;
              case 'toggle_any':
                await onToggleAllowAnyBranch(uid, !(data['allowAnyBranch'] == true));
                break;
              case 'edit_payroll':
                await onEditPayroll(uid, data);
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'approve', child: Text('Mark Approved')),
            PopupMenuItem(value: 'pending', child: Text('Mark Pending')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'role_employee', child: Text('Role: Employee')),
            PopupMenuItem(value: 'role_supervisor', child: Text('Role: Supervisor')),
            PopupMenuItem(value: 'role_manager', child: Text('Role: Branch Manager')),
            PopupMenuItem(value: 'role_admin', child: Text('Role: Admin')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'assign_branch', child: Text('Assign Branch')),
            PopupMenuItem(value: 'assign_shift', child: Text('Assign Shift')),
            PopupMenuItem(value: 'toggle_any', child: Text('Toggle Allow Any Branch')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'edit_payroll', child: Text('Edit Payroll')),
          ],
        ),
      ),
    );
  }
}

// ====== Absences (models) ======
class _AbsAgg {
  final String uid;
  final String userName;
  final String branchId;
  final String branchName;
  final String shiftId;
  final String shiftName;
  int absent = 0;
  int missingIn = 0;  // عنده OUT بس مفيش IN
  int missingOut = 0; // عنده IN بس مفيش OUT

  _AbsAgg({
    required this.uid,
    required this.userName,
    required this.branchId,
    required this.branchName,
    required this.shiftId,
    required this.shiftName,
  });
}

class _AbsDetailRow {
  final String uid;
  final String userName;
  final String branchName;
  final String shiftName;
  DateTime date;
  String localDay;
  bool hasIn;
  bool hasOut;
  bool isAbsent;
  DateTime? inAt;
  DateTime? outAt;

  _AbsDetailRow({
    required this.uid,
    required this.userName,
    required this.branchName,
    required this.shiftName,
    required this.date,
    required this.localDay,
    required this.hasIn,
    required this.hasOut,
    required this.isAbsent,
    required this.inAt,
    required this.outAt,
  });

  // أولوية الحالة: present > incomplete > absent
  String get status {
    if (hasIn && hasOut) return 'present';
    if (hasIn && !hasOut) return 'incomplete_out';
    if (!hasIn && hasOut) return 'incomplete_in';
    if (isAbsent) return 'absent';
    return 'absent';
  }
}

// ========== SELECT DIALOG ==========
class _SelectItem {
  final String id;
  final String label;
  const _SelectItem({required this.id, required this.label});
}

class _SelectDialog extends StatefulWidget {
  const _SelectDialog({required this.title, required this.items});
  final String title;
  final List<_SelectItem> items;

  @override
  State<_SelectDialog> createState() => _SelectDialogState();
}

class _SelectDialogState extends State<_SelectDialog> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: DropdownButtonFormField<String>(
        value: _selected,
        items: widget.items
            .map((e) => DropdownMenuItem(value: e.id, child: Text(e.label)))
            .toList(),
        onChanged: (v) => setState(() => _selected = v),
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
