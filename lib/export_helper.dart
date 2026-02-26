import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database.dart';

class ExportHelper {
  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';
  }

  static String _formatDateForFile(String date) {
    final parts = date.split('-');
    if (parts.length == 3) return '${parts[2]}-${parts[1]}-${parts[0]}';
    return date;
  }

  static String _formatDateDisplay(String date) {
    final parts = date.split('-');
    if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    return date;
  }

  static Future<void> exportToExcel(List<InventoryItem> items, String? date) async {
    final excel = Excel.createExcel();

    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#1A237E'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
    );

    void writeSheet(Sheet sheet, List<InventoryItem> sheetItems) {
      final headers = ['#', 'المنتج', 'المخزن', 'السريال', 'الحالة', 'تاريخ الصلاحية', 'ملاحظات'];
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      for (int i = 0; i < sheetItems.length; i++) {
        final item = sheetItems[i];
        final rowData = [
          (i + 1).toString(),
          item.productName,
          item.warehouseName,
          item.serial ?? '-',
          item.condition,
          item.expiryDate ?? '-',
          item.notes ?? '-',
        ];

        String bgColor = '#FFFFFF';
        if (item.condition == 'تالف') bgColor = '#FFEBEE';
        else if (item.condition == 'مستخدم') bgColor = '#FFF3E0';
        else if (item.condition == 'جديد') bgColor = '#E8F5E9';

        for (int j = 0; j < rowData.length; j++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
          cell.value = TextCellValue(rowData[j]);
          cell.cellStyle = CellStyle(
            backgroundColorHex: ExcelColor.fromHexString(bgColor),
            horizontalAlign: HorizontalAlign.Center,
          );
        }
      }

      sheet.setColumnWidth(0, 5);
      sheet.setColumnWidth(1, 35);
      sheet.setColumnWidth(2, 30);
      sheet.setColumnWidth(3, 20);
      sheet.setColumnWidth(4, 15);
      sheet.setColumnWidth(5, 18);
      sheet.setColumnWidth(6, 25);
    }

    if (date != null) {
      // يوم واحد بس
      final sheetName = _formatDateDisplay(date);
      final sheet = excel[sheetName];
      writeSheet(sheet, items);
    } else {
      // كل الأيام - كل يوم شيت لوحده
      final grouped = <String, List<InventoryItem>>{};
      for (final item in items) {
        grouped.putIfAbsent(item.inventoryDate, () => []).add(item);
      }

      // شيت ملخص كل الأيام
      final summarySheet = excel['الملخص الكامل'];
      final summaryHeaders = [
        '#', 'المنتج', 'المخزن', 'السريال',
        'الحالة', 'تاريخ الصلاحية', 'ملاحظات', 'تاريخ الجرد'
      ];
      for (int i = 0; i < summaryHeaders.length; i++) {
        final cell = summarySheet.cell(
            CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(summaryHeaders[i]);
        cell.cellStyle = headerStyle;
      }

      int summaryRow = 1;
      for (final item in items) {
        final rowData = [
          summaryRow.toString(),
          item.productName,
          item.warehouseName,
          item.serial ?? '-',
          item.condition,
          item.expiryDate ?? '-',
          item.notes ?? '-',
          _formatDateDisplay(item.inventoryDate),
        ];
        String bgColor = '#FFFFFF';
        if (item.condition == 'تالف') bgColor = '#FFEBEE';
        else if (item.condition == 'مستخدم') bgColor = '#FFF3E0';
        else if (item.condition == 'جديد') bgColor = '#E8F5E9';

        for (int j = 0; j < rowData.length; j++) {
          final cell = summarySheet.cell(
              CellIndex.indexByColumnRow(columnIndex: j, rowIndex: summaryRow));
          cell.value = TextCellValue(rowData[j]);
          cell.cellStyle = CellStyle(
            backgroundColorHex: ExcelColor.fromHexString(bgColor),
            horizontalAlign: HorizontalAlign.Center,
          );
        }
        summaryRow++;
      }

      // شيت لكل يوم
      final sortedDates = grouped.keys.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final d in sortedDates) {
        final sheetName = _formatDateDisplay(d);
        final sheet = excel[sheetName];
        writeSheet(sheet, grouped[d]!);
      }
    }

    // احذف الشيت الافتراضي
    try { excel.delete('Sheet1'); } catch (_) {}

    final dir = await getTemporaryDirectory();
    final fileName = date != null
        ? 'KaramStock_${_formatDateForFile(date)}.xlsx'
        : 'KaramStock_all.xlsx';

    // حفظ في Downloads
    try {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        final savedFile = File('${downloadsDir.path}/$fileName');
        await savedFile.writeAsBytes(excel.encode()!);
      }
    } catch (_) {}

    // مشاركة الملف
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(excel.encode()!);
    await Share.shareXFiles([XFile(file.path)], text: 'Karam Stock - $fileName');
  }
}