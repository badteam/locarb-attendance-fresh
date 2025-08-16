import 'package:flutter/material.dart';
import '../widgets/main_drawer.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppBar(title: Text('Users')),
      drawer: MainDrawer(),
      body: Center(child: Text('Users management — coming soon')),
    );
  }
}
