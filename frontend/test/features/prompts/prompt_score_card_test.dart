import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/prompts/domain/prompt_models.dart';
import 'package:gupmax_ai/features/prompts/presentation/prompt_score_card.dart';

PromptQualityScore score(int value) => PromptQualityScore(
      promptId: 'prompt-1',
      score: value,
      rating: value == 100
          ? 'excellent'
          : value == 0
              ? 'weak'
              : 'very_good',
      criteria: const [
        PromptQualityCriterion(
          key: 'objective',
          label: 'Objetivo',
          score: 18,
          maxScore: 20,
          status: 'good',
          feedback: 'O objetivo está claro.',
        ),
      ],
      strengths: const ['Objetivo claro.'],
      improvements: const ['Detalhe melhor o público.'],
      suggestions: const ['Defina para quem a resposta será criada.'],
    );

void main() {
  Future<void> pump(WidgetTester tester,
      {PromptQualityScore? value, bool loading = false, String? error}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PromptScoreCard(
            score: value,
            loading: loading,
            error: error,
            onImprove: (_) {},
          ),
        ),
      ),
    ));
  }

  testWidgets('mostra loading e erro', (tester) async {
    await pump(tester, loading: true);
    expect(find.byKey(const Key('score_loading')), findsOneWidget);
    await pump(tester, error: 'Falha ao calcular score.');
    expect(find.byKey(const Key('score_error')), findsOneWidget);
  });

  for (final value in [0, 100]) {
    testWidgets('renderiza score $value e classificação', (tester) async {
      await pump(tester, value: score(value));
      expect(find.text('$value / 100'), findsOneWidget);
      expect(find.text(value == 100 ? 'Excelente' : 'Fraco'), findsOneWidget);
    });
  }

  testWidgets('expande critérios, sugestões e ação de melhoria',
      (tester) async {
    String? instruction;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PromptScoreCard(
            score: score(82),
            loading: false,
            error: null,
            onImprove: (value) => instruction = value,
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('toggle_score_analysis')));
    await tester.pump();
    expect(find.text('Objetivo'), findsOneWidget);
    expect(find.text('Pontos fortes'), findsOneWidget);
    expect(find.text('O que pode melhorar'), findsOneWidget);
    expect(find.text('Sugestões'), findsOneWidget);
    expect(find.text('Melhorar'), findsOneWidget);
    expect(find.byKey(const Key('score_improvements')), findsOneWidget);
    expect(find.byKey(const Key('score_suggestions')), findsOneWidget);
    await tester.tap(find.byKey(const Key('improve_prompt_from_score')));
    expect(instruction, contains('Defina para quem'));
  });

  testWidgets('score 79 mostra todas as ações do smoke test', (tester) async {
    final smokeScore = PromptQualityScore(
      promptId: 'v3',
      score: 79,
      rating: 'very_good',
      criteria: const [
        PromptQualityCriterion(
            key: 'objective',
            label: 'Objetivo',
            score: 25,
            maxScore: 25,
            status: 'good',
            feedback: 'Objetivo claro.'),
        PromptQualityCriterion(
            key: 'context',
            label: 'Contexto',
            score: 0,
            maxScore: 5,
            status: 'missing',
            feedback: 'Contexto ausente.'),
        PromptQualityCriterion(
            key: 'audience',
            label: 'Público',
            score: 0,
            maxScore: 5,
            status: 'missing',
            feedback: 'Público ausente.'),
        PromptQualityCriterion(
            key: 'instructions',
            label: 'Instruções',
            score: 15,
            maxScore: 15,
            status: 'good',
            feedback: 'Instruções claras.'),
        PromptQualityCriterion(
            key: 'clarity',
            label: 'Clareza',
            score: 15,
            maxScore: 15,
            status: 'good',
            feedback: 'Texto claro.'),
        PromptQualityCriterion(
            key: 'output_format',
            label: 'Formato de saída',
            score: 0,
            maxScore: 5,
            status: 'missing',
            feedback: 'Formato ausente.'),
        PromptQualityCriterion(
            key: 'constraints',
            label: 'Restrições',
            score: 5,
            maxScore: 5,
            status: 'good',
            feedback: 'Restrições claras.'),
        PromptQualityCriterion(
            key: 'tone',
            label: 'Tom',
            score: 8,
            maxScore: 8,
            status: 'good',
            feedback: 'Tom claro.'),
        PromptQualityCriterion(
            key: 'language',
            label: 'Idioma',
            score: 4,
            maxScore: 7,
            status: 'partial',
            feedback: 'Idioma parcial.'),
        PromptQualityCriterion(
            key: 'specificity',
            label: 'Especificidade',
            score: 7,
            maxScore: 10,
            status: 'partial',
            feedback: 'Pode detalhar.'),
      ],
      strengths: const ['Objetivo está bem definido.'],
      improvements: const [
        'Detalhe melhor: contexto.',
        'Detalhe melhor: público.'
      ],
      suggestions: const [
        'Inclua onde o resultado será usado.',
        'Defina para quem a resposta será criada.'
      ],
    );
    await pump(tester, value: smokeScore);
    await tester.tap(find.byKey(const Key('toggle_score_analysis')));
    await tester.pump();

    expect(find.text('Pontos fortes'), findsOneWidget);
    expect(find.text('O que pode melhorar'), findsOneWidget);
    expect(find.text('Sugestões'), findsOneWidget);
    expect(find.text('Melhorar'), findsOneWidget);
    expect(find.byKey(const Key('score_improvements')), findsOneWidget);
    expect(find.byKey(const Key('score_suggestions')), findsOneWidget);
    expect(find.text('• Detalhe melhor: contexto.'), findsOneWidget);
    expect(find.text('• Inclua onde o resultado será usado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('não cria overflow em mobile', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await pump(tester, value: score(100));
    await tester.tap(find.byKey(const Key('toggle_score_analysis')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
