// lib/screens/payroll_center_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Payroll Center v2.3 — generated 2025-08-27
/// Tabs: Salaries • Leaves • Loans
/// Storage tree (per user uid):
/// - payroll/{uid}/settings/current    -> { baseSalary, allowances }
/// - payroll/{uid}/months/{YYYY-MM}    -> { bonuses, overtimeAmount, deductions, loanAuto }
/// - payroll/{uid}/loans/{loanId}      -> { title, principal, monthlyPercent, monthlyFixed, startMonth, status }
/// - payroll/{uid}/leave/current       -> { annualQuota, carryOver, manualAdjustments }
/// - payroll/{uid}/leave/years/{YYYY}  -> { usedByMonth: { 'YYYY-MM': days, ... } }
class PayrollCenterScreen extends StatefulWidget {
  const PayrollCenterScreen({super.key});
  @override
  State<PayrollCenterScreen> createState() => _PayrollCenterScreenState();
}

class _PayrollCenterScreenState extends State<PayrollCenterScreen>
    with SingleTickerProviderStateMixin {
  static const String _versionBadge = 'Payroll Center v2.3';

  late final TabController _tab;

  // Selected user
  String? _selectedUid;
  String? _selectedName;

  // Month focus (for monthly items / leaves)
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  // Text controllers (salaries)
  final TextEditingController _baseCtrl = TextEditingController(text: '0');
  final TextEditingController _allowCtrl = TextEditingController(text: '0');
  final TextEditingController _bonusCtrl = TextEditingController(text: '0');
  final TextEditingController _otCtrl = TextEditingController(text: '0');
  final TextEditingController _dedCtrl = TextEditingController(text: '0');

  // Leaves controllers
  final TextEditingController _quotaCtrl = TextEditingController(text: '0');
  final TextEditingController _carryCtrl = TextEditingController(text: '0');
  final TextEditingController _leaveDebitCtrl = TextEditingController(text: '0');

  // Loans controllers (create new loan)
  final TextEditingController _loanTitleCtrl = TextEditingController();
  final TextEditingController _loanPrincipalCtrl = TextEditingController(text: '0');
  final TextEditingController _loanPctCtrl = TextEditingController(text: '0');   // % per month
  final TextEditingController _loanFixedCtrl = TextEditingController(text: '0'); // fixed amount
  DateTime _loanStart = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _baseCtrl.dispose();
    _allowCtrl.dispose();
    _bonusCtrl.dispose();
    _otCtrl.dispose();
    _dedCtrl.dispose();
    _quotaCtrl.dispose();
    _carryCtrl.dispose();
    _leaveDebitCtrl.dispose();
    _loanTitleCtrl.dispose();
    _loanPrincipalCtrl.dispose();
    _loanPctCtrl.dispose();
    _loanFixedCtrl.dispose();
    super.dispose();
  }

  // ===== Helpers =====
  double _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0.0;

  String _ym(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  DateTime _addMonth(DateTime d, int delta) =>
      DateTime(d.year, d.month + delta);

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  CollectionReference<Map<String, dynamic>>? get _userPayrollRoot {
    final uid = _selectedUid;
    if (uid == null || uid.isEmpty) return null;
    return FirebaseFirestore.instance.collection('payroll').doc(uid).collection('_root'); // placeholder to resolve type
  }

  // Proper paths (workaround to keep type safety in code sections)
  DocumentReference<Map<String, dynamic>>? _settingsDoc() {
    final uid = _selectedUid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('payroll')
        .doc(uid)
        .collection('settings')
        .doc('current');
  }

  DocumentReference<Map<String, dynamic>>? _monthDoc([DateTime? dt]) {
    final uid = _selectedUid;
    if (uid == null) return null;
    final ym = _ym(dt ?? _month);
    return FirebaseFirestore.instance
        .collection('payroll')
        .doc(uid)
        .collection('months')
        .doc(ym);
  }

  CollectionReference<Map<String, dynamic>>? _loansCol() {
    final uid = _selectedUid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('payroll')
        .doc(uid)
        .collection('loans');
  }

  DocumentReference<Map<String, dynamic>>? _leaveCurrentDoc() {
    final uid = _selectedUid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('payroll')
        .doc(uid)
        .collection('leave')
        .doc('current');
  }

  DocumentReference<Map<String, dynamic>>? _leaveYearDoc(int year) {
    final uid = _selectedUid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('payroll')
        .doc(uid)
        .collection('leave')
        .doc('years')
        .collection('_')
        .doc('$year'); // sub-collection to bypass doc merge, alternative structure
  }

  // ===== Loaders =====
  Future<void> _loadSalaries() async {
    final sDoc = _settingsDoc();
    final mDoc = _monthDoc();

    if (sDoc != null) {
      final s = await sDoc.get();
      final data = s.data() ?? {};
      _baseCtrl.text = (data['baseSalary'] ?? 0).toString();
      _allowCtrl.text = (data['allowances'] ?? 0).toString();
    }
    if (mDoc != null) {
      final m = await mDoc.get();
      final data = m.data() ?? {};
      _bonusCtrl.text = (data['bonuses'] ?? 0).toString();
      _otCtrl.text = (data['overtimeAmount'] ?? 0).toString();
      _dedCtrl.text = (data['deductions'] ?? 0).toString();
      setState(() {});
    }
  }

  Future<Map<String, dynamic>> _loadLoansTotalsForMonth(DateTime month) async {
    final col = _loansCol();
    if (col == null) return {'total': 0.0, 'items': []};
    final q = await col.where('status', isEqualTo: 'active').get();
    double total = 0.0;
    final items = <Map<String, dynamic>>[];
    for (final d in q.docs) {
      final m = d.data();
      final String start = (m['startMonth'] ?? '').toString();
      if (start.isEmpty) continue;
      final sm = DateTime.tryParse('$start-01');
      if (sm == null) continue;
      if (DateTime(month.year, month.month).isBefore(sm)) continue; // not started yet
      final double principal =
          (m['principal'] is num) ? (m['principal'] as num).toDouble() : 0.0;
      final double monthlyFixed =
          (m['monthlyFixed'] is num) ? (m['monthlyFixed'] as num).toDouble() : 0.0;
      final double monthlyPercent =
          (m['monthlyPercent'] is num) ? (m['monthlyPercent'] as num).toDouble() : 0.0;

      final double installment =
          (monthlyFixed > 0) ? monthlyFixed : (principal * monthlyPercent / 100.0);
      total += installment;
      items.add({
        'id': d.id,
        'title': m['title'] ?? 'Loan',
        'installment': installment,
        'principal': principal,
        'monthlyFixed': monthlyFixed,
        'monthlyPercent': monthlyPercent,
        'startMonth': start,
      });
    }
    return {'total': total, 'items': items};
  }

  // ===== Actions =====
  Future<void> _saveSettings() async {
    final doc = _settingsDoc();
    if (doc == null) return;
    await doc.set({
      'baseSalary': _num(_baseCtrl),
      'allowances': _num(_allowCtrl),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _msg('Settings saved');
  }

  Future<void> _saveMonthly() async {
    final doc = _monthDoc();
    if (doc == null) return;
    await doc.set({
      'bonuses': _num(_bonusCtrl),
      'overtimeAmount': _num(_otCtrl),
      'deductions': _num(_dedCtrl),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _msg('Monthly items saved for ${_ym(_month)}');
  }

  Future<void> _applyLoansToMonth() async {
    final doc = _monthDoc();
    if (doc == null) return;
    final totals = await _loadLoansTotalsForMonth(_month);
    final double auto = (totals['total'] as num).toDouble();

    final cur = await doc.get();
    final data = cur.data() ?? {};
    final double curDed =
        (data['deductions'] is num) ? (data['deductions'] as num).toDouble() : 0.0;
    final double newDed = curDed + auto;

    await doc.set({
      'loanAuto': auto,
      'deductions': newDed,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _dedCtrl.text = newDed.toStringAsFixed(2);
    _msg('Applied loan auto-deductions (${auto.toStringAsFixed(2)}) to ${_ym(_month)}');
  }

  Future<void> _saveLeaveSettings() async {
    final doc = _leaveCurrentDoc();
    if (doc == null) return;
    await doc.set({
      'annualQuota': _num(_quotaCtrl),
      'carryOver': _num(_carryCtrl),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _msg('Leave settings saved');
  }

  Future<void> _recordLeaveDebitForMonth() async {
    final days = _num(_leaveDebitCtrl);
    if (days <= 0) {
      _msg('Enter days to deduct');
      return;
    }
    final doc = _leaveYearDoc(_month.year);
    if (doc == null) return;
    await doc.set({
      'usedByMonth.${_ym(_month)}': FieldValue.increment(days),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _leaveDebitCtrl.text = '0';
    _msg('Recorded $days day(s) leave for ${_ym(_month)}');
  }

  Future<void> _createLoan() async {
    final col = _loansCol();
    if (col == null) return;
    final title = _loanTitleCtrl.text.trim().isEmpty ? 'Loan' : _loanTitleCtrl.text.trim();
    await col.add({
      'title': title,
      'principal': double.tryParse(_loanPrincipalCtrl.text.trim()) ?? 0.0,
      'monthlyPercent': double.tryParse(_loanPctCtrl.text.trim()) ?? 0.0,
      'monthlyFixed': double.tryParse(_loanFixedCtrl.text.trim()) ?? 0.0,
      'startMonth': _ym(_loanStart),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _loanTitleCtrl.clear();
    _loanPrincipalCtrl.text = '0';
    _loanPctCtrl.text = '0';
    _loanFixedCtrl.text = '0';
    _msg('Loan added');
  }

  Future<void> _toggleLoanStatus(String id, bool active) async {
    final col = _loansCol();
    if (col == null) return;
    await col.doc(id).set({
      'status': active ? 'closed' : 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _msg(active ? 'Loan closed' : 'Loan re-activated');
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll Center'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_versionBadge, style: Theme.of(context).textTheme.labelMedium),
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
            child: TabBarView(
              controller: _tab,
              children: [
                _tabSalaries(),
                _tabLeaves(),
                _tabLoans(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _userPicker() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _UserSearch(
                  onPick: (uid, name) async {
                    setState(() {
                      _selectedUid = uid;
                      _selectedName = name;
                    });
                    await _loadSalaries();
                  },
                ),
              ),
              const SizedBox(width: 8),
              _monthChooser(),
            ],
          ),
          const SizedBox(height: 8),
          if (_selectedUid != null)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: const Icon(Icons.person, size: 18),
                  label: Text(_selectedName ?? _selectedUid ?? ''),
                ),
                Chip(
                  avatar: const Icon(Icons.calendar_month, size: 18),
                  label: Text('Month: ${_ym(_month)}'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _monthChooser() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () async {
              setState(() => _month = _addMonth(_month, -1));
              if (_selectedUid != null) await _loadSalaries();
            },
            icon: const Icon(Icons.chevron_left),
          ),
          Text(_ym(_month), style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            onPressed: () async {
              setState(() => _month = _addMonth(_month, 1));
              if (_selectedUid != null) await _loadSalaries();
            },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  // ---- Salaries ----
  Widget _tabSalaries() {
    if (_selectedUid == null) {
      return const Center(child: Text('Select a user to manage salaries.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _numField('Base salary', _baseCtrl,
                  hint: '0', info: 'Basic monthly salary (one-time setting, editable anytime).')),
              const SizedBox(width: 12),
              Expanded(child: _numField('Allowances', _allowCtrl,
                  hint: '0', info: 'Sum of fixed monthly allowances.')),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saveSettings,
            icon: const Icon(Icons.save),
            label: const Text('Save settings'),
          ),
          const SizedBox(height: 16),
          Text('Monthly items for ${_ym(_month)}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _numField('Bonuses', _bonusCtrl,
                  hint: '0', info: 'Bonuses for this month only.')),
              const SizedBox(width: 12),
              Expanded(child: _numField('Overtime amount', _otCtrl,
                  hint: '0', info: 'Overtime payout for this month.')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _numField('Deductions', _dedCtrl,
                  hint: '0', info: 'Other deductions (will include loan auto if applied).')),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _applyLoansToMonth,
                    icon: const Icon(Icons.fact_check),
                    label: const Text('Apply loan auto'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saveMonthly,
            icon: const Icon(Icons.save_as),
            label: const Text('Save monthly'),
          ),
        ],
      ),
    );
  }

  // ---- Leaves ----
  Widget _tabLeaves() {
    if (_selectedUid == null) {
      return const Center(child: Text('Select a user to manage leaves.'));
    }
    final currentDoc = _leaveCurrentDoc();
    final yearDoc = _leaveYearDoc(_month.year);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: currentDoc?.get(),
            builder: (_, s) {
              final data = s.data?.data() ?? {};
              _quotaCtrl.text = (data['annualQuota'] ?? 0).toString();
              _carryCtrl.text = (data['carryOver'] ?? 0).toString();
              final double quota =
                  (data['annualQuota'] is num) ? (data['annualQuota'] as num).toDouble() : 0.0;
              final double carry =
                  (data['carryOver'] is num) ? (data['carryOver'] as num).toDouble() : 0.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _numField('Annual quota', _quotaCtrl,
                          hint: '0', info: 'Total leave entitlement for the year.')),
                      const SizedBox(width: 12),
                      Expanded(child: _numField('Carry-over', _carryCtrl,
                          hint: '0', info: 'Remaining days carried from previous year.')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _saveLeaveSettings,
                    icon: const Icon(Icons.save),
                    label: const Text('Save leave settings'),
                  ),
                  const SizedBox(height: 16),
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: yearDoc?.get(),
                    builder: (_, y) {
                      final yData = y.data?.data() ?? {};
                      final Map<String, dynamic> usedMap =
                          (yData['usedByMonth'] is Map<String, dynamic>)
                              ? (yData['usedByMonth'] as Map<String, dynamic>)
                              : {};
                      double usedYtd = 0;
                      usedMap.forEach((k, v) {
                        if (k.toString().startsWith('${_month.year}-') && v is num) {
                          usedYtd += v.toDouble();
                        }
                      });
                      final balance = (quota + carry) - usedYtd;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            children: [
                              Chip(label: Text('Used YTD: ${usedYtd.toStringAsFixed(2)}')),
                              Chip(label: Text('Balance: ${balance.toStringAsFixed(2)}')),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _numField('Deduct days for ${_ym(_month)}', _leaveDebitCtrl,
                                  hint: '0', info: 'Record approved leave days for this month.')),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: _recordLeaveDebitForMonth,
                                icon: const Icon(Icons.remove_circle_outline),
                                label: const Text('Record leave'),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ---- Loans ----
  Widget _tabLoans() {
    if (_selectedUid == null) {
      return const Center(child: Text('Select a user to manage loans.'));
    }
    final col = _loansCol();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _applyLoansToMonth,
                  icon: const Icon(Icons.fact_check),
                  label: Text('Apply to ${_ym(_month)}'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: col?.orderBy('createdAt', descending: true).snapshots(),
            builder: (_, s) {
              if (s.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = s.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No loans yet. Add one below.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i];
                  final m = d.data();
                  final title = (m['title'] ?? 'Loan').toString();
                  final principal = (m['principal'] is num) ? (m['principal'] as num).toDouble() : 0.0;
                  final monthlyFixed = (m['monthlyFixed'] is num) ? (m['monthlyFixed'] as num).toDouble() : 0.0;
                  final monthlyPercent = (m['monthlyPercent'] is num) ? (m['monthlyPercent'] as num).toDouble() : 0.0;
                  final startMonth = (m['startMonth'] ?? '').toString();
                  final status = (m['status'] ?? 'active').toString();
                  final isActive = status == 'active';

                  final installment = (monthlyFixed > 0) ? monthlyFixed : (principal * monthlyPercent / 100.0);

                  // Remaining (rough estimate by elapsed months)
                  int elapsed = 0;
                  final sm = DateTime.tryParse('$startMonth-01');
                  if (sm != null) {
                    final nowYM = DateTime(_month.year, _month.month);
                    elapsed = (nowYM.year - sm.year) * 12 + (nowYM.month - sm.month) + 1;
                    if (elapsed < 0) elapsed = 0;
                  }
                  final paid = installment * elapsed;
                  final remaining = (principal - paid).clamp(0, double.infinity);

                  return Card(
                    child: ListTile(
                      title: Text(title),
                      subtitle: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Chip(label: Text('Principal: ${principal.toStringAsFixed(2)}')),
                          Chip(label: Text('Start: $startMonth')),
                          Chip(label: Text('Installment: ${installment.toStringAsFixed(2)}')),
                          Chip(label: Text('Remaining*: ${remaining.toStringAsFixed(2)}')),
                          const Text('*approx'),
                        ],
                      ),
                      trailing: TextButton.icon(
                        onPressed: () => _toggleLoanStatus(d.id, isActive),
                        icon: Icon(isActive ? Icons.check_circle : Icons.replay),
                        label: Text(isActive ? 'Close' : 'Reopen'),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add loan', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _textField('Title', _loanTitleCtrl, hint: 'e.g. Advance')),
                  const SizedBox(width: 12),
                  Expanded(child: _numField('Principal', _loanPrincipalCtrl, hint: '0')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _numField('% per month', _loanPctCtrl, hint: '0',
                      info: 'If >0, installment = principal * percent / 100 per month.')),
                  const SizedBox(width: 12),
                  Expanded(child: _numField('Fixed / month', _loanFixedCtrl, hint: '0',
                      info: 'If >0, overrides percent.')),
                  const SizedBox(width: 12),
                  _monthPickerMini('Start', _loanStart, (d) => setState(() => _loanStart = d)),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _createLoan,
                icon: const Icon(Icons.add),
                label: const Text('Add loan'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===== small widgets =====
  Widget _numField(String label, TextEditingController c,
      {String? hint, String? info}) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        suffixIcon: (info == null)
            ? null
            : _InfoIcon(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(label),
                    content: Text(info),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController c, {String? hint}) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _monthPickerMini(String label, DateTime value, ValueChanged<DateTime> onPick) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2023, 1, 1),
          lastDate: DateTime(2100, 12, 31),
          helpText: 'Pick any day in month',
        );
        if (d != null) onPick(DateTime(d.year, d.month));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ${_ym(value)}'),
            const SizedBox(width: 6),
            const Icon(Icons.edit_calendar, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Simple i (info) icon used in fields.
class _InfoIcon extends StatelessWidget {
  final VoidCallback onTap;
  const _InfoIcon({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Info',
      onPressed: onTap,
      icon: const Icon(Icons.info_outline),
    );
  }
}

/// Users search & pick widget
class _UserSearch extends StatefulWidget {
  const _UserSearch({required this.onPick});
  final void Function(String uid, String name) onPick;
  @override
  State<_UserSearch> createState() => _UserSearchState();
}

class _UserSearchState extends State<_UserSearch> {
  final TextEditingController _q = TextEditingController();
  String _selectedUid = '';
  String _selectedName = '';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _q,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search user by name or email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          constraints: const BoxConstraints(maxHeight: 220),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('status', isEqualTo: 'approved')
                .orderBy('fullName')
                .snapshots(),
            builder: (_, s) {
              if (!s.hasData) {
                return const SizedBox(
                  height: 56,
                  child: Center(child: LinearProgressIndicator(minHeight: 2)),
                );
              }
              final q = _q.text.trim().toLowerCase();
              final docs = s.data!.docs.where((d) {
                final m = d.data();
                final name = (m['fullName'] ?? m['name'] ?? '').toString().toLowerCase();
                final email = (m['email'] ?? '').toString().toLowerCase();
                return q.isEmpty || name.contains(q) || email.contains(q);
              }).toList();

              if (docs.isEmpty) {
                return const SizedBox(
                  height: 56,
                  child: Center(child: Text('No users match')),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final d = docs[i];
                  final m = d.data();
                  final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? '').toString();
                  final email = (m['email'] ?? '').toString();
                  final picked = d.id == _selectedUid;
                  return ListTile(
                    dense: true,
                    selected: picked,
                    title: Text(name.isEmpty ? d.id : name),
                    subtitle: Text(email),
                    trailing: picked ? const Icon(Icons.check_circle, color: Colors.green) : null,
                    onTap: () {
                      setState(() {
                        _selectedUid = d.id;
                        _selectedName = name.isEmpty ? d.id : name;
                      });
                      widget.onPick(d.id, _selectedName);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
