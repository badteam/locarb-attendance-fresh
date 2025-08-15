import 'package:cloud_firestore/cloud_firestore.dart';

class AdminService {
  static final _db = FirebaseFirestore.instance;

  static Future<void> approveUser(String uid) {
    return _db.doc('users/$uid').update({'status': 'approved'});
  }

  static Future<void> rejectUser(String uid) {
    return _db.doc('users/$uid').update({'status': 'rejected'});
  }

  static Future<void> makeAdmin(String uid) {
    return _db.doc('users/$uid').update({'role': 'admin', 'status': 'approved'});
  }

  static Future<void> makeEmployee(String uid) {
    return _db.doc('users/$uid').update({'role': 'employee'});
  }
}
