// lib/admin/screens/admin_users_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// نستخدم مسار نسبي لتفادي معرفة اسم الباكدج
import '../tabs/absences_tab.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  static const _tabs = <Tab>[
    Tab(text: 'Users'),
    Tab(text: 'Absences'),
    Tab(text: 'Branches'),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin • Users & Attendance'),
          bottom: const TabBar(isScrollable: true, tabs: _tabs),
          actions: [
            IconButton(
              tooltip: 'Reload current tab',
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: const TabBarView(
          children: [
            _UsersTab(),
            AbsencesTab(),        // ← تبويب الغياب الجديد
            _BranchesTab(),
          ],
        ),
      ),
    );
  }
}

/// ===============================
/// Users Tab
/// ===============================
class _UsersTab extends StatefulWidget {
  const _UsersTab({super.key});

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final _db = FirebaseFirestore.instance;

  // فلاتر
  String _role = 'all';     // employee | supervisor | manager | all
  String _status = 'all';   // active | on_leave | suspended | all
  String? _branchId;        // اختياري
  final _search = TextEditingController();

  // Paging
  static const int _pageSize = 40;
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _loading = false;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _items = [];

  // كاش للفروع لعرض الاسم بدل الـID
  Map<String, String> _branches = {};

  @override
  void initState() {
    super.initState();
    _loadBranchesCache();
    _refresh();
  }

  Future<void> _loadBranchesCache() async {
    try {
      final snap = await _db.collection('branches').get();
      final map = <String, String>{};
      for (final d in snap.docs) {
        final data = d.data();
        map[d.id] = (data['name'] ?? '').toString();
      }
      setState(() => _branches = map);
    } catch (_) {/* تجاهل */}
  }

  Future<void> _refresh() async {
    _items.clear();
    _lastDoc = null;
    _hasMore = true;
    await _loadMore();
  }

  Query<Map<String, dynamic>> _buildBaseQuery() {
    Query<Map<String, dynamic>> q = _db.collection('users');

    if (_role != 'all') {
      q = q.where('role', isEqualTo: _role);
    }
    if (_status != 'all') {
      q = q.where('status', isEqualTo: _status);
    }
    if (_branchId != null && _branchId!.isNotEmpty) {
      q = q.where('branchId', isEqualTo: _branchId);
    }

    // ترتيب ثابت
    q = q.orderBy('name', descending: false);

    return q;
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading) return;
    setState(() => _loading = true);

