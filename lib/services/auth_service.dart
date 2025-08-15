import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  // نحول اليوزرنيم لإيميل داخلي علشان Firebase Auth
  static String _usernameToEmail(String username) =>
      '${username.trim().toLowerCase()}@locarb.app';

  static Future<UserCredential> signUp(String username, String password) {
    return FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: _usernameToEmail(username),
      password: password,
    );
  }

  static Future<UserCredential> signIn(String username, String password) {
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: _usernameToEmail(username),
      password: password,
    );
  }

  static Future<void> signOut() => FirebaseAuth.instance.signOut();
}
