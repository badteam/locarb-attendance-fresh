// بسيط ومباشر للويب (نقدر نطوّره لاحقًا للمنصات الأخرى)
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
    apiKey: "AIzaSyDSKUx-6RtCuLiGcnMVko0vAKvL9ik7hSI",
    authDomain: "locarb-attendance-v2.firebaseapp.com",
    projectId: "locarb-attendance-v2",
    storageBucket: "locarb-attendance-v2.firebasestorage.app",
    messagingSenderId: "953944468274",
    appId: "1:953944468274:web:319947e61b55f1341b452b",
  );
}
