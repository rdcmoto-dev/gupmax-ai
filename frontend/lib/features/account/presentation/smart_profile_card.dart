import 'package:flutter/material.dart';

import '../domain/smart_profile.dart';
import 'account_controller.dart';

class SmartProfileCard extends StatefulWidget {
  const SmartProfileCard({required this.controller, super.key});
  final AccountController controller;

  @override
  State<SmartProfileCard> createState() => _SmartProfileCardState();
}

class _SmartProfileCardState extends State<SmartProfileCard> {
  final fields = List.generate(8, (_) => TextEditingController());
  bool enabled = false;
  SmartProfile? loaded;

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  void sync(SmartProfile profile) {
    if (identical(loaded, profile)) return;
    loaded = profile;
    enabled = profile.isEnabled;
    final values = [
      profile.defaultLanguage,
      profile.defaultTone,
      profile.defaultAudience,
      profile.defaultChannel,
      profile.defaultOutputFormat,
      profile.businessContext,
      profile.defaultConstraints.join('\n'),
      profile.defaultInstructions.join('\n')
    ];
    for (var index = 0; index < fields.length; index++) {
      fields[index].text = values[index] ?? '';
    }
  }

  String? optional(int index) =>
      fields[index].text.trim().isEmpty ? null : fields[index].text.trim();
  List<String> lines(int index) => fields[index]
      .text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    sync(widget.controller.smartProfile);
    return Card(
      key: const Key('smart_profile_card'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Smart Profile', style: Theme.of(context).textTheme.titleLarge),
          const Text(
              'Preferências explícitas e reutilizáveis para novos prompts.'),
          const SizedBox(height: 12),
          Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
            child: SwitchListTile(
              key: const Key('smart_profile_enabled'),
              title: const Text('Usar minhas preferências em novos prompts'),
              subtitle: const Text(
                'Ative para aplicar estas preferências automaticamente.',
              ),
              value: enabled,
              onChanged: (value) => setState(() => enabled = value),
            ),
          ),
          LayoutBuilder(builder: (context, constraints) {
            final inputs = [
              _field(0, 'Idioma padrão'),
              _field(1, 'Tom padrão'),
              _field(2, 'Público recorrente'),
              _field(3, 'Canal/plataforma'),
              _field(4, 'Formato de resposta'),
            ];
            return constraints.maxWidth < 620
                ? Column(children: inputs)
                : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: inputs
                        .map((item) => SizedBox(
                            width: (constraints.maxWidth - 12) / 2,
                            child: item))
                        .toList());
          }),
          _field(5, 'Contexto do negócio/projeto', multiline: true),
          _field(6, 'Restrições padrão', multiline: true),
          _field(7, 'Orientações padrão', multiline: true),
          const SizedBox(height: 16),
          Wrap(spacing: 12, children: [
            FilledButton(
                key: const Key('save_smart_profile'),
                onPressed: widget.controller.isSavingSmartProfile
                    ? null
                    : () => widget.controller.saveSmartProfile(SmartProfile(
                        isEnabled: enabled,
                        defaultLanguage: optional(0),
                        defaultTone: optional(1),
                        defaultAudience: optional(2),
                        defaultChannel: optional(3),
                        defaultOutputFormat: optional(4),
                        businessContext: optional(5),
                        defaultConstraints: lines(6),
                        defaultInstructions: lines(7))),
                child: const Text('Salvar preferências')),
            OutlinedButton(
                key: const Key('delete_smart_profile'),
                onPressed: widget.controller.isSavingSmartProfile
                    ? null
                    : widget.controller.deleteSmartProfile,
                child: const Text('Limpar preferências')),
          ]),
        ]),
      ),
    );
  }

  Widget _field(int index, String label, {bool multiline = false}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
            key: Key('smart_profile_field_$index'),
            controller: fields[index],
            maxLength: multiline ? 4000 : 1000,
            minLines: multiline ? 2 : 1,
            maxLines: multiline ? 4 : 1,
            decoration: InputDecoration(labelText: label)),
      );
}
