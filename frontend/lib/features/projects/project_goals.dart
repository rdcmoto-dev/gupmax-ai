import 'dart:math' as math;

import 'project_memory.dart';

class ProjectGoals {
  const ProjectGoals({this.objective, this.criteria = const []});

  static const maxCriteria = 5;
  static const objectiveLabel = 'Objetivo';
  static const criterionLabel = 'Critério de sucesso';

  final String? objective;
  final List<String> criteria;

  bool get isEmpty => objective == null && criteria.isEmpty;

  static ProjectGoals parse(String? context) {
    String? objective;
    final criteria = <String>[];
    for (final entry in ProjectMemory.parse(context)) {
      if (_isObjective(entry.label) && objective == null) {
        objective = entry.value;
      } else if (_isCriterion(entry.label) && criteria.length < maxCriteria) {
        criteria.add(entry.value);
      }
    }
    return ProjectGoals(
      objective: objective,
      criteria: List.unmodifiable(criteria),
    );
  }

  static List<ProjectMemoryEntry> memoryEntries(String? context) =>
      ProjectMemory.parse(context)
          .where((entry) => !_isGoalEntry(entry))
          .toList(growable: false);

  static int availableCriteria(String? context, {required bool hasObjective}) {
    final otherCount = ProjectMemory.parse(context)
        .where((entry) => !_isGoalEntry(entry))
        .length;
    final available =
        ProjectMemory.maxEntries - otherCount - (hasObjective ? 1 : 0);
    return math.max(0, math.min(maxCriteria, available));
  }

  static String? merge({
    required String? context,
    required String? objective,
    required Iterable<String> criteria,
  }) {
    final normalizedObjective = objective?.trim();
    final normalizedCriteria = criteria
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (normalizedCriteria.length > maxCriteria) {
      throw const FormatException(
        'Use no máximo 5 critérios de sucesso.',
      );
    }
    final others = ProjectMemory.parse(context)
        .where((entry) => !_isGoalEntry(entry))
        .toList(growable: false);
    final goals = <ProjectMemoryEntry>[
      if (normalizedObjective != null && normalizedObjective.isNotEmpty)
        ProjectMemoryEntry(
          label: objectiveLabel,
          value: normalizedObjective,
        ),
      for (final criterion in normalizedCriteria)
        ProjectMemoryEntry(label: criterionLabel, value: criterion),
    ];
    if (goals.length + others.length > ProjectMemory.maxEntries) {
      throw const FormatException(
        'Remova informações do contexto para respeitar o limite de 10 entradas.',
      );
    }
    return ProjectMemory.serialize([...goals, ...others]);
  }

  static bool _isGoalEntry(ProjectMemoryEntry entry) =>
      _isObjective(entry.label) || _isCriterion(entry.label);

  static bool _isObjective(String label) {
    final folded = _fold(label);
    return folded == 'objetivo' || folded == 'objetivo do projeto';
  }

  static bool _isCriterion(String label) {
    final folded = _fold(label);
    return folded == 'criterio de sucesso' || folded == 'criterios de sucesso';
  }

  static String _fold(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[áàãâä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòõôö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}
