import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Attendance Reports (English)
/// - Date range filter + optional branch & shift filter (branch/shift filtered on client)
/// - Grouped by day
/// - Shows employee name, avatar, branch name, shift name and time
/// - Highlights entries made from a branch different than user's assigned branch (at that time)
class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  String? _branchId;
  String? _shiftId;

  // Simple caches to avoid repeated reads
  final Map<String, String> _userNameCache = {};
  final Map<String, String> _userAvatarCache = {};
  final Map<String, String> _userAssignedBranchCache = {};
  final Map<String, String> _branchNameCache = {};
  final Map<String, String> _shiftNameCache = {};

  // Date pickers
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

  // YYYY-MM-DD (stable for ordering and comparisons)
  String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  // Fetch user display info (name + avatarUrl + assignedBranch at the moment)
  Future<(String name, String avatarUrl, String assignedBranchId)> _userInfo(String uid) async {
    String name, avatar, assignedBranch;
    if (_userNameCache.containsKey(uid)) {
      name = _userNameCache[uid]!;
      avatar = _userAvatarCache[uid] ?? '';
      assignedBranch = _userAssignedBranchCache[uid] ?? '';
      return (name, avatar, assignedBranch);
    }
    try {
      final s = await FirebaseFirestore.instance.doc('users/$uid').get();
      final m = s.data() ?? {};
      final full = (m['fullName'] ?? '').toString();
      final uname = (m['username'] ?? '').toString();
      name = full.isNotEmpty ? full : (uname.isNotEmpty ? uname : uid);
      avatar = (m['avatarUrl'] ?? '').toString();
      assignedBranch = (m['branchId'] ?? '').toString();
      _userNameCache[uid] = name;
      _userAvatarCache[uid] = avatar;
      _userAssignedBranchCache[uid] = assignedBranch;
      return (name, avatar, assignedBranch);
    } catch (_) {
      _userNameCache[uid] = uid;
      _userAvatarCache[uid] = '';
      _userAssignedBranchCache[uid] = '';
      return (uid, '', '');
    }
  }

  // Fetch branch name
  Future<String> _branchName(String id) async {
    if (id.isEmpty) return 'Unassigned';
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

  // Fetch shift name
  Future<String> _shiftName(String id) async {
    if (id.isEmpty) return 'Unassigned';
    if (_shiftNameCache.containsKey(id)) return _shiftNameCache[id]!;
    try {
      final s = await FirebaseFirestore.instance.doc('shifts/$id').get();
      final m = s.data() ?? {};
      final name = (m['name'] ?? id).toString();
      _shiftNameCache[id] = name;
      return name;
    } catch (_) {
      _shiftNameCache[id] = id;
      return id;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Query by date range only; order by the same field to avoid composite index
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('attendance')
        .where('localDay', isGreaterThanOrEqualTo: _fmtDay(_from))
        .where('localDay', isLessThanOrEqualTo: _fmtDay(_to))
        .orderBy('localDay', descending: true);

    final branchesRef =
        FirebaseFirestore.instance.collection('branches').orderBy('name');
    final shiftsRef =
        FirebaseFirestore.instance.collection('shifts').orderBy('name');

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filters bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Wrap(
              runSpacing: 8,
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _FilterButton(
                  icon: Icons.date_range,
                  label: 'From: ${_fmtDay(_from)}',
                  onTap: _pickFrom,
                ),
                _FilterButton(
                  icon: Icons.event,
                  label: 'To: ${_fmtDay(_to)}',
                  onTap: _pickTo,
                ),
                // Branch dropdown
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: branchesRef.snapshots(),
                  builder: (context, snap) {
                    final items = <DropdownMenuItem<String>>[
                      const DropdownMenuItem(value: '', child: Text('All branches')),
                    ];
                    if (snap.hasData) {
                      for (final d in snap.data!.docs) {
                        final name = (d.data()['name'] ?? d.id).toString();
                        items.add(DropdownMenuItem(value: d.id, child: Text(name)));
                      }
                    }
                    return InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Branch',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _branchId ?? '',
                          items: items,
                          onChanged: (v) =>
                              setState(() => _branchId = (v ?? '').isEmpty ? null : v),
                        ),
                      ),
                    );
                  },
                ),
                // Shift dropdown
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: shiftsRef.snapshots(),
                  builder: (context, snap) {
                    final items = <DropdownMenuItem<String>>[
                      const DropdownMenuItem(value: '', child: Text('All shifts')),
                    ];
                    if (snap.hasData) {
                      for (final d in snap.data!.docs) {
                        final name = (d.data()['name'] ?? d.id).toString();
                        items.add(DropdownMenuItem(value: d.id, child: Text(name)));
                      }
                    }
                    return InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Shift',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _shiftId ?? '',
                          items: items,
                          onChanged: (v) =>
                              setState(() => _shiftId = (v ?? '').isEmpty ? null : v),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // List
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

                var docs = snap.data?.docs ?? [];

                // Client-side filters (to avoid composite index for now)
                if (_branchId != null && _branchId!.isNotEmpty) {
                  docs = docs
                      .where((d) =>
                          (d.data()['branchId'] ?? '').toString() == _branchId)
                      .toList();
                }
                if (_shiftId != null && _shiftId!.isNotEmpty) {
                  docs = docs
                      .where((d) =>
                          (d.data()['shiftId'] ?? '').toString() == _shiftId)
                      .toList();
                }

                if (docs.isEmpty) {
                  return const Center(child: Text('No records in the selected range'));
                }

                // Summary
                final uniqueUsers = <String>{};
                for (final d in docs) {
                  uniqueUsers.add((d.data()['userId'] ?? '').toString());
                }

                // Group by day
                final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
                    byDay = {};
                for (final d in docs) {
                  final day = (d.data()['localDay'] ?? '').toString();
                  byDay.putIfAbsent(day, () => []).add(d);
                }
                final orderedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: orderedDays.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total records: ${docs.length}'),
                              Text('Employees: ${uniqueUsers.length}'),
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
                      userInfoOf: _userInfo,
                      branchNameOf: _branchName,
                      shiftNameOf: _shiftName,
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

/// Section for a single day
class _DaySection extends StatelessWidget {
  final String day;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> items;
  final Future<(String name, String avatarUrl, String assignedBranchId)> Function(String uid) userInfoOf;
  final Future<String> Function(String branchId) branchNameOf;
  final Future<String> Function(String shiftId) shiftNameOf;
  final String Function(Timestamp? ts) fmtTime;

  const _DaySection({
    required this.day,
    required this.items,
    required this.userInfoOf,
    required this.branchNameOf,
    required this.shiftNameOf,
    required this.fmtTime,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text('Date: $day', style: Theme.of(context).textTheme.titleMedium),
        ),
        ...items.map((d) {
          final m = d.data();
          final uid = (m['userId'] ?? '').toString();
          final typ = (m['type'] ?? '').toString(); // in / out
          final branchId = (m['branchId'] ?? '').toString();
          final shiftId = (m['shiftId'] ?? '').toString();
          final lat = (m['lat'] ?? 0).toString();
          final lng = (m['lng'] ?? 0).toString();
          final at = m['at'] is Timestamp ? (m['at'] as Timestamp) : null;

          return FutureBuilder<(String name, String avatarUrl, String assignedBranchId)>(
            future: userInfoOf(uid),
            builder: (context, userSnap) {
              final name = (userSnap.data?.$1 ?? uid);
              final avatarUrl = (userSnap.data?.$2 ?? '');
              final assignedBranchId = (userSnap.data?.$3 ?? '');

              return FutureBuilder<List<String>>(
                future: Future.wait([
                  branchNameOf(branchId),
                  shiftNameOf(shiftId),
                ]),
                builder: (context, infoSnap) {
                  final branchName = (infoSnap.data?.elementAtOrNull(0) ?? branchId);
                  final shiftName = (infoSnap.data?.elementAtOrNull(1) ?? 'Unassigned');

                  final usedDifferentBranch =
                      assignedBranchId.isNotEmpty &&
                      branchId.isNotEmpty &&
                      assignedBranchId != branchId;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 1.5,
                    child: ListTile(
                      leading: _Avatar(avatarUrl: avatarUrl, name: name, typ: typ),
                      title: Row(
                        children: [
                          Expanded(child: Text(name)),
                          const SizedBox(width: 8),
                          if (usedDifferentBranch)
                            Chip(
                              label: const Text(
                                'Other branch',
                                style: TextStyle(color: Colors.white),
                              ),
                              backgroundColor: Colors.indigo,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text('Branch: $branchName • Shift: $shiftName • Time: ${fmtTime(at)}'),
                          Text(
                            '($lat, $lng)',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                      trailing: Chip(
                        label: Text(
                          typ == 'in' ? 'Check-in' : 'Check-out',
                          style: const TextStyle(color: Colors.white),
                        ),
                        backgroundColor:
                            typ == 'in' ? Colors.green.shade600 : Colors.red.shade600,
                      ),
                    ),
                  );
                },
              );
            },
          );
        }),
      ],
    );
  }
}

/// Avatar with photo if available, otherwise first letter
class _Avatar extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final String typ;
  const _Avatar({required this.avatarUrl, required this.name, required this.typ});

  @override
  Widget build(BuildContext context) {
    final bg = typ == 'in' ? Colors.green.shade600 : Colors.red.shade600;
    if (avatarUrl.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(avatarUrl));
    }
    final ch = name.isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      backgroundColor: bg,
      child: Text(ch, style: const TextStyle(color: Colors.white)),
    );
  }
}

/// Nice filter button
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

/// Clear error box
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
            'Query error:\n$error\n\n'
            'If it mentions an index, you can either select "All branches" '
            'or create the composite index in Firebase Console > Firestore > Indexes.',
          ),
        ),
      ),
    );
  }
}

// Small helper for null-safe elementAt
extension<T> on List<T> {
  T? elementAtOrNull(int index) => (index >= 0 && index < length) ? this[index] : null;
}
