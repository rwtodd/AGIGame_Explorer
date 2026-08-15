import 'package:flutter/material.dart';
import 'package:flutter_agigame/domain/engine_memory.dart';
import 'package:flutter_agigame/logic/disassembler/disassembly_formatter.dart';
import 'package:flutter_agigame/logic/disassembler/logic_instruction.dart';

/// Semantic token types for syntax-highlighting AGI disassembly.
enum DisassemblyTokenType {
  address,
  keyword,
  opcode,
  variable,
  flag,
  object,
  inventory,
  message,
  stringVar,
  word,
  controller,
  number,
  stringLiteral,
  comment,
  punctuation,
  whitespace,
}

/// A syntax token in disassembled bytecode.
class DisassemblyToken {
  final DisassemblyTokenType type;
  final String text;

  const DisassemblyToken(this.type, this.text);

  @override
  String toString() => '[$type: "$text"]';
}

/// Tokenizer and syntax highlighter for AGI logic disassemblies.
class DisassemblyHighlighter {
  const DisassemblyHighlighter._();

  /// Tokenizes a disassembled instruction AST into a list of syntax tokens.
  static List<DisassemblyToken> tokenize(
    LogicInstruction ast, {
    DisassemblyContext context = const DisassemblyContext(),
    int baseAddress = 0,
    String indent = '',
  }) {
    final tokens = <DisassemblyToken>[];
    _tokenizeNode(ast, tokens, baseAddress, indent, context);
    return tokens;
  }

  static void _tokenizeNode(
    LogicInstruction node,
    List<DisassemblyToken> tokens,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    switch (node) {
      case CompoundInstruction compound:
        var curAddr = baseAddress;
        for (final child in compound.instructions) {
          _tokenizeNode(child, tokens, curAddr, indent, c);
          curAddr += child.length;
        }

      case BasicInstruction basic:
        _tokenizeBasic(basic, tokens, baseAddress, indent, c);

      case SaidInstruction said:
        _tokenizeSaid(said, tokens, baseAddress, indent, c);

      case IfInstruction ifIns:
        _tokenizeIf(ifIns, tokens, baseAddress, indent, c);

      case UnlessGotoInstruction unlessIns:
        _tokenizeUnless(unlessIns, tokens, baseAddress, indent, c);

      case GotoInstruction gotoIns:
        _tokenizeGoto(gotoIns, tokens, baseAddress, indent);

      case OrInstruction orIns:
        _tokenizeOr(orIns, tokens, baseAddress, indent, c);

      case NotInstruction notIns:
        _tokenizeNot(notIns, tokens, baseAddress, indent, c);
    }
  }

