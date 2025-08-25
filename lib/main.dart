import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Screens
import 'screens/dashboard_screen.dart';
import 'screens/attendance_report_screen.dart';
import 'admin/fix_missing_shift_for_statuses.dart';
import 'admin/fix_ids_screen.dart'; // أعلى الملف


// كان: import 'screens/users_screen.dart';
import 'screens/admin_users_screen.dart';           // ✅ النسخة الإدارية الجديدة
// كان: import 'screens/branches_screen.dart';
import 'screens/branches_shifts_screen.dart';      // ✅ فروع + شفتات في شاشة واحدة
import 'screens/admin_panel_screen.dart';
import 'screens/employee_home_screen.dart';

/* ----------------------------- Firebase init ----------------------------- */

Future<void> _initFirebase() async {
  if (kIsWeb) {
    const webOptions = FirebaseOptions(
      apiKey: "AIzaSyDSKUx-6RtCuLiGcnMVko0vAKvL9ik7hSI",
      authDomain: "locarb-attendance-v2.firebaseapp.com",
      projectId: "locarb-attendance-v2",
      storageBucket: "locarb-attendance-v2.firebasestorage.app",
      messagingSenderId: "953944468274",
      appId: "1:953944468274:web:319947e61b55f1341b452b",
    );
    await Firebase.initializeApp(options: webOptions);
  } else {
    await Firebase.initializeApp();
  }
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
}

/* --------------------------- (اختياري) الثيم ---------------------------- */

class ThemeController {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);
  static void setDark(bool isDark) {
    mode.value = isDark ? ThemeMode.dark : ThemeMode.light;
  }
}

/* --------------------------------- main --------------------------------- */

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebase();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    // لو مش عايز وضع ليلي دلوقتي، تقدر تلغي الـ ValueListenableBuilder
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (_, themeMode, __) {
        return MaterialApp(
          title: 'LoCarb Attendance',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00B894)),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00B894),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: themeMode, // كان ثابت → بقى ديناميكي لو احتجته
          home: const RootGate(),
          routes: {
            '/': (_) => const DashboardScreen(),
            '/dashboard': (_) => const DashboardScreen(),                 // ✅ جديد
            '/reports': (_) => const AttendanceReportScreen(),
            '/users': (_) => const AdminUsersScreen(),                    // ✅ بدل UsersScreen
            '/branches': (_) => const BranchesShiftsScreen(),             // ✅ بدل BranchesScreen
            '/admin': (_) => const AdminPanelScreen(),
            '/employee': (_) => const EmployeeHomeScreen(),
            '/admin/fix-status-shift': (_) => const FixMissingShiftForStatusesScreen(),
            '/admin/fix-ids': (_) => const FixIdsScreen(),


          },
        );
      },
    );
  }
}

/* ------------------------------ Auth Gate ------------------------------- */

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (user == null) return const _LoginScreen();

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.doc('users/${user.uid}').get(),
          builder: (context, us) {
            if (us.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final data = us.data?.data() ?? {};
            final status = (data['status'] ?? 'pending').toString();

            if (status != 'approved') {
              return Scaffold(
                appBar: AppBar(title: const Text('Waiting Approval')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Your account status is "$status". Please wait for admin approval.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            // افتح الـ Dashboard كبداية
            return const DashboardScreen();
          },
        );
      },
    );
  }
}

/* ------------------------------ Login Screen ---------------------------- */

class _LoginScreen extends StatefulWidget {
  const _LoginScreen();
  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signUp() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _email.text.trim(),
            password: _pass.text,
          );
      await FirebaseFirestore.instance.doc('users/${cred.user!.uid}').set({
        'email': _email.text.trim(),
        'username': _email.text.split('@').first,
        'fullName': _email.text.split('@').first,
        'role': 'employee',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('LoCarb Attendance', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _loading ? null : _signIn,
                          child: _loading
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Sign in'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loading ? null : _signUp,
                          child: const Text('Create account'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
