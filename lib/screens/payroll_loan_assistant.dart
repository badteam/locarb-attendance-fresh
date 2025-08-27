// lib/screens/payroll_loan_assistant.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Payroll Loan Assistant — v1.0 (2025-08-27  🕒)
/// - يعرض قروض الموظفين (collection: loans)
/// - يحسب قسط شهري تلقائي = principal * monthlyRatePercent / 100
/// - يحسب المتبقي بناءً على عدد الشهور المنقضية منذ startPeriodId وحتى الفترة المختارة
/// - يكتب القسط المقترح داخل payroll_periods/{periodId}/entries/{userId}.loanInstallment (Merge)
///
/// المتطلبات من Firestore:
/// loans (collection)
///   - loanId (doc id)
///   - userId (String)
///   - userName (String)
///   - principal (num)
///   - monthlyRatePercent (num)  // نسبة القسط الشهري
///   - startPeriodId (String: "YYYY-MM")
///   - status ("active" | "closed")
///   - notes (String, optional)
///
/// payroll_periods/{periodId}/entries/{userId} (doc)
///   - loanInstallment (num)  // هنكتبها من الشاشة دي
///   - ممكن تضيف أي حقول أخرى عندك (baseSalary, allowances, ...etc)
///
/// ملاحظات:
/// - الحساب هنا إرشادي/أوتوماتيك ناعم، مفيش كتابة لمدفوعات القرض نفسها.
/// - لو عايز تسجّل سداد القرض كـ payments، نضيف شاشة/كولكشن لاحقًا.

class PayrollLoanAssistantScreen extends StatefulWidget {
  const PayrollLoanAssistantScreen({super.key});

  @override
  State<PayrollLoanAssistantScreen> createState() => _PayrollLoanAssistantScreenState();
}

class _PayrollLoanAssistantScreenState extends State<PayrollLoanAssistantScreen> {
  final _periodCtrl = TextEditingController(text: _defaultPeriodId());
  final _searchCtrl = TextEditingController(); // بحث بالاسم/الإيميل/اليوزر
  String _statusFilter = 'active'; // active | closed | all

  @override
  void dispose() {
    _periodCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  static String _defaultPeriodId() {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  int _monthsBetween(String startPeriodId, String endPeriodId) {
    // format: YYYY-MM
    final sp = startPeriodId.split('-');
    final ep = endPeriodId.split('-');
    if (sp.length != 2 || ep.length != 2) return 0;
    final sy = int.tryParse(sp[0]) ?? 0;
    final sm = int.tryParse(sp[1]) ?? 0;
    final ey = int.tryParse(ep[0]) ?? 0;
    final em = int.tryParse(ep[1]) ?? 0;
    return (ey - sy) * 12 + (em - sm) + 1; // +1: احسب شهر البداية ضمنيًا
  }

  double _toDouble(dynamic v, [double def = 0]) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim()) ?? def;
    return def;
  }

