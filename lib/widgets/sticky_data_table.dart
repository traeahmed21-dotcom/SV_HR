import 'package:flutter/material.dart';

class StickyDataTable extends StatefulWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final List<double>? columnWidths;
  final WidgetStateProperty<Color?>? headingRowColor;
  final double headingRowHeight;
  final double dataRowMinHeight;
  final double dataRowMaxHeight;
  final double columnSpacing;
  final double horizontalMargin;
  final bool showCheckboxColumn;
  final double? dividerThickness;

  const StickyDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.columnWidths,
    this.headingRowColor,
    this.headingRowHeight = 56,
    this.dataRowMinHeight = 48,
    this.dataRowMaxHeight = 56,
    this.columnSpacing = 18,
    this.horizontalMargin = 24,
    this.showCheckboxColumn = false,
    this.dividerThickness,
  });

  @override
  State<StickyDataTable> createState() => _StickyDataTableState();
}

class _StickyDataTableState extends State<StickyDataTable> {
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();

  List<DataColumn> _wrapColumns(
    List<DataColumn> columns,
    List<double> widths,
  ) {
    return List.generate(columns.length, (index) {
      final column = columns[index];
      final width = widths[index];
      return DataColumn(
        numeric: column.numeric,
        tooltip: column.tooltip,
        onSort: column.onSort,
        label: SizedBox(width: width, child: column.label),
      );
    });
  }

  List<DataRow> _wrapRows(
    List<DataRow> rows,
    List<double> widths,
  ) {
    return rows.map((row) {
      return DataRow(
        key: row.key,
        selected: row.selected,
        onSelectChanged: row.onSelectChanged,
        onLongPress: row.onLongPress,
        color: row.color,
        mouseCursor: row.mouseCursor,
        cells: List.generate(row.cells.length, (index) {
          final cell = row.cells[index];
          final width = widths[index];
          return DataCell(
            SizedBox(width: width, child: cell.child),
            placeholder: cell.placeholder,
            showEditIcon: cell.showEditIcon,
            onTap: cell.onTap,
            onLongPress: cell.onLongPress,
            onDoubleTap: cell.onDoubleTap,
            onTapDown: cell.onTapDown,
            onTapCancel: cell.onTapCancel,
          );
        }),
      );
    }).toList(growable: false);
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final widths = widget.columnWidths;
    final columns = widths != null && widths.length == widget.columns.length
        ? _wrapColumns(widget.columns, widths)
        : widget.columns;
    final rows = widths != null && widths.length == widget.columns.length
        ? _wrapRows(widget.rows, widths)
        : widget.rows;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final bodyHeight = (availableHeight - widget.headingRowHeight)
            .clamp(0.0, availableHeight);

        return Scrollbar(
          controller: _vertical,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Column(
                children: [
                  DataTable(
                    headingRowColor: widget.headingRowColor,
                    headingRowHeight: widget.headingRowHeight,
                    dataRowMinHeight: widget.dataRowMinHeight,
                    dataRowMaxHeight: widget.dataRowMaxHeight,
                    columnSpacing: widget.columnSpacing,
                    horizontalMargin: widget.horizontalMargin,
                    showCheckboxColumn: widget.showCheckboxColumn,
                    dividerThickness: widget.dividerThickness,
                    columns: columns,
                    rows: const [],
                  ),
                  SizedBox(
                    height: bodyHeight,
                    child: SingleChildScrollView(
                      controller: _vertical,
                      child: DataTable(
                        headingRowColor: widget.headingRowColor,
                        headingRowHeight: 0,
                        dataRowMinHeight: widget.dataRowMinHeight,
                        dataRowMaxHeight: widget.dataRowMaxHeight,
                        columnSpacing: widget.columnSpacing,
                        horizontalMargin: widget.horizontalMargin,
                        showCheckboxColumn: widget.showCheckboxColumn,
                        dividerThickness: widget.dividerThickness,
                        columns: columns,
                        rows: rows,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
