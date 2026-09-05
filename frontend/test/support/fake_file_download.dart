import 'dart:typed_data';

import 'package:gupmax_ai/core/download/file_download.dart';

class FakeFileDownload implements FileDownloadService {
  int calls = 0;
  Uint8List? bytes;
  String? filename;
  String? mimeType;

  @override
  void download({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) {
    calls++;
    this.bytes = bytes;
    this.filename = filename;
    this.mimeType = mimeType;
  }
}
