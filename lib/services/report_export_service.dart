import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReportExportService {
  static Future<void> exportExcelCsv({
    required String fileBaseName,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final csv = const ListToCsvConverter().convert(<List<String>>[
      headers,
      ...rows,
    ]);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileBaseName.csv');
    await file.writeAsString('\uFEFF$csv', encoding: utf8, flush: true);
    await OpenFile.open(file.path);
  }

  static Future<void> exportPdfTable({
    required BuildContext context,
    required String fileBaseName,
    required String title,
    String? subtitle,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final textDirection = Directionality.of(context);
    final isRtl = textDirection == TextDirection.rtl;
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final overlay = Overlay.of(context);
    final doc = pw.Document();

    final maxRowsPerPage = 18;
    final chunks = <List<List<String>>>[];
    for (var i = 0; i < rows.length; i += maxRowsPerPage) {
      chunks.add(rows.sublist(i, (i + maxRowsPerPage).clamp(0, rows.length)));
    }

    for (var pageIndex = 0; pageIndex < chunks.length; pageIndex++) {
      final chunk = chunks[pageIndex];
      final widget = _buildSnapshotPage(
        theme: theme,
        title: pageIndex == 0 ? title : null,
        subtitle: pageIndex == 0 ? subtitle : null,
        headers: headers,
        rows: chunk,
      );

      final png = await _captureWidgetPng(
        overlay: overlay,
        theme: theme,
        mediaQuery: mediaQuery,
        child: widget,
        logicalSize: const Size(1400, 900),
        isRtl: isRtl,
      );

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (_) => pw.Center(
            child: pw.Image(
              pw.MemoryImage(png),
              fit: pw.BoxFit.contain,
            ),
          ),
        ),
      );
    }

    final bytes = await doc.save();
    await _saveAndOpen(
      fileBaseName: fileBaseName,
      extension: '.pdf',
      bytes: bytes,
    );
  }

  static Widget _buildSnapshotPage({
    required ThemeData theme,
    String? title,
    String? subtitle,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final scheme = theme.colorScheme;
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(18),
      child: DefaultTextStyle(
        style: baseStyle ?? const TextStyle(fontSize: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null && title.trim().isNotEmpty)
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
            if ((title != null && title.trim().isNotEmpty) ||
                (subtitle != null && subtitle.trim().isNotEmpty))
              const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFBDBDBD), width: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    ),
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 42,
                    columnSpacing: 14,
                    columns: headers
                        .map(
                          (h) => DataColumn(
                            label: Text(
                              h,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                    rows: rows
                        .map(
                          (r) => DataRow(
                            cells: r
                                .map(
                                  (c) => DataCell(
                                    Text(
                                      c,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<Uint8List> _captureWidgetPng({
    required OverlayState overlay,
    required ThemeData theme,
    required MediaQueryData mediaQuery,
    required Widget child,
    required Size logicalSize,
    required bool isRtl,
  }) {
    final completer = Completer<Uint8List>();
    final repaintKey = GlobalKey();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) {
        return Offstage(
          offstage: true,
          child: MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(1),
            ),
            child: Theme(
              data: theme,
              child: Directionality(
                textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: RepaintBoundary(
                      key: repaintKey,
                      child: SizedBox(
                        width: logicalSize.width,
                        height: logicalSize.height,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = repaintKey.currentContext;
      if (ctx == null) {
        entry.remove();
        completer.completeError(Exception('فشل إنشاء صورة التقرير'));
        return;
      }

      final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        entry.remove();
        completer.completeError(Exception('فشل التقاط صورة التقرير'));
        return;
      }

      boundary.toImage(pixelRatio: 3).then((image) {
        return image.toByteData(format: ui.ImageByteFormat.png);
      }).then((byteData) {
        entry.remove();
        if (byteData == null) {
          completer.completeError(Exception('فشل تحويل التقرير لصورة'));
          return;
        }
        completer.complete(byteData.buffer.asUint8List());
      }).catchError((e) {
        entry.remove();
        completer.completeError(e);
      });
    });

    return completer.future;
  }

  static Future<void> _saveAndOpen({
    required String fileBaseName,
    required String extension,
    required Uint8List bytes,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileBaseName$extension');
    await file.writeAsBytes(bytes, flush: true);
    await OpenFile.open(file.path);
  }
}
