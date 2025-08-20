// lib/admin/tabs/absences_tab.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AbsencesTab extends StatefulWidget {
  const AbsencesTab({super.key});
  @override
  State<AbsencesTab> createState() => _AbsencesTabState();
}

class _AbsencesTabState extends State<AbsencesTab> {
  final _db = FirebaseFirestore.instance;

  // فلاتر مبدئية: الشهر الحالي
  late DateTime _from;
  late DateTime _to;
  String _status = 'all'; // all | absent | missing | present
  String? _branchId;
  final TextEditingController _search = TextEditingController();

  // كاش لأسماء الموظفين
  Map<String, String> _userNames = {}; // userId -> name(code)
  Map<String, String> _userCodes = {}; // userId -> code
  Map<String, String> _userBranchName = {}; // userId -> last branchName (احتياطي)

  late Future<List<AbsenceRow>> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);
    _future = _loadData();
  }

  String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadUsersCache() async {
    final snap = await _db.collection('users').get();
    _userNames = {};
    _userCodes = {};
    _userBranchName = {};
    for (final d in snap.docs) {
      final data = d.data();
      final code = (data['code'] ?? '').toString();
      final name = (data['name'] ?? '').toString();
      final branchName = (data['branchName'] ?? '').toString();
      _userCodes[d.id] = code;
      _userNames[d.id] = name.isEmpty ? code : '$name (${code})';
      if (branchName.isNotEmpty) _userBranchName[d.id] = branchName;
    }
  }

  Future<List<AbsenceRow>> _loadData() async {
    // 1) كاش أسماء الموظفين (مرة واحدة تكفي في الجلسة)
    if (_userNames.isEmpty) {
      await _loadUsersCache();
    }

    final fromStr = _fmtDay(_from);
    final toStr = _fmtDay(_to);

    // 2) بناء Query على attendance
    Query<Map<String, dynamic>> q = _db
        .collection('attendance')
        .where('localDay', isGreaterThanOrEqualTo: fromStr)
        .where('localDay', isLessThanOrEqualTo: toStr);

    if (_branchId != null && _branchId!.isNotEmpty) {
      q = q.where('branchId', isEqualTo: _branchId);
    }

    // NOTE: لا نفلتر بالـstatus هنا لأننا بنستنتجه من in/out/absent بعد التجميع

    // 3) جلب البيانات بحد أقصى وانتظار مع timeout
    final snap = await q.orderBy('localDay')
        .limit(20000) // يكفي لشهر واحد لعدد معقول من الموظفين
        .get()
        .timeout(const Duration(seconds: 20));

    // 4) تجميع per (userId, localDay)
    final Map<String, _DayAgg> agg = {}; // key = "$userId|$localDay"
    for (final d in snap.docs) {
      final data = d.data();
      final userId = (data['userId'] ?? '').toString();
      final localDay = (data['localDay'] ?? '').toString();
      final type = (data['type'] ?? '').toString(); // in|out|absent
      final branchName = (data['branchName'] ?? '').toString();

      if (userId.isEmpty || localDay.isEmpty || type.isEmpty) continue;
      final key = '$userId|$localDay';
      agg.putIfAbsent(key, () => _DayAgg(userId: userId, localDay: localDay));
      agg[key]!.types.add(type);
      if (branchName.isNotEmpty) {
        agg[key]!.branchName = branchName;
      }
    }

    // 5) تحويل التجميعة لنتيجة قابلة للعرض
    final List<AbsenceRow> rows = [];
    agg.forEach((key, a) {
      String status;
      if (a.types.contains('absent')) {
        status = 'absent';
      } else if (a.types.contains('in') && a.types.contains('out')) {
        status = 'present';
      } else {
        status = 'missing';
      }

      // فلترة حسب المطلوب
      if (_status != 'all' && status != _status) return;

      final userTitle = _userNames[a.userId] ?? a.userId;
      final code = _userCodes[a.userId] ?? '';
      final branchName = a.branchName.isNotEmpty
          ? a.branchName
          : (_userBranchName[a.userId] ?? '');

      // بحث بالاسم/الكود
      final query = _search.text.trim().toLowerCase();
      if (query.isNotEmpty) {
        final t = '$userTitle $code'.toLowerCase();
        if (!t.contains(query)) return;
      }

      rows.add(
        AbsenceRow(
          userId: a.userId,
          userTitle: userTitle,
          localDay: a.localDay,
          status: status, // absent | missing | present
          branchName: branchName,
        ),
      );
    });

    // ترتيب بسيط: بالتاريخ ثم بالاسم
    rows.sort((a, b) {
      final c = a.localDay.compareTo(b.localDay);
      if (c != 0) return c;
      return a.userTitle.compareTo(b.userTitle);
    });

    return rows;
  }

  void _applyFilters({DateTime? from, DateTime? to, String? status, String? branchId}) {
    if (from != null) _from = from;
    if (to != null) _to = to;
    if (status != null) _status = status;
    _branchId = branchId;
    setState(() {
      _future = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FiltersBar(
          from: _from,
          to: _to,
          status: _status,
          branchId: _branchId,
          searchCtrl: _search,
          onApply: (f) => _applyFilters(
            from: f.from,
            to: f.to,
            status: f.status,
            branchId: f.branchId,
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AbsenceRow>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _StateMessage(
                  icon: Icons.error_outline,
                  text: 'حدث خطأ أثناء التحميل.\n${snap.error}',
                  onRetry: () => setState(() => _future = _loadData()),
                );
              }
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                return _StateMessage(
                  icon: Icons.inbox_outlined,
                  text: 'لا يوجد غياب/نواقص في الفترة المحددة.',
                  onRetry: () => setState(() => _future = _loadData()),
                );
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final icon = r.status == 'absent'
                      ? Icons.event_busy
                      : (r.status == 'missing'
                          ? Icons.report_problem_outlined
                          : Icons.check_circle_outline);
                  final statusText = r.status == 'absent'
                      ? 'Absent'
                      : (r.status == 'missing' ? 'Missing' : 'Present');
                  return ListTile(
                    leading: Icon(icon),
                    title: Text(r.userTitle),
                    subtitle: Text('${r.localDay}  •  ${r.branchName.isEmpty ? '—' : r.branchName}'),
                    trailing: Text(statusText),
                    onTap: () {
                      // ممكن تفتح تفاصيل اليوم للمستخدم هنا
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

class _DayAgg {
  final String userId;
  final String localDay;
  final Set<String> types = <String>{}; // in/out/absent
  String branchName = '';
  _DayAgg({required this.userId, required this.localDay});
}

class AbsenceRow {
  final String userId;
  final String userTitle;
  final String localDay; // YYYY-MM-DD
  final String status; // absent | missing | present
  final String branchName;
  AbsenceRow({
    required this.userId,
    required this.userTitle,
    required this.localDay,
    required this.status,
    required this.branchName,
  });
}

class _FiltersBar extends StatefulWidget {
  final DateTime from;
  final DateTime to;
  final String status;
  final String? branchId;
  final TextEditingController searchCtrl;
  final void Function(_FiltersData) onApply;
  const _FiltersBar({
    required this.from,
    required this.to,
    required this.status,
    required this.branchId,
    required this.searchCtrl,
    required this.onApply,
  });

  @override
  State<_FiltersBar> createState() => _FiltersBarState();
}

class _FiltersBarState extends State<_FiltersBar> {
  late DateTime _from = widget.from;
  late DateTime _to = widget.to;
  late String _status = widget.status;
  String? _branchId;
  @override
  void initState() {
    super.initState();
    _branchId = widget.branchId;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            _DateChip(
              label: 'من',
              date: _from,
              onPick: (d) => setState(() => _from = d),
            ),
            _DateChip(
              label: 'إلى',
              date: _to,
              onPick: (d) => setState(() => _to = d),
            ),
            DropdownButton<String>(
              value: _status,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'absent', child: Text('Absent')),
                DropdownMenuItem(value: 'missing', child: Text('Missing')),
                DropdownMenuItem(value: 'present', child: Text('Present')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'all'),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: widget.searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'بحث بالاسم/الكود',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            // إدخال branchId يدويًا كقيمة (أو بدّله بقائمة فروع من Firestore)
            SizedBox(
              width: 160,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Branch ID (اختياري)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _branchId = v.trim().isEmpty ? null : v.trim(),
              ),
            ),
            FilledButton.icon(
              onPressed: () => widget.onApply(_FiltersData(
                from: _from,
                to: _to,
                status: _status,
                branchId: _branchId,
              )),
              icon: const Icon(Icons.search),
              label: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FiltersData {
  final DateTime from;
  final DateTime to;
  final String status;
  final String? branchId;
  _FiltersData({required this.from, required this.to, required this.status, this.branchId});
}

class _DateChip extends StatelessWidget {
  final String label;
  final DateTime date;
  final ValueChanged<DateTime> onPick;
  const _DateChip({required this.label, required this.date, required this.onPick, super.key});
  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text('$label: ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2023, 1, 1),
          lastDate: DateTime(2030, 12, 31),
        );
        if (picked != null) onPick(picked);
      },
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onRetry;
  const _StateMessage({required this.icon, required this.text, required this.onRetry, super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