  bool _matchesSearch(Map<String, dynamic> m) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final userName = (m['userName'] ?? '').toString().toLowerCase();
    final userId   = (m['userId'] ?? '').toString().toLowerCase();
    final notes    = (m['notes'] ?? '').toString().toLowerCase();
    return userName.contains(q) || userId.contains(q) || notes.contains(q);
  }

  Query<Map<String, dynamic>> _loansQuery() {
    var q = FirebaseFirestore.instance.collection('loans');
    if (_statusFilter != 'all') {
      q = q.where('status', isEqualTo: _statusFilter);
    }
    return q.orderBy('userName');
  }

  Future<void> _applyOneToPayroll({
    required String periodId,
    required String userId,
    required double amount,
  }) async {
    final entryRef = FirebaseFirestore.instance
        .collection('payroll_periods')
        .doc(periodId)
        .collection('entries')
        .doc(userId);

    await entryRef.set({
      'loanInstallment': amount,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _applyAllVisibleToPayroll(List<_LoanCalc> list) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final item in list) {
      final entryRef = FirebaseFirestore.instance
          .collection('payroll_periods')
          .doc(item.periodId)
          .collection('entries')
          .doc(item.userId);
      batch.set(entryRef, {
        'loanInstallment': item.installmentToWrite,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    final periodId = _periodCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll • Loan Assistant'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('v1.0 — 2025-08-27'),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _filtersBar(periodId),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _loansQuery().snapshots(),
              builder: (context, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = (s.data?.docs ?? [])
                    .where((d) => _matchesSearch(d.data()))
                    .toList();

                final calcs = <_LoanCalc>[];
                for (final d in docs) {
                  final m = d.data();
                  final status = (m['status'] ?? 'active').toString();
                  final userId = (m['userId'] ?? '').toString();
                  final userName = (m['userName'] ?? userId).toString();
                  final principal = _toDouble(m['principal']);
                  final rate = _toDouble(m['monthlyRatePercent']);
                  final startPid = (m['startPeriodId'] ?? '').toString();

                  // Safety
                  if (principal <= 0 || rate <= 0 || startPid.isEmpty) continue;

                  final monthsElapsed = _monthsBetween(startPid, periodId);
                  final monthlyInstallment = (principal * rate / 100.0);
                  final suggestedTotalPaid =
                      (monthsElapsed <= 0) ? 0 : (monthlyInstallment * monthsElapsed);
                  final cappedPaid = suggestedTotalPaid > principal ? principal : suggestedTotalPaid;
                  final remaining = (principal - cappedPaid);

                  calcs.add(_LoanCalc(
                    loanId: d.id,
                    userId: userId,
                    userName: userName,
                    principal: principal,
                    monthlyRatePercent: rate,
                    startPeriodId: startPid,
                    periodId: periodId,
                    monthsElapsed: monthsElapsed < 0 ? 0 : monthsElapsed,
                    monthlyInstallment: monthlyInstallment,
                    suggestedThisMonth: remaining <= 0 ? 0 : (remaining < monthlyInstallment ? remaining : monthlyInstallment),
                    remaining: remaining < 0 ? 0 : remaining,
                  ));
                }

                if (calcs.isEmpty) {
                  return const Center(child: Text('No loans match current filters.'));
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Text('Found ${calcs.length} loan(s).'),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () async {
                              // اكتب الافتراضي لكل العناصر (بعد السماح بالتعديل من UI)
                              await _applyAllVisibleToPayroll(calcs);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Applied suggested installments to payroll entries.')),
                                );
                              }
                            },
                            icon: const Icon(Icons.playlist_add_check),
                            label: const Text('Apply All to Payroll'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
                        itemCount: calcs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          return _loanTile(calcs[i]);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtersBar(String periodId) {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      elevation: .5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                controller: _periodCtrl,
                decoration: const InputDecoration(
                  labelText: 'Period (YYYY-MM)',
                  isDense: true, border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState((){}),
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _statusFilter,
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                  DropdownMenuItem(value: 'all', child: Text('All')),
                ],
                onChanged: (v) => setState(() => _statusFilter = v ?? 'active'),
              ),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState((){}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name / id / notes',
                  isDense: true, border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const _Legend(),
          ],
        ),
      ),
    );
  }

  Widget _loanTile(_LoanCalc c) {
    final instCtrl = TextEditingController(
      text: c.suggestedThisMonth.toStringAsFixed(2),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(child: Text(c.userName.isNotEmpty ? c.userName[0].toUpperCase() : '?')),
                const SizedBox(width: 10),
                Expanded(child: Text('${c.userName}  •  ${c.userId}')),
                Chip(
                  label: Text('Remaining: ${c.remaining.toStringAsFixed(2)}'),
                  avatar: const Icon(Icons.account_balance_wallet, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Facts
            Wrap(
              spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _kv('Principal', c.principal),
                _kv('Rate %/mo', c.monthlyRatePercent),
                _kv('Start', c.startPeriodId),
                _kv('Now', c.periodId),
                _kv('Months', c.monthsElapsed),
                _kv('Monthly', c.monthlyInstallment),
              ],
            ),
            const SizedBox(height: 10),
            // Controls
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: instCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Installment to write',
                      isDense: true, border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () async {
                    final v = double.tryParse(instCtrl.text.trim()) ?? 0;
                    await _applyOneToPayroll(
                      periodId: c.periodId,
                      userId: c.userId,
                      amount: v < 0 ? 0 : v,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Applied to ${c.userName} (${c.userId})')),
                      );
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Apply to Payroll'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, Object v) {
    return Chip(
      label: Text('$k: $v'),
      avatar: const Icon(Icons.info_outline, size: 16),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6, runSpacing: 4,
      children: const [
        Chip(label: Text('Remaining'), avatar: Icon(Icons.account_balance_wallet, size: 16)),
        Chip(label: Text('Monthly'),   avatar: Icon(Icons.schedule, size: 16)),
      ],
    );
  }
}

class _LoanCalc {
  _LoanCalc({
    required this.loanId,
    required this.userId,
    required this.userName,
    required this.principal,
    required this.monthlyRatePercent,
    required this.startPeriodId,
    required this.periodId,
    required this.monthsElapsed,
    required this.monthlyInstallment,
    required this.suggestedThisMonth,
    required this.remaining,
  });

  final String loanId;
  final String userId;
  final String userName;

  final double principal;
  final double monthlyRatePercent;
  final String startPeriodId;

  final String periodId;       // الفترة المختارة حاليًا
  final int monthsElapsed;     // الشهور المنقضية (تتضمن شهر البدء)
  final double monthlyInstallment;
  final double suggestedThisMonth; // min(monthlyInstallment, remaining)
  final double remaining;

  double get installmentToWrite => suggestedThisMonth;
}
