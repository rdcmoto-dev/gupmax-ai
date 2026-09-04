import 'dart:math' as math;

import 'project_memory.dart';

class ProjectGoals {
  const ProjectGoals(
      {this.objective,
      this.criteria = const [],
      this.completedCriteria = const {}});

  static const maxCriteria = 5;
  static const objectiveLabel = 'Objetivo';
  static const criterionLabel = 'Critério de sucesso';

  final String? objective;
  final List<String> criteria;
  final Set<String> completedCriteria;

  bool get isEmpty => objective == null && criteria.isEmpty;

  static ProjectGoals parse(String? context) {
    String? objective;
    final criteria = <String>[];
    final completed = <String>{};
    for (final entry in ProjectMemory.parse(context)) {
      if (_isObjective(entry.label) && objective == null) {
        objective = entry.value;
      } else if (_isCriterion(entry.label) && criteria.length < maxCriteria) {
        final status = _completion(entry.value);
        criteria.add(status.$2);
        if (status.$1) completed.add(_fold(status.$2));
      }
    }
    return ProjectGoals(
      objective: objective,
      criteria: List.unmodifiable(criteria),
      completedCriteria: Set.unmodifiable(completed),
    );
  }

  static List<ProjectMemoryEntry> memoryEntries(String? context) =>
      ProjectMemory.parse(context)
          .where((entry) => !isGoalEntry(entry))
          .toList(growable: false);

  static int availableCriteria(String? context, {required bool hasObjective}) {
    final otherCount = ProjectMemory.parse(context)
        .where((entry) => !isGoalEntry(entry))
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
    final current = parse(context);
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
        .where((entry) => !isGoalEntry(entry))
        .toList(growable: false);
    final goals = <ProjectMemoryEntry>[
      if (normalizedObjective != null && normalizedObjective.isNotEmpty)
        ProjectMemoryEntry(
          label: objectiveLabel,
          value: normalizedObjective,
        ),
      for (final criterion in normalizedCriteria)
        ProjectMemoryEntry(
          label: criterionLabel,
          value: current.isCriterionCompleted(criterion)
              ? '[x] $criterion'
              : criterion,
        ),
    ];
    if (goals.length + others.length > ProjectMemory.maxEntries) {
      throw const FormatException(
        'Limite de informações do projeto atingido. Remova uma informação para adicionar outra.',
      );
    }
    return ProjectMemory.serialize([...goals, ...others]);
  }

  static bool isGoalEntry(ProjectMemoryEntry entry) =>
      _isObjective(entry.label) || _isCriterion(entry.label);

  bool isCriterionCompleted(String value) =>
      completedCriteria.contains(_fold(value));

  static String? toggleCriterion(
      {required String? context,
      required String criterion,
      required bool completed}) {
    final target = _fold(criterion);
    return ProjectMemory.serialize(ProjectMemory.parse(context).map((entry) {
      if (!_isCriterion(entry.label)) return entry;
      final status = _completion(entry.value);
      if (_fold(status.$2) != target) return entry;
      return ProjectMemoryEntry(
          label: criterionLabel,
          value: completed ? '[x] ${status.$2}' : status.$2);
    }));
  }

  static (bool, String) _completion(String value) {
    final match = RegExp(r'^\[\s*x\s*\]\s*(.*)$', caseSensitive: false)
        .firstMatch(value.trim());
    return match == null ? (false, value) : (true, match.group(1)!.trim());
  }

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
