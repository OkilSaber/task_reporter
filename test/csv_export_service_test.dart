import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_reporter/models/category.dart';
import 'package:task_reporter/services/csv_export_service.dart';

void main() {
  final categories = [
    Category(id: 'p1', name: 'Projet Alpha', color: Colors.blue),
    Category(id: 'p2', name: 'Projet; Beta', color: Colors.red),
  ];

  String export(
    Map<String, Map<String, double>> records, [
    Map<String, String> comments = const {},
  ]) => CsvExportService.buildMonthCsv(
    month: DateTime(2026, 9, 1),
    dayRecords: records,
    dayComments: comments,
    categories: categories,
  );

  test('exports one line per entry, in category order', () {
    final csv = export(
      {
        '2026-09-03': {'p2': 0.25, 'p1': 0.75},
      },
      {'2026-09-03': 'Réunion client'},
    );

    expect(
      csv,
      'p1;Projet Alpha;2026/09/03;Réunion client;0.75\r\n'
      'p2;"Projet; Beta";2026/09/03;Réunion client;0.25\r\n',
    );
  });

  test('keeps only the requested month and skips zero durations', () {
    final csv = export({
      '2026-08-31': {'p1': 1.0},
      '2026-09-10': {'p1': 0.0, 'p2': 1.0},
      '2026-10-01': {'p1': 1.0},
    });

    expect(csv, 'p2;"Projet; Beta";2026/09/10;;1.00\r\n');
  });

  test('sorts days chronologically', () {
    final csv = export({
      '2026-09-20': {'p1': 1.0},
      '2026-09-02': {'p1': 1.0},
    });

    expect(
      csv,
      'p1;Projet Alpha;2026/09/02;;1.00\r\n'
      'p1;Projet Alpha;2026/09/20;;1.00\r\n',
    );
  });

  test('quotes comments containing separators, quotes or newlines', () {
    final csv = export(
      {
        '2026-09-01': {'p1': 0.5},
      },
      {'2026-09-01': 'a;b "c"\nd'},
    );

    expect(csv, 'p1;Projet Alpha;2026/09/01;"a;b ""c""\nd";0.50\r\n');
  });

  test('falls back to the id for unknown categories, listed last', () {
    final csv = export({
      '2026-09-01': {'napta_bank_holiday': 1.0, 'p1': 0.5},
    });

    expect(
      csv,
      'p1;Projet Alpha;2026/09/01;;0.50\r\n'
      'napta_bank_holiday;napta_bank_holiday;2026/09/01;;1.00\r\n',
    );
  });

  test('returns an empty string when the month has no entry', () {
    expect(export({}), '');
  });

  test('file name carries the exported month', () {
    expect(
      CsvExportService.fileNameFor(DateTime(2026, 9, 1)),
      'task_reporter_2026-09.csv',
    );
  });
}