    try {
      Query<Map<String, dynamic>> q = _buildBaseQuery();
      if (_lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }
      q = q.limit(_pageSize);

      // Timeout حتى لا يفضل تحميل
      final snap = await q.get().timeout(const Duration(seconds: 20));
      if (snap.docs.isNotEmpty) {
        _items.addAll(snap.docs);
        _lastDoc = snap.docs.last;
      }
      if (snap.docs.length < _pageSize) {
        _hasMore = false;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل المستخدمين: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _applyClientSearch(_items, _search.text.trim());

    return Column(
      children: [
        _UsersFiltersBar(
          role: _role,
          status: _status,
          branchId: _branchId,
          branches: _branches,
          searchCtrl: _search,
          onApply: (f) {
            _role = f.role;
            _status = f.status;
            _branchId = f.branchId;
            _refresh();
          },
          onClear: () {
            _role = 'all';
            _status = 'all';
            _branchId = null;
            _search.clear();
            _refresh();
          },
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                _loadMore();
              }
              return false;
            },
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: filtered.length + (_hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i >= filtered.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final d = filtered[i].data();
                  final code = (d['code'] ?? '').toString();
                  final name = (d['name'] ?? '').toString();
                  final email = (d['email'] ?? '').toString();
                  final phone = (d['phone'] ?? '').toString();
                  final role = (d['role'] ?? '').toString();
                  final status = (d['status'] ?? '').toString();
                  final branchId = (d['branchId'] ?? '').toString();
                  final branchName = (d['branchName'] ?? '').toString();

                  final bn = branchName.isNotEmpty
                      ? branchName
                      : (_branches[branchId] ?? branchId);

                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(name.isEmpty ? code : '$name ($code)'),
                    subtitle: Text([
                      if (email.isNotEmpty) email,
                      if (phone.isNotEmpty) phone,
                      if (bn.isNotEmpty) 'Branch: $bn',
                    ].join('  •  ')),
                    trailing: _UserBadges(role: role, status: status),
                    onTap: () {
                      // فتح تفاصيل المستخدم/تعديل - موضعك هنا
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyClientSearch(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> source, String query) {
    if (query.isEmpty) return source;
    final q = query.toLowerCase();
    return source.where((doc) {
      final d = doc.data();
      final code = (d['code'] ?? '').toString().toLowerCase();
      final name = (d['name'] ?? '').toString().toLowerCase();
      final email = (d['email'] ?? '').toString().toLowerCase();
      final phone = (d['phone'] ?? '').toString().toLowerCase();
      return code.contains(q) || name.contains(q) || email.contains(q) || phone.contains(q);
    }).toList();
  }
}

class _UsersFiltersBar extends StatefulWidget {
  final String role;
  final String status;
  final String? branchId;
  final Map<String, String> branches; // id -> name
  final TextEditingController searchCtrl;
  final void Function(_UsersFiltersData) onApply;
  final VoidCallback onClear;

  const _UsersFiltersBar({
    required this.role,
    required this.status,
    required this.branchId,
    required this.branches,
    required this.searchCtrl,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<_UsersFiltersBar> createState() => _UsersFiltersBarState();
}

class _UsersFiltersBarState extends State<_UsersFiltersBar> {
  late String _role = widget.role;
  late String _status = widget.status;
  String? _branchId = widget.branchId;

  @override
  Widget build(BuildContext context) {
    final branchItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem(value: null, child: Text('All branches')),
      ...widget.branches.entries.map(
        (e) => DropdownMenuItem(value: e.key, child: Text(e.value.isEmpty ? e.key : e.value)),
      ),
    ];

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: widget.searchCtrl,
                decoration: const InputDecoration(
                  hintText: 'Search name/code/email/phone',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => widget.onApply(_UsersFiltersData(
                  role: _role, status: _status, branchId: _branchId,
                )),
              ),
            ),
            DropdownButton<String>(
              value: _role,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All roles')),
                DropdownMenuItem(value: 'employee', child: Text('Employee')),
                DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
                DropdownMenuItem(value: 'manager', child: Text('Manager')),
              ],
              onChanged: (v) => setState(() => _role = v ?? 'all'),
            ),
            DropdownButton<String>(
              value: _status,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All statuses')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'on_leave', child: Text('On leave')),
                DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'all'),
            ),
            DropdownButton<String?>(
              value: _branchId,
              items: branchItems,
              onChanged: (v) => setState(() => _branchId = v),
            ),
            FilledButton.icon(
              onPressed: () => widget.onApply(_UsersFiltersData(
                role: _role, status: _status, branchId: _branchId,
              )),
              icon: const Icon(Icons.filter_alt),
              label: const Text('Apply'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onClear,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsersFiltersData {
  final String role;
  final String status;
  final String? branchId;
  _UsersFiltersData({required this.role, required this.status, required this.branchId});
}

class _UserBadges extends StatelessWidget {
  final String role;
  final String status;
  const _UserBadges({super.key, required this.role, required this.status});

  Color _statusColor(BuildContext c) {
    final s = status.toLowerCase();
    if (s == 'active') return Colors.green;
    if (s == 'on_leave') return Colors.orange;
    if (s == 'suspended') return Colors.red;
    return Theme.of(c).colorScheme.secondary;
    }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        Chip(
          label: Text(role.isEmpty ? '—' : role),
          visualDensity: VisualDensity.compact,
        ),
        Chip(
          label: Text(status.isEmpty ? '—' : status),
          backgroundColor: _statusColor(context).withOpacity(0.15),
          side: BorderSide(color: _statusColor(context)),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// ===============================
/// Branches Tab
/// ===============================
class _BranchesTab extends StatelessWidget {
  const _BranchesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Column(
      children: [
        const _BranchesHeader(),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('branches').orderBy('name').snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('خطأ في تحميل الفروع: ${snap.error}'));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('لا توجد فروع مسجلة'));
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final name = (d['name'] ?? '').toString();
                  final code = (d['code'] ?? '').toString();
                  final address = (d['address'] ?? '').toString();
                  final lat = d['geo']?['lat'];
                  final lng = d['geo']?['lng'];
                  final radius = d['radiusMeters'];

                  return ListTile(
                    leading: const Icon(Icons.store_outlined),
                    title: Text(name.isEmpty ? '—' : name),
                    subtitle: Text([
                      if (code.toString().isNotEmpty) 'Code: $code',
                      if (address.toString().isNotEmpty) address,
                      if (lat != null && lng != null) '($lat,$lng)',
                      if (radius != null) 'R: ${radius}m',
                    ].join('  •  ')),
                    onTap: () {
                      // تفاصيل الفرع (لو عايز تضيف شاشة تحرير فيما بعد)
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

class _BranchesHeader extends StatelessWidget {
  const _BranchesHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.apartment_outlined),
            Text(
              'Branches',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: 12),
            const Text('عرض الفروع المسجلة (قراءة فقط)'),
          ],
        ),
      ),
    );
  }
}
