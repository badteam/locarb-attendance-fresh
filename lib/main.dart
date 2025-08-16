import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// شاشاتك (عدّل المسارات لو مختلفة)
import 'screens/attendance_report_screen.dart'; // شاشة التقارير للأدمن
// import 'screens/user_home_screen.dart';       // شاشة الموظف (لو عندك)
// import 'screens/admin_dashboard.dart';        // لوحة الأدمن (لو عندك)

// ============= Firebase init =============
Future<void> _initFirebase() async {
  if (kIsWeb) {
    // الويب: نمرّر FirebaseOptions يدويًا (من بيانات مشروعك)
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
    // الموبايل/ديسكتوب:
    // لو عندك firebase_options.dart (FlutterFire CLI) استخدم:
    // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // غير كده، هنستدعي init الافتراضي (لازم تكون مهيئ Android/iOS Gradle/Firebase JSON/Plist)
    await Firebase.initializeApp();
  }

  // إعدادات Firestore (اختياري)
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
}

// دالة تجيب دور المستخدم وحالته من وثيقة users/{uid}
Future<({String role, String status, String displayName})> _loadUserRole(String uid) async {
  try {
    final doc = await FirebaseFirestore.instance.doc('users/$uid').get();
    final data = doc.data() ?? {};
    final role = (data['role'] ?? 'employee').toString();     // admin | manager | employee
    final status = (data['status'] ?? 'pending').toString();  // approved | pending | rejected
    final dn = (data['fullName'] ?? data['username'] ?? uid).toString();
    return (role: role, status: status, displayName: dn);
  } catch (_) {
    return (role: 'employee', status: 'pending', displayName: uid);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebase();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LoCarb Attendance',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00B894)), // أخضر قريب من هوية لوكارب
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const RootGate(),
      // لو عندك Routes زيادة عرفها هنا
      routes: {
        '/reports': (_) => const AttendanceReportScreen(),
      },
    );
  }
}

/// RootGate:
/// - لو المستخدم مش مسجل دخول: يفتح شاشة تسجيل الدخول البسيطة هنا
/// - لو مسجل: يجيب دوره من Firestore ويوجه حسب الدور/الحالة
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  StreamSubscription<User?>? _sub;
  User? _user;
  ({String role, String status, String displayName})? _profile;
  bool _loadingProfile = false;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseAuth.instance.authStateChanges().listen((u) async {
      setState(() {
        _user = u;
        _profile = null;
        _loadingProfile = u != null;
      });
      if (u != null) {
        final p = await _loadUserRole(u.uid);
        if (!mounted) return;
        setState(() {
          _profile = p;
          _loadingProfile = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1) لسه بنجيب حالة تسجيل الدخول
    if (_user == null) {
      return const LoginScreen(); // شاشة تسجيل دخول بسيطة
    }

    // 2) بنحمّل بيانات الدور/الحالة
    if (_loadingProfile || _profile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final role = _profile!.role;
    final status = _profile!.status;
    final name = _profile!.displayName;

    // 3) حالات الموافقة
    if (status != 'approved' && role != 'admin') {
      // الموظفين والمديرين ينتظروا موافقة
      return WaitingApprovalScreen(displayName: name, status: status);
    }

    // 4) التوجيه حسب الدور
    if (role == 'admin' || role == 'manager') {
      // لوحة الأدمن/المشرف — هنا موجّه مؤقتًا لصفحة التقارير مباشرة
      // بدّلها لشاشة Dashboard إذا عندك شاشة منفصلة
      return const AttendanceReportScreen();
    } else {
      // شاشة الموظف (اكتب شاشتك أو حاليًا Placeholder)
      return EmployeeHomeScreen(displayName: name);
    }
  }
}

// ===================== Login (بسيطة) =====================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// تسجيل دخول ببريد/باسورد + زر "تسجيل حساب جديد" (username/password بديله بالإيميل)
class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _busy = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signUp() async {
    // تسجيل جديد بسيط بالإيميل كبديلاً عن username — يفضل لاحقًا تعمل شاشة Signup مخصصة
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Please enter email & password');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text,
      );
      // إنشاء وثيقة المستخدم في Firestore بحالة pending
      final uid = cred.user!.uid;
      await FirebaseFirestore.instance.doc('users/$uid').set({
        'email': _email.text.trim(),
        'username': _email.text.split('@').first,
        'fullName': _email.text.split('@').first,
        'role': 'employee',     // الموظّف افتراضيًا
        'status': 'pending',    // يحتاج موافقة الأدمن
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            elevation: 2,
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
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!, style: TextStyle(color: scheme.error)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy ? null : _signIn,
                          child: _busy
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
                          onPressed: _busy ? null : _signUp,
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

// ===================== Waiting Approval =====================
class WaitingApprovalScreen extends StatelessWidget {
  final String displayName;
  final String status; // pending / rejected
  const WaitingApprovalScreen({super.key, required this.displayName, required this.status});

  @override
  Widget build(BuildContext context) {
    final text = status == 'rejected'
        ? 'Your account was rejected. Please contact admin.'
        : 'Hi $displayName — Your account is pending admin approval.';
    return Scaffold(
      appBar: AppBar(title: const Text('Waiting Approval')),
      body: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}

// ===================== Employee Home (Placeholder) =====================
class EmployeeHomeScreen extends StatelessWidget {
  final String displayName;
  const EmployeeHomeScreen({super.key, required this.displayName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, $displayName'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Employee Home (placeholder)'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).pushNamed('/reports'),
              child: const Text('Open Reports (admin only typically)'),
            ),
          ],
        ),
      ),
    );
  }
}
