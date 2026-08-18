import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/prompt_models.dart';
import '../prompt_providers.dart';

class PromptRefinementPanel extends ConsumerStatefulWidget {
  const PromptRefinementPanel(
      {required this.prompt, this.initialInstruction, super.key});
  final PromptRecord prompt;
  final String? initialInstruction;

  @override
  ConsumerState<PromptRefinementPanel> createState() =>
      _PromptRefinementPanelState();
}

class _PromptRefinementPanelState extends ConsumerState<PromptRefinementPanel> {
  final _instruction = TextEditingController();
  bool _expanded = false;
  bool _withAi = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialInstruction != null) {
      _instruction.text = widget.initialInstruction!;
      _expanded = true;
    }
    if (kDebugMode) {
      final controller = ref.read(promptControllerProvider);
      debugPrint(
        '[prompt_refinement_ui] event=init_state '
        'controller=${identityHashCode(controller)} prompt_id=${widget.prompt.id} '
        'with_ai=$_withAi expanded=$_expanded',
      );
    }
  }

  @override
  void didUpdateWidget(covariant PromptRefinementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kDebugMode) {
      final controller = ref.read(promptControllerProvider);
      debugPrint(
        '[prompt_refinement_ui] event=did_update_widget '
        'controller=${identityHashCode(controller)} prompt_id=${widget.prompt.id} '
        'with_ai=$_withAi expanded=$_expanded',
      );
    }
  }

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  PromptRefineInput get _input => PromptRefineInput(
        instruction: _instruction.text.trim(),
        optimizeWithAi: _withAi,
      );

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Prompt copiado.')));
    }
  }

  Future<void> _submit() async {
    if (_instruction.text.trim().length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe como deseja refinar.')));
      return;
    }
    final result =
        await ref.read(promptControllerProvider).refine(widget.prompt, _input);
    if (result != null && mounted) {
      setState(() {
        _expanded = false;
        _instruction.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(promptControllerProvider);
    final current = state.selected ?? widget.prompt;
    if (kDebugMode && _expanded) {
      debugPrint(
        '[prompt_refinement_ui] controller=${identityHashCode(state)} '
        'error=${state.error ?? 'null'} '
        'refinement_error=${state.refinementError ?? 'null'} '
        'estimate_error=${state.refinementEstimateError ?? 'null'} '
        'selected_id=${state.selected?.id ?? 'null'} '
        'prompt_id=${widget.prompt.id} with_ai=$_withAi '
        'estimate=${state.estimate == null ? 'null' : 'present'} '
        'expanded=$_expanded',
      );
    }
    PromptRecord? previous;
    for (final version in state.versions) {
      if (version.versionNumber == current.versionNumber - 1) {
        previous = version;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('refine_prompt'),
            onPressed: state.isSubmitting
                ? null
                : () {
                    final expanding = !_expanded;
                    if (expanding) {
                      final controller = ref.read(promptControllerProvider);
                      if (kDebugMode) {
                        debugPrint(
                          '[prompt_refinement] action=open '
                          'controller=${identityHashCode(controller)} '
                          'before=${controller.refinementError ?? 'null'}',
                        );
                      }
                      controller.beginRefinement();
                    }
                    setState(() => _expanded = expanding);
                  },
            icon: const Icon(Icons.auto_fix_high, color: AppColors.gold),
            label: const Text('Refinar prompt'),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
          Card(
            key: const Key('refinement_form'),
            color: AppColors.paleBlue,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Criar nova versão',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('refinement_instruction'),
                    controller: _instruction,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Como deseja refinar?',
                      hintText: 'Ex.: Deixe mais persuasivo e mantenha curto.',
                    ),
                  ),
                  SwitchListTile(
                    key: const Key('refine_with_ai'),
                    contentPadding: EdgeInsets.zero,
                    secondary:
                        const Icon(Icons.psychology, color: AppColors.gold),
                    title: const Text('Refinar com IA'),
                    value: _withAi,
                    onChanged: state.isSubmitting
                        ? null
                        : (value) async {
                            setState(() => _withAi = value);
                            if (value && _instruction.text.trim().length >= 3) {
                              await ref
                                  .read(promptControllerProvider)
                                  .estimateRefinement(current, _input);
                            } else {
                              ref
                                  .read(promptControllerProvider)
                                  .clearEstimate();
                            }
                          },
                  ),
                  if (_withAi && state.isEstimating)
                    const LinearProgressIndicator(
                        key: Key('refinement_estimate_loading')),
                  if (_withAi && state.estimate != null)
                    ListTile(
                      key: const Key('refinement_estimate'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.toll_outlined),
                      title: Text(
                          'Estimativa: ${state.estimate!.estimatedCredits} créditos'),
                      subtitle: Text(
                          'Saldo: ${state.estimate!.availableCredits} créditos'),
                      trailing: state.estimate!.canExecute
                          ? null
                          : TextButton(
                              onPressed: () => context.go('/credits'),
                              child: const Text('Créditos e planos'),
                            ),
                    ),
                  if (_withAi && state.refinementEstimateError != null)
                    Text(state.refinementEstimateError!,
                        key: const Key('refinement_estimate_error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (state.refinementError != null)
                    Text(state.refinementError!,
                        key: const Key('refinement_error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('submit_refinement'),
                    onPressed: state.isSubmitting ||
                            (_withAi &&
                                state.estimate != null &&
                                !state.estimate!.canExecute)
                        ? null
                        : _submit,
                    icon: state.isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_fix_high),
                    label: Text(state.isSubmitting
                        ? 'Criando nova versão...'
                        : 'Criar nova versão'),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (state.versions.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Histórico de versões',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            key: const Key('prompt_versions'),
            child: Column(
              children: state.versions
                  .map((version) => ListTile(
                        title: Text(
                            'Versão ${version.versionNumber}${version.versionNumber == 1 ? ' • Original' : ''}'),
                        subtitle: Text(version.refinementInstruction ??
                            '${version.mode.name.toUpperCase()} • ${version.category.label} • ${_date(version.createdAt)}'),
                        leading: Icon(
                          version.status == 'optimized'
                              ? Icons.psychology
                              : Icons.history,
                          color: version.status == 'optimized'
                              ? AppColors.gold
                              : AppColors.deepBlue,
                        ),
                        trailing: Wrap(children: [
                          if (state.scores[version.id] case final score?)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Chip(
                                key: Key('version_score_${version.id}'),
                                label: Text('Score ${score.score}'),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Copiar versão',
                            onPressed: () => _copy(version.generatedPrompt),
                            icon: const Icon(Icons.copy),
                          ),
                          TextButton(
                            onPressed: () => ref
                                .read(promptControllerProvider)
                                .selectVersion(version),
                            child: const Text('Usar esta'),
                          ),
                        ]),
                      ))
                  .toList(),
            ),
          ),
        ],
        if (state.versionsError != null) ...[
          const SizedBox(height: 12),
          Text(
            state.versionsError!,
            key: const Key('prompt_versions_error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (previous case final previousVersion?) ...[
          const SizedBox(height: 24),
          Text('Comparar versões',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final cards = [
              _ComparisonCard(
                  title: 'VERSÃO ${previousVersion.versionNumber} — ANTERIOR',
                  prompt: previousVersion,
                  score: state.scores[previousVersion.id],
                  onCopy: _copy),
              _ComparisonCard(
                  title: 'VERSÃO ${current.versionNumber} — NOVA',
                  prompt: current,
                  score: state.scores[current.id],
                  previousScore: state.scores[previousVersion.id],
                  onCopy: _copy),
            ];
            return constraints.maxWidth < 720
                ? Column(children: cards)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:
                        cards.map((card) => Expanded(child: card)).toList(),
                  );
          }),
        ],
      ],
    );
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard(
      {required this.title,
      required this.prompt,
      required this.onCopy,
      this.score,
      this.previousScore});
  final String title;
  final PromptRecord prompt;
  final PromptQualityScore? score;
  final PromptQualityScore? previousScore;
  final Future<void> Function(String) onCopy;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              if (score != null)
                Text(
                  'Score ${score!.score}${previousScore == null ? '' : ' (${score!.score - previousScore!.score >= 0 ? '+' : ''}${score!.score - previousScore!.score} pontos)'}',
                  key: Key('comparison_score_${prompt.id}'),
                ),
              const SizedBox(height: 12),
              SelectableText(prompt.generatedPrompt),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => onCopy(prompt.generatedPrompt),
                icon: const Icon(Icons.copy),
                label: const Text('Copiar versão'),
              ),
            ],
          ),
        ),
      );
}
