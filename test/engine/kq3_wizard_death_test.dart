import 'dart:io';
import 'package:flutter_agigame/domain/dictionary.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';
import 'package:flutter_agigame/logic/disassembler/disassembly_formatter.dart';
import 'package:test/test.dart';

void main() {
  test('Disassemble Logic 2 in KQ3', () {
    final kq3Dir = Directory('reference_games/kings-quest-3');
    if (!kq3Dir.existsSync()) return;

    final loader = AgiResourceLoader.fromDirectorySync('reference_games/kings-quest-3');
    final dict = loader.dictionary;

    final logic2 = loader.loadLogic(2);
    final formatter = DisassemblyFormatter(
      context: DisassemblyContext(
        script: logic2,
        dictionary: dict,
        objects: loader.initialObjects,
      ),
    );
    final code = formatter.formatScript(logic2);
    final scratchDir = Directory('scratch');
    if (!scratchDir.existsSync()) scratchDir.createSync();
    File('scratch/logic2_disasm.txt').writeAsStringSync(code);
    print('Wrote logic 2 to scratch/logic2_disasm.txt');
  });
}
