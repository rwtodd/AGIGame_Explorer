import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/domain/logic_script.dart';
import 'package:flutter_agigame/loader/resource_loader.dart';

/// Expands Sierra AGI message placeholders (`%v`, `%w`, `%s`, `%m`, `%g`, `%o`)
/// and backslash escapes.
class AgiMessageFormatter {
  const AgiMessageFormatter._();

  static String format(
    String text, {
    required AgiMemory memory,
    AgiResourceLoader? loader,
    List<String> inputWords = const [],
    AgiLogicScript? currentScript,
  }) {
    if (!text.contains('%') && !text.contains('\\')) return text;

    String expand(String source) => format(
          source,
          memory: memory,
          loader: loader,
          inputWords: inputWords,
          currentScript: currentScript,
        );

    final sb = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      if (ch == '\\') {
        i++;
        if (i < text.length) {
          sb.write(text[i]);
          i++;
        }
      } else if (ch == '%' && i + 1 < text.length) {
        i++;
        final type = text[i];
        i++;
        if (type == 'v' ||
            type == 'w' ||
            type == 's' ||
            type == 'm' ||
            type == 'g' ||
            type == 'o' ||
            type == '0') {
          final numBuf = StringBuffer();
          while (i < text.length &&
              text.codeUnitAt(i) >= 48 &&
              text.codeUnitAt(i) <= 57) {
            numBuf.write(text[i]);
            i++;
          }
          final num = int.tryParse(numBuf.toString()) ?? 0;
          int? pad;
          if (type == 'v' && i < text.length && text[i] == '|') {
            i++;
            final padBuf = StringBuffer();
            while (i < text.length &&
                text.codeUnitAt(i) >= 48 &&
                text.codeUnitAt(i) <= 57) {
              padBuf.write(text[i]);
              i++;
            }
            pad = int.tryParse(padBuf.toString());
          }

          switch (type) {
            case 'v':
              final val = memory.getVar(num);
              var str = val.toString();
              if (pad != null && pad > str.length) {
                str = str.padLeft(pad, '0');
              }
              sb.write(str);
              break;

            case 'w':
              if (num >= 1 && num <= inputWords.length) {
                sb.write(inputWords[num - 1]);
              }
              break;

            case 's':
              sb.write(expand(memory.getString(num)));
              break;

            case 'm':
              sb.write(expand(currentScript?.getMessage(num) ?? ''));
              break;

            case 'g':
              final logic0 = loader?.loadLogic(0);
              sb.write(expand(logic0?.getMessage(num) ?? ''));
              break;

            case 'o':
            case '0':
              final objIdx = memory.getVar(num);
              if (loader != null &&
                  objIdx >= 0 &&
                  objIdx < loader.initialObjects.length) {
                sb.write(expand(loader.initialObjects[objIdx].name));
              }
              break;
          }
        } else {
          sb.write('%');
          sb.write(type);
        }
      } else {
        sb.write(ch);
        i++;
      }
    }
    return sb.toString();
  }
}
