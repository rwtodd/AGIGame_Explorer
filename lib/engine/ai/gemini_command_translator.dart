import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Result of testing connectivity to the Gemini API.
class ConnectionTestResult {
  final bool success;
  final String message;
  final int? statusCode;

  const ConnectionTestResult({
    required this.success,
    required this.message,
    this.statusCode,
  });
}

/// Result of an AI command translation attempt.
class AiTranslationResult {
  /// The player's original input string.
  final String originalInput;

  /// The translated AGI command (e.g. "look screen", "take card").
  final String translatedCommand;

  /// Whether the translation was matched to a specific room command from logic scripts.
  final bool isRoomCommandMatch;

  /// Whether this result came from the in-memory cache.
  final bool fromCache;

  const AiTranslationResult({
    required this.originalInput,
    required this.translatedCommand,
    this.isRoomCommandMatch = false,
    this.fromCache = false,
  });
}

/// Service that translates natural language player inputs into Sierra AGI commands using the Gemini API.
class GeminiCommandTranslator {
  static const String defaultModel = 'gemini-3.5-flash-lite';
  static const String apiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  final HttpClient _httpClient;
  final Duration timeout;
  final Map<String, String> _cache = {};
  static const int _maxCacheSize = 200;

  GeminiCommandTranslator({
    HttpClient? httpClient,
    this.timeout = const Duration(milliseconds: 10000),
  }) : _httpClient = httpClient ?? HttpClient();

