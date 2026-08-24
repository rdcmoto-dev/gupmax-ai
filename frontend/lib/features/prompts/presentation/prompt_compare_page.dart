import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/prompt_models.dart';
import '../prompt_providers.dart';
import 'prompt_scaffold.dart';

class PromptComparePage extends ConsumerWidget {
  const PromptComparePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(promptControllerProvider);
    return PromptScaffold(
      title: 'Comparar versões por IA',
      child: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          if (state.isComparing) {
            return const Center(
              child: CircularProgressIndicator(key: Key('comparison_loading')),
            );
          }
          if (state.comparisonError != null) {
            return Text(state.comparisonError!,
                key: const Key('comparison_page_error'));
          }
          if (state.comparisonItems.isEmpty) {
            return _EmptyComparison(onCreate: () => context.go('/prompts/new'));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Estas versões ainda não fazem parte do histórico. Copie qualquer '
                'uma ou salve somente as que quiser manter.',
                key: Key('comparison_preview_notice'),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 760;
                final width = desktop
                    ? (constraints.maxWidth - 16) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: state.comparisonItems
                      .map((preview) => SizedBox(
                            width: width,
                            child: _PreviewCard(preview: preview),
                          ))
                      .toList(),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.preview});
  final MultiTargetPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(promptControllerProvider);
    final saved = state.savedComparisons[preview.targetAi];
    return Card(
      key: Key('comparison_card_${preview.targetAi.value}'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(preview.targetAi.label,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                Chip(
                  key: Key('comparison_score_${preview.targetAi.value}'),
                  label: Text('${preview.score}/100 • ${preview.ratingLabel}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(minHeight: 220),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectionArea(child: Text(preview.content)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  key: Key('copy_comparison_${preview.targetAi.value}'),
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: preview.content));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text('${preview.targetAi.label} copiado.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copiar'),
                ),
                if (saved == null)
                  FilledButton.icon(
                    key: Key('save_comparison_${preview.targetAi.value}'),
                    onPressed: state.isSubmitting
                        ? null
                        : () => ref
                            .read(promptControllerProvider)
                            .saveComparison(preview),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Salvar versão'),
                  )
                else
                  FilledButton.icon(
                    key: Key('open_comparison_${preview.targetAi.value}'),
                    onPressed: () => context.go('/prompts/${saved.id}'),
                    icon: const Icon(Icons.check),
                    label: const Text('Versão salva'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyComparison extends StatelessWidget {
  const _EmptyComparison({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          children: [
            const Text('Nenhuma comparação disponível.'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: onCreate, child: const Text('Criar comparação')),
          ],
        ),
      );
}
