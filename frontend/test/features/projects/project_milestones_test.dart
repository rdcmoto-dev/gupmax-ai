import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/projects/project_memory.dart';
import 'package:gupmax_ai/features/projects/project_milestones.dart';

void main() {
  test('parseia aliases e deduplica trim case e espaços', () {
    const context = 'Marco: Publicar campanha\n'
        'milestone:   publicar   campanha\n'
        'Milestone: Avaliar resultados\n'
        'Público: Famílias';

    expect(ProjectMilestones.parse(context).items,
        ['Publicar campanha', 'Avaliar resultados']);
  });

  test('persiste formato canônico e preserva Goals e memória', () {
    final merged = ProjectMilestones.merge(
      context: 'Objetivo: Lançar campanha\nCanal: Instagram',
      milestones: [' Definir   posicionamento ', 'Publicar campanha'],
    );

    expect(
      merged,
      'Marco: Definir posicionamento\n'
      'Marco: Publicar campanha\n'
      'Objetivo: Lançar campanha\n'
      'Canal: Instagram',
    );
  });

  test('edita e remove aliases anteriores', () {
    final merged = ProjectMilestones.merge(
      context: 'Milestone: Antigo\nTom: Claro',
      milestones: ['Novo'],
    );
    expect(merged, 'Marco: Novo\nTom: Claro');

    expect(
      ProjectMilestones.merge(context: merged, milestones: const []),
      'Tom: Claro',
    );
  });

  test('ignora vazios e rejeita duplicados normalizados', () {
    expect(
      ProjectMilestones.merge(context: null, milestones: ['', '  ']),
      isNull,
    );
    expect(
      () => ProjectMilestones.merge(
        context: null,
        milestones: ['Publicar campanha', '  publicar   campanha  '],
      ),
      throwsFormatException,
    );
  });

  test('aplica máximo de cinco marcos e 500 caracteres', () {
    expect(
      () => ProjectMilestones.merge(
        context: null,
        milestones: List.generate(6, (index) => 'Marco $index'),
      ),
      throwsFormatException,
    );
    expect(
      () => ProjectMilestones.merge(
        context: null,
        milestones: [List.filled(501, 'x').join()],
      ),
      throwsFormatException,
    );
  });

  test('respeita limite global sem truncar entradas existentes', () {
    final context =
        List.generate(20, (index) => 'Campo $index: Valor').join('\n');
    expect(ProjectMilestones.availableSlots(context), 0);
    expect(
      () => ProjectMilestones.merge(
        context: context,
        milestones: ['Novo marco'],
      ),
      throwsFormatException,
    );
  });

  test('nove entradas reais ainda permitem cinco marcos', () {
    final context =
        List.generate(9, (index) => 'Campo $index: Valor').join('\n');
    expect(ProjectMilestones.availableSlots(context), 5);
    expect(
      ProjectMilestones.merge(
        context: context,
        milestones: List.generate(5, (index) => 'Marco $index'),
      ),
      contains('Marco: Marco 4'),
    );
  });

  test('explica limites específico, global e total do contexto', () {
    expect(
      ProjectMilestones.addUnavailableReason(
        context: null,
        milestones: List.generate(5, (index) => 'Marco $index'),
      ),
      'Limite de 5 marcos atingido.',
    );
    final full = List.generate(20, (index) => 'Campo $index: Valor').join('\n');
    expect(
      ProjectMilestones.addUnavailableReason(
          context: full, milestones: const []),
      contains('Limite de informações do projeto'),
    );
    expect(
      ProjectMilestones.addUnavailableReason(
        context: List.filled(ProjectMemory.maxSerializedLength, 'x').join(),
        milestones: const [],
      ),
      contains('4.000 caracteres'),
    );
  });

  test('habilita nova linha somente quando os marcos locais são válidos', () {
    expect(
        ProjectMilestones.canAdd(context: null, milestones: const []), isTrue);
    expect(ProjectMilestones.canAdd(context: null, milestones: const ['']),
        isFalse);
    expect(
      ProjectMilestones.canAdd(context: null, milestones: const ['Marco 1']),
      isTrue,
    );
    expect(
      ProjectMilestones.canAdd(
        context: null,
        milestones: const ['Marco 1', '  marco   1 '],
      ),
      isFalse,
    );
    expect(
      ProjectMilestones.canAdd(
        context: null,
        milestones: List.generate(5, (index) => 'Marco $index'),
      ),
      isFalse,
    );
  });
}
