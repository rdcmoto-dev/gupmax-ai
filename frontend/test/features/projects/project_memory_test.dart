import 'package:flutter_test/flutter_test.dart';
import 'package:gupmax_ai/features/projects/project_memory.dart';

void main() {
  test('memoria vazia e formato legado continuam compativeis', () {
    expect(ProjectMemory.parse(null), isEmpty);
    final parsed = ProjectMemory.parse('Pizzaria com delivery');
    expect(parsed.single.label, 'Informação');
    expect(parsed.single.value, 'Pizzaria com delivery');
  });

  test('serializa e reconstroi informacoes estruturadas', () {
    final value = ProjectMemory.serialize(const [
      ProjectMemoryEntry(label: 'Público', value: 'Famílias da região'),
      ProjectMemoryEntry(label: 'Canal', value: 'Instagram'),
    ]);

    expect(value, 'Público: Famílias da região\nCanal: Instagram');
    final parsed = ProjectMemory.parse(value);
    expect(parsed.map((entry) => entry.label), ['Público', 'Canal']);
    expect(parsed.map((entry) => entry.value),
        ['Famílias da região', 'Instagram']);
  });

  test('ignora pares vazios e aplica limite de entradas', () {
    final entries = List.generate(
      12,
      (index) => ProjectMemoryEntry(label: 'Campo $index', value: 'Valor'),
    )..add(const ProjectMemoryEntry(label: '', value: 'ignorar'));

    final parsed = ProjectMemory.parse(ProjectMemory.serialize(entries));
    expect(parsed, hasLength(ProjectMemory.maxEntries));
  });

  test('rejeita memoria serializada acima de 4000 caracteres', () {
    expect(
      () => ProjectMemory.serialize([
        ProjectMemoryEntry(label: 'Contexto', value: 'x' * 3995),
      ]),
      throwsFormatException,
    );
  });
}
