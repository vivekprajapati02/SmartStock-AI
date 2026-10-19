import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedCsv {
  const PickedCsv({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Lets the user choose a CSV file on any platform (mobile, web, desktop).
abstract class CsvFilePicker {
  /// Returns null when the user cancels.
  Future<PickedCsv?> pick();
}

class PlatformCsvFilePicker implements CsvFilePicker {
  @override
  Future<PickedCsv?> pick() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a sales CSV',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    if (file == null) return null;
    return PickedCsv(name: file.name, bytes: await file.readAsBytes());
  }
}
