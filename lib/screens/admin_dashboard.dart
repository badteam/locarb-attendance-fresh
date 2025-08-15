import 'package:flutter/material.dart';
import 'admin_users_screen.dart';
import 'branches_screen.dart';
import 'attendance_report_screen.dart'; // ⬅️1 جديد

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3, // ⬅️ كان 2
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة الأدمن'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'المستخدمون'),
              Tab(icon: Icon(Icons.store_mall_directory), text: 'الفروع'),
              Tab(icon: Icon(Icons.fact_check), text: 'تقارير الحضور'), // ⬅️ جديد
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminUsersScreen(),
            BranchesScreen(),
            AttendanceReportScreen(), // ⬅️ جديد
          ],
        ),
      ),
    );
  }
}