  static void _tokenizeBasic(
    BasicInstruction basic,
    List<DisassemblyToken> tokens,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    final addrHex = baseAddress.toRadixString(16).padLeft(4, '0').toUpperCase();
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, addrHex));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ':'));
    tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, ' $indent'));
    tokens.add(DisassemblyToken(DisassemblyTokenType.opcode, basic.name));

    final extraComments = <String>[];
    final extraIndent = indent.isEmpty ? '' : ' ' * indent.length;

    if (basic.args.isNotEmpty) {
      tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '('));
      for (var i = 0; i < basic.args.length; i++) {
        if (i > 0) {
          tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ','));
          tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, ' '));
        }
        final argType = basic.getArgType(i);
        final val = basic.args[i];

        final tokenType = switch (argType) {
          AgiArgType.variable => DisassemblyTokenType.variable,
          AgiArgType.flg => DisassemblyTokenType.flag,
          AgiArgType.msg => DisassemblyTokenType.message,
          AgiArgType.obj => DisassemblyTokenType.object,
          AgiArgType.inv => DisassemblyTokenType.inventory,
          AgiArgType.wrd => DisassemblyTokenType.word,
          AgiArgType.ctl => DisassemblyTokenType.controller,
          AgiArgType.str => DisassemblyTokenType.stringVar,
          _ => DisassemblyTokenType.number,
        };

        tokens.add(DisassemblyToken(tokenType, '${argType.prefix}$val'));

        // Inline annotations
        switch (argType) {
          case AgiArgType.msg:
            final msgText = c.script?.getMessage(val);
            if (msgText != null && msgText.isNotEmpty) {
              extraComments.add('      $extraIndent[ MSG %m$val: "$msgText"');
            }
          case AgiArgType.flg:
            final flgDesc = c.memory?.getFlagDisplayName(val) ?? AgiMemory.defaultFlagDescriptions[val];
            if (flgDesc != null) {
              extraComments.add('      $extraIndent[ FLAG %f$val: $flgDesc');
            }
          case AgiArgType.variable:
            final varDesc = c.memory?.getVarDisplayName(val) ?? AgiMemory.defaultVarDescriptions[val];
            if (varDesc != null) {
              extraComments.add('      $extraIndent[ VAR %v$val: $varDesc');
            }
          case AgiArgType.inv:
            if (c.objects != null && val < c.objects!.length) {
              extraComments.add('      $extraIndent[ INVENTORY %i$val: "${c.objects![val].name}"');
            }
          default:
            break;
        }
      }
      tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ')'));
    }
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));

    for (final comment in extraComments) {
      tokens.add(DisassemblyToken(DisassemblyTokenType.comment, comment));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));
    }
  }

  static void _tokenizeSaid(
    SaidInstruction said,
    List<DisassemblyToken> tokens,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    final addrHex = baseAddress.toRadixString(16).padLeft(4, '0').toUpperCase();
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, addrHex));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ':'));
    tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, ' $indent'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.opcode, 'said'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '('));

    final extraComments = <String>[];
    final extraIndent = indent.isEmpty ? '' : ' ' * indent.length;

    for (var i = 0; i < said.wordGroupIds.length; i++) {
      if (i > 0) {
        tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ','));
        tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, ' '));
      }
      final wordId = said.wordGroupIds[i];
      tokens.add(DisassemblyToken(DisassemblyTokenType.word, '%w$wordId'));

      if (c.dictionary != null) {
        final words = c.dictionary!.idToWords(wordId);
        if (words.isNotEmpty) {
          final wordList = words.map((w) => '<$w>').join(' ');
          extraComments.add('      $extraIndent[ WORD %w$wordId: $wordList');
        }
      }
    }
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ')'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));

    for (final comment in extraComments) {
      tokens.add(DisassemblyToken(DisassemblyTokenType.comment, comment));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));
    }
  }

  static void _tokenizeIf(
    IfInstruction ifIns,
    List<DisassemblyToken> tokens,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    var cur = baseAddress;
    final addrHex = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, addrHex));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ':'));
    tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, ' $indent'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.keyword, 'IF-AND'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, ' '));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '('));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));

    cur += 1;
    final childIndent = '$indent    ';
    _tokenizeNode(ifIns.condition, tokens, cur, childIndent, c);
    cur += ifIns.condition.length;

    final closeHex = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, closeHex));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ':'));
    tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, ' $indent'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ') {'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));
    cur += 3;

    _tokenizeNode(ifIns.thenBlock, tokens, cur, childIndent, c);
    cur += ifIns.thenBlock.length;

    if (ifIns.elseBlock != null) {
      final elseHex = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
      tokens.add(DisassemblyToken(DisassemblyTokenType.address, elseHex));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ':'));
      tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, ' $indent'));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '} '));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.keyword, 'else'));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, ' '));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '{'));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));
      cur += 3;

      _tokenizeNode(ifIns.elseBlock!, tokens, cur, childIndent, c);
      tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, '      $indent'));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '}'));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));
    } else {
      tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, '      $indent'));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '}'));
      tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));
    }
  }

  static void _tokenizeUnless(
    UnlessGotoInstruction unlessIns,
    List<DisassemblyToken> tokens,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    var cur = baseAddress;
    final addrHex = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, addrHex));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ':'));
    tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, ' $indent'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.keyword, 'UNLESS'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, ' '));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '('));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));

    cur += 1;
    final childIndent = '$indent    ';
    _tokenizeNode(unlessIns.condition, tokens, cur, childIndent, c);
    cur += unlessIns.condition.length;

    final targetHex = unlessIns.targetAddress.toRadixString(16).padLeft(4, '0').toUpperCase();
    final jumpHex = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, jumpHex));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ':'));
    tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, ' $indent'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ') '));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.keyword, 'GOTO'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '('));
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, '0x$targetHex'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ')'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));
  }

  static void _tokenizeGoto(
    GotoInstruction gotoIns,
    List<DisassemblyToken> tokens,
    int baseAddress,
    String indent,
  ) {
    final addrHex = baseAddress.toRadixString(16).padLeft(4, '0').toUpperCase();
    final targetHex = gotoIns.targetAddress.toRadixString(16).padLeft(4, '0').toUpperCase();
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, addrHex));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ':'));
    tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, ' $indent'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.keyword, 'GOTO'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '('));
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, '0x$targetHex'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ')'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));
  }

  static void _tokenizeOr(
    OrInstruction orIns,
    List<DisassemblyToken> tokens,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    var cur = baseAddress;
    final addrHex = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, addrHex));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ':'));
    tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, ' $indent'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.keyword, 'OR'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, ' '));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, '('));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));

    cur += 1;
    _tokenizeNode(orIns.condition, tokens, cur, '$indent    ', c);
    cur += orIns.condition.length;

    final closeHex = cur.toRadixString(16).padLeft(4, '0').toUpperCase();
    tokens.add(DisassemblyToken(DisassemblyTokenType.address, closeHex));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ':'));
    tokens.add(DisassemblyToken(DisassemblyTokenType.whitespace, ' $indent'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.punctuation, ')'));
    tokens.add(const DisassemblyToken(DisassemblyTokenType.whitespace, '\n'));
  }

  static void _tokenizeNot(
    NotInstruction notIns,
    List<DisassemblyToken> tokens,
    int baseAddress,
    String indent,
    DisassemblyContext c,
  ) {
    final notIndent = '${indent}NOT ';
    _tokenizeNode(notIns.inner, tokens, baseAddress + 1, notIndent, c);
  }

  /// Converts a token list into ANSI colored text for terminal/console output.
  static String toAnsiString(List<DisassemblyToken> tokens) {
    final sb = StringBuffer();
    for (final token in tokens) {
      final code = switch (token.type) {
        DisassemblyTokenType.address => '\x1B[90m', // Dark Grey
        DisassemblyTokenType.keyword => '\x1B[95m\x1B[1m', // Magenta Bold
        DisassemblyTokenType.opcode => '\x1B[94m', // Blue
        DisassemblyTokenType.variable => '\x1B[93m', // Yellow
        DisassemblyTokenType.flag => '\x1B[92m', // Green
        DisassemblyTokenType.message => '\x1B[96m', // Cyan
        DisassemblyTokenType.object => '\x1B[33m', // Orange / Dark Yellow
        DisassemblyTokenType.inventory => '\x1B[35m', // Purple
        DisassemblyTokenType.word => '\x1B[36m', // Cyan
        DisassemblyTokenType.controller => '\x1B[32m', // Light Green
        DisassemblyTokenType.number => '\x1B[91m', // Red / Coral
        DisassemblyTokenType.stringLiteral => '\x1B[32m', // Green
        DisassemblyTokenType.comment => '\x1B[38;5;244m\x1B[3m', // Dim / Italic Gray
        DisassemblyTokenType.punctuation => '\x1B[37m', // White
        DisassemblyTokenType.whitespace => '',
        DisassemblyTokenType.stringVar => '\x1B[96m',
      };
      if (code.isEmpty) {
        sb.write(token.text);
      } else {
        sb.write('$code${token.text}\x1B[0m');
      }
    }
    return sb.toString();
  }

  /// Default color palette for Flutter [TextSpan] workbench display.
  static const Map<DisassemblyTokenType, Color> defaultWorkbenchColors = {
    DisassemblyTokenType.address: Color(0xFF757575),
    DisassemblyTokenType.keyword: Color(0xFFFF79C6),
    DisassemblyTokenType.opcode: Color(0xFF8BE9FD),
    DisassemblyTokenType.variable: Color(0xFFF1FA8C),
    DisassemblyTokenType.flag: Color(0xFF50FA7B),
    DisassemblyTokenType.message: Color(0xFF80D8FF),
    DisassemblyTokenType.object: Color(0xFFFFB86C),
    DisassemblyTokenType.inventory: Color(0xFFFF79C6),
    DisassemblyTokenType.word: Color(0xFFA4FFFF),
    DisassemblyTokenType.controller: Color(0xFF69F0AE),
    DisassemblyTokenType.number: Color(0xFFFF5555),
    DisassemblyTokenType.stringLiteral: Color(0xFFF1FA8C),
    DisassemblyTokenType.comment: Color(0xFF6272A4),
    DisassemblyTokenType.punctuation: Color(0xFFF8F8F2),
    DisassemblyTokenType.whitespace: Color(0xFFF8F8F2),
    DisassemblyTokenType.stringVar: Color(0xFF80D8FF),
  };

  /// Converts a token list into Flutter [TextSpan]s for UI rendering in workbench.
  static List<TextSpan> toTextSpans(
    List<DisassemblyToken> tokens, {
    Map<DisassemblyTokenType, Color>? colorMap,
    double fontSize = 13.0,
    String fontFamily = 'Courier',
  }) {
    final colors = colorMap ?? defaultWorkbenchColors;
    return tokens.map((token) {
      final color = colors[token.type] ?? const Color(0xFFF8F8F2);
      final isItalic = token.type == DisassemblyTokenType.comment;
      final isBold = token.type == DisassemblyTokenType.keyword;

      return TextSpan(
        text: token.text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: fontFamily,
          fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      );
    }).toList();
  }
}
