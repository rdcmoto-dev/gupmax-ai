class ProjectMemoryEntry {
  const ProjectMemoryEntry({required this.label, required this.value});

  final String label;
  final String value;
}

abstract final class ProjectMemory {
  static const maxEntries = 10;
  static const maxLabelLength = 80;
  static const maxValueLength = 1000;
  static const maxSerializedLength = 4000;

  static List<ProjectMemoryEntry> parse(String? context) {
    final source = context?.trim();
    if (source == null || source.isEmpty) return const [];
    final entries = <ProjectMemoryEntry>[];
    for (final rawLine in source.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf(':');
      if (separator > 0) {
        final label = line.substring(0, separator).trim();
        final value = line.substring(separator + 1).trim();
        if (label.isNotEmpty && value.isNotEmpty) {
          entries.add(ProjectMemoryEntry(label: label, value: value));
          continue;
        }
      }
      entries.add(ProjectMemoryEntry(label: 'Informação', value: line));
    }
    return entries.take(maxEntries).toList(growable: false);
  }

  static String? serialize(Iterable<ProjectMemoryEntry> entries) {
    final normalized = entries
        .map((entry) => ProjectMemoryEntry(
              label: _compact(entry.label),
              value: _compact(entry.value),
            ))
        .where((entry) => entry.label.isNotEmpty && entry.value.isNotEmpty)
        .take(maxEntries)
        .toList();
    if (normalized.isEmpty) return null;
    final value =
        normalized.map((entry) => '${entry.label}: ${entry.value}').join('\n');
    if (value.length > maxSerializedLength) {
      throw const FormatException(
          'Contexto do projeto excede 4.000 caracteres.');
    }
    return value;
  }

  static String _compact(String value) => value.trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
}
