// Syntax tokenizer and highlighter for SCI disassembly and decompiled script views.

import 'package:flutter/material.dart';
import 'package:flutter_agigame/ui/core/theme.dart';

/// Semantic token types for syntax-highlighting SCI scripts and disassembly.
enum SciTokenType {
  address,
  hexByte,
  keyword,
  opcode,
  selector,
  kernel,
  className,
  identifier,
  stringLiteral,
  number,
  comment,
  punctuation,
  whitespace,
}

/// A syntax token with an associated semantic token type.
class SciToken {
  final SciTokenType type;
  final String text;

  const SciToken(this.type, this.text);

  @override
  String toString() => '[$type: "$text"]';
}

/// Tokenizer and syntax highlighter for SCI script code and disassembly.
class SciScriptHighlighter {
  const SciScriptHighlighter._();

  static const _keywords = {
    'script',
    'exports',
    'local',
    'instance',
    'class',
    'properties',
    'method',
    'procedure',
    'of',
    'synonyms',
  };

  static final _hexAddrRegex = RegExp(r'^\[([0-9A-Fa-f]{4})\]');
  static final _numberRegex = RegExp(r'^(?:0x[0-9A-Fa-f]+|-?\d+)');
  static final _stringRegex = RegExp(r'^"[^"\r\n]*"');

  /// Highlights a decompiled script line or disassembly line into a rich [TextSpan].
  static TextSpan highlightLine(
    String line, {
    String? searchQuery,
    int? highlightMatchIndex,
    int currentMatchIndexOffset = 0,
  }) {
    final tokens = tokenizeLine(line);
    final children = <TextSpan>[];

    for (final token in tokens) {
      final baseStyle = _styleForToken(token.type);

      // If search query is present, check if token text contains the search query
      if (searchQuery != null &&
          searchQuery.isNotEmpty &&
          token.text.toLowerCase().contains(searchQuery.toLowerCase())) {
        children.addAll(_splitForSearchHighlight(token.text, searchQuery, baseStyle));
      } else {
        children.add(TextSpan(text: token.text, style: baseStyle));
      }
    }

    return TextSpan(children: children);
  }

