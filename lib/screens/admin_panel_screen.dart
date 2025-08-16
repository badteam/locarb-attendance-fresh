import 'package:flutter/material.dart';
import '../widgets/main_drawer.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Admin Panel')),
      drawer: MainDrawer(),
      body: Center(child: Text('Admin tools — coming soon')),
    );
  }
}
