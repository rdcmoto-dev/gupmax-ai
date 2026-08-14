import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frontend não contém secrets de providers hardcoded', () {
    final patterns = <RegExp>[
      RegExp(r'sk_live_[A-Za-z0-9]{16,}'),
      RegExp(r'sk_test_[A-Za-z0-9]{16,}'),
      RegExp(r'whsec_[A-Za-z0-9]{16,}'),
      RegExp(r'APP_USR-[A-Za-z0-9_-]{16,}'),
      RegExp(r'TEST-[0-9]+-[A-Za-z0-9_-]{16,}'),
      RegExp(r'OPENAI_API_KEY\s*='),
    ];
    final sourceFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in sourceFiles) {
      final source = file.readAsStringSync();
      for (final pattern in patterns) {
        expect(pattern.hasMatch(source), isFalse,
            reason: 'Padrão sensível encontrado em ${file.path}');
      }
    }
  });
}
