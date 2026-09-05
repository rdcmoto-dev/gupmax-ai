import 'dart:typed_data';

import 'file_download_stub.dart' if (dart.library.html) 'file_download_web.dart'
    as platform;

abstract interface class FileDownloadService {
  void download(
      {required Uint8List bytes,
      required String filename,
      required String mimeType});
}

class PlatformFileDownloadService implements FileDownloadService {
  const PlatformFileDownloadService();

  @override
  void download(
          {required Uint8List bytes,
          required String filename,
          required String mimeType}) =>
      platform.downloadFile(bytes, filename, mimeType);
}
