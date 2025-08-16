import 'package:flutter/material.dart';
import '../screens/branches_shifts_screen.dart';
import '../screens/admin_users_screen.dart'; // 👈 جديد


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

            ListTile(
              leading: const Icon(Icons.storefront),
              title: const Text('Branches & Shifts'),
              onTap: () {
                Navigator.of(context).pop(); // اغلق الدروار
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BranchesShiftsScreen(),
                  ),
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
