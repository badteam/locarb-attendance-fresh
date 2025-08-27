// lib/screens/payroll_center_screen.dart
// Payroll Center — v1.0 — 2025-08-27  (tabs, monthly items, loans auto-calc, leave balances, tooltips)
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PayrollCenterScreen extends StatefulWidget {
  const PayrollCenterScreen({super.key});

  @override
  State<PayrollCenterScreen> createState() => _PayrollCenterScreenState();
}

class _PayrollCenterScreenState extends State<PayrollCenterScreen> with SingleTickerProviderStateMixin {
  // ------------ Version label ------------
  static const String _versionLabel = 'Payroll Center v1.0 — 2025-08-27';

  // ------------ Controllers / State ------------
  late TabController _tab;

  String? _selectedUserId;
  Map<String, dynamic> _selectedUser = {};

  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  // Base salary (one-time; editable anytime)
  final TextEditingController _baseSalaryCtrl = TextEditingController(text: '0');

  // Monthly items
  final TextEditingController _allowancesCtrl = TextEditingController(text: '0');
  final TextEditingController _deductionsCtrl = TextEditingController(text: '0');
  final TextEditingController _bonusCtrl = TextEditingController(text: '0');
  final TextEditingController _overtimeAmountCtrl = TextEditingController(text: '0');

  // Loans (create form)
  final TextEditingController _loanPrincipalCtrl = TextEditingController(text: '0');
  final TextEditingController _loanPercentCtrl = TextEditingController(text: '10'); // % per month by default
  DateTime _loanStart = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // Leave balances
  final TextEditingController _annualQuotaCtrl = TextEditingController(text: '21');
  final TextEditingController _carriedOverCtrl = TextEditingController(text: '0');
  final TextEditingController _takenYTDCtrl = TextEditingController(text: '0');
  final TextEditingController _manualAdjustCtrl = TextEditingController(text: '0'); // +/-

  // ------------ Utils ------------
  double _toDouble(TextEditingController c) {
    final s = c.text.trim().replaceAll(',', '');
    final v = double.tryParse(s);
    return v ?? 0.0;
  }

  double _toDoubleAny(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '').trim()) ?? 0.0;
    return 0.0;
  }

  int _yyyymm(int year, int month) => (year * 100) + month;

  String _yyyymmStr(int year, int month) =>
    '${year.toString()}-${month.toString().padLeft(2, '0')}';

  int _monthsBetweenInclusive(DateTime start, int y, int m) {
    final target = DateTime(y, m);
    int months = (target.year - start.year) * 12 + (target.month - start.month) + 1;
    if (months < 0) months = 0;
    return months;
  }

  // ------------ Firestore refs ------------
  final _fs = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _usersCol => _fs.collection('users');
  DocumentReference<Map<String, dynamic>> _baseDoc(String uid) => _fs.collection('payroll_base').doc(uid);
  DocumentReference<Map<String, dynamic>> _monthlyDoc(String uid, int y, int m) =>
