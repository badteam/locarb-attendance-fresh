import 'package:flutter/material.dart';
import 'admin_users_screen.dart';
import 'branches_screen.dart';
import 'attendance_report_screen.dart';
import 'shifts_screen.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'Users'),
              Tab(icon: Icon(Icons.store_mall_directory), text: 'Branches'),
              Tab(icon: Icon(Icons.access_time_filled), text: 'Shifts'),
              Tab(icon: Icon(Icons.fact_check), text: 'Attendance'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminUsersScreen(),
            BranchesScreen(),
            ShiftsScreen(),            // ⬅️ NEW
            AttendanceReportScreen(),
          ],
        ),
      ),
    );
  }
}
