// lib/utils/export.dart
import 'package:excel/excel.dart';

/// ألوان الحالات لعمود Status
const Map<String, String> kStatusColorHex = {
  'Present':     '#C6EFCE', // أخضر فاتح
  'Absent':      '#FFC7CE', // أحمر فاتح
  'Missing IN':  '#FFEB9C', // أصفر
  'Missing OUT': '#FFEB9C',
  'Off':         '#E7E6E6', // رمادي فاتح
  'Sick':        '#D9D2E9', // موف فاتح
  'Leave':       '#BDD7EE', // أزرق فاتح
};

class Export {
  /// rows: قائمة خرائط جاهزة من الشاشة (date, user, branch, shift, status, in, out, worked, scheduled, ot)
  static Future<List<int>> buildExcelFromSummariesV2({
    required List<Map<String, String>> rows,
  }) async {
    final excel = Excel.createExcel();
    // اشتغل على الشيت الافتراضي "Sheet1" لتجنب إنشاء شيت فاضي
    final String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final Sheet sheet = excel[defaultSheet]!;

    // تنسيقات عامة
    final headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      backgroundColorHex: '#D9D9D9', // رمادي فاتح للهيدر
    );

    final normalStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
    );

    // عناوين الأعمدة
    final headers = <String>[
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

    // اكتب الهيدر
    for (int c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.value = TextCellValue(headers[c]);
      cell.cellStyle = headerStyle;
    }

    // اكتب الصفوف
    for (int r = 0; r < rows.length; r++) {
      final rowMap = rows[r];

      final List<String> ordered = [
        rowMap['date'] ?? '',
        rowMap['user'] ?? '',
        rowMap['branch'] ?? '',
        rowMap['shift'] ?? '',
        rowMap['status'] ?? '',
        rowMap['in'] ?? '',
        rowMap['out'] ?? '',
        rowMap['worked'] ?? '',
        rowMap['scheduled'] ?? '',
        rowMap['ot'] ?? '',
      ];

      final rowIndex = r + 1; // لأن 0 للهيدر
      for (int c = 0; c < ordered.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex));
        cell.value = TextCellValue(ordered[c]);
        cell.cellStyle = normalStyle;
      }

      // تلوين عمود Status (العمود الخامس = index 4)
      final String status = rowMap['status'] ?? '';
      final String? hex = kStatusColorHex[status];
      if (hex != null) {
        final statusCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex));
        statusCell.cellStyle = CellStyle(
          backgroundColorHex: hex,
          bold: true,
          horizontalAlign: HorizontalAlign.Center,
          verticalAlign: VerticalAlign.Center,
        );
      }
    }

    // عرض أعمدة مناسب
    // لو الباكدج عندك يدعم setColWidth
    try {
      // أعرض أعرض شوية للأسماء، والفروع، والـStatus
      sheet.setColWidth(0, 10); // Date
      sheet.setColWidth(1, 24); // User
      sheet.setColWidth(2, 22); // Branch
      sheet.setColWidth(3, 18); // Shift
      sheet.setColWidth(4, 14); // Status
      sheet.setColWidth(5, 8);  // IN
      sheet.setColWidth(6, 8);  // OUT
      sheet.setColWidth(7, 10); // Worked
      sheet.setColWidth(8, 12); // Scheduled
      sheet.setColWidth(9, 8);  // OT
    } catch (_) {
      // بعض الإصدارات لا تدعم setColWidth؛ نتجاهل بهدوء
    }

    final encoded = excel.encode();
    return encoded ?? <int>[];
  }

  // (اختياري) خليه موجود كغلاف للاسم القديم لو في أماكن بتنده عليه
  static Future<List<int>> buildExcelFromSummaries({
    required List<Map<String, String>> rows,
  }) {
    return buildExcelFromSummariesV2(rows: rows);
  }
}
