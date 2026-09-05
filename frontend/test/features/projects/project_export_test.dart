import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/projects/project_export.dart';

void main() {
  test('normaliza filename com acentos e caracteres de caminho', () {
    expect(
      safeExportFilename(null,
          projectName: 'Lançamento / Pizzaria Donatello',
          format: ProjectExportFormat.markdown),
      'lancamento-pizzaria-donatello.md',
    );
    expect(
      safeExportFilename('attachment; filename="../../segredo.json"',
          projectName: 'Projeto', format: ProjectExportFormat.json),
      'segredo.json',
    );
  });

  test('preserva filename seguro enviado pelo servidor', () {
    expect(
      safeExportFilename(
        "attachment; filename*=UTF-8''projeto-final%20v1.json",
        projectName: 'Projeto',
        format: ProjectExportFormat.json,
      ),
      'projeto-final-v1.json',
    );
  });
}
