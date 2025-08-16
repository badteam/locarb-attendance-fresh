import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/main_drawer.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      drawer: const MainDrawer(),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, c) {
            final isWide = c.maxWidth > 820;
            return GridView.count(
              crossAxisCount: isWide ? 3 : 1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _NavCard(
                  icon: Icons.assessment_outlined,
                  title: 'Attendance Reports',
                  subtitle: 'Filter & export',
                  onTap: () => Navigator.pushNamed(context, '/reports'),
                ),
                _NavCard(
                  icon: Icons.group_outlined,
                  title: 'Users',
                  subtitle: 'Manage employees',
                  onTap: () => Navigator.pushNamed(context, '/users'),
                ),
                _NavCard(
                  icon: Icons.store_outlined,
                  title: 'Branches & Shifts',
                  subtitle: 'Locations, rotations',
                  onTap: () => Navigator.pushNamed(context, '/branches'),
                ),
                _NavCard(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Admin Panel',
                  subtitle: 'Approvals & roles',
                  onTap: () => Navigator.pushNamed(context, '/admin'),
                ),
                _NavCard(
                  icon: Icons.person_outline,
                  title: 'Employee Home',
                  subtitle: 'Check-in/out',
                  onTap: () => Navigator.pushNamed(context, '/employee'),
                ),
                _TodayStats(dayStr: dayStr),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(radius: 26, child: Icon(icon, size: 26)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayStats extends StatelessWidget {
  final String dayStr;
  const _TodayStats({required this.dayStr});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('attendance')
        .where('localDay', isEqualTo: dayStr);

    return StreamBuilder(
      stream: q.snapshots(),
      builder: (context, snap) {
        final total = snap.hasData ? snap.data!.docs.length : 0;
        final inCount =
            snap.hasData ? snap.data!.docs.where((d) => d['type'] == 'in').length : 0;
        final outCount =
            snap.hasData ? snap.data!.docs.where((d) => d['type'] == 'out').length : 0;

        return Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Today Overview', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('Date: $dayStr'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _chip('Total', total, Colors.blueGrey),
                    const SizedBox(width: 8),
                    _chip('IN', inCount, Colors.green),
                    const SizedBox(width: 8),
                    _chip('OUT', outCount, Colors.red),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, int v, Color c) {
    return Chip(
      label: Text('$label: $v'),
      avatar: CircleAvatar(backgroundColor: c, radius: 8),
    );
  }
}