  /// Tests connectivity and API key validity with a lightweight prompt.
  Future<ConnectionTestResult> testConnection({
    required String apiKey,
    String model = defaultModel,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      return const ConnectionTestResult(
        success: false,
        message: 'API key is empty',
      );
    }

    try {
      final uri = Uri.parse('$apiBaseUrl/$model:generateContent?key=$cleanKey');
      final request = await _httpClient.postUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': 'Ping. Reply with PONG.'}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.0,
          'maxOutputTokens': 256,
        }
      });

      request.write(body);
      final response = await request.close().timeout(timeout);
      final responseStr = await response.transform(utf8.decoder).join();

      debugPrint('[Gemini API] testConnection ($model) status: ${response.statusCode}');
      debugPrint('[Gemini API] testConnection ($model) body: $responseStr');

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(responseStr);
        final candidates = json['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          return ConnectionTestResult(
            success: true,
            message: 'Connected successfully to $model',
            statusCode: 200,
          );
        }
        return const ConnectionTestResult(
          success: false,
          message: 'Received empty response candidates from Gemini API',
          statusCode: 200,
        );
      } else {
        String errorDetail = 'HTTP ${response.statusCode}';
        try {
          final Map<String, dynamic> json = jsonDecode(responseStr);
          if (json['error'] != null && json['error']['message'] != null) {
            errorDetail = '${json['error']['message']} (HTTP ${response.statusCode})';
          }
        } catch (_) {}
        return ConnectionTestResult(
          success: false,
          message: errorDetail,
          statusCode: response.statusCode,
        );
      }
    } catch (e, stack) {
      debugPrint('[Gemini API] testConnection error: $e\n$stack');
      return ConnectionTestResult(
        success: false,
        message: 'Error: $e',
      );
    }
  }

  /// Translates [rawInput] against [roomCommands] using Gemini.
  Future<AiTranslationResult?> translate({
    required String rawInput,
    required List<String> roomCommands,
    required String apiKey,
    String model = defaultModel,
    int? roomNumber,
  }) async {
    final clean = rawInput.trim();
    if (clean.isEmpty || apiKey.trim().isEmpty) return null;

    bool isRoomMatch(String cmd) {
      return roomCommands.any((rc) {
        final base = rc.split(' (').first.trim();
        return base == cmd || rc == cmd;
      });
    }

    final cacheKey = '${roomNumber ?? 0}:${clean.toLowerCase()}';
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      return AiTranslationResult(
        originalInput: clean,
        translatedCommand: cached,
        isRoomCommandMatch: isRoomMatch(cached),
        fromCache: true,
      );
    }

    final prompt = _buildPrompt(
      rawInput: clean,
      roomCommands: roomCommands,
      roomNumber: roomNumber,
    );

    try {
      final uri = Uri.parse('$apiBaseUrl/$model:generateContent?key=$apiKey');
      final request = await _httpClient.postUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 500,
          'topP': 0.95,
        }
      });

      request.write(body);
      final response = await request.close().timeout(timeout);
      final responseStr = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        debugPrint('[Gemini API] translate HTTP error ${response.statusCode}: $responseStr');
        return null;
      }

      final Map<String, dynamic> json = jsonDecode(responseStr);
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;

      // Extract model response text
      String text = '';
      for (final part in parts) {
        if (part is Map && part.containsKey('text')) {
          final t = part['text'] as String? ?? '';
          if (t.isNotEmpty) {
            text = t;
            break;
          }
        }
      }

      final cleanedResult = _cleanModelOutput(text);
      if (cleanedResult.isEmpty) return null;

      debugPrint('[Gemini API] Translated "$clean" -> "$cleanedResult"');
      _storeCache(cacheKey, cleanedResult);

      return AiTranslationResult(
        originalInput: clean,
        translatedCommand: cleanedResult,
        isRoomCommandMatch: isRoomMatch(cleanedResult),
        fromCache: false,
      );
    } catch (e, stack) {
      debugPrint('[Gemini API] translate exception: $e\n$stack');
      return null;
    }
  }

  String _buildPrompt({
    required String rawInput,
    required List<String> roomCommands,
    int? roomNumber,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
      'You are an expert command parser for classic Sierra On-Line AGI text adventure games '
      '(e.g. King\'s Quest, Space Quest, Police Quest, Black Cauldron).',
    );
    buffer.writeln(
      'Convert the player\'s natural English input into concise Sierra AGI command syntax '
      '(usually 2-3 words, lowercase verb + noun, e.g. "look screen", "take card", "push button").',
    );
    buffer.writeln();

    if (roomCommands.isNotEmpty) {
      buffer.writeln('VALID ACTIONS RECOGNIZED IN THIS ROOM (Room ${roomNumber ?? 0}):');
      for (final cmd in roomCommands.take(60)) {
        buffer.writeln('- $cmd');
      }
      buffer.writeln();
      buffer.writeln(
        'RULE 1: If the player\'s input matches any of the above valid actions or their listed synonyms in parentheses, '
        'return the primary action phrase before the parentheses (e.g. "look wizard", "take key").',
      );
    }

    buffer.writeln(
      'RULE 2: If no valid room action matches, translate the player\'s input into canonical AGI-speak '
      '(e.g. "take a look at that tapestry" -> "look tapestry", "is there water to swim in" -> "swim", '
      '"kick the machine" -> "kick machine", "grab purple flower" -> "take flower"). '
      'Do not invent complex logic; output the simplest 2-word verb+noun command.',
    );
    buffer.writeln();
    buffer.writeln('FORMAT: Output ONLY the final command text (lowercase, no markdown, no quotes, no explanation).');
    buffer.writeln();
    buffer.writeln('PLAYER INPUT: "$rawInput"');
    buffer.write('AGI COMMAND:');

    return buffer.toString();
  }

  static final _synonymsOrBracketsRegex = RegExp(r'\(.*?\)|\[.*?\]');
  static final _quotesOrControlRegex = RegExp(r'[`"*\n\r]');
  static final _punctuationRegex = RegExp(r'[.,;:!?\(\)\[\]\{\}\/\\_\-\+=<>@#$%^&~|]');
  static final _whitespaceRegex = RegExp(r'\s+');

  String _cleanModelOutput(String raw) {
    var text = raw.trim().toLowerCase();
    // Remove parenthesized synonyms if echoed by model
    text = text.replaceAll(_synonymsOrBracketsRegex, ' ');
    // Remove markdown quotes, backticks, asterisks, prefix labels
    text = text.replaceAll(_quotesOrControlRegex, ' ');
    if (text.startsWith('agi command:')) {
      text = text.substring('agi command:'.length).trim();
    }
    if (text.startsWith('command:')) {
      text = text.substring('command:'.length).trim();
    }
    // Remove punctuation
    text = text.replaceAll(_punctuationRegex, ' ');
    // Collapse spaces
    text = text.replaceAll(_whitespaceRegex, ' ').trim();
    return text;
  }

  void _storeCache(String key, String value) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  /// Clears the translation cache.
  void clearCache() {
    _cache.clear();
  }
}
