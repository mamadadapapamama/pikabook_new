import 'package:flutter/foundation.dart';

/// 텍스트 정리 서비스
/// OCR 결과에서 불필요한 텍스트를 제거하고 텍스트를 분석하는 기능을 제공합니다.

class TextCleanerService {
  // 싱글톤 패턴 구현
  static final TextCleanerService _instance = TextCleanerService._internal();
  factory TextCleanerService() => _instance;
  TextCleanerService._internal();

  // 중국어 문자 범위 (유니코드)
  static final RegExp chineseCharPattern = RegExp(r'[\u4e00-\u9fff]');

  // 핀인 성조 기호
  static const List<String> toneMarks = [
    'ā', 'á', 'ǎ', 'à',
    'ē', 'é', 'ě', 'è',
    'ī', 'í', 'ǐ', 'ì',
    'ō', 'ó', 'ǒ', 'ò',
    'ū', 'ú', 'ǔ', 'ù',
    'ǖ', 'ǘ', 'ǚ', 'ǜ'
  ];

  // 정규식 패턴 (클래스 레벨 상수)
  static final RegExp pinyinPattern = RegExp(r'[a-zA-Z' + toneMarks.join('') + r']+');
  static final RegExp onlyNumbersPattern = RegExp(r'^[0-9]+$');
  static final RegExp onlyPunctuationPattern = RegExp(r'^[\s\p{P}]+$', unicode: true);
  
  // 페이지 번호 패턴 (e.g. "page 12", "12", "第12页")
  static final RegExp pageNumberPattern = RegExp(r'^(?:page\s*)?[0-9]+(?:\s*页)?$', caseSensitive: false);
  
  // 섹션 제목 패턴 (e.g. "Lesson 1", "练习", "Chapter 2")
  static final RegExp sectionTitlePattern = RegExp(
    r'^(?:Lesson|Chapter|Unit|练习|第[一二三四五六七八九十百千万]+[课章])\s*[0-9一二三四五六七八九十百千万]*$',
    caseSensitive: false
  );
  
  // 저작권 및 특수 문자 패턴
  static final RegExp copyrightPattern = RegExp(r'^[^a-zA-Z\u4e00-\u9fff]*[©®™@#$%^&*]+[^a-zA-Z\u4e00-\u9fff]*$');
  
  // 중복된 제목/지시사항 체크를 위한 세션 저장소
  final Set<String> _seenHeadings = {};
  final Set<String> _seenInstructions = {};

  // 텍스트 정리 결과 캐싱 (FIFO 방식으로 자동 관리)
  final Map<String, String> _cleanTextCache = {};
  final int _maxCacheSize = 100;

  /// 불필요한 텍스트 제거
  /// - 핀인 줄 제거
  /// - 숫자만 단독으로 있는 문장 제거
  /// - 페이지 번호 제거
  /// - 섹션 제목 제거
  /// - 저작권 및 특수 문자만 있는 줄 제거
  /// - 중복된 제목/지시사항 제거
  /// - 문장부호만 있는 문장 제거
  /// - 너무 짧은 줄 제거 (중국어가 아닌 경우)

  String cleanText(String text) {
    if (text.isEmpty) return text;

    // 캐시 확인
    if (_cleanTextCache.containsKey(text)) {
      return _cleanTextCache[text]!;
    }

    if (kDebugMode) {
      debugPrint('🧹 텍스트 정리 시작: "$text"');
      debugPrint('🧹 중국어 포함 여부: ${containsChinese(text)}');
    }

    // 핀인 줄 제거
    final originalText = text;
    text = removePinyinLines(text);
    if (kDebugMode && text != originalText) {
      debugPrint('🧹 핀인 줄 제거 후: "$text"');
    }

    // 줄 단위로 분리
    final lines = text.split('\n');
    final cleanedLines = <String>[];

    for (final line in lines) {
      final trimmedLine = line.trim();

      // 빈 줄 건너뛰기
      if (trimmedLine.isEmpty) {
        if (kDebugMode) {
          debugPrint('🧹 빈 줄 건너뛰기: "$line"');
        }
        continue;
      }

      // 숫자만 있는 줄 건너뛰기 (페이지 번호 등)
      if (_isOnlyNumbers(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 숫자만 있는 줄 건너뛰기: "$trimmedLine"');
        }
        continue;
      }

      // 페이지 번호 건너뛰기
      if (_isPageNumber(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 페이지 번호 건너뛰기: "$trimmedLine"');
        }
        continue;
      }

      // 섹션 제목 건너뛰기
      if (_isSectionTitle(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 섹션 제목 건너뛰기: "$trimmedLine"');
        }
        continue;
      }

      // 저작권 및 특수 문자만 있는 줄 건너뛰기
      if (_isCopyrightOrSpecialChars(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 저작권/특수문자 건너뛰기: "$trimmedLine"');
        }
        continue;
      }

      // 중복된 제목/지시사항 건너뛰기
      if (_isDuplicateHeadingOrInstruction(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 중복 제목/지시사항 건너뛰기: "$trimmedLine"');
        }
        continue;
      }

      // 문장부호만 있는 줄 건너뛰기
      if (_isOnlyPunctuation(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 문장부호만 있는 줄 건너뛰기: "$trimmedLine"');
        }
        continue;
      }

      // 너무 짧은 줄 건너뛰기 (10글자 이내이면서 중국어가 아닌 경우)
      if (_isTooShort(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 너무 짧은 줄 건너뛰기: "$trimmedLine" (길이: ${trimmedLine.length}, 중국어포함: ${containsChinese(trimmedLine)})');
        }
        continue;
      }

      if (kDebugMode) {
        debugPrint('🧹 ✅ 줄 유지: "$trimmedLine"');
      }
      cleanedLines.add(trimmedLine);
    }

    final result = cleanedLines.join('\n');

    if (kDebugMode) {
      debugPrint('🧹 텍스트 정리 완료: "${text}" → "$result"');
    }

    // 캐시에 저장 (캐시 크기 제한)
    if (_cleanTextCache.length >= _maxCacheSize) {
      // 가장 오래된 항목 제거 (간단한 FIFO 방식)
      final oldestKey = _cleanTextCache.keys.first;
      _cleanTextCache.remove(oldestKey);
    }
    _cleanTextCache[text] = result;

    return result;
  }

