// lib/screens/payroll_center_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PayrollCenterScreen extends StatefulWidget {
  const PayrollCenterScreen({super.key});

  @override
  State<PayrollCenterScreen> createState() => _PayrollCenterScreenState();
}

class _PayrollCenterScreenState extends State<PayrollCenterScreen>
    with SingleTickerProviderStateMixin {
  // ====== Version badge ======
  static const String _versionBadge = 'Payroll Center v2 — ';

  // ====== Tabs ======
  late final TabController _tab = TabController(length: 3, vsync: this);

  // ====== User selection & search ======
  String? _selectedUserId;
  String? _selectedUserName; // للعرض فقط
  final _searchCtrl = TextEditingController();

  // ====== Month selection (Monthly items) ======
  DateTime _currentMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);

  // ====== Controllers ======
  final _baseCtrl = TextEditingController();
  final _allowCtrl = TextEditingController();
  final _bonusCtrl = TextEditingController();
  final _otCtrl = TextEditingController();
  final _deductCtrl = TextEditingController();

  // لمنع إعادة حقن البيانات أكثر من مرة
  bool _seededSettings = false;
  bool _seededMonth = false;

  // ====== Helpers: Firestore refs ======
  CollectionReference<Map<String, dynamic>> get _usersCol =>
      FirebaseFirestore.instance.collection('users');

  DocumentReference<Map<String, dynamic>> _settingsDoc(String uid) =>
      FirebaseFirestore.instance
          .collection('payroll')
          .doc(uid)
          .collection('settings')
          .doc('current');

  DocumentReference<Map<String, dynamic>> _monthDoc(
          String uid, String yyyymm) =>
      FirebaseFirestore.instance
          .collection('payroll')
          .doc(uid)
          .collection('months')
          .doc(yyyymm);

  CollectionReference<Map<String, dynamic>> _loansCol(String uid) =>
      FirebaseFirestore.instance
          .collection('payroll')
          .doc(uid)
          .collection('loans');

  // ====== Format / parse ======
  final _numFormatter =
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'));

  String _ym(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  double _toNum(String? s) =>
      double.tryParse((s ?? '').trim().isEmpty ? '0' : s!.trim()) ?? 0.0;

  String _numTxt(dynamic v) {
    if (v == null) return '0';
    if (v is int) return v.toString();
    if (v is double) return v.toStringAsFixed(2);
    return double.tryParse(v.toString())?.toStringAsFixed(2) ?? '0';
  }

  // ====== Action: change user ======
  void _onPickUser(String uid, String displayName) {
    setState(() {
      _selectedUserId = uid;
      _selectedUserName = displayName;

      // صفّر كل الحقول وسييدنج
      _seededSettings = false;
      _seededMonth = false;

      _baseCtrl.clear();
      _allowCtrl.clear();
      _bonusCtrl.clear();
      _otCtrl.clear();
      _deductCtrl.clear();

      // ارجع الشهر الحالي
      _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    });
  }

  // ====== Month nav ======
  void _shiftMonth(int delta) {
    setState(() {
      _currentMonth =
          DateTime(_currentMonth.year, _currentMonth.month + delta, 1);
      _seededMonth = false;
      _bonusCtrl.clear();
      _otCtrl.clear();
      _deductCtrl.clear();
    });
  }

  // ====== Save actions ======
  Future<void> _saveSettings() async {
    final uid = _selectedUserId;
    if (uid == null) return;

    final base = _toNum(_baseCtrl.text);
    final allow = _toNum(_allowCtrl.text);

    await _settingsDoc(uid).set({
      'salaryBase': base,
      'allowances': allow,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  Future<void> _saveMonthly() async {
    final uid = _selectedUserId;
    if (uid == null) return;

    final key = _ym(_currentMonth);
    final bonuses = _toNum(_bonusCtrl.text);
    final ot = _toNum(_otCtrl.text);
    final deducts = _toNum(_deductCtrl.text);

    await _monthDoc(uid, key).set({
      'bonuses': bonuses,
      'overtimeAmount': ot,
      'deductions': deducts,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Monthly items saved')));
  }

  // ====== Loans ======
  Future<void> _addLoanDialog() async {
    final uid = _selectedUserId;
    if (uid == null) return;

    final principalCtrl = TextEditingController();
    final rateCtrl = TextEditingController(); // كنسبة مئوية من الأصل تُحسم شهرياً
    final monthsCtrl = TextEditingController();
    DateTime startMonth =
        DateTime(_currentMonth.year, _currentMonth.month, 1);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add loan'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _numField('Principal amount', principalCtrl),
              const SizedBox(height: 8),
              _numField('Monthly % (of principal)', rateCtrl,
                  hint: 'e.g. 10 for 10%'),
              const SizedBox(height: 8),
              _numField('Number of months', monthsCtrl, digitsOnly: true),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Start month: '),
                  const SizedBox(width: 6),
                  FilledButton.tonal(
                    onPressed: () async {
                      final m = await showDatePicker(
                        context: context,
                        initialDate: startMonth,
                        firstDate: DateTime(DateTime.now().year - 3),
                        lastDate: DateTime(DateTime.now().year + 3),
                        helpText: 'Pick any day in the start month',
                      );
                      if (m != null) {
                        setState(() {
                          startMonth = DateTime(m.year, m.month, 1);
                        });
                      }
                    },
                    child: Text(_ym(startMonth)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Monthly deduction is computed automatically = principal × (rate% / 100). '
                'Remaining amount reduces every month.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final principal = _toNum(principalCtrl.text);
    final rate = _toNum(rateCtrl.text);
    final months = int.tryParse(monthsCtrl.text.trim()) ?? 0;
    if (principal <= 0 || rate <= 0 || months <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid principal, % and months')),
      );
      return;
    }

    await _loansCol(uid).add({
      'principal': principal,
      'monthlyRatePercent': rate,
      'months': months,
      'startMonth': _ym(startMonth),
      'createdAt': FieldValue.serverTimestamp(),
      'active': true,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Loan added')));
  }

  // حساب المتبقي للسلفة عند شهر معيّن
  double _loanRemainingAtMonth(Map<String, dynamic> loan, DateTime atMonth) {
    final principal = (loan['principal'] as num?)?.toDouble() ?? 0.0;
    final rate = (loan['monthlyRatePercent'] as num?)?.toDouble() ?? 0.0;
    final months = (loan['months'] as num?)?.toInt() ?? 0;
    final start = loan['startMonth']?.toString() ?? _ym(DateTime.now());

    if (principal <= 0 || rate <= 0 || months <= 0) return 0.0;

    final startParts = start.split('-');
    final startMonth = DateTime(
      int.tryParse(startParts[0]) ?? DateTime.now().year,
      int.tryParse(startParts[1]) ?? DateTime.now().month,
      1,
    );

    // عدد الأشهر المنقضية
    int elapsed =
        (atMonth.year - startMonth.year) * 12 + (atMonth.month - startMonth.month) + 1;
    if (elapsed < 0) elapsed = 0;
    if (elapsed > months) elapsed = months;

    final monthlyDeduct = principal * (rate / 100.0);
    final deducted = monthlyDeduct * elapsed;
    final remaining = (principal - deducted).clamp(0, double.infinity);
    return remaining;
  }

  // ====== UI helpers ======
  Widget _numField(String label, TextEditingController c,
      {bool digitsOnly = false, String? hint}) {
    return TextField(
      controller: c,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: false),
      inputFormatters: digitsOnly
          ? [FilteringTextInputFormatter.digitsOnly]
          : [_numFormatter],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _moneyField({
    required String label,
    required TextEditingController controller,
    required bool enabled,
    String? tooltip,
  }) {
    final field = TextField(
      enabled: enabled,
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: false),
      inputFormatters: [_numFormatter],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: tooltip == null
            ? null
            : Tooltip(message: tooltip, child: const Padding(
                padding: EdgeInsets.all(10), child: Icon(Icons.info_outline))),
      ),
    );
    return field;
  }

  // ====== BUILD ======
  @override
  Widget build(BuildContext context) {
    final headerBadge =
        '$_versionBadge ${DateTime.now().toLocal().toString().substring(0, 16)}';

    final canEditSettings = _selectedUserId != null;
    final canEditMonth = _selectedUserId != null; // الشهر موجود دائمًا بأسهم

    final monthKey = _ym(_currentMonth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll Center'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Salaries'),
            Tab(text: 'Leaves'),
            Tab(text: 'Loans'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(headerBadge, style: Theme.of(context).textTheme.labelMedium),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _userPickerBar(),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                // ===== Salaries tab =====
                SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Settings (base + allowances)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('Salary settings'),
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message:
                                        'Base & allowances are NOT monthly. You can update them any time.',
                                    child: const Icon(Icons.info_outline, size: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                key: ValueKey('settings-$_selectedUserId'),
                                stream: (_selectedUserId == null)
                                    ? const Stream.empty()
                                    : _settingsDoc(_selectedUserId!).snapshots(),
                                builder: (context, snap) {
                                  final data = snap.data?.data();
                                  if (!_seededSettings &&
                                      data != null &&
                                      _selectedUserId != null) {
                                    _baseCtrl.text =
                                        _numTxt(data['salaryBase'] ?? 0);
                                    _allowCtrl.text =
                                        _numTxt(data['allowances'] ?? 0);
                                    _seededSettings = true;
                                  }
                                  return Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _moneyField(
                                              label: 'Base salary',
                                              controller: _baseCtrl,
                                              enabled: canEditSettings,
                                              tooltip:
                                                  'Fixed base salary (not monthly record).',
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _moneyField(
                                              label: 'Allowances',
                                              controller: _allowCtrl,
                                              enabled: canEditSettings,
                                              tooltip:
                                                  'Sum of recurring allowances.',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton.icon(
                                          onPressed: canEditSettings
                                              ? _saveSettings
                                              : null,
                                          icon: const Icon(Icons.save),
                                          label: const Text('Save settings'),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Monthly items
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Previous month',
                                    onPressed: canEditMonth ? () => _shiftMonth(-1) : null,
                                    icon: const Icon(Icons.chevron_left),
                                  ),
                                  Text(
                                    'Monthly items — $monthKey',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  IconButton(
                                    tooltip: 'Next month',
                                    onPressed: canEditMonth ? () => _shiftMonth(1) : null,
                                    icon: const Icon(Icons.chevron_right),
                                  ),
                                  const SizedBox(width: 8),
                                  const Tooltip(
                                    message:
                                        'Monthly items are bonuses, overtime amount and deductions that apply only to this month.',
                                    child: Icon(Icons.info_outline, size: 18),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              StreamBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>>(
                                key: ValueKey(
                                    'month-$_selectedUserId-$monthKey'),
                                stream: (_selectedUserId == null)
                                    ? const Stream.empty()
                                    : _monthDoc(_selectedUserId!, monthKey)
                                        .snapshots(),
                                builder: (context, snap) {
                                  final m = snap.data?.data();
                                  if (!_seededMonth &&
                                      m != null &&
                                      _selectedUserId != null) {
                                    _bonusCtrl.text =
                                        _numTxt(m['bonuses'] ?? 0);
                                    _otCtrl.text =
                                        _numTxt(m['overtimeAmount'] ?? 0);
                                    _deductCtrl.text =
                                        _numTxt(m['deductions'] ?? 0);
                                    _seededMonth = true;
                                  }
                                  return Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _moneyField(
                                              label: 'Bonuses',
                                              controller: _bonusCtrl,
                                              enabled: canEditMonth,
                                              tooltip:
                                                  'One-off bonuses for $monthKey.',
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _moneyField(
                                              label: 'Overtime amount',
                                              controller: _otCtrl,
                                              enabled: canEditMonth,
                                              tooltip:
                                                  'Total overtime value for $monthKey.',
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _moneyField(
                                              label: 'Deductions',
                                              controller: _deductCtrl,
                                              enabled: canEditMonth,
                                              tooltip:
                                                  'Total deductions for $monthKey.',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: FilledButton.icon(
                                          onPressed: canEditMonth
                                              ? _saveMonthly
                                              : null,
                                          icon: const Icon(Icons.save_as),
                                          label: const Text('Save monthly'),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ===== Leaves tab (placeholder حالياً) =====
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.beach_access, size: 40),
                      SizedBox(height: 8),
                      Text('Leaves center coming soon.'),
                    ],
                  ),
                ),

                // ===== Loans tab =====
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text('Loans', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(width: 8),
                          const Tooltip(
                            message:
                                'Monthly deduction = principal × (%/100). Remaining declines each month.',
                            child: Icon(Icons.info_outline, size: 18),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _selectedUserId == null
                                ? null
                                : _addLoanDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Add loan'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: (_selectedUserId == null)
                            ? const Center(child: Text('Pick a user to view loans'))
                            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                stream: _loansCol(_selectedUserId!)
                                    .orderBy('createdAt', descending: true)
                                    .snapshots(),
                                builder: (context, snap) {
                                  if (snap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                        child: CircularProgressIndicator());
                                  }
                                  final docs = snap.data?.docs ?? [];
                                  if (docs.isEmpty) {
                                    return const Center(
                                        child: Text('No loans found'));
                                  }
                                  return ListView.separated(
                                    itemCount: docs.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (_, i) {
                                      final d = docs[i];
                                      final m = d.data();
                                      final principal =
                                          (m['principal'] as num?)?.toDouble() ??
                                              0.0;
                                      final rate =
                                          (m['monthlyRatePercent'] as num?)
                                                  ?.toDouble() ??
                                              0.0;
                                      final months =
                                          (m['months'] as num?)?.toInt() ?? 0;
                                      final start = (m['startMonth'] ?? '')
                                          .toString();
                                      final remaining = _loanRemainingAtMonth(
                                          m, _currentMonth);

                                      return Card(
                                        child: ListTile(
                                          title: Text(
                                              'Principal ${_numTxt(principal)} — ${_numTxt(rate)}% × $months mo'),
                                          subtitle: Text(
                                              'Start: $start • Remaining at ${_ym(_currentMonth)}: ${_numTxt(remaining)}'),
                                          trailing: (m['active'] == true)
                                              ? const Chip(
                                                  label: Text('Active'),
                                                  avatar: Icon(Icons.payments,
                                                      size: 16),
                                                )
                                              : const Chip(
                                                  label: Text('Closed'),
                                                  avatar: Icon(Icons.done,
                                                      size: 16),
                                                ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ====== User picker bar ======
  Widget _userPickerBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search user by name or email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          // Users dropdown
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _usersCol
                .where('status', isEqualTo: 'approved')
                .orderBy('fullName')
                .snapshots(),
            builder: (context, snap) {
              final items = <DropdownMenuItem<String>>[];
              if (snap.hasData) {
                final q = _searchCtrl.text.trim().toLowerCase();
                final docs = snap.data!.docs.where((d) {
                  final m = d.data();
                  final name = (m['fullName'] ??
                          m['name'] ??
                          m['username'] ??
                          '')
                      .toString()
                      .toLowerCase();
                  final email = (m['email'] ?? '').toString().toLowerCase();
                  return q.isEmpty || name.contains(q) || email.contains(q);
                }).toList();

                for (final d in docs) {
                  final m = d.data();
                  final name = (m['fullName'] ??
                          m['name'] ??
                          m['username'] ??
                          d.id)
                      .toString();
                  final email = (m['email'] ?? '').toString();
                  items.add(
                    DropdownMenuItem(
                      value: d.id,
                      child: Row(
                        children: [
                          Text(name, overflow: TextOverflow.ellipsis),
                          if (email.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text('• $email',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Theme.of(context).hintColor)),
                          ],
                        ],
                      ),
                    ),
                  );
                }
              }

              return InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Select user',
                  border: OutlineInputBorder(),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedUserId,
                    isExpanded: true,
                    items: items,
                    onChanged: (v) {
                      if (v == null) return;
                      final label = (items
                              .firstWhere((e) => e.value == v)
                              .child as Row)
                          .children
                          .whereType<Text>()
                          .first
                          .data!;
                      _onPickUser(v, label);
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ====== Lifecycle ======
  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _baseCtrl.dispose();
    _allowCtrl.dispose();
    _bonusCtrl.dispose();
    _otCtrl.dispose();
    _deductCtrl.dispose();
    super.dispose();
  }
}
