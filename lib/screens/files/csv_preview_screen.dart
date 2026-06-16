import 'package:flutter/material.dart';

import 'package:blu/app.dart';

class CsvPreviewScreen extends StatelessWidget {
  final String filename;
  final List<List<String>> rows;

  const CsvPreviewScreen({
    super.key,
    required this.filename,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final headers = rows.isNotEmpty ? rows.first : <String>[];
    final dataRows = rows.length > 1 ? rows.sublist(1) : const <List<String>>[];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: sensorXRed,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        title: Text('Preview: $filename'),
      ),
      body: rows.isEmpty
          ? const Center(child: Text('No data'))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 600),
                child: SingleChildScrollView(
                  child: DataTable(
                    columns:
                        headers.map((h) => DataColumn(label: Text(h))).toList(),
                    rows: dataRows
                        .map(
                          (r) => DataRow(
                            cells: r.map((c) => DataCell(Text(c))).toList(),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
    );
  }
}
