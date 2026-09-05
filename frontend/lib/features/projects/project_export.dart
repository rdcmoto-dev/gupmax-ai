import 'dart:typed_data';

enum ProjectExportFormat {
  markdown('markdown', 'md', 'text/markdown;charset=utf-8'),
  json('json', 'json', 'application/json;charset=utf-8');

  const ProjectExportFormat(this.queryValue, this.extension, this.mimeType);
  final String queryValue;
  final String extension;
  final String mimeType;
}

class ProjectExportFile {
  const ProjectExportFile(
      {required this.bytes, required this.filename, required this.mimeType});
  final Uint8List bytes;
  final String filename;
  final String mimeType;
}

String safeExportFilename(String? disposition,
    {required String projectName, required ProjectExportFormat format}) {
  final match = disposition == null
      ? null
      : RegExp(r'''filename\*?=(?:UTF-8''|)["']?([^"';]+)''',
              caseSensitive: false)
          .firstMatch(disposition);
  String? candidate = match?.group(1);
  if (candidate != null) {
    try {
      candidate = Uri.decodeComponent(candidate);
    } on FormatException {
      candidate = null;
    }
  }
  candidate ??= '${_slug(projectName)}.${format.extension}';
  candidate = candidate
      .replaceAll(RegExp(r'[/\\]'), '-')
      .replaceAll('..', '-')
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  if (!candidate.toLowerCase().endsWith('.${format.extension}')) {
    candidate = '$candidate.${format.extension}';
  }
  return candidate.isEmpty ? 'projeto.${format.extension}' : candidate;
}

String _slug(String value) {
  const accented = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  const plain = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
  var normalized = value;
  for (var i = 0; i < accented.length; i++) {
    normalized = normalized.replaceAll(accented[i], plain[i]);
  }
  return normalized
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