_fs.collection('payroll_monthly').doc('${uid}_${y.toString()}-${m.toString().padLeft(2, '0')}');
  CollectionReference<Map<String, dynamic>> _loansCol() => _fs.collection('payroll_loans');
  DocumentReference<Map<String, dynamic>> _leaveDoc(String uid) => _fs.collection('leave_balances').doc(uid);

  // ------------ Loaders ------------
  Future<void> _loadAllForUser(String uid) async {
    // Base
    final baseSnap = await _baseDoc(uid).get();
    final base = baseSnap.data() ?? {};
    _baseSalaryCtrl.text = _toDoubleAny(base['baseSalary']).toStringAsFixed(2);

    // Monthly
    final monSnap = await _monthlyDoc(uid, _year, _month).get();
    final mon = monSnap.data() ?? {};
    _allowancesCtrl.text = _toDoubleAny(mon['allowances']).toStringAsFixed(2);
    _deductionsCtrl.text = _toDoubleAny(mon['deductions']).toStringAsFixed(2);
    _bonusCtrl.text = _toDoubleAny(mon['bonus']).toStringAsFixed(2);
    _overtimeAmountCtrl.text = _toDoubleAny(mon['overtimeAmount']).toStringAsFixed(2);

    // Leave
    final leaveSnap = await _leaveDoc(uid).get();
    final lv = leaveSnap.data() ?? {};
    _annualQuotaCtrl.text = (lv['annualQuota'] is num) ? (lv['annualQuota'] as num).toStringAsFixed(0) : (lv['annualQuota']?.toString() ?? '21');
    _carriedOverCtrl.text = _toDoubleAny(lv['carriedOver']).toStringAsFixed(1);
    _takenYTDCtrl.text = _toDoubleAny(lv['takenYTD']).toStringAsFixed(1);
    _manualAdjustCtrl.text = _toDoubleAny(lv['manualAdjust']).toStringAsFixed(1);

    setState(() {});
  }

  // ------------ Save actions ------------
  Future<void> _saveBase() async {
    if (_selectedUserId == null) return;
    await _baseDoc(_selectedUserId!).set({
      'baseSalary': _toDouble(_baseSalaryCtrl),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _snack('Base salary saved');
  }

  Future<void> _saveMonthly() async {
    if (_selectedUserId == null) return;
    await _monthlyDoc(_selectedUserId!, _year, _month).set({
      'allowances': _toDouble(_allowancesCtrl),
      'deductions': _toDouble(_deductionsCtrl),
      'bonus': _toDouble(_bonusCtrl),
      'overtimeAmount': _toDouble(_overtimeAmountCtrl),
      'year': _year,
      'month': _month,
      'userId': _selectedUserId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _snack('Monthly items saved for \${_yyyymmStr(_year, _month)}');
  }

  Future<void> _createLoan() async {
    if (_selectedUserId == null) return;
    final principal = _toDouble(_loanPrincipalCtrl);
    final pct = _toDouble(_loanPercentCtrl);
    if (principal <= 0 || pct <= 0) {
      _snack('Enter principal and % > 0');
      return;
    }
    await _loansCol().add({
      'userId': _selectedUserId,
      'principal': principal,
      'monthlyPercent': pct, // e.g., 10% of principal per month
      'startYear': _loanStart.year,
      'startMonth': _loanStart.month,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _loanPrincipalCtrl.text = '0';
    _loanPercentCtrl.text = '10';
    setState(() {});
    _snack('Loan created');
  }

  Future<void> _toggleLoanActive(String loanId, bool newVal) async {
    await _loansCol().doc(loanId).set({
      'isActive': newVal,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _snack(newVal ? 'Loan activated' : 'Loan deactivated');
  }

  Future<void> _saveLeave() async {
    if (_selectedUserId == null) return;
    await _leaveDoc(_selectedUserId!).set({
      'annualQuota': int.tryParse(_annualQuotaCtrl.text.trim()) ?? 21,
      'carriedOver': _toDouble(_carriedOverCtrl),
      'takenYTD': _toDouble(_takenYTDCtrl),
      'manualAdjust': _toDouble(_manualAdjustCtrl),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _snack('Leave balance saved');
  }

  // ------------ Loan helpers ------------
  double _loanMonthlyInstallment(double principal, double monthlyPercent) {
    // simple percent of principal per month (no interest compounding)
    return principal * (monthlyPercent / 100.0);
  }

  double _loanRemainingAtMonth({
    required double principal,
    required double monthlyPercent,
    required DateTime start,
    required int year,
    required int month,
  }) {
    final int monthsPaid = _monthsBetweenInclusive(start, year, month);
    final double installment = _loanMonthlyInstallment(principal, monthlyPercent);
    final num remaining = principal - (installment * monthsPaid);
    return remaining.toDouble().clamp(0.0, principal);
  }

  // ------------ UI helpers ------------
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<DropdownMenuItem<int>> _monthItems() => List.generate(12, (i) {
    final m = i + 1;
    return DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0')));
  });

  List<DropdownMenuItem<int>> _yearItems() {
    final now = DateTime.now().year;
    final years = [for (int y = now - 2; y <= now + 2; y++) y];
    return years.map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList();
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _baseSalaryCtrl.dispose();
    _allowancesCtrl.dispose();
    _deductionsCtrl.dispose();
    _bonusCtrl.dispose();
    _overtimeAmountCtrl.dispose();
    _loanPrincipalCtrl.dispose();
    _loanPercentCtrl.dispose();
    _annualQuotaCtrl.dispose();
    _carriedOverCtrl.dispose();
    _takenYTDCtrl.dispose();
    _manualAdjustCtrl.dispose();
    super.dispose();
  }

  // Reset controllers when switching user or month
  Future<void> _onUserOrPeriodChanged() async {
    if (_selectedUserId == null) return;
    await _loadAllForUser(_selectedUserId!);
  }

  // ------------ Widgets ------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll Center'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(child: Text(_versionLabel, style: Theme.of(context).textTheme.labelMedium)),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Base Salary'),
            Tab(text: 'Monthly Items'),
            Tab(text: 'Loans'),
            Tab(text: 'Leave Balance'),
          ],
        ),
      ),
      body: Column(
        children: [
          _headerFilters(),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _tabBaseSalary(),
                _tabMonthlyItems(),
                _tabLoans(),
                _tabLeaveBalance(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // User selector
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _usersCol.where('status', isEqualTo: 'approved').orderBy('fullName').snapshots(),
            builder: (context, s) {
              final items = <DropdownMenuItem<String>>[];
              if (s.hasData) {
                for (final d in s.data!.docs) {
                  final m = d.data();
                  final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? d.id).toString();
                  items.add(DropdownMenuItem(value: d.id, child: Text(name)));
                }
              }
              return InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'User',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedUserId,
                    isExpanded: false,
                    hint: const Text('Select user'),
                    items: items,
                    onChanged: (v) async {
                      setState(() {
                        _selectedUserId = v;
                        _selectedUser = {};
                      });
                      if (v != null) {
                        final doc = await _usersCol.doc(v).get();
                        _selectedUser = doc.data() ?? {};
                        await _onUserOrPeriodChanged();
                      }
                    },
                  ),
                ),
              );
            },
          ),

          // Month / Year
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Month',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _month,
                items: _monthItems(),
                onChanged: (v) async {
                  setState(() => _month = v ?? _month);
                  await _onUserOrPeriodChanged();
                },
              ),
            ),
          ),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Year',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _year,
                items: _yearItems(),
                onChanged: (v) async {
                  setState(() => _year = v ?? _year);
                  await _onUserOrPeriodChanged();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------- Tab 1: Base salary --------
  Widget _tabBaseSalary() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Base salary', 'هذا هو الراتب الأساسي للموظف (مرة واحدة). يمكن تعديله في أي وقت لكنه لا يعتمد على الشهر.'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _baseSalaryCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Base salary',
                    border: const OutlineInputBorder(),
                    suffixIcon: _helpIcon('يُدفَع شهريًا كأساس قبل الإضافات والخصومات.'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _selectedUserId == null ? null : _saveBase,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------- Tab 2: Monthly items --------
  Widget _tabMonthlyItems() {
    final double base = _toDouble(_baseSalaryCtrl);
    final double allowances = _toDouble(_allowancesCtrl);
    final double bonus = _toDouble(_bonusCtrl);
    final double overtimeAmount = _toDouble(_overtimeAmountCtrl);
    final double deductions = _toDouble(_deductionsCtrl);

    final double total = base + allowances + bonus + overtimeAmount - deductions;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Period: \${_yyyymmStr(_year, _month)}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            runSpacing: 10,
            spacing: 10,
            children: [
              _numberField(_allowancesCtrl, 'Allowances (this month)', 'قيمة العلاوات لهذا الشهر فقط.'),
              _numberField(_bonusCtrl, 'Bonus (this month)', 'أي مكافأة تُصرف لهذا الشهر.'),
              _numberField(_overtimeAmountCtrl, 'Overtime amount (this month)', 'قيمة الأوفر تايم لهذا الشهر (مبلغ نهائي).'),
              _numberField(_deductionsCtrl, 'Deductions (this month)', 'خصومات هذا الشهر.'),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            elevation: .5,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total (base + month items)', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(total.toStringAsFixed(2)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _selectedUserId == null ? null : _saveMonthly,
              icon: const Icon(Icons.save),
              label: const Text('Save monthly items'),
            ),
          ),
        ],
      ),
    );
  }

  // -------- Tab 3: Loans --------
  Widget _tabLoans() {
    return Column(
      children: [
        // Create form
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Loans', 'أدخل سلفة/قرض مرة واحدة: أصل المبلغ + نسبة التقسيط الشهري (٪ من الأصل). الحسبة أوتوماتيك.'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10, runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _loanPrincipalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Principal',
                        border: const OutlineInputBorder(),
                        suffixIcon: _helpIcon('أصل المبلغ المسلّف.'),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _loanPercentCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Monthly % of principal',
                        border: const OutlineInputBorder(),
                        suffixIcon: _helpIcon('نسبة تُخصم شهريًا من أصل المبلغ (ليس فائدة مركبة).'),
                      ),
                    ),
                  ),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Start (month)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: InkWell(
                      onTap: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _loanStart,
                          firstDate: DateTime(DateTime.now().year - 3, 1, 1),
                          lastDate: DateTime(DateTime.now().year + 3, 12, 31),
                          helpText: 'Pick any date in the first month of loan',
                        );
                        if (d != null) setState(() => _loanStart = DateTime(d.year, d.month, 1));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Text(_yyyymmStr(_loanStart.year, _loanStart.month)),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: (_selectedUserId == null) ? null : _createLoan,
                    icon: const Icon(Icons.add),
                    label: const Text('Create loan'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 20),
        // List of loans
        Expanded(
          child: (_selectedUserId == null)
              ? const Center(child: Text('Select a user to view loans'))
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _loansCol()
                      .where('userId', isEqualTo: _selectedUserId)
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, s) {
                    if (s.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = s.data?.docs ?? [];
                    if (docs.isEmpty) return const Center(child: Text('No loans found.'));
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final m = d.data();
                        final double principal = _toDoubleAny(m['principal']);
                        final double pct = _toDoubleAny(m['monthlyPercent']);
                        final int sy = (m['startYear'] ?? DateTime.now().year) as int;
                        final int sm = (m['startMonth'] ?? DateTime.now().month) as int;
                        final bool active = (m['isActive'] ?? true) == true;

                        final remaining = _loanRemainingAtMonth(
                          principal: principal,
                          monthlyPercent: pct,
                          start: DateTime(sy, sm, 1),
                          year: _year, month: _month,
                        );

                        final monthlyInstallment = _loanMonthlyInstallment(principal, pct);

                        return Card(
                          child: ListTile(
                            title: Text('Principal: ' + principal.toStringAsFixed(2) + ' — ' +
                                'Monthly: ' + monthlyInstallment.toStringAsFixed(2) + ' (' + pct.toStringAsFixed(1) + '%)'),
                            subtitle: Text('Start: ' + _yyyymmStr(sy, sm) +
                                ' • Remaining @ ' + _yyyymmStr(_year, _month) + ': ' + remaining.toStringAsFixed(2)),
                            trailing: Switch(
                              value: active,
                              onChanged: (v) => _toggleLoanActive(d.id, v),
                            ),
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

  // -------- Tab 4: Leave Balance --------
  Widget _tabLeaveBalance() {
    final double carried = _toDouble(_carriedOverCtrl);
    final double annual = double.tryParse(_annualQuotaCtrl.text.trim())?.toDouble() ?? 21.0;
    final double taken = _toDouble(_takenYTDCtrl);
    final double manual = _toDouble(_manualAdjustCtrl);
    final double balance = (annual + carried + manual) - taken;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Leave balance', 'تُخزَّن القيم هنا كمرجع إداري. لاحقًا سنربطها بطلبات الإجازة لتخصم/تزيد تلقائيًا.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _annualQuotaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Annual quota (days)',
                    border: const OutlineInputBorder(),
                    suffixIcon: _helpIcon('الإجمالي السنوي المسموح به من الأيام.'),
                  ),
                ),
              ),
              _numberField(_carriedOverCtrl, 'Carried over (days)', 'أيام مُرحّلة من سنة سابقة.'),
              _numberField(_takenYTDCtrl, 'Taken YTD (days)', 'أيام تم أخذها منذ بداية السنة.'),
              _numberField(_manualAdjustCtrl, 'Manual adjust (±days)', 'تصحيح يدوي يزيد/ينقص الرصيد.'),
            ],
          ),
          const SizedBox(height: 10),
          Card(
            elevation: .5,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Current balance (computed)', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(balance.toStringAsFixed(1)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _selectedUserId == null ? null : _saveLeave,
              icon: const Icon(Icons.save),
              label: const Text('Save leave balance'),
            ),
          ),
        ],
      ),
    );
  }

  // --------- Small UI helpers ----------
  Widget _numberField(TextEditingController c, String label, String help) {
    return SizedBox(
      width: 220,
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: _helpIcon(help),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _helpIcon(String message) {
    return IconButton(
      icon: const Icon(Icons.help_outline),
      tooltip: 'Info',
      onPressed: () {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Info'),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String title, String desc) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 6),
        _helpIcon(desc),
      ],
    );
  }
}
