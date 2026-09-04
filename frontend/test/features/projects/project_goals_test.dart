import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/projects/project_goals.dart';
import 'package:gupmax_ai/features/projects/project_memory.dart';

void main() {
  test('marca e desmarca critério manualmente sem criar entrada adicional', () {
    const context =
        'Objetivo: Meta\nCritério de sucesso: Campanha pronta\nTom: Claro';
    final completed = ProjectGoals.toggleCriterion(
      context: context,
      criterion: '  campanha   pronta ',
      completed: true,
    );
    final goals = ProjectGoals.parse(completed);
    expect(goals.criteria, ['Campanha pronta']);
    expect(goals.isCriterionCompleted('CAMPANHA PRONTA'), isTrue);
    expect(ProjectMemory.parse(completed), hasLength(3));
    expect(
      ProjectGoals.toggleCriterion(
        context: completed,
        criterion: 'Campanha pronta',
        completed: false,
      ),
      context,
    );
  });
  test('parseia objetivo e múltiplos critérios sem duplicar memória', () {
    const context = 'Público: Famílias\n'
        'Objetivo: Aumentar reconhecimento local\n'
        'Critério de sucesso: Campanha pronta para Instagram\n'
        'Critério de sucesso: Oferta claramente definida';
    final goals = ProjectGoals.parse(context);

    expect(goals.objective, 'Aumentar reconhecimento local');
    expect(goals.criteria, [
      'Campanha pronta para Instagram',
      'Oferta claramente definida',
    ]);
    expect(ProjectGoals.memoryEntries(context).single.label, 'Público');
  });

  test('adiciona objetivo e critérios preservando memória existente', () {
    final merged = ProjectGoals.merge(
      context: 'Público: Famílias\nCanal: Instagram',
      objective: 'Criar campanha local',
      criteria: ['Mensagem definida', 'Oferta definida'],
    );

    expect(
        merged,
        'Objetivo: Criar campanha local\n'
        'Critério de sucesso: Mensagem definida\n'
        'Critério de sucesso: Oferta definida\n'
        'Público: Famílias\n'
        'Canal: Instagram');
  });

  test('edita objetivo e critérios removendo valores anteriores', () {
    final merged = ProjectGoals.merge(
      context: 'Objetivo: Antigo\nCritério de sucesso: Antigo\nTom: Claro',
      objective: 'Novo objetivo',
      criteria: ['Novo critério'],
    );
    expect(ProjectGoals.parse(merged).objective, 'Novo objetivo');
    expect(ProjectGoals.parse(merged).criteria, ['Novo critério']);
    expect(merged, contains('Tom: Claro'));
    expect(merged, isNot(contains('Antigo')));
  });

  test('remove objetivo e critérios sem remover as outras informações', () {
    final merged = ProjectGoals.merge(
      context: 'Objetivo: Meta\nCritério de sucesso: Resultado\nTom: Claro',
      objective: '',
      criteria: const [],
    );
    expect(merged, 'Tom: Claro');
    expect(ProjectGoals.parse(merged).isEmpty, isTrue);
  });

  test('limita critérios a cinco', () {
    expect(
      () => ProjectGoals.merge(
        context: null,
        objective: 'Meta',
        criteria: List.generate(6, (index) => 'Critério $index'),
      ),
      throwsFormatException,
    );
  });

  test('respeita limite global sem truncar memória existente', () {
    final context =
        List.generate(20, (index) => 'Campo $index: Valor').join('\n');
    expect(
      () => ProjectGoals.merge(
        context: context,
        objective: 'Meta',
        criteria: const [],
      ),
      throwsFormatException,
    );
    expect(ProjectGoals.availableCriteria(context, hasObjective: true), 0);
  });
}
