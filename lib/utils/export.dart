// lib/utils/export.dart
import 'dart:typed_data';
import 'package:excel/excel.dart';

class Export {
  /// يبني ملف XLSX من صفوف الملخصات الجاهزة.
  /// كل صف عبارة عن Map فيه المفاتيح التالية (كلها نصوص جاهزة للعرض):
  /// date, user, branch, shift, status, in, out, worked, scheduled, ot
  static Future<Uint8List> buildExcelFromSummaries({
    required List<Map<String, String>> rows,
    String sheetName = 'Attendance',
  }) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel[sheetName];

    // رؤوس الأعمدة
    final headers = [
      'Date','User','Branch','Shift','Status','IN','OUT',
      'Worked(HH:MM)','Scheduled(HH:MM)','OT(HH:MM)',
    ];
    sheet.appendRow(headers);

    for (final r in rows) {
      sheet.appendRow([
        r['date'] ?? '',
        r['user'] ?? '',
        r['branch'] ?? '',
        r['shift'] ?? '',
        r['status'] ?? '',
        r['in'] ?? '',
        r['out'] ?? '',
        r['worked'] ?? '',
        r['scheduled'] ?? '',
        r['ot'] ?? '',
      ]);
    }

    // عرض الأعمدة معقول
    for (var c = 0; c < headers.length; c++) {
      sheet.setColAutoFit(c);
    }

    final bytes = excel.encode()!;
    return Uint8List.fromList(bytes);
  }
}
