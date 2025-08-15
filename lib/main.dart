import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/db_init.dart';

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
      theme: ThemeData(colorSchemeSeed: const Color(0xFFFF8A00), useMaterial3: true),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/home': (_) => const HomeScreen(),
        '/pending': (_) => const PendingScreen(),
      },
      home: const RootRouter(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class RootRouter extends StatelessWidget {
  const RootRouter({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const OnboardingScreen();
        // بعد تسجيل الدخول ننفّذ تهيئة قاعدة البيانات
        return InitGate(user: user);
      },
    );
  }
}

class InitGate extends StatefulWidget {
  final User user;
  const InitGate({super.key, required this.user});

  @override
  State<InitGate> createState() => _InitGateState();
}

class _InitGateState extends State<InitGate> {
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // 1) تأكيد مستند المستخدم (بدون افتراض وجوده مسبقًا)
      await DBInit.ensureCurrentUserDoc(
        uid: widget.user.uid,
        username: (widget.user.email ?? '').split('@').first,
        email: widget.user.email,
        fullName: '', // لو عندك قيمة من واجهة التسجيل مرّرها هنا
      );
      // 2) إنشاء المجموعات الأساسية لو فاضية
      await DBInit.ensureBaseCollections();

      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(child: Text('Init error: $_error')),
      );
    }
    if (!_done) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // بعد التهيئة، وجّه حسب حالة المستخدم
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.doc('users/${widget.user.uid}').get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data!.data() ?? {};
        final status = (data['status'] ?? 'pending') as String;
        if (status == 'approved') return const HomeScreen();
        return const PendingScreen();
      },
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
          const SizedBox(height: 12),
          const Text('مرحبًا بك في LoCarb Attendance',
              textDirection: TextDirection.rtl, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          const Text('سجّل دخولك أو أنشئ حساب جديد',
              textDirection: TextDirection.rtl, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: ()=> Navigator.pushReplacementNamed(context, '/login'),
            child: const Text('ابدأ', textDirection: TextDirection.rtl),
          ),
        ]),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  String? error; bool loading = false;

  Future<void> _login() async {
    setState(() { loading = true; error = null; });
    try {
      await AuthService.signIn(username.text, password.text);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message);
    } catch (e) { setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل الدخول')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: username, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
              const SizedBox(height: 8),
              TextField(controller: password, decoration: const InputDecoration(labelText: 'كلمة المرور'), obscureText: true),
              const SizedBox(height: 12),
              FilledButton(onPressed: loading? null : _login,
                child: loading? const CircularProgressIndicator() : const Text('دخول')),
              TextButton(onPressed: ()=> Navigator.pushNamed(context, '/signup'),
                child: const Text('إنشاء حساب جديد')),
              if (error != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
        ),
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final username = TextEditingController();
  final password = TextEditingController();
  final fullName = TextEditingController();
  String? error; bool loading = false;

  Future<void> _signup() async {
    setState(() { loading = true; error = null; });
    try {
      // إنشاء الحساب
      final cred = await AuthService.signUp(username.text, password.text);
      final uid = cred.user!.uid;

      // بدون أي استعلامات: الحسابات الجديدة = pending + employee
      await FirebaseFirestore.instance.doc('users/$uid').set({
        'uid': uid,
        'username': username.text.trim(),
        'fullName': fullName.text.trim(),
        'role': 'employee',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تم إنشاء الحساب (بانتظار موافقة الأدمن)'),
      ));
      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: username, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
              const SizedBox(height: 8),
              TextField(controller: password, decoration: const InputDecoration(labelText: 'كلمة المرور'), obscureText: true),
              const SizedBox(height: 8),
              TextField(controller: fullName, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
              const SizedBox(height: 12),
              FilledButton(onPressed: loading? null : _signup,
                child: loading? const CircularProgressIndicator() : const Text('تسجيل')),
              if (error != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
        ),
      ),
    );
  }
}

class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('تم إنشاء الحساب، بانتظار موافقة الأدمن', textDirection: TextDirection.rtl)),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('الرئيسية'), actions: [
        IconButton(onPressed: () async {
          await AuthService.signOut();
          if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
        }, icon: const Icon(Icons.logout))
      ]),
      body: Center(
        child: Text('أهلًا ${user?.email ?? ''}', textDirection: TextDirection.rtl),
      ),
    );
  }
}
