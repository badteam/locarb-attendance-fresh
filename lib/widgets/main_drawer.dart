  import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
              child: Text('LoCarb Menu', style: TextStyle(fontSize: 18)),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Dashboard'),
              onTap: () => Navigator.pushReplacementNamed(context, '/'),
            ),
            ListTile(
              leading: const Icon(Icons.assessment_outlined),
              title: const Text('Attendance Reports'),
              onTap: () => Navigator.pushReplacementNamed(context, '/reports'),
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: const Text('Users'),
              onTap: () => Navigator.pushReplacementNamed(context, '/users'),
            ),
            ListTile(
              leading: const Icon(Icons.store_outlined),
              title: const Text('Branches & Shifts'),
              onTap: () => Navigator.pushReplacementNamed(context, '/branches'),
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Admin Panel'),
              onTap: () => Navigator.pushReplacementNamed(context, '/admin'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Employee Home'),
              onTap: () => Navigator.pushReplacementNamed(context, '/employee'),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  Navigator.pushReplacementNamed(context, '/');
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
