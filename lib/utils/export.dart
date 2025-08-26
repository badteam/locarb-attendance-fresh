// lib/utils/export.dart
import 'dart:typed_data';
import 'package:excel/excel.dart';

class Export {
  /// يبني ملف Excel لتقرير الحضور (الأزمنة كـ دقائق رقمية لسهولة الـ SUM)
  /// شكل كل صف:
  /// {
  ///   'date': String (YYYY-MM-DD),
  ///   'user': String,
  ///   'branch': String,
  ///   'shift': String,
  ///   'status': String,
  ///   'in': String (HH:MM أو —),
  ///   'out': String (HH:MM أو —),
  ///   'workedMin': int,
  ///   'scheduledMin': int,
  ///   'otMin': int,
  /// }
  static Future<Uint8List> buildExcelFromSummariesV2({
    required List<Map<String, dynamic>> rows,
    String sheetName = 'Attendance',
  }) async {
    final excel = Excel.createExcel();

    // ❗️بدل rename/delete: أنشئ شيت جديد بالاسم المطلوب لو مش موجود، واكتب عليه
    if (!excel.sheets.containsKey(sheetName)) {
      excel.createSheet(sheetName);
    }
final Sheet sheet = excel['Sheet1']!;

    // ===== Header =====
    final headers = <String>[
      'Date',
      'User',
      'Branch',
      'Shift',
      'Status',
      'IN',
      'OUT',
      'Worked (min)',
      'Scheduled (min)',
      'OT (min)',
    ];
    sheet.appendRow(headers);

    final headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.cellStyle = headerStyle;
    }

    // ===== Data rows =====
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];

      final date = (r['date'] ?? '').toString();
      final user = (r['user'] ?? '').toString();
      final branch = (r['branch'] ?? '').toString();
      final shift = (r['shift'] ?? '').toString();
      final status = (r['status'] ?? '').toString();
      final inTxt = (r['in'] ?? '—').toString();
      final outTxt = (r['out'] ?? '—').toString();

      final workedMin = _toInt(r['workedMin']);
      final scheduledMin = _toInt(r['scheduledMin']);
      final otMin = _toInt(r['otMin']);

      sheet.appendRow([
        date,
        user,
        branch,
        shift,
        status,
        inTxt,
        outTxt,
        '', // worked (min) numeric below
        '', // scheduled (min)
        '', // ot (min)
      ]);

      final rowIndex = i + 1; // 0 = header

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex))
          .value = workedMin;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex))
          .value = scheduledMin;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex))
          .value = otMin;
    }

    // ===== Totals =====
    final lastDataRow = rows.length;
    sheet.appendRow(List.filled(headers.length, '')); // spacer
    sheet.appendRow(List.filled(headers.length, '')); // totals row
    final totalsRowIndex = lastDataRow + 2;

    final totalsLabelCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalsRowIndex),
    );
    totalsLabelCell.value = 'Totals';
    totalsLabelCell.cellStyle = CellStyle(bold: true);

    String colName(int colIndexZeroBased) => String.fromCharCode(65 + colIndexZeroBased);
    String sumRef(int colIndexZeroBased) =>
        'SUM(${colName(colIndexZeroBased)}2:${colName(colIndexZeroBased)}${lastDataRow + 1})';

    for (final col in [7, 8, 9]) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: totalsRowIndex),
      );
      cell.setFormula(sumRef(col));
      cell.cellStyle = CellStyle(bold: true);
    }

    // ===== Autofit (أحيانًا بتكسر في نسخ معينة) — نخليها داخل try/catch
    try {
      for (var c = 0; c < headers.length; c++) {
        sheet.setColAutoFit(c);
      }
    } catch (_) {
      // تجاهل أي خطأ من المكتبة
    }

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
