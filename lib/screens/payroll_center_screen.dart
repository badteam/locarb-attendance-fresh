
// lib/screens/payroll_center_screen.dart
// Payroll Center v2.2 — shows salaries (fixed) + monthly items with tooltips.
// Requires: cloud_firestore, flutter/material

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
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  // User selection + search
  final TextEditingController _searchCtrl = TextEditingController();
  String? _selectedUid;
  String? _selectedName;

  // Fixed settings controllers
  final TextEditingController _salaryCtrl = TextEditingController(text: '0');
  final TextEditingController _allowCtrl = TextEditingController(text: '0');
  bool _seededSettings = false;

  // Monthly controllers
  final TextEditingController _bonusCtrl = TextEditingController(text: '0');
  final TextEditingController _otCtrl = TextEditingController(text: '0');
  final TextEditingController _deductCtrl = TextEditingController(text: '0');
  bool _seededMonth = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _salaryCtrl.dispose();
    _allowCtrl.dispose();
    _bonusCtrl.dispose();
    _otCtrl.dispose();
    _deductCtrl.dispose();
    super.dispose();
  }

  String get _monthId =>
      '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}';

  // Helpers
  double _toNum(String v) {
    final t = v.trim();
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? 0;
  }

  InputDecoration _numDecoration(String label, {String? hint, String? help}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: '',
      border: const OutlineInputBorder(),
      isDense: true,
      suffixIcon: (help == null)
          ? null
          : Tooltip(
              message: help,
              preferBelow: false,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.info_outline, size: 18),
              ),
            ),
    );
  }

  Future<void> _saveSettings() async {
    if (_selectedUid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('payroll')
        .doc(_selectedUid)
        .collection('settings')
        .doc('current');
    await ref.set({
      'salaryBase': _toNum(_salaryCtrl.text),
      'allowances': _toNum(_allowCtrl.text),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fixed settings saved.')),
      );
    }
  }

  Future<void> _saveMonth() async {
    if (_selectedUid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('payroll')
        .doc(_selectedUid)
        .collection('months')
        .doc(_monthId);
    await ref.set({
      'bonuses': _toNum(_bonusCtrl.text),
      'overtimeAmount': _toNum(_otCtrl.text),
      'deductions': _toNum(_deductCtrl.text),
      'month': _monthId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved items for $_monthId')),
      );
    }
  }

  void _bumpMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _seededMonth = false; // re-seed month fields on next build
    });
  }

  @override
  Widget build(BuildContext context) {
    final usersQuery = FirebaseFirestore.instance
        .collection('users')
        .orderBy('fullName', descending: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll Center'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Payroll Center v2.2 — '
                  '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')} '
                  '${TimeOfDay.now().format(context)}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
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
      body: TabBarView(
        controller: _tab,
        children: [
          // ======== Salaries tab ========
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search user by name or email',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message:
                          '1) اختر موظف\n2) أدخل الراتب الثابت/العلاوات مرة واحدة (يحفظان في Settings)\n3) اختر شهرًا وأدخل البنود الشهرية (بونص/OT/خصم) ثم احفظ.',
                      child: const Icon(Icons.info_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // User selector
                SizedBox(
                  height: 56,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: usersQuery.snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? [];
                      final q = _searchCtrl.text.trim().toLowerCase();
                      final filtered = docs.where((d) {
                        final m = d.data();
                        final name = (m['fullName'] ?? m['name'] ?? '').toString().toLowerCase();
                        final email = (m['email'] ?? '').toString().toLowerCase();
                        return q.isEmpty || name.contains(q) || email.contains(q);
                      }).toList();

                      return DropdownButtonFormField<String>(
                        value: _selectedUid,
                        items: filtered.map((d) {
                          final m = d.data();
                          final nm = (m['fullName'] ?? m['name'] ?? d.id).toString();
                          return DropdownMenuItem(
                            value: d.id,
                            child: Text('$nm  •  ${(m['email'] ?? '').toString()}',
                                overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedUid = v;
                            _selectedName = filtered
                                .firstWhere((e) => e.id == v, orElse: () => filtered.first)
                                .data()['fullName']
                                ?.toString();
                            _seededSettings = false;
                            _seededMonth = false;
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Select user',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                if (_selectedUid == null)
                  const Expanded(
                    child: Center(child: Text('Select a user to edit payroll.')),
                  )
                else
                  Expanded(
                    child: ListView(
                      children: [
                        // Month chooser
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: () => _bumpMonth(-1),
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                Expanded(
                                  child: Center(
                                    child: Text(
                                      'Select month for monthly items (Bonuses / OT / Deductions)',
                                      style: Theme.of(context).textTheme.bodyLarge,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _bumpMonth(1),
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Fixed settings
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('payroll')
                              .doc(_selectedUid)
                              .collection('settings')
                              .doc('current')
                              .snapshots(),
                          builder: (context, s) {
                            final m = s.data?.data() ?? {};
                            if (!_seededSettings) {
                              _salaryCtrl.text =
                                  (m['salaryBase'] is num) ? (m['salaryBase'] as num).toString() : (m['salaryBase'] ?? '0').toString();
                              _allowCtrl.text =
                                  (m['allowances'] is num) ? (m['allowances'] as num).toString() : (m['allowances'] ?? '0').toString();
                              _seededSettings = true;
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Fixed settings', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _salaryCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: _numDecoration(
                                          'Base salary',
                                          help: 'الراتب الشهري الثابت. يُحفظ مرة واحدة ويمكن تعديله لاحقًا.',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _allowCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: _numDecoration(
                                          'Allowances',
                                          help: 'إجمالي العلاوات الشهرية الثابتة (بدل سكن/مواصلات…الخ).',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FilledButton.icon(
                                    onPressed: _saveSettings,
                                    icon: const Icon(Icons.save_alt),
                                    label: const Text('Save settings'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Monthly items
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('payroll')
                              .doc(_selectedUid)
                              .collection('months')
                              .doc(_monthId)
                              .snapshots(),
                          builder: (context, s) {
                            final m = s.data?.data() ?? {};
                            if (!_seededMonth) {
                              _bonusCtrl.text =
                                  (m['bonuses'] is num) ? (m['bonuses'] as num).toString() : (m['bonuses'] ?? '0').toString();
                              _otCtrl.text =
                                  (m['overtimeAmount'] is num) ? (m['overtimeAmount'] as num).toString() : (m['overtimeAmount'] ?? '0').toString();
                              _deductCtrl.text =
                                  (m['deductions'] is num) ? (m['deductions'] as num).toString() : (m['deductions'] ?? '0').toString();
                              _seededMonth = true;
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Monthly items for $_monthId',
                                    style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _bonusCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: _numDecoration(
                                          'Bonuses',
                                          help: 'مكافآت هذا الشهر فقط. لا تؤثر على الشهور الأخرى.',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _otCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: _numDecoration(
                                          'Overtime amount',
                                          help:
                                              'قيمة الأوفر تايم لهذا الشهر (بالعملة). لو هتستخدم حسبة تلقائية لاحقًا نقدر نملأه آليًا.',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _deductCtrl,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: _numDecoration(
                                          'Deductions',
                                          help: 'أي خصومات على راتب هذا الشهر (تأخير، جزاءات، ...).',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FilledButton.icon(
                                    onPressed: _saveMonth,
                                    icon: const Icon(Icons.save),
                                    label: const Text('Save month items'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ======== Leaves tab (placeholder with tips) ========
          _InfoTab(
            title: 'Leaves',
            message:
                'هنا سندير أرصدة الإجازات للموظفين (سنوية/مرضية/بدل راحة...). '
                'يمكن تعريف سياسة الرصيد في وثيقة مشتركة، ثم إنشاء حركات + و - لكل شهر. '
                'عند الموافقة على طلب إجازة من شاشة الموظف سيتم الخصم آليًا.',
          ),

          // ======== Loans tab (placeholder with tips) ========
          _InfoTab(
            title: 'Loans',
            message:
                'سندير هنا السلف/القروض: المبلغ الأصل + نسبة الاستقطاع الشهري + الرصيد المتبقي. '
                'عند حفظ كشف الراتب لشهر معين سيتم خصم القسط الآلي وتحديث الرصيد.',
          ),
        ],
      ),
    );
  }
}

// Simple information placeholder with icon
class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 8),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
