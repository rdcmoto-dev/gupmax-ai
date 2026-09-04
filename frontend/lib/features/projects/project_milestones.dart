import 'dart:math' as math;

import 'project_memory.dart';

class ProjectMilestones {
  const ProjectMilestones(this.items, {this.completedItems = const {}});

  static const maxItems = 5;
  static const maxItemLength = 500;
  static const canonicalLabel = 'Marco';

  final List<String> items;
  final Set<String> completedItems;

  bool get isEmpty => items.isEmpty;

  static ProjectMilestones parse(String? context) {
    final items = <String>[];
    final seen = <String>{};
    final completed = <String>{};
    for (final entry in ProjectMemory.parse(context)) {
      if (!isMilestoneEntry(entry)) continue;
      final status = _completion(entry.value);
      final signature = _signature(status.$2);
      if (signature.isNotEmpty && seen.add(signature)) items.add(status.$2);
      if (status.$1) completed.add(signature);
      if (items.length == maxItems) break;
    }
    return ProjectMilestones(List.unmodifiable(items),
        completedItems: Set.unmodifiable(completed));
  }

  static bool isMilestoneEntry(ProjectMemoryEntry entry) {
    final label = _signature(entry.label);
    return label == 'marco' || label == 'milestone';
  }

  bool isCompleted(String value) => completedItems.contains(_signature(value));

  static String? toggle(
      {required String? context,
      required String milestone,
      required bool completed}) {
    final target = _signature(milestone);
    return ProjectMemory.serialize(ProjectMemory.parse(context).map((entry) {
      if (!isMilestoneEntry(entry)) return entry;
      final status = _completion(entry.value);
      if (_signature(status.$2) != target) return entry;
      return ProjectMemoryEntry(
          label: canonicalLabel,
          value: completed ? '[x] ${status.$2}' : status.$2);
    }));
  }

  static int availableSlots(String? context) {
    final otherCount = ProjectMemory.parse(context)
        .where((entry) => !isMilestoneEntry(entry))
        .length;
    return math.max(
      0,
      math.min(maxItems, ProjectMemory.maxEntries - otherCount),
    );
  }

  static bool canAdd({
    required String? context,
    required Iterable<String> milestones,
  }) {
    final values = milestones.toList(growable: false);
    if (values.length >= availableSlots(context)) return false;
    final signatures = <String>{};
    for (final rawValue in values) {
      final value = _compact(rawValue);
      if (value.isEmpty || value.length > maxItemLength) return false;
      if (!signatures.add(_signature(value))) return false;
    }
    return true;
  }

  static String? addUnavailableReason({
    required String? context,
    required Iterable<String> milestones,
  }) {
    final values = milestones.toList(growable: false);
    if (values.length >= maxItems) return 'Limite de 5 marcos atingido.';
    if (values.length >= availableSlots(context)) {
      return 'Limite de informações do projeto atingido. Remova uma informação para adicionar outra.';
    }
    if ((context?.length ?? 0) >= ProjectMemory.maxSerializedLength) {
      return 'Limite total de 4.000 caracteres do contexto atingido.';
    }
    final normalized = values.map(_compact).toList(growable: false);
    if (normalized.any((value) => value.isEmpty)) {
      return 'Preencha o marco atual antes de adicionar outro.';
    }
    if (normalized.any((value) => value.length > maxItemLength)) {
      return 'Cada marco deve ter no máximo 500 caracteres.';
    }
    if (normalized.map(_signature).toSet().length != normalized.length) {
      return 'Não adicione marcos duplicados.';
    }
    return null;
  }

  static String? merge({
    required String? context,
    required Iterable<String> milestones,
  }) {
    final current = parse(context);
    final normalized = milestones
        .map(_compact)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalized.length > maxItems) {
      throw const FormatException('Use no máximo 5 marcos.');
    }
    if (normalized.any((value) => value.length > maxItemLength)) {
      throw const FormatException(
        'Cada marco deve ter no máximo 500 caracteres.',
      );
    }
    final signatures = normalized.map(_signature).toList(growable: false);
    if (signatures.toSet().length != signatures.length) {
      throw const FormatException('Não adicione marcos duplicados.');
    }
    final others = ProjectMemory.parse(context)
        .where((entry) => !isMilestoneEntry(entry))
        .toList(growable: false);
    if (others.length + normalized.length > ProjectMemory.maxEntries) {
      throw const FormatException(
        'Limite de informações do projeto atingido. Remova uma informação para adicionar outra.',
      );
    }
    return ProjectMemory.serialize([
      for (final value in normalized)
        ProjectMemoryEntry(
          label: canonicalLabel,
          value: current.isCompleted(value) ? '[x] $value' : value,
        ),
      ...others,
    ]);
  }

  static String _compact(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _signature(String value) => _compact(value).toLowerCase();

  static (bool, String) _completion(String value) {
    final match = RegExp(r'^\[\s*x\s*\]\s*(.*)$', caseSensitive: false)
        .firstMatch(value.trim());
    return match == null ? (false, value) : (true, match.group(1)!.trim());
  }
}
