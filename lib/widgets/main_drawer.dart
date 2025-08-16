import 'package:flutter/material.dart';

import '../screens/branches_shifts_screen.dart';
import '../screens/admin_users_screen.dart';
import '../screens/employee_home_screen.dart';
import '../screens/attendance_report_screen.dart';

class MainDrawer extends StatelessWidget {
  const MainDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(),
              child: Text(
                'LoCarb Admin',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),

            // Employee Home (الحضور/الانصراف للموظف)
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Employee Home'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EmployeeHomeScreen()),
                );
              },
            ),

            // إدارة المستخدمين (الأدمن)
            ListTile(
              leading: const Icon(Icons.people_alt_outlined),
              title: const Text('Users'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
                );
              },
            ),

            // الفروع + الشفتات
            ListTile(
              leading: const Icon(Icons.storefront),
              title: const Text('Branches & Shifts'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BranchesShiftsScreen()),
                );
              },
            ),

            // التقارير
            ListTile(
              leading: const Icon(Icons.insert_chart_outlined),
              title: const Text('Attendance Reports'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AttendanceReportScreen()),
                );
              },
            ),

            const Divider(height: 24),

            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
