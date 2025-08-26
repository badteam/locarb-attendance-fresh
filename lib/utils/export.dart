// lib/utils/export.dart
import 'package:excel/excel.dart';

class Export {
  static Future<List<int>> buildExcelFromSummaries({
    required List<Map<String, String>> rows,
  }) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Sheet1']; // نستخدم الافتراضي

    // الصف العلوي
    final headers = const [
      'Date',
      'User',
      'Branch',
      'Shift',
      'Status',
      'IN',
      'OUT',
      'Worked(HH:MM)',
      'Scheduled(HH:MM)',
      'OT(HH:MM)',
    ];
    sheet.appendRow(headers);

    // Bold style للـ header
    for (int c = 0; c < headers.length; c++) {
      final cell = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.cellStyle = CellStyle(bold: true);
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

    return excel.encode() ?? <int>[];
  }

  static Future<List<int>> buildExcelFromSummariesV2({
    required List<Map<String, String>> rows,
  }) =>
      buildExcelFromSummaries(rows: rows);
}
