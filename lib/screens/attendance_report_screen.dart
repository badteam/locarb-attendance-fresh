import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// شاشة تقارير الحضور – عرض مهني مع:
/// - فلاتر تاريخ + فرع
/// - تجميع حسب اليوم
/// - إظهار اسم الموظف والفرع من كاش بسيط
/// - كروت أنيقة و Chips لنوع الحركة
class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  String? _branchId;

  // كاش بسيط للأسماء (يجنبنا استعلامات مكررة)
  final Map<String, String> _userNameCache = {};
  final Map<String, String> _branchNameCache = {};

  // أدوات اختيار التاريخ
  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _from = DateTime(d.year, d.month, d.day));
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _to = DateTime(d.year, d.month, d.day));
  }

  String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  // يجلب الاسم المعروض للمستخدم من الكاش أو Firestore
  Future<String> _displayUser(String uid) async {
    if (_userNameCache.containsKey(uid)) return _userNameCache[uid]!;
    try {
      final s = await FirebaseFirestore.instance.doc('users/$uid').get();
      final m = s.data() ?? {};
      final full = (m['fullName'] ?? '').toString();
      final uname = (m['username'] ?? '').toString();
      final name = full.isNotEmpty ? full : (uname.isNotEmpty ? uname : uid);
      _userNameCache[uid] = name;
      return name;
    } catch (_) {
      _userNameCache[uid] = uid;
      return uid;
    }
  }

  // يجلب اسم الفرع من الكاش أو Firestore
  Future<String> _displayBranch(String id) async {
    if (id.isEmpty) return 'غير مُعيّن';
    if (_branchNameCache.containsKey(id)) return _branchNameCache[id]!;
    try {
      final s = await FirebaseFirestore.instance.doc('branches/$id').get();
      final m = s.data() ?? {};
      final name = (m['name'] ?? id).toString();
      _branchNameCache[id] = name;
      return name;
    } catch (_) {
      _branchNameCache[id] = id;
      return id;
    }
  }

  @override
  Widget build(BuildContext context) {
    // استعلام الحضور: فلترة بالمدى (localDay) + فرع اختياري
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('attendance')
        .where('localDay', isGreaterThanOrEqualTo: _fmtDay(_from))
        .where('localDay', isLessThanOrEqualTo: _fmtDay(_to));

    if (_branchId != null && _branchId!.isNotEmpty) {
      q = q.where('branchId', isEqualTo: _branchId);
    }

    // لتقليل الفهارس المطلوبة: نرتب على نفس حقل الفلترة
    q = q.orderBy('localDay', descending: true);

    // قائمة الفروع لعنصر الفلتر
    final branchesRef =
        FirebaseFirestore.instance.collection('branches').orderBy('name');

    return Scaffold(
      body: Column(
        children: [
          // شريط الفلاتر (تصميم نظيف)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Wrap(
              runSpacing: 8,
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _FilterButton(
                  icon: Icons.date_range,
                  label: 'من: ${_fmtDay(_from)}',
                  onTap: _pickFrom,
                ),
                _FilterButton(
                  icon: Icons.event,
                  label: 'إلى: ${_fmtDay(_to)}',
                  onTap: _pickTo,
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: branchesRef.snapshots(),
                  builder: (context, snap) {
                    final items = <DropdownMenuItem<String>>[
                      const DropdownMenuItem(value: '', child: Text('كل الفروع')),
                    ];
                    if (snap.hasData) {
                      for (final d in snap.data!.docs) {
                        final name = (d.data()['name'] ?? d.id).toString();
                        items.add(DropdownMenuItem(
                            value: d.id, child: Text(name)));
                      }
                    }
                    return InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'الفرع',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _branchId ?? '',
                          items: items,
                          onChanged: (v) => setState(
                              () => _branchId = (v ?? '').isEmpty ? null : v),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 1),

          // القائمة
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _ErrorBox(error: snap.error.toString());
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('لا توجد سجلات في المدى المختار'));
                }

                // ملخص سريع
                final uniqueUsers = <String>{};
                for (final d in docs) {
                  uniqueUsers.add((d.data()['userId'] ?? '').toString());
                }

                // تجميع حسب اليوم
                final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
                    byDay = {};
                for (final d in docs) {
                  final day = (d.data()['localDay'] ?? '').toString();
                  byDay.putIfAbsent(day, () => []).add(d);
                }
                final orderedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a)); // تنازلي

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: orderedDays.length + 1, // +1 للملخص أعلى
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // كارت الملخص
                      return Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('إجمالي السجلات: ${docs.length}'),
                              Text('عدد الموظفين: ${uniqueUsers.length}'),
                            ],
                          ),
                        ),
                      );
                    }

                    final day = orderedDays[index - 1];
                    final items = byDay[day]!;
                    return _DaySection(
                      day: day,
                      items: items,
                      userNameOf: _displayUser,
                      branchNameOf: _displayBranch,
                      fmtTime: _fmtTime,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// عنصر تجميعي ليوم واحد
class _DaySection extends StatelessWidget {
  final String day;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> items;
  final Future<String> Function(String uid) userNameOf;
  final Future<String> Function(String branchId) branchNameOf;
  final String Function(Timestamp? ts) fmtTime;

  const _DaySection({
    required this.day,
    required this.items,
    required this.userNameOf,
    required this.branchNameOf,
    required this.fmtTime,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // عنوان اليوم
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text('التاريخ: $day',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        // كروت السجلات
        ...items.map((d) {
          final m = d.data();
          final uid = (m['userId'] ?? '').toString();
          final typ = (m['type'] ?? '').toString(); // in/out
          final branchId = (m['branchId'] ?? '').toString();
          final lat = (m['lat'] ?? 0).toString();
          final lng = (m['lng'] ?? 0).toString();
          final at = m['at'] is Timestamp ? (m['at'] as Timestamp) : null;

          return FutureBuilder<List<String>>(
            future: Future.wait([
              userNameOf(uid),
              branchNameOf(branchId),
            ]),
            builder: (context, snap) {
              final userName = (snap.data?[0] ?? uid);
              final branchName = (snap.data?[1] ?? branchId);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 1.5,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        typ == 'in' ? Colors.green.shade600 : Colors.red.shade600,
                    child: Icon(
                      typ == 'in' ? Icons.login : Icons.logout,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(userName, textDirection: TextDirection.rtl),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        'الفرع: $branchName • الوقت: ${fmtTime(at)}',
                        textDirection: TextDirection.rtl,
                      ),
                      Text(
                        '(${lat}, ${lng})',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                  ),
                  trailing: Chip(
                    label: Text(
                      typ == 'in' ? 'دخول' : 'انصراف',
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor:
                        typ == 'in' ? Colors.green.shade600 : Colors.red.shade600,
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}

/// زر فلتر أنيق
class _FilterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FilterButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

/// صندوق خطأ واضح
class _ErrorBox extends StatelessWidget {
  final String error;
  const _ErrorBox({required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'خطأ في الاستعلام:\n$error\n\n'
            'لو الرسالة تشير إلى Index، افتح Firebase Console > Firestore > Indexes وأنشئ الفهرس المطلوب.',
            textDirection: TextDirection.rtl,
          ),
        ),
      ),
    );
  }
}
