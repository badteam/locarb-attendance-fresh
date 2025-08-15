import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const LoCarbApp());
}

class LoCarbApp extends StatelessWidget {
  const LoCarbApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LoCarb Attendance',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFFF8A00),
        useMaterial3: true,
      ),
      home: const OnboardingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.verified_user, size: 96),
          SizedBox(height: 16),
          Text('مرحبًا بك في LoCarb Attendance',
              textDirection: TextDirection.rtl, textAlign: TextAlign.center),
          SizedBox(height: 8),
          Text('نسخة البداية — هنكمل الصفحات لاحقًا',
              textDirection: TextDirection.rtl, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
