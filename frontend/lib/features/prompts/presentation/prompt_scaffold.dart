import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PromptScaffold extends StatelessWidget {
  const PromptScaffold({required this.title, required this.child, super.key});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
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
