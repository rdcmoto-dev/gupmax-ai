import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../prompts/presentation/prompt_scaffold.dart';
import '../../prompts/prompt_providers.dart';
import '../../prompts/domain/prompt_models.dart';
import '../domain/interview_models.dart';
import '../interview_providers.dart';

class InterviewPage extends ConsumerStatefulWidget {
  const InterviewPage({required this.interviewId, super.key});
  final String interviewId;

  @override
  ConsumerState<InterviewPage> createState() => _InterviewPageState();
}

class _InterviewPageState extends ConsumerState<InterviewPage> {
  final _text = TextEditingController();
  final _selected = <String>{};
  final _skipped = <String>{};
  bool? _booleanValue;
  String? _questionKey;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      final controller = ref.read(interviewControllerProvider);
      if (controller.session?.id != widget.interviewId) {
        controller.load(widget.interviewId);
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _syncQuestion(InterviewQuestion? question) {
    if (_questionKey == question?.key) return;
    _questionKey = question?.key;
    _text.clear();
    _selected.clear();
    _booleanValue = null;
  }

  Object? _answerValue(InterviewQuestion question) => switch (question.type) {
        InterviewQuestionType.text ||
        InterviewQuestionType.multiline =>
          _text.text.trim().isEmpty ? null : _text.text.trim(),
        InterviewQuestionType.singleChoice =>
          _selected.isEmpty ? null : _selected.first,
        InterviewQuestionType.multiChoice =>
          _selected.isEmpty ? null : _selected.toList(),
        InterviewQuestionType.boolean => _booleanValue,
      };

  InterviewQuestion? _nextQuestion(InterviewSession session) {
    final answered =
        session.answers.map((answer) => answer.questionKey).toSet();
    for (final question in session.questions) {
      if (!answered.contains(question.key) &&
          !_skipped.contains(question.key)) {
        return question;
      }
    }
    return null;
  }

  Future<void> _continue(InterviewQuestion question) async {
    final value = _answerValue(question);
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe uma resposta para continuar.')),
      );
      return;
    }
    await ref.read(interviewControllerProvider).answer(question.key, value);
  }

  Future<void> _generate() async {
    final interviews = ref.read(interviewControllerProvider);
    final promptInput = interviews.session?.status == InterviewStatus.completed
        ? interviews.session?.structuredPrompt
        : await interviews.complete();
    if (promptInput == null || !mounted) return;
    final result =
        await ref.read(promptControllerProvider).generate(promptInput);
    if (mounted && result != null) context.go('/prompts/${result.id}');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(interviewControllerProvider);
    final promptState = ref.watch(promptControllerProvider);
    final session =
        state.session?.id == widget.interviewId ? state.session : null;
    final question = session == null ? null : _nextQuestion(session);
    _syncQuestion(question);

    return PromptScaffold(
      title: 'Entrevista guiada',
      child: AnimatedBuilder(
        animation: Listenable.merge([state, promptState]),
        builder: (context, _) {
          if (state.isLoading && session == null) {
            return const Center(
              child: CircularProgressIndicator(key: Key('interview_loading')),
            );
          }
          if (session == null) {
            if (state.isExpired) {
              return _InterviewMessage(
                key: const Key('interview_expired'),
                icon: Icons.schedule,
                title: 'Esta entrevista expirou.',
                description: 'Inicie uma nova criação para continuar.',
                actionLabel: 'Criar novo prompt',
                onPressed: () => context.go('/prompts/new'),
              );
            }
            return _InterviewMessage(
              icon: Icons.error_outline,
              title: state.error ?? 'Entrevista não encontrada.',
              actionLabel: 'Tentar novamente',
              onPressed: () => state.load(widget.interviewId),
            );
          }
          if (session.status == InterviewStatus.expired) {
            return _InterviewMessage(
              key: const Key('interview_expired'),
              icon: Icons.schedule,
              title: 'Esta entrevista expirou.',
              description: 'Inicie uma nova criação para continuar.',
              actionLabel: 'Criar novo prompt',
              onPressed: () => context.go('/prompts/new'),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InterviewHeader(session: session),
              const SizedBox(height: 20),
              if (session.status == InterviewStatus.active && question != null)
                _QuestionCard(
                  question: question,
                  textController: _text,
                  selected: _selected,
                  booleanValue: _booleanValue,
                  enabled: !state.isSubmitting,
                  onSelectionChanged: (values) => setState(() => _selected
                    ..clear()
                    ..addAll(values)),
                  onBooleanChanged: (value) =>
                      setState(() => _booleanValue = value),
                  onSkip: question.required
                      ? null
                      : () => setState(() => _skipped.add(question.key)),
                  onContinue: () => _continue(question),
                )
              else
                _ReadyCard(
                  completed: session.status == InterviewStatus.completed,
                  isSubmitting: state.isSubmitting || promptState.isSubmitting,
                  onGenerate: _generate,
                ),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.error!,
                  key: const Key('interview_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (promptState.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  promptState.error!,
                  key: const Key('interview_generate_error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InterviewHeader extends StatelessWidget {
  const _InterviewHeader({required this.session});
  final InterviewSession session;

  @override
  Widget build(BuildContext context) {
    final progress = session.progress.total == 0
        ? 1.0
        : session.progress.answered / session.progress.total;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Vamos melhorar seu prompt',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('${_modeLabel(session.mode)} • ${session.category.label}'),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              key: const Key('interview_progress'),
              value: progress,
            ),
            const SizedBox(height: 8),
            Text(
              '${session.progress.answered} de ${session.progress.total} respondidas',
              key: const Key('interview_progress_text'),
            ),
          ],
        ),
      ),
    );
  }

  static String _modeLabel(PromptMode mode) => switch (mode) {
        PromptMode.pro => 'GUPMAX Pro',
        PromptMode.expert => 'GUPMAX Expert',
        PromptMode.basic => 'GUPMAX Rápido',
      };
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.textController,
    required this.selected,
    required this.booleanValue,
    required this.enabled,
    required this.onSelectionChanged,
    required this.onBooleanChanged,
    required this.onSkip,
    required this.onContinue,
  });

  final InterviewQuestion question;
  final TextEditingController textController;
  final Set<String> selected;
  final bool? booleanValue;
  final bool enabled;
  final ValueChanged<Set<String>> onSelectionChanged;
  final ValueChanged<bool> onBooleanChanged;
  final VoidCallback? onSkip;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Card(
        key: Key('question_${question.key}'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(question.required ? 'Obrigatória' : 'Opcional',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Text(question.text,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              _control(),
              const SizedBox(height: 20),
              if (onSkip != null) ...[
                OutlinedButton(
                  key: const Key('interview_skip'),
                  onPressed: enabled ? onSkip : null,
                  child: const Text('Pular pergunta opcional'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const Key('interview_continue'),
                onPressed: enabled ? onContinue : null,
                child: enabled
                    ? const Text('Continuar')
                    : const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            ],
          ),
        ),
      );

  Widget _control() => switch (question.type) {
        InterviewQuestionType.text => TextField(
            key: const Key('answer_text'),
            controller: textController,
            enabled: enabled,
            decoration: const InputDecoration(labelText: 'Sua resposta'),
          ),
        InterviewQuestionType.multiline => TextField(
            key: const Key('answer_multiline'),
            controller: textController,
            enabled: enabled,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Sua resposta'),
          ),
        InterviewQuestionType.singleChoice => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: question.options
                .map((option) => ChoiceChip(
                      key: Key('choice_$option'),
                      label: Text(option),
                      selected: selected.contains(option),
                      onSelected:
                          enabled ? (_) => onSelectionChanged({option}) : null,
                    ))
                .toList(),
          ),
        InterviewQuestionType.multiChoice => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: question.options
                .map((option) => FilterChip(
                      key: Key('choice_$option'),
                      label: Text(option),
                      selected: selected.contains(option),
                      onSelected: enabled
                          ? (value) {
                              final next = {...selected};
                              value ? next.add(option) : next.remove(option);
                              onSelectionChanged(next);
                            }
                          : null,
                    ))
                .toList(),
          ),
        InterviewQuestionType.boolean => SegmentedButton<bool>(
            key: const Key('answer_boolean'),
            segments: const [
              ButtonSegment(value: true, label: Text('Sim')),
              ButtonSegment(value: false, label: Text('Não')),
            ],
            selected: booleanValue == null ? {} : {booleanValue!},
            emptySelectionAllowed: true,
            onSelectionChanged: enabled
                ? (values) {
                    if (values.isNotEmpty) onBooleanChanged(values.first);
                  }
                : null,
          ),
      };
}

class _ReadyCard extends StatelessWidget {
  const _ReadyCard({
    required this.completed,
    required this.isSubmitting,
    required this.onGenerate,
  });
  final bool completed;
  final bool isSubmitting;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) => Card(
        key: Key(completed ? 'interview_completed' : 'interview_ready'),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Icon(Icons.check_circle_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                completed
                    ? 'Entrevista concluída'
                    : 'Pronto para criar seu prompt',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('interview_generate'),
                onPressed: isSubmitting ? null : onGenerate,
                icon: isSubmitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: const Text('Gerar meu prompt'),
              ),
            ],
          ),
        ),
      );
}

class _InterviewMessage extends StatelessWidget {
  const _InterviewMessage({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onPressed,
    this.description,
    super.key,
  });
  final IconData icon;
  final String title;
  final String? description;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(description!),
              ],
              const SizedBox(height: 20),
              FilledButton(onPressed: onPressed, child: Text(actionLabel)),
            ],
          ),
        ),
      );
}
