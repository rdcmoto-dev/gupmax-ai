import 'package:flutter/material.dart';

import '../../../core/widgets/app_page_app_bar.dart';

class PromptScaffold extends StatelessWidget {
  const PromptScaffold({required this.title, required this.child, super.key});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppPageAppBar(title: title),
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
