// lib/screens/payroll_center_screen.dart
// Payroll Center v2.2 — generated at runtime
// Notes:
// - Collections used:
//   users/{uid}
//   payroll/{uid}/settings/current { baseSalary, allowances }
//   payroll/{uid}/months/{YYYY-MM} { bonuses, overtimeAmount, deductions, loanAuto }
//   payroll/{uid}/loans/{loanId} {
//       title, principal, monthlyPercent, monthlyFixed, startMonth(YYYY-MM),
//       status('active'|'closed'), createdAt, updatedAt
//   }
//
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PayrollCenterScreen extends StatefulWidget {
  const PayrollCenterScreen({super.key});

  @override
  State<PayrollCenterScreen> createState() => _PayrollCenterScreenState();
}

class _PayrollCenterScreenState extends State<PayrollCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String _versionText = '';

  // user select
  String? _selectedUserId;
  Map<String, dynamic>? _selectedUser;
  final _userSearch = TextEditingController();

  // salaries const fields
  final _baseCtrl = TextEditingController(text: '0');
  final _allowCtrl = TextEditingController(text: '0');

  // monthly fields
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final _bonusCtrl = TextEditingController(text: '0');
  final _otCtrl = TextEditingController(text: '0');
  final _dedCtrl = TextEditingController(text: '0');

  // loans form
  final _loanTitleCtrl = TextEditingController();
  final _loanPrincipalCtrl = TextEditingController(text: '0');
  final _loanPercentCtrl = TextEditingController(text: '0'); // % of principal monthly
  final _loanFixedCtrl = TextEditingController(text: '0');   // fixed monthly amount
  DateTime _loanStart = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _versionText =
        'Payroll Center v2.2 — ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _tab.dispose();
    _userSearch.dispose();
    _baseCtrl.dispose();
    _allowCtrl.dispose();
    _bonusCtrl.dispose();
    _otCtrl.dispose();
    _dedCtrl.dispose();
    _loanTitleCtrl.dispose();
    _loanPrincipalCtrl.dispose();
    _loanPercentCtrl.dispose();
    _loanFixedCtrl.dispose();
    super.dispose();
  }

  // ---------- helpers ----------
  String _ym(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';
  DateTime _ymParse(String ym) {
    final p = ym.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), 1);
  }

  int _monthsDiffInclusive(String startYM, String currentYM) {
    // months elapsed including current if current>=start
    final s = _ymParse(startYM);
    final c = _ymParse(currentYM);
    if (c.isBefore(s)) return 0;
    return (c.year - s.year) * 12 + (c.month - s.month) + 1;
    // +1 to include the starting month
  }

  double _toNum(TextEditingController c) {
    return double.tryParse(c.text.trim()) ?? 0.0;
  }

  Future<void> _loadSalariesSettings() async {
    if (_selectedUserId == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('payroll').doc(_selectedUserId)
        .collection('settings').doc('current').get();
    final m = doc.data() ?? {};
    _baseCtrl.text = (m['baseSalary'] ?? 0).toString();
    _allowCtrl.text = (m['allowances'] ?? 0).toString();
    // load month items
    final monthDoc = await FirebaseFirestore.instance
        .collection('payroll').doc(_selectedUserId)
        .collection('months').doc(_ym(_month)).get();
    final mm = monthDoc.data() ?? {};
    _bonusCtrl.text = (mm['bonuses'] ?? 0).toString();
    _otCtrl.text = (mm['overtimeAmount'] ?? 0).toString();
    _dedCtrl.text = (mm['deductions'] ?? 0).toString();
    setState(() {});
  }

  Future<void> _saveSettings() async {
    if (_selectedUserId == null) return;
    final ref = FirebaseFirestore.instance
        .collection('payroll').doc(_selectedUserId)
        .collection('settings').doc('current');
    await ref.set({
      'baseSalary': _toNum(_baseCtrl),
      'allowances': _toNum(_allowCtrl),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved base & allowances')),
      );
    }
  }

  Future<void> _saveMonth() async {
    if (_selectedUserId == null) return;
    final ref = FirebaseFirestore.instance
        .collection('payroll').doc(_selectedUserId)
        .collection('months').doc(_ym(_month));
    await ref.set({
      'bonuses': _toNum(_bonusCtrl),
      'overtimeAmount': _toNum(_otCtrl),
      'deductions': _toNum(_dedCtrl),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved monthly items for ${_ym(_month)}')),
      );
    }
  }

  // ----- LOANS -----
  Future<void> _addLoan() async {
    if (_selectedUserId == null) return;
    final principal = double.tryParse(_loanPrincipalCtrl.text.trim()) ?? 0;
    final monthlyPercent = double.tryParse(_loanPercentCtrl.text.trim()) ?? 0;
    final monthlyFixed = double.tryParse(_loanFixedCtrl.text.trim()) ?? 0;
    if (principal <= 0 || (monthlyPercent <= 0 && monthlyFixed <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter principal and monthly % or fixed')),
      );
      return;
    }
    final loansRef = FirebaseFirestore.instance
        .collection('payroll').doc(_selectedUserId)
        .collection('loans');
    await loansRef.add({
      'title': _loanTitleCtrl.text.trim().isEmpty ? 'Loan' : _loanTitleCtrl.text.trim(),
      'principal': principal,
      'monthlyPercent': monthlyPercent, // % of principal per month (optional)
      'monthlyFixed': monthlyFixed,     // fixed per month (optional)
      'startMonth': _ym(_loanStart),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _loanTitleCtrl.clear();
    _loanPrincipalCtrl.text = '0';
    _loanPercentCtrl.text = '0';
    _loanFixedCtrl.text = '0';
  }

  double _installmentFor(Map<String, dynamic> loan) {
    final principal = (loan['principal'] ?? 0).toDouble();
    final p = (loan['monthlyPercent'] ?? 0).toDouble();
    final f = (loan['monthlyFixed'] ?? 0).toDouble();
    final byPercent = (p > 0) ? principal * (p / 100.0) : 0.0;
    if (f > 0 && p > 0) return f; // prefer fixed if both present
    if (f > 0) return f;
    return byPercent;
  }

  double _remainingForLoan(Map<String, dynamic> loan, String currentYM) {
    final principal = (loan['principal'] ?? 0).toDouble();
    final startYM = (loan['startMonth'] ?? '').toString();
    final status = (loan['status'] ?? 'active').toString();
    if (status != 'active' || startYM.isEmpty) return 0;
    final inst = _installmentFor(loan);
    if (inst <= 0) return principal;
    final paidMonths = _monthsDiffInclusive(startYM, currentYM);
    final paid = inst * paidMonths;
    final remaining = principal - paid;
    return remaining < 0 ? 0 : remaining;
  }

  double _autoLoanDeductionForMonth(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    // sum installments of active loans whose startMonth <= selected month
    final ym = _ym(_month);
    double sum = 0;
    for (final d in docs) {
      final m = d.data();
      if ((m['status'] ?? 'active') != 'active') continue;
      final startYM = (m['startMonth'] ?? '').toString();
      if (startYM.isEmpty) continue;
      if (_monthsDiffInclusive(startYM, ym) <= 0) continue; // not started yet
      sum += _installmentFor(m);
    }
    return sum;
  }

  Future<void> _applyLoansToMonth(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    if (_selectedUserId == null) return;
    final amount = _autoLoanDeductionForMonth(docs);
    final ref = FirebaseFirestore.instance
        .collection('payroll').doc(_selectedUserId)
        .collection('months').doc(_ym(_month));
    await ref.set({
      'loanAuto': amount,
      // add also into deductions for the month (merge with existing)
      'deductions': FieldValue.increment(amount),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied loan auto-deduction: ${amount.toStringAsFixed(2)}')),
      );
    }
  }

  Future<void> _closeLoan(String loanId) async {
    if (_selectedUserId == null) return;
    await FirebaseFirestore.instance
        .collection('payroll').doc(_selectedUserId)
        .collection('loans').doc(loanId)
        .set({'status': 'closed', 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
  }

  // ---------- UI ----------
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
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(_versionText, style: Theme.of(context).textTheme.labelSmall),
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
                _salariesTab(),
                _leavesTab(),
                _loansTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _userPicker() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snap) {
        final users = snap.data?.docs ?? [];
        final q = _userSearch.text.trim().toLowerCase();
        final filtered = q.isEmpty
            ? users
            : users.where((d) {
                final m = d.data();
                final name = ((m['fullName'] ?? m['name'] ?? m['username'] ?? '')).toString().toLowerCase();
                final email = (m['email'] ?? '').toString().toLowerCase();
                return name.contains(q) || email.contains(q);
              }).toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _userSearch,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search user by name or email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedUserId,
                items: filtered.map((d) {
                  final m = d.data();
                  final name = (m['fullName'] ?? m['name'] ?? m['username'] ?? '—').toString();
                  final email = (m['email'] ?? '').toString();
                  return DropdownMenuItem<String>(
                    value: d.id,
                    child: Row(
                      children: [
                        Text(name),
                        const SizedBox(width: 8),
                        Text('• $email', style: TextStyle(color: Theme.of(context).hintColor)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedUserId = v;
                    _selectedUser = filtered.firstWhere((d) => d.id == v).data();
                  });
                  _loadSalariesSettings();
                },
                decoration: const InputDecoration(
                  labelText: 'Select user',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _monthSelector(String label) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _month = DateTime(_month.year, _month.month - 1, 1);
                });
                _loadSalariesSettings();
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: Text('$label  ${_ym(_month)}',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  _month = DateTime(_month.year, _month.month + 1, 1);
                });
                _loadSalariesSettings();
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  Widget _salariesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _monthSelector('Select month for monthly items (Bonuses / OT / Deductions)'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: _numField('Base salary', _baseCtrl,
                    help: 'المبلغ الثابت للموظف (مرة واحدة، يمكن تعديله لاحقاً)')),
                const SizedBox(width: 12),
                Expanded(child: _numField('Allowances', _allowCtrl,
                    help: 'العلاوات الثابتة (بدلات… مرة واحدة، يمكن تعديلها)')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: FilledButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('Save settings'),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('Monthly items for ${_ym(_month)}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: _numField('Bonuses', _bonusCtrl,
                    help: 'حوافز/بونص الشهر الحالي')),
                const SizedBox(width: 12),
                Expanded(child: _numField('Overtime amount', _otCtrl,
                    help: 'قيمة الأوفر تايم بالشهر (بالعملة)')),
                const SizedBox(width: 12),
                Expanded(child: _numField('Deductions', _dedCtrl,
                    help: 'خصومات الشهر (تضاف لها السلف الأوتوماتيكية إن وُجدت)')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: FilledButton.icon(
              onPressed: _saveMonth,
              icon: const Icon(Icons.save),
              label: Text('Save monthly for ${_ym(_month)}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leavesTab() {
    return Center(
      child: Text(
        'Leaves dashboard coming next (balances & approvals)',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _loansTab() {
    if (_selectedUserId == null) {
      return const Center(child: Text('Select a user first'));
    }
    final loansQuery = FirebaseFirestore.instance
        .collection('payroll').doc(_selectedUserId)
        .collection('loans')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: loansQuery.snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final autoAmount = _autoLoanDeductionForMonth(docs);

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _monthSelector('Selected month for loan auto-deduction'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.calculate_outlined),
                    title: Text('Auto deduction for ${_ym(_month)}: ${autoAmount.toStringAsFixed(2)}'),
                    subtitle: const Text('مجموع الأقساط النشطة التي ستخصم في هذا الشهر'),
                    trailing: FilledButton.icon(
                      onPressed: docs.isEmpty ? null : () => _applyLoansToMonth(docs),
                      icon: const Icon(Icons.swap_vert_circle_outlined),
                      label: const Text('Apply to month'),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text('Add new loan', style: Theme.of(context).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(child: _textField('Title', _loanTitleCtrl, hint: 'Loan/Advance')),
                    const SizedBox(width: 12),
                    Expanded(child: _numField('Principal', _loanPrincipalCtrl, help: 'قيمة السلفة/القرض')),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: _numField('Monthly % of principal', _loanPercentCtrl,
                        help: 'نسبة مئوية من أصل السلفة تخصم شهرياً (اتركها 0 لو ستستخدم قيمة ثابتة)')),
                    const SizedBox(width: 12),
                    Expanded(child: _numField('Monthly fixed amount', _loanFixedCtrl,
                        help: 'قيمة ثابتة تخصم شهرياً (اتركها 0 لو ستستخدم نسبة)')),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _monthPickerField(
                        label: 'Start month',
                        value: _loanStart,
                        onPick: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _loanStart,
                            firstDate: DateTime(now.year - 5, 1, 1),
                            lastDate: DateTime(now.year + 5, 12, 31),
                            helpText: 'Pick any day in the start month',
                          );
                          if (picked != null) {
                            setState(() {
                              _loanStart = DateTime(picked.year, picked.month, 1);
                            });
                          }
                        },
                        help: 'الشهر الذي يبدأ فيه خصم السلفة',
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8, right: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _addLoan,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Add loan'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('Active & closed loans', style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(height: 6),
              ...docs.map((d) {
                final m = d.data();
                final inst = _installmentFor(m);
                final remaining = _remainingForLoan(m, _ym(_month));
                final status = (m['status'] ?? 'active').toString();
                final isActive = status == 'active';
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text('${m['title'] ?? 'Loan'} • principal ${ (m['principal'] ?? 0).toString() }'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Start: ${m['startMonth'] ?? ''}  •  Monthly installment: ${inst.toStringAsFixed(2)}'),
                        Text('Remaining (est. by ${_ym(_month)}): ${remaining.toStringAsFixed(2)}  •  Status: $status'),
                      ],
                    ),
                    trailing: isActive
                        ? IconButton(
                            tooltip: 'Mark closed',
                            onPressed: () => _closeLoan(d.id),
                            icon: const Icon(Icons.lock_outline),
                          )
                        : const Icon(Icons.check_circle, color: Colors.green),
                  ),
                );
              }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // ---------- small widgets ----------
  Widget _numField(String label, TextEditingController c, {String? help}) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: help == null
            ? null
            : Tooltip(
                message: help,
                preferBelow: false,
                child: const Padding(
                  padding: EdgeInsets.all(10.0),
                  child: Icon(Icons.info_outline),
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

  Widget _monthPickerField({
    required String label,
    required DateTime value,
    required VoidCallback onPick,
    String? help,
  }) {
    return InkWell(
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: help == null
              ? null
              : Tooltip(
                  message: help,
                  child: const Padding(
                    padding: EdgeInsets.all(10.0),
                    child: Icon(Icons.info_outline),
                  ),
                ),
        ),
        child: Text(_ym(value)),
      ),
    );
  }
}