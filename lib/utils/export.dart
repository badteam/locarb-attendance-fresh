// lib/utils/export.dart
import 'dart:typed_data';
import 'package:excel/excel.dart';

class Export {
  /// V2: يكتب Worked/Scheduled/OT كـ Durations حقيقية (hh:mm) + Totals
  /// rows: كل عنصر Map يحتوي:
  ///   date, user, branch, shift, status, in, out  (Strings)
  ///   workedMin, scheduledMin, otMin             (ints بالدقائق)
  static Future<Uint8List> buildExcelFromSummariesV2({
    required List<Map<String, dynamic>> rows,
    String sheetName = 'Attendance',
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName];

    // Header
    final headers = [
      'Date','User','Branch','Shift','Status','IN','OUT',
      'Worked(HH:MM)','Scheduled(HH:MM)','OT(HH:MM)',
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

    // Helper: duration as Excel days (minutes / 1440)
    void writeDuration(int col, int row, int minutes) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
      final value = minutes <= 0 ? 0 : minutes / 1440.0;
      cell.value = value;
      cell.cellStyle = CellStyle(numberFormat: "hh:mm");
    }

    // Rows
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final excelRow = i + 1; // 0 = header
      sheet.appendRow([
        (r['date'] ?? '').toString(),
        (r['user'] ?? '').toString(),
        (r['branch'] ?? '').toString(),
        (r['shift'] ?? '').toString(),
        (r['status'] ?? '').toString(),
        (r['in'] ?? '—').toString(),
        (r['out'] ?? '—').toString(),
        '', '', '', // durations to be filled
      ]);
      writeDuration(7, excelRow, (r['workedMin'] ?? 0) as int);
      writeDuration(8, excelRow, (r['scheduledMin'] ?? 0) as int);
      writeDuration(9, excelRow, (r['otMin'] ?? 0) as int);
    }

    // Totals
    final lastDataRow = rows.length;            // first data row is index 1
    final totalsRowIndex = lastDataRow + 2;     // خط فاصل + سطر توتال
    sheet.appendRow(List.filled(headers.length, ''));
    sheet.appendRow(List.filled(headers.length, ''));

    final labelCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalsRowIndex));
    labelCell.value = 'Totals';
    labelCell.cellStyle = CellStyle(bold: true);

    String colName(int col) => String.fromCharCode(65 + col); // 0->A
    String sumRef(int col) => 'SUM(${colName(col)}2:${colName(col)}${lastDataRow + 1})';

    for (final col in [7, 8, 9]) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: totalsRowIndex));
      cell.setFormula(sumRef(col));
      cell.cellStyle = CellStyle(bold: true, numberFormat: "hh:mm");
    }

    // Auto-fit columns
    for (var c = 0; c < headers.length; c++) {
      sheet.setColAutoFit(c);
    }

    return Uint8List.fromList(excel.encode()!);
  }
}
