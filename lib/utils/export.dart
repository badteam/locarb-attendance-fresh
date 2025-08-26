// lib/utils/export.dart
import 'dart:typed_data';
import 'package:excel/excel.dart';

class Export {
  /// يبني ملف Excel لتقرير الحضور.
  /// المتوقع في كل عنصر من rows:
  /// {
  ///   'date': String (YYYY-MM-DD),
  ///   'user': String,
  ///   'branch': String,
  ///   'shift': String,
  ///   'status': String,
  ///   'in': String (HH:MM أو —),
  ///   'out': String (HH:MM أو —),
  ///   'workedMin': int (دقائق),
  ///   'scheduledMin': int (دقائق),
  ///   'otMin': int (دقائق),
  /// }
  static Future<Uint8List> buildExcelFromSummariesV2({
    required List<Map<String, dynamic>> rows,
    String sheetName = 'Attendance',
  }) async {
    final excel = Excel.createExcel();
    // تأكد إن الشيت موجود بالاسم المحدد (Excel package بتنشئ شيت Default اسمها Sheet1)
    if (!excel.sheets.containsKey(sheetName)) {
      excel.rename('Sheet1', sheetName);
    }
    final sheet = excel[sheetName];

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

    // تنسيق رأس الجدول
    final headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
      cell.cellStyle = headerStyle;
    }

    // ===== Rows =====
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];

      final date = (r['date'] ?? '').toString();
      final user = (r['user'] ?? '').toString();
      final branch = (r['branch'] ?? '').toString();
      final shift = (r['shift'] ?? '').toString();
      final status = (r['status'] ?? '').toString();
      final inTxt = (r['in'] ?? '—').toString();
      final outTxt = (r['out'] ?? '—').toString();

      // الدقائق كأرقام (int) عشان تقدر تعمل SUM في الإكسيل
      final workedMin = _toInt(r['workedMin']);
      final scheduledMin = _toInt(r['scheduledMin']);
      final otMin = _toInt(r['otMin']);

      // أبند الصف (هنكتب الأرقام بعد appendRow مباشرة)
      sheet.appendRow([
        date,
        user,
        branch,
        shift,
        status,
        inTxt,
        outTxt,
        '', // Worked (min)
        '', // Scheduled (min)
        '', // OT (min)
      ]);

      final rowIndex = i + 1; // 0 للهيدر، إذن أول صف بيانات = 1

      // كتابة القيم الرقمية في الأعمدة: 7,8,9 (0-based: 7..9)
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
    final lastDataRow = rows.length;       // آخر صف بيانات اندكسه = rows.length (لأن 0 للهيدر)
    final totalsRowIndex = lastDataRow + 2; // سطر فاصل + سطر توتال

    // سطر فاصل
    sheet.appendRow(List.filled(headers.length, ''));
    // سطر التوتال
    sheet.appendRow(List.filled(headers.length, ''));

    // خانة "Totals" في أول عمود A
    final totalsLabelCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalsRowIndex),
    );
    totalsLabelCell.value = 'Totals';
    totalsLabelCell.cellStyle = CellStyle(bold: true);

    // دوال SUM للأعمدة H, I, J (0-based: 7, 8, 9)
    String colName(int colIndexZeroBased) => String.fromCharCode(65 + colIndexZeroBased);
    String sumRef(int colIndexZeroBased) =>
        'SUM(${colName(colIndexZeroBased)}2:${colName(colIndexZeroBased)}${lastDataRow + 1})';

    for (final col in [7, 8, 9]) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: col,
        rowIndex: totalsRowIndex,
      ));
      cell.setFormula(sumRef(col));
      cell.cellStyle = CellStyle(bold: true);
    }

    // ===== AutoFit للأعمدة =====
    for (var c = 0; c < headers.length; c++) {
      sheet.setColAutoFit(c);
    }

    final bytes = excel.encode()!;
    return Uint8List.fromList(bytes);
  }

  // ===== Helpers =====
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
