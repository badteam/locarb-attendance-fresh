// lib/screens/payroll_center_screen.dart
// Payroll Center v2 — 2025-08-27 15:40

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PayrollCenterScreen extends StatefulWidget {
  const PayrollCenterScreen({super.key});

  @override
  State<PayrollCenterScreen> createState() => _PayrollCenterScreenState();
}

class _PayrollCenterScreenState extends State<PayrollCenterScreen>
    with SingleTickerProviderStateMixin {
  static const String _versionLabel = 'Payroll Center v2 — 2025-08-27 15:40';

  late TabController _tab;
  String? _selectedUserId;
  String _search = '';

  // الشهر الحالي (مفتاح بصيغة YYYY-MM)
  late String _monthKey;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _monthKey = _fmtMonthKey(now);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ===== Utils =====
  String _fmtMonthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  DateTime _parseMonthKey(String mk) {
    final p = mk.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]));
  }

  String _numTxt(dynamic v) {
    if (v is num) return v is int ? v.toString() : v.toStringAsFixed(2);
    final d = double.tryParse(v.toString()) ?? 0;
    return d.toStringAsFixed(2);
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0;
    return 0;
  }

  DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  // تولتيب + Dialog ⓘ
  Widget _withInfo({
    required String label,
    required Widget field,
    String? tooltip,
    String? dialogTitle,
    String? dialogBody,
  }) {
    final icon = GestureDetector(
      onTap: (dialogTitle == null && dialogBody == null)
          ? null
          : () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(dialogTitle ?? label),
                  content: Text(dialogBody ?? tooltip ?? ''),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                  ],
                ),
              );
            },
      child: Tooltip(
        message: tooltip ?? label,
        child: CircleAvatar(
          radius: 10,
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          child: const Icon(Icons.info_outline, size: 14),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label),
          const SizedBox(width: 6),
          icon,
        ]),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  // ===== Firestore =====
  final _fs = FirebaseFirestore.instance;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _usersStream() {
    // نجيب كل المستخدمين ونفلتر بالبحث client-side
    return _fs.collection('users').orderBy('fullName', descending: false).snapshots().map(
      (s) => s.docs.where((d) {
        final m = d.data();
        final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? '').toString().toLowerCase();
        final email = (m['email'] ?? '').toString().toLowerCase();
        final q = _search.trim().toLowerCase();
        if (q.isEmpty) return true;
        return name.contains(q) || email.contains(q);
      }).toList(),
    );
  }

  // ===== BUILD =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll Center'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_versionLabel, style: Theme.of(context).textTheme.labelMedium),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Salaries'),
            Tab(text: 'Leaves'),
            Tab(text: 'Loans'),
          ],
        ),
      ),
      body: Column(
        children: [
          _userPicker(),
          const Divider(height: 1),
          Expanded(
            child: _selectedUserId == null
                ? const Center(child: Text('Select a user to manage payroll.'))
                : TabBarView(
                    controller: _tab,
                    children: [
                      _salariesTab(_selectedUserId!),
                      _leavesTab(_selectedUserId!),
                      _loansTab(_selectedUserId!),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ===== User Picker =====
  Widget _userPicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: _usersStream(),
        builder: (context, s) {
          final docs = s.data ?? [];
          final items = docs
              .map((d) {
                final m = d.data();
                final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? d.id).toString();
                final email = (m['email'] ?? '').toString();
                return DropdownMenuItem<String>(
                  value: d.id,
                  child: Text('$name  •  $email', overflow: TextOverflow.ellipsis),
                );
              })
              .toList();

          return Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 340,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search user by name or email',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  labelText: 'Select user',
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedUserId,
                    items: items,
                    onChanged: (v) => setState(() => _selectedUserId = v),
                    hint: const Text('Choose user'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===== Month picker row for Salaries tab =====
  Widget _monthPickerRow() {
    // نعرض آخر 18 شهرًا في الدروب داون
    final now = DateTime.now();
    final months = <String>[];
    for (int i = 0; i < 18; i++) {
      final d = DateTime(now.year, now.month - i);
      months.add(_fmtMonthKey(d));
    }

    void prev() {
      final d = _parseMonthKey(_monthKey);
      final p = DateTime(d.year, d.month - 1);
      setState(() => _monthKey = _fmtMonthKey(p));
    }

    void next() {
      final d = _parseMonthKey(_monthKey);
      final n = DateTime(d.year, d.month + 1);
      setState(() => _monthKey = _fmtMonthKey(n));
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(onPressed: prev, icon: const Icon(Icons.chevron_left)),
            DropdownButton<String>(
              value: _monthKey,
              items: months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => setState(() => _monthKey = v ?? _monthKey),
            ),
            IconButton(onPressed: next, icon: const Icon(Icons.chevron_right)),
            const SizedBox(width: 8),
            const Text('Select month for monthly items (Bonuses / OT / Deductions)'),
          ],
        ),
      ),
    );
  }

  // ===== Salaries Tab =====
  Widget _salariesTab(String uid) {
    final settingsRef = _fs.collection('payroll').doc(uid).collection('settings').doc('current');
    final monthRef = _fs.collection('payroll').doc(uid).collection('months').doc(_monthKey);

    return Column(
      children: [
        _monthPickerRow(),
        Expanded(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: settingsRef.snapshots(),
            builder: (context, sSettings) {
              final ms = sSettings.data?.data() ?? {};
              final baseCtrl = TextEditingController(text: _numTxt(ms['salaryBase'] ?? 0));
              final allowanceCtrl = TextEditingController(text: _numTxt(ms['allowances'] ?? 0));

              final base = _toDouble(baseCtrl.text);
              final allow = _toDouble(allowanceCtrl.text);

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: monthRef.snapshots(),
                builder: (context, sMonth) {
                  final mm = sMonth.data?.data() ?? {};
                  final bonusCtrl = TextEditingController(text: _numTxt(mm['bonuses'] ?? 0));
                  final overtimeCtrl = TextEditingController(text: _numTxt(mm['overtimeAmount'] ?? 0));
                  final deductionsCtrl = TextEditingController(text: _numTxt(mm['deductions'] ?? 0));

                  final bonus = _toDouble(bonusCtrl.text);
                  final ot = _toDouble(overtimeCtrl.text);
                  final ded = _toDouble(deductionsCtrl.text);

                  final monthTotal = base + allow + bonus + ot - ded;

                  Future<void> _saveSettings() async {
                    await settingsRef.set({
                      'salaryBase': _toDouble(baseCtrl.text),
                      'allowances': _toDouble(allowanceCtrl.text),
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
                    }
                  }

                  Future<void> _saveMonth() async {
                    await monthRef.set({
                      'bonuses': _toDouble(bonusCtrl.text),
                      'overtimeAmount': _toDouble(overtimeCtrl.text),
                      'deductions': _toDouble(deductionsCtrl.text),
                      'monthKey': _monthKey,
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved for month $_monthKey')));
                    }
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ===== Settings (once) =====
                        Text('Settings (one-time)', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12, runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 240,
                              child: _withInfo(
                                label: 'Base salary',
                                tooltip: 'الراتب الثابت الشهري — يُعدل عند الحاجة فقط',
                                field: TextField(
                                  controller: baseCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 240,
                              child: _withInfo(
                                label: 'Allowances',
                                tooltip: 'بدلات/علاوات ثابتة — تُعدل عند الحاجة فقط',
                                field: TextField(
                                  controller: allowanceCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.icon(
                                onPressed: _saveSettings,
                                icon: const Icon(Icons.save),
                                label: const Text('Save settings'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const Divider(),
                        const SizedBox(height: 12),

                        // ===== Monthly (per month) =====
                        Text('Monthly items for $_monthKey', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12, runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 220,
                              child: _withInfo(
                                label: 'Bonuses',
                                tooltip: 'مكافآت هذا الشهر',
                                field: TextField(
                                  controller: bonusCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: _withInfo(
                                label: 'Overtime amount',
                                tooltip: 'قيمة الأوفر تايم لهذا الشهر',
                                field: TextField(
                                  controller: overtimeCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: _withInfo(
                                label: 'Deductions',
                                tooltip: 'خصومات هذا الشهر',
                                field: TextField(
                                  controller: deductionsCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.icon(
                                onPressed: _saveMonth,
                                icon: const Icon(Icons.save),
                                label: Text('Save for $_monthKey'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Card(
                          elevation: .3,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Chip(label: Text('Base: ${_numTxt(base)}')),
                                Chip(label: Text('Allowances: ${_numTxt(allow)}')),
                                Chip(label: Text('Bonuses ($_monthKey): ${_numTxt(bonus)}')),
                                Chip(label: Text('OT ($_monthKey): ${_numTxt(ot)}')),
                                Chip(label: Text('Deductions ($_monthKey): ${_numTxt(ded)}')),
                                Text('Monthly total ($_monthKey): ${_numTxt(monthTotal)}',
                                    style: Theme.of(context).textTheme.titleMedium),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ===== Leaves Tab (كما هي) =====
  Widget _leavesTab(String uid) {
    final docRef = _fs.collection('leave_balances').doc(uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: docRef.snapshots(),
      builder: (context, s) {
        final m = s.data?.data() ?? {};
        final annualTotalCtrl = TextEditingController(text: _numTxt(m['annualTotal'] ?? 0));
        final annualUsedCtrl = TextEditingController(text: _numTxt(m['annualUsed'] ?? 0));
        final carryCtrl = TextEditingController(text: _numTxt(m['carryOver'] ?? 0));
        final sickTotalCtrl = TextEditingController(text: _numTxt(m['sickTotal'] ?? 0));
        final sickUsedCtrl = TextEditingController(text: _numTxt(m['sickUsed'] ?? 0));

        final annualRemain = _toDouble(annualTotalCtrl.text) + _toDouble(carryCtrl.text) - _toDouble(annualUsedCtrl.text);
        final sickRemain = _toDouble(sickTotalCtrl.text) - _toDouble(sickUsedCtrl.text);

        Future<void> _save() async {
          await docRef.set({
            'annualTotal': _toDouble(annualTotalCtrl.text),
            'annualUsed': _toDouble(annualUsedCtrl.text),
            'carryOver': _toDouble(carryCtrl.text),
            'sickTotal': _toDouble(sickTotalCtrl.text),
            'sickUsed': _toDouble(sickUsedCtrl.text),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leaves saved')));
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12, runSpacing: 12,
                children: [
                  SizedBox(
                    width: 220,
                    child: _withInfo(
                      label: 'Annual total',
                      tooltip: 'الرصيد السنوي المستحق',
                      field: TextField(
                        controller: annualTotalCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: _withInfo(
                      label: 'Carry over',
                      tooltip: 'الأيام المرحلة من السنة السابقة',
                      field: TextField(
                        controller: carryCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: _withInfo(
                      label: 'Annual used',
                      tooltip: 'السنوي المستخدم (موافق عليه)',
                      field: TextField(
                        controller: annualUsedCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: _withInfo(
                      label: 'Sick total',
                      tooltip: 'رصيد المرضي',
                      field: TextField(
                        controller: sickTotalCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: _withInfo(
                      label: 'Sick used',
                      tooltip: 'المَرَضي المستخدم',
                      field: TextField(
                        controller: sickUsedCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12, runSpacing: 10,
                children: [
                  Chip(label: Text('Annual remaining: ${_numTxt(annualRemain)}')),
                  Chip(label: Text('Sick remaining: ${_numTxt(sickRemain)}')),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Save')),
            ],
          ),
        );
      },
    );
  }

  // ===== Loans Tab (كما كانت v1) =====
  Widget _loansTab(String uid) {
    final loansCol = _fs.collection('payroll').doc(uid).collection('loans').orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: loansCol.snapshots(),
      builder: (context, s) {
        final loanDocs = s.data?.docs ?? [];

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final loanRef = _fs.collection('payroll').doc(uid).collection('loans').doc();
                      await loanRef.set({
                        'principal': 0.0,
                        'monthlyPercent': 10.0,
                        'paidAmount': 0.0,
                        'startDate': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
                        'status': 'active', // active | paid
                        'createdAt': FieldValue.serverTimestamp(),
                        'updatedAt': FieldValue.serverTimestamp(),
                        'note': '',
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add loan'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: loanDocs.isEmpty
                    ? const Center(child: Text('No loans yet. Click "Add loan".'))
                    : _loanDetails(uid, loanDocs),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _loanDetails(String uid, List<QueryDocumentSnapshot<Map<String, dynamic>>> loanDocs) {
    return ListView.separated(
      itemCount: loanDocs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final d = loanDocs[i];
        final m = d.data();

        final principalCtrl = TextEditingController(text: _numTxt(m['principal'] ?? 0));
        final monthlyPercentCtrl = TextEditingController(text: _numTxt(m['monthlyPercent'] ?? 10));
        final paidCtrl = TextEditingController(text: _numTxt(m['paidAmount'] ?? 0));
        final status = (m['status'] ?? 'active').toString();
        final noteCtrl = TextEditingController(text: (m['note'] ?? '').toString());
        final startDate = _toDate(m['startDate']);

        final principal = _toDouble(principalCtrl.text);
        final monthlyPercent = _toDouble(monthlyPercentCtrl.text);
        final paidAmount = _toDouble(paidCtrl.text);
        final monthlyInstallment = (principal * monthlyPercent) / 100.0;
        final remaining = (principal - paidAmount).clamp(0, double.infinity);
        final isPaid = remaining <= 0.0001;

        Future<void> _save() async {
          await _fs.collection('payroll').doc(uid).collection('loans').doc(d.id).set({
            'principal': _toDouble(principalCtrl.text),
            'monthlyPercent': _toDouble(monthlyPercentCtrl.text),
            'paidAmount': _toDouble(paidCtrl.text),
            'status': isPaid ? 'paid' : 'active',
            'note': noteCtrl.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loan saved')));
          }
        }

        Future<void> _applyMonthlyInstallment() async {
          final newPaid = paidAmount + monthlyInstallment;
          await _fs.collection('payroll').doc(uid).collection('loans').doc(d.id).set({
            'paidAmount': newPaid,
            'status': (principal - newPaid) <= 0.0001 ? 'paid' : 'active',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12, runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 200,
                      child: _withInfo(
                        label: 'Principal',
                        tooltip: 'أصل السلفة',
                        field: TextField(
                          controller: principalCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          onChanged: (_) => setState(() {}),
                        ),
                        dialogBody: 'المبلغ الأصلي للسلفة التي حصل عليها الموظف.',
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: _withInfo(
                        label: 'Monthly %',
                        tooltip: 'نسبة السداد شهريًا من أصل السلفة',
                        field: TextField(
                          controller: monthlyPercentCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          onChanged: (_) => setState(() {}),
                        ),
                        dialogBody: 'مثال: 10% يعني يتم خصم 10% من أصل السلفة كل شهر كقسط ثابت.',
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: _withInfo(
                        label: 'Paid amount',
                        tooltip: 'إجمالي ما تم سداده حتى الآن',
                        field: TextField(
                          controller: paidCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          onChanged: (_) => setState(() {}),
                        ),
                        dialogBody: 'يمكنك تعديله يدويًا إذا لزم.',
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: _withInfo(
                        label: 'Start date',
                        tooltip: 'تاريخ بداية السلفة',
                        field: InputDecorator(
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          child: Text(startDate == null
                              ? '—'
                              : '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}'),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: _withInfo(
                        label: 'Status',
                        tooltip: 'الحالة الحالية للسلفة',
                        field: InputDecorator(
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                          child: Text(isPaid ? 'paid' : status),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12, runSpacing: 10,
                  children: [
                    Chip(label: Text('Monthly installment: ${_numTxt(monthlyInstallment)}')),
                    Chip(label: Text('Remaining: ${_numTxt(remaining)}')),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _applyMonthlyInstallment,
                      icon: const Icon(Icons.event_available),
                      label: const Text('Apply monthly installment now'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                    ),
                    if (!isPaid)
                      TextButton.icon(
                        onPressed: () async {
                          await _fs.collection('payroll').doc(uid).collection('loans').doc(d.id).set({
                            'status': 'paid',
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        },
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Mark paid'),
                      ),
                  ],
                ),
                if ((m['note'] ?? '').toString().isNotEmpty) const SizedBox(height: 10),
                _withInfo(
                  label: 'Note',
                  tooltip: 'ملاحظات داخلية',
                  field: TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
