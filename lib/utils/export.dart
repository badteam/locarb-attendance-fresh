// lib/utils/export.dart
import 'package:excel/excel.dart';

class Export {
  /// rows: قائمة من الخرائط بالمفاتيح:
  /// date, user, branch, shift, status, in, out, worked, scheduled, ot
  static Future<List<int>> buildExcelFromSummaries({
    required List<Map<String, String>> rows,
    String sheetName = 'Attendance',
  }) async {
    final excel = Excel.createExcel(); // ينشئ Sheet1 افتراضياً
    // هنكتب على الشيت الافتراضي علشان ما يحصلش شيت فاضي
    final Sheet sheet = excel['Sheet1'];

    // ممكن نحاول تعيين الاسم الافتراضي (لو مدعوم)، لو مش مدعوم مش مشكلة
    try {
      excel.setDefaultSheet('Sheet1');
      // بعض الإصدارات تدعم rename، البعض لا — نخليها داخل try
      if (sheetName != 'Sheet1') {
        excel.rename('Sheet1', sheetName);
      }
    } catch (_) {
      // تجاهل لو الـ API مش موجودة — الأهم المحتوى نفسه
    }

    // الصف العلوي: عناوين الأعمدة
    final headers = const [
      'Date',
      'User',
      'Branch',
      'Shift',
      'Status',
      'IN',
      'OUT',
      'Worked',
      'Scheduled',
      'OT',
    ];
    sheet.appendRow(headers);

    // تنسيق العناوين (Bold فقط، بدون numberFormat)
    try {
      for (int c = 0; c < headers.length; c++) {
        final cell = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
        cell.cellStyle = CellStyle(bold: true);
      }
    } catch (_) {
      // بعض الإصدارات ممكن تتصرف بشكل مختلف — مش مشكلة
    }

    // البيانات
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

    // تحسين عرض بسيط: عرض أعمدة
    try {
      final widths = <int, double>{
        0: 14, // Date
        1: 22, // User
        2: 18, // Branch
        3: 16, // Shift
        4: 14, // Status
        5: 8,  // IN
        6: 8,  // OUT
        7: 10, // Worked
        8: 11, // Scheduled
        9: 8,  // OT
      };
      widths.forEach((col, w) {
        sheet.setColWidth(col, w);
      });
    } catch (_) {
      // لو غير مدعوم، نتجاهل
    }

    final bytes = excel.encode();
    return bytes ?? <int>[];
  }

  /// لو حاب تحافظ على أسماء دوال قديمة:
  static Future<List<int>> buildExcelFromSummariesV2({
    required List<Map<String, String>> rows,
    String sheetName = 'Attendance',
  }) =>
      buildExcelFromSummaries(rows: rows, sheetName: sheetName);
}
