import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Screens
import '../screens/dashboard_screen.dart';
import '../screens/attendance_report_screen.dart';
import '../screens/admin_users_screen.dart';
import '../screens/branches_shifts_screen.dart';
import '../screens/payroll_loan_assistant.dart';
import '../screens/payroll_center_screen.dart';



// Admin tools (اتأكد إن الملفات دي موجودة)
import '../admin/fix_missing_shift_for_statuses.dart';
import '../admin/fix_ids_screen.dart';

class MainDrawer extends StatefulWidget {
  /// مرّر كولباك لتبديل الثيم (اختياري). مثال: (isDark) => ThemeController.setDark(isDark)
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
    _dark = Theme.of(context).brightness == Brightness.dark;
  }

  void _open(Widget screen) {
    Navigator.of(context).pop(); // اغلاق الدروار
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1,
              color: Theme.of(context).hintColor,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? 'LoCarb User';
    final email = user?.email ?? '—';
    final photo = user?.photoURL;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header (Profile)
            UserAccountsDrawerHeader(
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              currentAccountPicture: CircleAvatar(
                backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
                child: (photo == null || photo.isEmpty)
                    ? Text((name.isNotEmpty ? name[0] : 'U').toUpperCase(), style: const TextStyle(fontSize: 22))
                    : null,
              ),
              accountName: Text(name, overflow: TextOverflow.ellipsis),
              accountEmail: Text(email, overflow: TextOverflow.ellipsis),
            ),

            // Body
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _section('Overview'),
                  ListTile(
                    leading: const Icon(Icons.dashboard_outlined),
                    title: const Text('Dashboard'),
                    onTap: () => _open(const DashboardScreen()),
                  ),

                  _section('Reports'),
                  ListTile(
                    leading: const Icon(Icons.insert_chart_outlined),
                    title: const Text('Attendance Reports'),
                    subtitle: const Text('Filter & export'),
                    onTap: () => _open(const AttendanceReportScreen()),
                  ),

                  _section('Management'),
                  ListTile(
                    leading: const Icon(Icons.people_alt_outlined),
                    title: const Text('Users'),
                    subtitle: const Text('Approvals & roles'),
                    onTap: () => _open(const AdminUsersScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.storefront),
                    title: const Text('Branches & Shifts'),
                    subtitle: const Text('Locations, geofence & shifts'),
                    onTap: () => _open(const BranchesShiftsScreen()),
                  ),
                  

                  _section('Admin Tools'),
                  ListTile(
                    leading: const Icon(Icons.rule_folder),
                    title: const Text('Fix status shift (missing shiftId)'),
                    subtitle: const Text('Fill shiftId/shiftName for absent/off/sick/leave'),
                    onTap: () => _open(const FixMissingShiftForStatusesScreen()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.auto_fix_high),
                    title: const Text('Fix legacy IDs'),
                    subtitle: const Text('Convert old branchId/shiftId to real doc IDs'),
                    onTap: () => _open(const FixIdsScreen()),
                  ),
                  ListTile(
  leading: const Icon(Icons.account_balance_wallet_outlined),
  title: const Text('Payroll • Loan Assistant'),
  subtitle: const Text('Set monthly loan installments into payroll'),
  onTap: () => _open(const PayrollLoanAssistantScreen()),
),

                  ListTile(
  leading: const Icon(Icons.payments_outlined),
  title: const Text('Payroll Center'),
  subtitle: const Text('Salaries, leaves & loans'),
  onTap: () => _open(const PayrollCenterScreen()),
),
                  _section('Settings'),
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
                            content: Text('Wire onToggleTheme in MaterialApp to apply theme.'),
                          ),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Support'),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Support screen coming soon.')),
                      );
                    },
                  ),
                ],
              ),
            ),

            const Divider(height: 1),
            // Footer
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout'),
              onTap: () async {
                try {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) Navigator.of(context).pop();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Logout failed: $e')));
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