  /// 텍스트가 중국어를 포함하는지 확인
  bool containsChinese(String text) {
    return chineseCharPattern.hasMatch(text);
  }

  /// 텍스트에서 중국어 문자만 추출
  String extractChineseChars(String text) {
    if (text.isEmpty) return '';

    final matches = chineseCharPattern.allMatches(text);
    final buffer = StringBuffer();

    for (final match in matches) {
      buffer.write(match.group(0));
    }

    return buffer.toString();
  }

  /// 텍스트가 핀인인지 확인 (전체 줄이 핀인인 경우)
  bool isPinyinLine(String line) {
    // 중국어 문자가 없고, 핀인 패턴과 일치하는 경우
    return !containsChinese(line) &&
        pinyinPattern.allMatches(line).length > 0 &&
        line.trim().split(' ').every(
            (word) => pinyinPattern.hasMatch(word) || word.trim().isEmpty);
  }

  // 핀인 줄 캐싱
  final Map<String, String> _pinyinRemovalCache = {};

  /// 중국어 텍스트에서 핀인 줄 제거
  String removePinyinLines(String text) {
    if (text.isEmpty) return text;

    // 캐시 확인
    if (_pinyinRemovalCache.containsKey(text)) {
      return _pinyinRemovalCache[text]!;
    }

    final lines = text.split('\n');
    final filteredLines = lines.where((line) => !isPinyinLine(line)).toList();
    final result = filteredLines.join('\n');

    // 캐시에 저장 (캐시 크기 제한)
    if (_pinyinRemovalCache.length >= _maxCacheSize) {
      // 가장 오래된 항목 제거
      final oldestKey = _pinyinRemovalCache.keys.first;
      _pinyinRemovalCache.remove(oldestKey);
    }
    _pinyinRemovalCache[text] = result;

    return result;
  }

  /// 중국어 텍스트에서 핀인 줄 추출
  List<String> extractPinyinLines(String text) {
    final lines = text.split('\n');
    return lines.where((line) => isPinyinLine(line)).toList();
  }

  /// 숫자만 있는지 확인
  bool _isOnlyNumbers(String text) {
    return onlyNumbersPattern.hasMatch(text);
  }

  /// 페이지 번호인지 확인
  bool _isPageNumber(String text) {
    return pageNumberPattern.hasMatch(text);
  }

  /// 섹션 제목인지 확인
  bool _isSectionTitle(String text) {
    return sectionTitlePattern.hasMatch(text);
  }

  /// 저작권 및 특수 문자만 있는지 확인
  bool _isCopyrightOrSpecialChars(String text) {
    return copyrightPattern.hasMatch(text) && !containsChinese(text);
  }

  /// 중복된 제목/지시사항인지 확인
  bool _isDuplicateHeadingOrInstruction(String text) {
    // 제목 패턴 (짧고 끝에 문장부호가 없는 경우)
    if (text.length < 50 && !text.endsWith(RegExp(r'[.!?。！？]').pattern)) {
      if (_seenHeadings.contains(text)) {
        return true;
      }
      _seenHeadings.add(text);
    }
    
    // 지시사항 패턴 (시작이 특정 단어로 시작하는 경우)
    if (text.toLowerCase().startsWith(RegExp(r'^(note|注意|提示|说明|练习|作业)').pattern)) {
      if (_seenInstructions.contains(text)) {
        return true;
      }
      _seenInstructions.add(text);
    }
    
    return false;
  }

  /// 문장부호만 있는지 확인
  bool _isOnlyPunctuation(String text) {
    return onlyPunctuationPattern.hasMatch(text);
  }

  /// 너무 짧은 줄인지 확인 (10글자 이내이면서 중국어가 아닌 경우)
  bool _isTooShort(String text) {
    return text.length <= 10 && !containsChinese(text);
  }
}
