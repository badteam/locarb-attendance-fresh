// lib/screens/payroll_loan_assistant.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// شاشة مساعد السلف (Loan Assistant)
/// - تعرض المستخدمين "approved"
/// - لكل مستخدم: أصل السلفة (principal) + نسبة تقسيط شهري (%) => يحسب القسط لهذا الشهر
/// - يحفظ إعدادات السلفة داخل users/{uid}
/// - ويسجّل خصم القسط داخل users/{uid}/payroll/monthly/{YYYY-MM}
class PayrollLoanAssistantScreen extends StatefulWidget {
  const PayrollLoanAssistantScreen({super.key});

  @override
  State<PayrollLoanAssistantScreen> createState() =>
      _PayrollLoanAssistantScreenState();
}

class _PayrollLoanAssistantScreenState
    extends State<PayrollLoanAssistantScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // ✅ لاحظ النوع هنا Query وليس CollectionReference
  late final Query<Map<String, dynamic>> _usersQuery;

  @override
  void initState() {
    super.initState();
    _usersQuery = FirebaseFirestore.instance
        .collection('users')
        .where('status', isEqualTo: 'approved')
        .orderBy('fullName'); // orderBy بيرجع Query
  }

  String _ymKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Future<void> _pickMonth() async {
    // بديل بسيط لاختيار الشهر: نعرض DatePicker ونثبت اليوم = 1
    final d = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Select month (any day in month)',
    );
    if (d != null) {
      setState(() => _month = DateTime(d.year, d.month, 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ym = _ymKey(_month);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll • Loan Assistant'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Month: $ym',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _filtersBar(),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _usersQuery.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text('Error: ${snap.error}'),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No approved users.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _UserLoanCard(
                    uid: docs[i].id,
                    data: docs[i].data(),
                    monthKey: _ymKey(_month),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtersBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('Month: ${_ymKey(_month)}'),
          ),
          const SizedBox(width: 6),
          const Text(
            'Tip: Edit principal & % → Save; then "Post installment" لتسجيله في payroll.',
          ),
        ],
      ),
    );
  }
}

class _UserLoanCard extends StatefulWidget {
  const _UserLoanCard({
    required this.uid,
    required this.data,
    required this.monthKey,
  });

  final String uid;
  final Map<String, dynamic> data;
  final String monthKey; // YYYY-MM

  @override
  State<_UserLoanCard> createState() => _UserLoanCardState();
}

class _UserLoanCardState extends State<_UserLoanCard> {
  late final TextEditingController _principalCtrl;
  late final TextEditingController _percentCtrl;
  String _savingState = 'idle'; // idle | saving | saved | error
  String _postingState = 'idle'; // idle | posting | posted | error

  @override
  void initState() {
    super.initState();
    final m = widget.data;

    // نجلب إعدادات السلفة المخزنة (إن وجدت) داخل users/{uid}
    final principal = _toDouble(m['loanPrincipal']);
    final percent = _toDouble(m['loanPercentMonthly']); // نسبة شهريًا

    _principalCtrl =
        TextEditingController(text: principal == 0 ? '' : _fmt(principal));
    _percentCtrl =
        TextEditingController(text: percent == 0 ? '' : _fmt(percent));
  }

  @override
  void dispose() {
    _principalCtrl.dispose();
    _percentCtrl.dispose();
    super.dispose();
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? 0.0;
    return 0.0;
  }

  String _fmt(num v) => v is int ? v.toString() : v.toStringAsFixed(2);

  double get _principal => _toDouble(_principalCtrl.text);
  double get _percent => _toDouble(_percentCtrl.text);

  double get _installment => (_principal * _percent / 100);

  Future<void> _saveLoanSettings() async {
    final p = _principal;
    final c = _percent;

    if (p < 0 || c < 0) {
      setState(() => _savingState = 'error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Values must be >= 0 (principal, percent).')));
      }
      return;
    }

    setState(() => _savingState = 'saving');
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
        'loanPrincipal': p, // أصل السلفة
        'loanPercentMonthly': c, // نسبة القسط شهريًا
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _savingState = 'saved');
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Loan settings saved')));
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) setState(() => _savingState = 'idle');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingState = 'error');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _postInstallmentToPayroll() async {
    final installment = _installment;
    setState(() => _postingState = 'posting');
    try {
      final doc = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('payroll')
          .doc('monthly')
          .collection('months')
          .doc(widget.monthKey); // users/{uid}/payroll/monthly/months/{YYYY-MM}

      await doc.set({
        'loanInstallment': installment, // خصم القسط للشهر
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _postingState = 'posted');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Installment $_installment posted to payroll for ${widget.monthKey}')));
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) setState(() => _postingState = 'idle');
    } catch (e) {
      if (!mounted) return;
      setState(() => _postingState = 'error');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Post failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        (widget.data['fullName'] ??
                widget.data['name'] ??
                widget.data['username'] ??
                widget.data['email'] ??
                widget.uid)
            .toString();
    final email = (widget.data['email'] ?? '').toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Text(email, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),

            // Inputs
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _principalCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Loan principal (EGP)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _percentCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Installment % / month',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Calculated installment
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  label: Text('Installment this month: ${_fmt(_installment)}'),
                  avatar: const Icon(Icons.calculate, size: 16),
                ),
                if (_principal > 0 && _percent > 0)
                  Text(
                    'Note: installment = principal × ${_fmt(_percent)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Actions
            Row(
              children: [
                FilledButton.icon(
                  onPressed:
                      _savingState == 'saving' ? null : _saveLoanSettings,
                  icon: _savingState == 'saving'
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save settings'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: (_postingState == 'posting' ||
                          _principal <= 0 ||
                          _percent <= 0)
                      ? null
                      : _postInstallmentToPayroll,
                  icon: _postingState == 'posting'
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_rounded),
                  label: const Text('Post installment to payroll'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
