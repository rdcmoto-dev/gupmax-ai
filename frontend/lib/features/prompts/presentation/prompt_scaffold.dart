import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PromptScaffold extends StatelessWidget {
  const PromptScaffold({required this.title, required this.child, super.key});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: compact
            ? [
                PopupMenuButton<String>(
                  tooltip: 'Navegação de prompts',
                  onSelected: context.go,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: '/prompts/new',
                      child: ListTile(
                        leading: Icon(Icons.auto_awesome),
                        title: Text('Criar prompt'),
                      ),
                    ),
                    PopupMenuItem(
                      value: '/prompts',
                      child: ListTile(
                        leading: Icon(Icons.history),
                        title: Text('Meus prompts'),
                      ),
                    ),
                  ],
                ),
              ]
            : [
                TextButton.icon(
                  onPressed: () => context.go('/prompts/new'),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Criar prompt'),
                ),
                TextButton.icon(
                  onPressed: () => context.go('/prompts'),
                  icon: const Icon(Icons.history),
                  label: const Text('Meus prompts'),
                ),
                const SizedBox(width: 12),
              ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
