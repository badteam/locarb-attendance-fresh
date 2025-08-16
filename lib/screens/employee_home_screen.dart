import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../widgets/main_drawer.dart';
import '../utils/geo.dart';

class EmployeeHomeScreen extends StatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  String? _selectedBranchId; // لو المستخدم يسمح له بأي فرع
  bool _submitting = false;
  String? _error;

  Future<Map<String, dynamic>?> _loadMyProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final snap = await FirebaseFirestore.instance.doc('users/$uid').get();
    return snap.data();
  }

  String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submitAttendance({required String type}) async {
    setState(() { _submitting = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _error = 'Not logged in');
        return;
      }

      final profile = await _loadMyProfile();
      if (profile == null) {
        setState(() => _error = 'Profile not found');
        return;
      }

      final allowAny = (profile['allowAnyBranch'] ?? false) == true;
      final primaryBranchId = (profile['primaryBranchId'] ?? '').toString();

      // حدّد branchId المقصود:
      String? branchId;
      if (allowAny) {
        // لازم يختار من القائمة
        if ((_selectedBranchId ?? '').isEmpty) {
          setState(() => _error = 'Please select a branch first');
          return;
        }
        branchId = _selectedBranchId;
      } else {
        // لازم الفرع الأساسي
        if (primaryBranchId.isEmpty) {
          setState(() => _error = 'No primary branch assigned to your profile');
          return;
        }
        branchId = primaryBranchId;
      }

      // هات بيانات الفرع للتأكد من النطاق
      final bSnap = await FirebaseFirestore.instance.doc('branches/$branchId').get();
      final b = bSnap.data() ?? {};
      final centerLat = (b['lat'] ?? 0.0).toDouble();
      final centerLng = (b['lng'] ?? 0.0).toDouble();
      final radius = (b['radiusMeters'] ?? 0) is int
          ? (b['radiusMeters'] as int)
          : int.tryParse(b['radiusMeters'].toString()) ?? 0;

      // موقع المستخدم الآن
      final pos = await getCurrentPosition();
      final userLat = pos.lat;
      final userLng = pos.lng;

      // تحقق المسافة (لو radius == 0 نعتبر مفيش قيد مسافة)
      if (radius > 0) {
        final inside = isInsideRadius(
          lat: userLat,
          lng: userLng,
          centerLat: centerLat,
          centerLng: centerLng,
          radiusMeters: radius,
        );
        if (!inside) {
          setState(() => _error = 'You are outside the allowed area for this branch.');
          return;
        }
      }

      // (اختياري) تحديد الشفت: هنا بسيط — ما بنجبر شفت
      String? shiftId;

      // اكتب سجل الحضور
      final now = DateTime.now();
      final localDay = _fmtDay(now);

      await FirebaseFirestore.instance.collection('attendance').add({
        'userId': user.uid,
        'type': type, // 'in' or 'out'
        'at': FieldValue.serverTimestamp(),
        'localDay': localDay,
        'branchId': branchId,
        'shiftId': shiftId ?? '',
        'lat': userLat,
        'lng': userLng,
        'via': kIsWeb ? 'web' : 'mobile',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Check-$type recorded successfully')),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final userDoc = FirebaseFirestore.instance.doc('users/$uid');
    final branchesRef = FirebaseFirestore.instance.collection('branches').orderBy('name');

    return Scaffold(
      appBar: AppBar(title: const Text('Employee Home')),
      drawer: const MainDrawer(),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: userDoc.get(),
        builder: (context, profileSnap) {
          if (profileSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = profileSnap.data?.data() ?? {};
          final fullName = (data['fullName'] ?? '').toString();
          final username = (data['username'] ?? '').toString();
          final displayName = fullName.isNotEmpty ? fullName : (username.isNotEmpty ? username : uid);
          final allowAny = (data['allowAnyBranch'] ?? false) == true;
          final primaryBranchId = (data['primaryBranchId'] ?? '').toString();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                Text('Welcome, $displayName', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('Check-in / Check-out with geofence validation.'),

                const SizedBox(height: 16),
                if (_error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!, style: const TextStyle(color: Colors.black)),
                    ),
                  ),

                const SizedBox(height: 8),
                if (allowAny) ...[
                  Text('You are allowed to check-in from ANY branch. Select one:'),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: branchesRef.snapshots(),
                    builder: (context, snap) {
                      final items = <DropdownMenuItem<String>>[
                        const DropdownMenuItem(value: '', child: Text('— Select branch —')),
                      ];
                      if (snap.hasData) {
                        for (final d in snap.data!.docs) {
                          final m = d.data();
                          final bName = (m['name'] ?? d.id).toString();
                          items.add(DropdownMenuItem(value: d.id, child: Text(bName)));
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
                            value: _selectedBranchId ?? '',
                            items: items,
                            onChanged: (v) => setState(() => _selectedBranchId = v ?? ''),
                          ),
                        ),
                      );
                    },
                  ),
                ] else ...[
                  // عرض الفرع الأساسي
                  FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: primaryBranchId.isEmpty
                        ? null
                        : FirebaseFirestore.instance.doc('branches/$primaryBranchId').get(),
                    builder: (context, bSnap) {
                      String branchName = '— not assigned —';
                      if (primaryBranchId.isNotEmpty) {
                        if (bSnap.hasData && bSnap.data!.data() != null) {
                          branchName = (bSnap.data!.data()!['name'] ?? primaryBranchId).toString();
                        } else {
                          branchName = primaryBranchId;
                        }
                      }
                      return ListTile(
                        title: const Text('Primary branch'),
                        subtitle: Text(branchName),
                        leading: const Icon(Icons.store_outlined),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _submitting ? null : () => _submitAttendance(type: 'in'),
                        icon: const Icon(Icons.login),
                        label: _submitting ? const Text('Working...') : const Text('Check-In'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _submitting ? null : () => _submitAttendance(type: 'out'),
                        icon: const Icon(Icons.logout),
                        label: _submitting ? const Text('Working...') : const Text('Check-Out'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                Text('Recent records', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _RecentMyAttendance(uid: uid),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RecentMyAttendance extends StatelessWidget {
  final String uid;
  const _RecentMyAttendance({required this.uid});

  String _fmtDay(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtTime(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final from = DateTime.now().subtract(const Duration(days: 7));
    final q = FirebaseFirestore.instance
        .collection('attendance')
        .where('userId', isEqualTo: uid)
        .where('localDay', isGreaterThanOrEqualTo: _fmtDay(from))
        .orderBy('localDay', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Error: ${snap.error}');
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Text('No recent records');

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final m = docs[i].data();
            final typ = (m['type'] ?? '').toString();
            final at = m['at'] is Timestamp ? (m['at'] as Timestamp) : null;
            final branchId = (m['branchId'] ?? '').toString();
            final coords = '(${(m['lat'] ?? 0).toString()}, ${(m['lng'] ?? 0).toString()})';

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: typ == 'in' ? Colors.green.shade600 : Colors.red.shade600,
                  child: Text(typ == 'in' ? 'IN' : 'OUT', style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
                title: Text('Day: ${m['localDay'] ?? ''}  •  Time: ${_fmtTime(at)}'),
                subtitle: Text('Branch: $branchId • $coords'),
              ),
            );
          },
        );
      },
    );
  }
}
