// lib/utils/export.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

/// يبني ملف Excel بنمط Pivot: صف = موظف، عمود = يوم (YYYY-MM-DD)
/// القيمة = HH:mm - HH:mm | Absent | "HH:mm - ?" | "? - HH:mm"
class Export {
  static Future<List<int>> buildPivotExcelBytes({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> attendanceDocs,
    required DateTime from,
    required DateTime to,
    required Map<String, String> userNames, // uid -> displayName
  }) async {
    final fmtYmd = DateFormat('yyyy-MM-dd');

    // 1) days of range
    final days = <String>[];
    for (DateTime d = DateTime(from.year, from.month, from.day);
        !d.isAfter(to);
        d = d.add(const Duration(days: 1))) {
      days.add(fmtYmd.format(d));
    }

    // 2) init pivot for seen users
    final pivot = <String, Map<String, String>>{}; // uid -> { day -> value }
    final userSet = <String>{};
    for (final d in attendanceDocs) {
      final uid = (d.data()['userId'] ?? '').toString();
      if (uid.isNotEmpty) userSet.add(uid);
    }
    for (final uid in userSet) {
      pivot[uid] = { for (final day in days) day: 'Absent' };
    }

    // 3) group first IN / last OUT per user/day
    final grouped = <String, Map<String, List<Timestamp>>>{}; // key=uid|day
    for (final doc in attendanceDocs) {
      final m = doc.data();
      final uid = (m['userId'] ?? '').toString();
      final day = (m['localDay'] ?? '').toString();
      if (!pivot.containsKey(uid) || !days.contains(day)) continue;

      final key = '$uid|$day';
      grouped.putIfAbsent(key, () => {'in': <Timestamp>[], 'out': <Timestamp>[]});
      final type = (m['type'] ?? '').toString();
      final at = m['at'];
      if (at is Timestamp) {
        if (type == 'in') grouped[key]!['in']!.add(at);
        if (type == 'out') grouped[key]!['out']!.add(at);
      }
    }

    String _fmtTime(Timestamp ts) {
      final dt = ts.toDate();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }

    grouped.forEach((key, val) {
      final parts = key.split('|');
      final uid = parts[0];
      final day = parts[1];
      final ins = val['in']!..sort((a, b) => a.compareTo(b));
      final outs = val['out']!..sort((a, b) => a.compareTo(b));
      String cell = 'Absent';
      if (ins.isNotEmpty && outs.isNotEmpty) {
        cell = '${_fmtTime(ins.first)} - ${_fmtTime(outs.last)}';
      } else if (ins.isNotEmpty) {
        cell = '${_fmtTime(ins.first)} - ?';
      } else if (outs.isNotEmpty) {
        cell = '? - ${_fmtTime(outs.last)}';
      }
      pivot[uid]![day] = cell;
    });

    // 4) build Excel (excel: 2.1.0)
    final excel = Excel.createExcel();
    final sheet = excel['Attendance'];
    excel.setDefaultSheet('Attendance');

    // Styles
    final headerStyle = CellStyle(bold: true, horizontalAlign: HorizontalAlign.Center);
    final center = CellStyle(horizontalAlign: HorizontalAlign.Center);
    final red = CellStyle(
      backgroundColorHex: "#FF9999", // Absent
      horizontalAlign: HorizontalAlign.Center,
    );
    final orange = CellStyle(
      backgroundColorHex: "#FFD580", // includes '?'
      horizontalAlign: HorizontalAlign.Center,
    );

    // Header row
    final header = ['Employee Name', ...days];
    sheet.appendRow(header);
    for (int c = 0; c < header.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = headerStyle;
    }

    // Data rows (sorted by display name)
    final sortedUids = userSet.toList()
      ..sort((a, b) => (userNames[a] ?? a).compareTo(userNames[b] ?? b));

    int row = 1;
    for (final uid in sortedUids) {
      final name = userNames[uid] ?? uid;
      final rowValues = [name, ...days.map((d) => pivot[uid]![d]!)];
      sheet.appendRow(rowValues);

      for (int c = 1; c < rowValues.length; c++) {
        final v = rowValues[c];
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
        if (v == 'Absent') {
          cell.cellStyle = red;
        } else if (v.contains('?')) {
          cell.cellStyle = orange;
        } else {
          cell.cellStyle = center;
        }
      }
      row++;
    }

    // widths
    sheet.setColWidth(0, 24); // employee name
    for (int c = 1; c < header.length; c++) {
      sheet.setColWidth(c, 12);
    }

    return excel.encode()!;
  }
}