  /// Splits [text] by [searchQuery] and applies yellow background highlight to matches.
  static List<TextSpan> _splitForSearchHighlight(
    String text,
    String searchQuery,
    TextStyle baseStyle,
  ) {
    final spans = <TextSpan>[];
    final queryLower = searchQuery.toLowerCase();
    final textLower = text.toLowerCase();
    var start = 0;

    while (start < text.length) {
      final matchIdx = textLower.indexOf(queryLower, start);
      if (matchIdx == -1) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }

      if (matchIdx > start) {
        spans.add(TextSpan(text: text.substring(start, matchIdx), style: baseStyle));
      }

      final matchText = text.substring(matchIdx, matchIdx + searchQuery.length);
      spans.add(
        TextSpan(
          text: matchText,
          style: baseStyle.copyWith(
            backgroundColor: const Color(0xFF886600),
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      start = matchIdx + searchQuery.length;
    }

    return spans;
  }

  /// Tokenizes a single line of SCI code or disassembly into [SciToken]s.
  static List<SciToken> tokenizeLine(String line) {
    final tokens = <SciToken>[];
    var i = 0;

    while (i < line.length) {
      // 1. Whitespace
      if (line[i] == ' ' || line[i] == '\t') {
        final start = i;
        while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
          i++;
        }
        tokens.add(SciToken(SciTokenType.whitespace, line.substring(start, i)));
        continue;
      }

      // 2. Comments (; ...)
      if (line[i] == ';') {
        tokens.add(SciToken(SciTokenType.comment, line.substring(i)));
        break;
      }

      // 3. Address brackets [01A4]
      if (line[i] == '[') {
        final match = _hexAddrRegex.matchAsPrefix(line, i);
        if (match != null) {
          tokens.add(SciToken(SciTokenType.address, match.group(0)!));
          i += match.group(0)!.length;
          continue;
        }
      }

      // 4. String literals
      if (line[i] == '"') {
        final match = _stringRegex.matchAsPrefix(line, i);
        if (match != null) {
          tokens.add(SciToken(SciTokenType.stringLiteral, match.group(0)!));
          i += match.group(0)!.length;
          continue;
        }
      }

      // 5. Selectors prefixed with # (#init, #view)
      if (line[i] == '#') {
        final start = i++;
        while (i < line.length && _isIdentChar(line[i])) {
          i++;
        }
        tokens.add(SciToken(SciTokenType.selector, line.substring(start, i)));
        continue;
      }

      // 6. Numbers (0x1234 or decimal)
      if (_isDigit(line[i]) || (line[i] == '-' && i + 1 < line.length && _isDigit(line[i + 1]))) {
        final match = _numberRegex.matchAsPrefix(line, i);
        if (match != null) {
          tokens.add(SciToken(SciTokenType.number, match.group(0)!));
          i += match.group(0)!.length;
          continue;
        }
      }

      // 7. Punctuation
      if ('()[]{},:='.contains(line[i])) {
        tokens.add(SciToken(SciTokenType.punctuation, line[i]));
        i++;
        continue;
      }

      // 8. Word (keyword, opcode, identifier)
      if (_isIdentChar(line[i])) {
        final start = i;
        while (i < line.length && _isIdentChar(line[i])) {
          i++;
        }
        final word = line.substring(start, i);

        if (_keywords.contains(word)) {
          tokens.add(SciToken(SciTokenType.keyword, word));
        } else if (_isKernel(word)) {
          tokens.add(SciToken(SciTokenType.kernel, word));
        } else if (_isHexByteString(word)) {
          tokens.add(SciToken(SciTokenType.hexByte, word));
        } else {
          tokens.add(SciToken(SciTokenType.identifier, word));
        }
        continue;
      }

      // Default fallback
      tokens.add(SciToken(SciTokenType.punctuation, line[i]));
      i++;
    }

    return tokens;
  }

  static bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;

  static bool _isIdentChar(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || // A-Z
        (c >= 97 && c <= 122) || // a-z
        (c >= 48 && c <= 57) || // 0-9
        c == 95 || // _
        c == 45 || // -
        c == 63; // ? (e.g. eq?, le?)
  }

  static bool _isKernel(String word) {
    const knownKernels = {
      'DrawPic',
      'Show',
      'PicNotValid',
      'Animate',
      'SetNowSeen',
      'NumLoops',
      'NumCels',
      'CelWide',
      'CelHigh',
      'DrawCel',
      'AddToPic',
      'NewWindow',
      'GetPort',
      'SetPort',
      'DisposeWindow',
      'TextSize',
      'Display',
      'GetEvent',
      'GlobalToLocal',
      'LocalToGlobal',
      'MapKeyToDir',
      'Parse',
      'Said',
      'SetSynonyms',
      'HaveMouse',
      'SetCursor',
      'DoSound',
      'NewList',
      'DisposeList',
      'NewNode',
      'FirstNode',
      'LastNode',
      'EmptyList',
      'NextNode',
      'PrevNode',
      'NodeValue',
      'AddAfter',
      'AddToSyn',
      'DeleteKey',
      'Random',
      'Load',
      'UnLoad',
      'ScriptID',
      'DisposeScript',
      'Clone',
      'DisposeClone',
      'IsObject',
      'RespondsTo',
      'StrEnd',
      'StrCat',
      'StrCmp',
      'StrLen',
      'StrCpy',
      'Format',
      'GetFarText',
      'ReadNumber',
      'BaseSetter',
      'DirLoop',
      'CantBeHere',
      'OnControl',
      'InitBresen',
      'DoBresen',
      'DoAvoider',
      'SetJump',
    };
    return knownKernels.contains(word);
  }

  static bool _isHexByteString(String word) {
    if (word.length != 2) return false;
    final c1 = word.codeUnitAt(0);
    final c2 = word.codeUnitAt(1);
    final isHex1 = (c1 >= 48 && c1 <= 57) || (c1 >= 65 && c1 <= 70) || (c1 >= 97 && c1 <= 102);
    final isHex2 = (c2 >= 48 && c2 <= 57) || (c2 >= 65 && c2 <= 70) || (c2 >= 97 && c2 <= 102);
    return isHex1 && isHex2;
  }

  static TextStyle _styleForToken(SciTokenType type) {
    const defaultStyle = TextStyle(
      fontFamily: 'Courier',
      fontSize: 13,
      letterSpacing: 0.2,
      color: AgiTheme.egaWhite,
    );

    switch (type) {
      case SciTokenType.address:
        return defaultStyle.copyWith(color: const Color(0xFF6B82A8));
      case SciTokenType.hexByte:
        return defaultStyle.copyWith(color: const Color(0xFF8899AA));
      case SciTokenType.keyword:
        return defaultStyle.copyWith(
          color: AgiTheme.egaMagenta,
          fontWeight: FontWeight.bold,
        );
      case SciTokenType.opcode:
        return defaultStyle.copyWith(
          color: AgiTheme.egaCyan,
          fontWeight: FontWeight.w600,
        );
      case SciTokenType.selector:
        return defaultStyle.copyWith(color: AgiTheme.egaAmber);
      case SciTokenType.kernel:
        return defaultStyle.copyWith(
          color: const Color(0xFF55FFAA),
          fontWeight: FontWeight.bold,
        );
      case SciTokenType.className:
        return defaultStyle.copyWith(
          color: const Color(0xFFFFAA55),
          fontWeight: FontWeight.bold,
        );
      case SciTokenType.stringLiteral:
        return defaultStyle.copyWith(color: AgiTheme.egaGreen);
      case SciTokenType.number:
        return defaultStyle.copyWith(color: const Color(0xFF88DDFF));
      case SciTokenType.comment:
        return defaultStyle.copyWith(
          color: const Color(0xFF7A8B9E),
          fontStyle: FontStyle.italic,
        );
      case SciTokenType.punctuation:
        return defaultStyle.copyWith(color: const Color(0xFFAAAAAA));
      case SciTokenType.identifier:
        return defaultStyle.copyWith(color: AgiTheme.egaWhite);
      case SciTokenType.whitespace:
        return defaultStyle;
    }
  }
}
