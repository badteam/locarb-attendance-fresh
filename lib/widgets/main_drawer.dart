import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Screens
import '../screens/dashboard_screen.dart';
import '../screens/attendance_report_screen.dart';
import '../screens/admin_users_screen.dart';
import '../screens/branches_shifts_screen.dart';

class MainDrawer extends StatefulWidget {
  /// مرّر كولباك يغيّر الثيم على مستوى التطبيق (اختياري)
  final void Function(bool isDark)? onToggleTheme;

  const MainDrawer({super.key, this.onToggleTheme});

  @override
  State<MainDrawer> createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  bool _dark = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // خُد الحالة الحالية من الثيم
    final isDarkNow = Theme.of(context).brightness == Brightness.dark;
    _dark = isDarkNow;
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).pop(); // اغلاق الدروار
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.0,
              color: Theme.of(context).hintColor,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? '';
    final email = user?.email ?? '';
    final photoUrl = user?.photoURL;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // ---- Profile Header ----
            UserAccountsDrawerHeader(
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              currentAccountPicture: CircleAvatar(
                backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                    ? NetworkImage(photoUrl)
                    : null,
                child: (photoUrl == null || photoUrl.isEmpty)
                    ? Text(
                        (displayName.isNotEmpty
                                ? displayName[0]
                                : (email.isNotEmpty ? email[0] : 'U'))
                            .toUpperCase(),
                        style: const TextStyle(fontSize: 24),
                      )
                    : null,
              ),
              accountName: Text(
                displayName.isNotEmpty ? displayName : 'LoCarb User',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              accountEmail: Text(email.isNotEmpty ? email : '—'),
            ),

            // ---- Body (scrollable) ----
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _sectionTitle('Overview'),
                  ListTile(
                    leading: const Icon(Icons.dashboard_outlined),
                    title: const Text('Dashboard'),
                    subtitle: const Text('Main overview'),
                    onTap: () => _open(context, const DashboardScreen()),
                  ),

                  _sectionTitle('Reports'),
                  ListTile(
                    leading: const Icon(Icons.insert_chart_outlined),
                    title: const Text('Attendance Reports'),
                    subtitle: const Text('Filter & export'),
                    onTap: () => _open(context, const AttendanceReportScreen()),
                  ),

                  _sectionTitle('Management'),
                  ListTile(
                    leading: const Icon(Icons.people_alt_outlined),
                    title: const Text('Users'),
                    subtitle: const Text('Approvals & roles'),
                    onTap: () => _open(context, const AdminUsersScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.storefront),
                    title: const Text('Branches & Shifts'),
                    subtitle: const Text('Locations, geofence & shifts'),
                    onTap: () => _open(context, const BranchesShiftsScreen()),
                  ),

                  _sectionTitle('Settings'),
                  SwitchListTile(
                    secondary: const Icon(Icons.dark_mode_outlined),
                    title: const Text('Dark Mode'),
                    value: _dark,
                    onChanged: (v) {
                      setState(() => _dark = v);
                      if (widget.onToggleTheme != null) {
                        widget.onToggleTheme!(v);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Theme toggle needs wiring in MaterialApp (onToggleTheme not provided).'),
                          ),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Support'),
                    subtitle: const Text('FAQs & contact'),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Support screen coming soon.'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const Divider(height: 1),
            // ---- Footer actions ----
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout'),
              onTap: () async {
                try {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Logout failed: $e')),
                    );
                  }
                }
              },
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'LoCarb Admin © 2025',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).hintColor,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
