import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/projects/domain/project.dart';
import 'package:gupmax_ai/features/projects/project_organization.dart';
import 'package:gupmax_ai/features/projects/project_overview.dart';
import 'package:gupmax_ai/features/prompt_chains/domain/prompt_chain.dart';

void main() {
  ProjectRecord project(
    String id, {
    bool isFavorite = false,
    String? name,
    String? context,
    ProjectStatus status = ProjectStatus.active,
    int day = 1,
  }) =>
      ProjectRecord(
        id: id,
        isFavorite: isFavorite,
        name: name ?? id,
        context: context,
        status: status,
        promptCount: 0,
        templateCount: 0,
        createdAt: DateTime.utc(2026, 1, day),
        updatedAt: DateTime.utc(2026, 1, day),
      );

  PromptChainRecord chain(
    String id, {
    String? projectId,
    bool completed = false,
    int completedSteps = 0,
    String? currentStepId,
    PromptChainStatus status = PromptChainStatus.active,
    int day = 1,
  }) =>
      PromptChainRecord(
        id: id,
        name: id,
        projectId: projectId,
        status: status,
        stepCount: 2,
        completedStepCount: completedSteps,
        currentStepId: currentStepId,
        executionCompleted: completed,
        createdAt: DateTime.utc(2026, 1, day),
        updatedAt: DateTime.utc(2026, 1, day),
      );

  final items = [
    ProjectOverview(project: project('Pizzaria Antiga', day: 1)),
    ProjectOverview(
      project: project('Campanha Atual', day: 2),
      chain: chain('chain-running',
          projectId: 'Campanha Atual', currentStepId: 'step-1', day: 2),
    ),
    ProjectOverview(
      project: project('Entrega Concluída', day: 3),
      chain: chain('chain-done',
          projectId: 'Entrega Concluída',
          completed: true,
          completedSteps: 2,
          day: 3),
    ),
    ProjectOverview(
      project: project('Projeto Encerrado',
          context: 'Projeto encerrado: sim', day: 4),
    ),
    ProjectOverview(
      project:
          project('Projeto Arquivado', status: ProjectStatus.archived, day: 5),
    ),
  ];

  test('busca por nome ignora caixa e espaços extras e aceita nenhum resultado',
      () {
    expect(
      organizeProjects(items, search: '  pizzaria   antiga  ').single.name,
      'Pizzaria Antiga',
    );
    expect(organizeProjects(items, search: 'inexistente'), isEmpty);
    expect(organizeProjects(const []), isEmpty);
  });

  test('filtros distinguem andamento, concluído, encerrado e arquivado', () {
    expect(organizeProjects(items), hasLength(5));
    expect(
      organizeProjects(items, filter: ProjectListFilter.inProgress)
          .map((item) => item.name),
      containsAll(['Pizzaria Antiga', 'Campanha Atual']),
    );
    expect(
      organizeProjects(items, filter: ProjectListFilter.completed).single.name,
      'Entrega Concluída',
    );
    expect(
      organizeProjects(items, filter: ProjectListFilter.closed).single.name,
      'Projeto Encerrado',
    );
    expect(
      organizeProjects(items, filter: ProjectListFilter.archived).single.name,
      'Projeto Arquivado',
    );
  });

  test('arquivado prevalece sem ser misturado com encerramento manual', () {
    final both = ProjectOverview(
      project: project(
        'Ambos',
        status: ProjectStatus.archived,
        context: 'Projeto encerrado: sim',
      ),
    );
    expect(projectListState(both), ProjectListFilter.archived);
    expect(both.statusLabel, 'Arquivado');
  });

  test('ordena por datas e nomes deterministicamente', () {
    expect(
      organizeProjects(items).map((item) => item.name).first,
      'Projeto Arquivado',
    );
    expect(
      organizeProjects(items, order: ProjectListOrder.oldest).first.name,
      'Pizzaria Antiga',
    );
    expect(
      organizeProjects(items, order: ProjectListOrder.nameAscending).first.name,
      'Campanha Atual',
    );
    expect(
      organizeProjects(items, order: ProjectListOrder.nameDescending)
          .first
          .name,
      'Projeto Encerrado',
    );
  });

  test('Favoritos combina busca e estados sem mudar as quatro ordenações', () {
    final favorite =
        ProjectOverview(project: project('Zeta', isFavorite: true, day: 1));
    final ordinary = ProjectOverview(project: project('Alfa', day: 2));
    final archived = ProjectOverview(
        project: project('Zeta arquivo',
            isFavorite: true, status: ProjectStatus.archived));
    final closed = ProjectOverview(
        project: project('Zeta encerrado',
            isFavorite: true, context: 'Projeto encerrado: sim'));
    final source = [
      ordinary,
      favorite,
      archived,
      closed,
      ProjectOverview(chain: chain('solo'))
    ];
    expect(organizeProjects(source, filter: ProjectListFilter.favorites),
        hasLength(3));
    expect(
        organizeProjects(source,
                filter: ProjectListFilter.favorites,
                search: '  ZETA   arquivo ')
            .single,
        archived);
    expect(organizeProjects([ordinary], filter: ProjectListFilter.favorites),
        isEmpty);
    expect(organizeProjects(source, filter: ProjectListFilter.archived).single,
        archived);
    expect(organizeProjects(source, filter: ProjectListFilter.closed).single,
        closed);
    expect(
        organizeProjects([favorite, ordinary], order: ProjectListOrder.recent),
        [ordinary, favorite]);
    expect(
        organizeProjects([favorite, ordinary], order: ProjectListOrder.oldest),
        [favorite, ordinary]);
    expect(
        organizeProjects([favorite, ordinary],
            order: ProjectListOrder.nameAscending),
        [ordinary, favorite]);
    expect(
        organizeProjects([favorite, ordinary],
            order: ProjectListOrder.nameDescending),
        [favorite, ordinary]);
  });

  test('combina busca filtro e ordenação sem mutar a entrada', () {
    final source = [...items];
    final result = organizeProjects(
      source,
      search: 'campanha',
      filter: ProjectListFilter.inProgress,
      order: ProjectListOrder.nameDescending,
    );
    expect(result.map((item) => item.name), ['Campanha Atual']);
    expect(source, items);
  });
}
