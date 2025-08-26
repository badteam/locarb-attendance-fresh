import 'dart:typed_data';
import 'package:excel/excel.dart';

class Export {
  static Future<Uint8List> buildExcelFromSummariesV2({
    required List<Map<String, dynamic>> rows,
    String sheetName = 'Attendance', // غير مستخدم، ممكن تسيبه أو تشيله
  }) async {
    final excel = Excel.createExcel();

    // ✅ اشتغل دايمًا على Sheet1 لتجنب إنشاء تبويبات إضافية أو أخطاء API
    final Sheet sheet = excel['Sheet1']!;

    // الهيدر
    final headers = <String>[
      'Date','User','Branch','Shift','Status','IN','OUT',
      'Worked (min)','Scheduled (min)','OT (min)',
    ];
    sheet.appendRow(headers);

    final headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    for (var c = 0; c < headers.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
           .cellStyle = headerStyle;
    }

    // البيانات
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final date = (r['date'] ?? '').toString();
      final user = (r['user'] ?? '').toString();
      final branch = (r['branch'] ?? '').toString();
      final shift = (r['shift'] ?? '').toString();
      final status = (r['status'] ?? '').toString();
      final inTxt = (r['in'] ?? '—').toString();
      final outTxt = (r['out'] ?? '—').toString();
      final workedMin    = _toInt(r['workedMin']);
      final scheduledMin = _toInt(r['scheduledMin']);
      final otMin        = _toInt(r['otMin']);

      sheet.appendRow([date,user,branch,shift,status,inTxt,outTxt,'','','']);
      final rowIndex = i + 1; // 0 للهيدر

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex)).value = workedMin;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex)).value = scheduledMin;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex)).value = otMin;
    }

    // Totals
    final lastDataRow = rows.length;
    sheet.appendRow(List.filled(headers.length, '')); // spacer
    sheet.appendRow(List.filled(headers.length, '')); // totals row
    final totalsRowIndex = lastDataRow + 2;

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalsRowIndex))
         ..value = 'Totals'
         ..cellStyle = CellStyle(bold: true);

    String colName(int i) => String.fromCharCode(65 + i);
    String sumRef(int col) => 'SUM(${colName(col)}2:${colName(col)}${lastDataRow + 1})';

    for (final col in [7, 8, 9]) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: totalsRowIndex))
           ..setFormula(sumRef(col))
           ..cellStyle = CellStyle(bold: true);
    }

    // AutoFit (لو المكتبة عندها مشكلة، نتجاهل)
    try {
      for (var c = 0; c < headers.length; c++) {
        sheet.setColAutoFit(c);
      }
    } catch (_) {}

    final bytes = excel.encode()!;
    return Uint8List.fromList(bytes);
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is num) return v.toInt();
    if (v is String) {
      final n = int.tryParse(v.trim());
      if (n != null) return n;
      final d = double.tryParse(v.trim());
      if (d != null) return d.round();
    }
    return 0;
  }
}
