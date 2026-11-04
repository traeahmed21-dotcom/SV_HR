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
    final result = await OpenFile.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
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

    final maxRowsPerPage = 12;
    final chunks = <List<List<String>>>[];
    for (var i = 0; i < rows.length; i += maxRowsPerPage) {
      chunks.add(rows.sublist(i, (i + maxRowsPerPage).clamp(0, rows.length)));
    }

    const maxColsPerPage = 8;
    final colChunks = <List<int>>[];
    for (var c = 0; c < headers.length; c += maxColsPerPage) {
      final end = (c + maxColsPerPage).clamp(0, headers.length);
      colChunks.add(List<int>.generate(end - c, (i) => c + i));
    }

    for (var rowPage = 0; rowPage < chunks.length; rowPage++) {
      final chunk = chunks[rowPage];
      final rowFrom = rowPage * maxRowsPerPage + 1;
      final rowTo = rowFrom + chunk.length - 1;

      for (var colPage = 0; colPage < colChunks.length; colPage++) {
        final colIdx = colChunks[colPage];
        final h = colIdx.map((i) => headers[i]).toList(growable: false);
        final r = chunk
            .map((row) => colIdx.map((i) => row[i]).toList(growable: false))
            .toList(growable: false);

        final colFrom = colIdx.first + 1;
        final colTo = colIdx.last + 1;
        final sub = subtitle == null || subtitle.trim().isEmpty
            ? 'الأعمدة: $colFrom-$colTo | الصفوف: $rowFrom-$rowTo'
            : '$subtitle | الأعمدة: $colFrom-$colTo | الصفوف: $rowFrom-$rowTo';

        final widget = _buildSnapshotPage(
          theme: theme,
          title: rowPage == 0 && colPage == 0 ? title : null,
          subtitle: sub,
          headers: h,
          rows: r,
        );

        final width = (h.length * 240).clamp(1400, 2800).toDouble();
        final height = (520 + (r.length * 86)).clamp(1000, 2200).toDouble();

        final png = await _captureWidgetPng(
          overlay: overlay,
          theme: theme,
          mediaQuery: mediaQuery,
          child: widget,
          logicalSize: Size(width, height),
          isRtl: isRtl,
          pixelRatio: 2,
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
    required double pixelRatio,
  }) {
    final completer = Completer<Uint8List>();
    final repaintKey = GlobalKey();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) {
        return IgnorePointer(
          child: Opacity(
            opacity: 0.01,
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

      () async {
        try {
          await WidgetsBinding.instance.endOfFrame;
          final image = await boundary
              .toImage(pixelRatio: pixelRatio)
              .timeout(const Duration(seconds: 12));
          final byteData = await image
              .toByteData(format: ui.ImageByteFormat.png)
              .timeout(const Duration(seconds: 12));
          entry.remove();
          if (byteData == null) {
            completer.completeError(Exception('فشل تحويل التقرير لصورة'));
            return;
          }
          completer.complete(byteData.buffer.asUint8List());
        } catch (e) {
          entry.remove();
          completer.completeError(e);
        }
      }();
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
    final result = await OpenFile.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }
}
