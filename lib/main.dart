import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
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
      theme: ThemeData(colorSchemeSeed: const Color(0xFFFF8A00), useMaterial3: true),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_user, size: 96),
          const SizedBox(height: 16),
          const Text('مرحبًا بك في LoCarb Attendance', textDirection: TextDirection.rtl, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('نسخة البداية — هنكمل باقي الصفحات خطوة بخطوة', textDirection: TextDirection.rtl, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {},
            child: const Text('متابعة', textDirection: TextDirection.rtl),
          ),
        ]),
      ),
    );
  }
}
