import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/prompt_models.dart';

class PromptScoreCard extends StatefulWidget {
  const PromptScoreCard(
      {required this.score,
      required this.loading,
      required this.error,
      required this.onImprove,
      super.key});
  final PromptQualityScore? score;
  final bool loading;
  final String? error;
  final ValueChanged<String> onImprove;

  @override
  State<PromptScoreCard> createState() => _PromptScoreCardState();
}

class _PromptScoreCardState extends State<PromptScoreCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('gupmax_score_card'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: widget.loading
              ? const Center(
                  child: CircularProgressIndicator(key: Key('score_loading')))
              : widget.error != null
                  ? Text(widget.error!,
                      key: const Key('score_error'),
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
                  : _content(context, widget.score!),
        ),
      );

  Widget _content(BuildContext context, PromptQualityScore score) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('GUPMAX SCORE', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${score.score} / 100',
                    key: const Key('score_value'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: score.score >= 75
                            ? AppColors.gold
                            : AppColors.deepBlue,
                        fontWeight: FontWeight.bold)),
                Text(score.ratingLabel,
                    key: const Key('score_rating'),
                    style: Theme.of(context).textTheme.titleMedium),
              ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: score.score / 100, key: const Key('score_progress')),
          TextButton(
              key: const Key('toggle_score_analysis'),
              onPressed: () => setState(() => expanded = !expanded),
              child: Text(expanded ? 'Ocultar análise' : 'Ver análise')),
          if (expanded) ...[
            ...score.criteria.map((criterion) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(criterion.label),
                trailing: Text('${criterion.score}/${criterion.maxScore}'),
                subtitle: Text(criterion.feedback))),
            if (score.strengths.isNotEmpty)
              _section('Pontos fortes', score.strengths,
                  key: const Key('score_strengths')),
            if (score.improvements.isNotEmpty)
              _section('O que pode melhorar', score.improvements,
                  key: const Key('score_improvements')),
            if (score.suggestions.isNotEmpty) ...[
              _section('Sugestões', score.suggestions,
                  key: const Key('score_suggestions')),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                  key: const Key('improve_prompt_from_score'),
                  onPressed: () =>
                      widget.onImprove(score.suggestions.join(' ')),
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Melhorar')),
            ],
          ],
        ],
      );

  static Widget _section(String title, List<String> values,
          {required Key key}) =>
      Container(
        key: key,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.paleBlue,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.deepBlue.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ...values.map((value) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $value'),
                )),
          ],
        ),
      );
}
