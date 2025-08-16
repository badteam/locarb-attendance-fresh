import 'package:flutter/material.dart';
import '../widgets/main_drawer.dart';

class EmployeeHomeScreen extends StatelessWidget {
  const EmployeeHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Employee Home')),
      drawer: MainDrawer(),
      body: Center(child: Text('Employee home (check-in/out coming later)')),
    );
  }
}
