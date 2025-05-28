import 'package:flutter/foundation.dart';

/// 텍스트 정리 서비스
/// 
/// OCR 결과에서 불필요한 텍스트를 제거하고 중국어 텍스트만 추출하는 기능을 제공합니다.
/// 
/// **주요 기능:**
/// - 핀인(병음) 줄 자동 감지 및 제거
/// - 페이지 번호, 저작권 표시 등 불필요한 텍스트 제거
/// - 중국어 문자만 추출 및 검증
/// - 성능 최적화를 위한 결과 캐싱
/// 
/// **사용 예시:**
/// ```dart
/// final cleaner = TextCleanerService();
/// final cleanedText = cleaner.cleanText(ocrResult);
/// final hasChinese = cleaner.containsChinese(text);
/// ```
class TextCleanerService {
  // ========== 싱글톤 패턴 ==========
  static final TextCleanerService _instance = TextCleanerService._internal();
  factory TextCleanerService() => _instance;
  TextCleanerService._internal();

  // ========== 정규식 패턴 상수 ==========
  
  /// 중국어 문자 범위 (유니코드 4E00-9FFF)
  /// 한자(漢字) 기본 블록과 확장 블록을 포함
  static final RegExp chineseCharPattern = RegExp(r'[\u4e00-\u9fff]');

  /// 핀인(병음) 성조 기호 목록
  /// 4개 성조 × 6개 모음 = 24개 성조 표시 문자
  static const List<String> toneMarks = [
    'ā', 'á', 'ǎ', 'à',  // a 성조
    'ē', 'é', 'ě', 'è',  // e 성조
    'ī', 'í', 'ǐ', 'ì',  // i 성조
    'ō', 'ó', 'ǒ', 'ò',  // o 성조
    'ū', 'ú', 'ǔ', 'ù',  // u 성조
    'ǖ', 'ǘ', 'ǚ', 'ǜ'   // ü 성조
  ];

  /// 핀인 패턴: 영문자 + 성조 기호 조합
  static final RegExp pinyinPattern = RegExp(r'[a-zA-Z' + toneMarks.join('') + r']+');
  
  /// 숫자만 있는 패턴 (예: "123", "45")
  static final RegExp onlyNumbersPattern = RegExp(r'^[0-9]+$');
  
  /// 문장부호만 있는 패턴 (공백 + 구두점)
  static final RegExp onlyPunctuationPattern = RegExp(r'^[\s\p{P}]+$', unicode: true);
  
  /// 페이지 번호 패턴 (예: "page 12", "12", "第12页")
  static final RegExp pageNumberPattern = RegExp(r'^(?:page\s*)?[0-9]+(?:\s*页)?$', caseSensitive: false);
  
  /// 저작권 및 특수 문자 패턴 (©, ®, ™, @, #, $ 등)
  static final RegExp copyrightPattern = RegExp(r'^[^a-zA-Z\u4e00-\u9fff]*[©®™@#$%^&*+-]+[^a-zA-Z\u4e00-\u9fff]*$');
  
  /// 저작권 관련 키워드 패턴 (영어 + 중국어)
  static final RegExp copyrightKeywordsPattern = RegExp(
    r'(copyright|all rights reserved|版权所有|保留所有权利|ltd\.?|inc\.?|corp\.?|company|pte\.?\s*ltd\.?|limited|international.*\(\d{4}\)|rights?\s+reserved)',
    caseSensitive: false,
  );

  // ========== 캐시 시스템 ==========
  
  /// 텍스트 정리 결과 캐시 (성능 최적화)
  final Map<String, String> _cleanTextCache = {};
  
  /// 핀인 제거 결과 캐시
  final Map<String, String> _pinyinRemovalCache = {};
  
  /// 캐시 최대 크기 (메모리 사용량 제한)
  final int _maxCacheSize = 100;

  // ========== 주요 공개 메서드 ==========

  /// **메인 텍스트 정리 메서드**
  /// 
  /// OCR 결과에서 불필요한 텍스트를 제거하고 중국어 텍스트만 추출합니다.
  /// 
  /// **제거되는 요소들:**
  /// - 핀인(병음) 줄
  /// - 숫자만 있는 줄 (페이지 번호 등)
  /// - 페이지 번호 표시
  /// - 저작권 및 특수 문자
  /// - 문장부호만 있는 줄
  /// - 중국어가 없는 영어 전용 줄
  /// 
  /// **매개변수:**
  /// - `text`: 정리할 원본 텍스트 (OCR 결과)
  /// 
  /// **반환값:**
  /// - 정리된 중국어 텍스트
  /// 
  /// **예시:**
  /// ```dart
  /// final input = "你好\nNǐ hǎo\npage 1\n世界";
  /// final output = cleaner.cleanText(input); // "你好\n世界"
  /// ```
  String cleanText(String text) {
    if (text.isEmpty) return text;

    // 1. 캐시 확인 (성능 최적화)
    if (_cleanTextCache.containsKey(text)) {
      return _cleanTextCache[text]!;
    }

    if (kDebugMode) {
      debugPrint('🧹 텍스트 정리 시작: "$text"');
      debugPrint('🧹 중국어 포함 여부: ${containsChinese(text)}');
    }

    // 2. 핀인 줄 제거
    final originalText = text;
    text = removePinyinLines(text);
    if (kDebugMode && text != originalText) {
      debugPrint('🧹 핀인 줄 제거 후: "$text"');
    }

    // 3. 줄 단위로 분리하여 각각 검사
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

      // 저작권 및 특수 문자만 있는 줄 건너뛰기
      if (_isCopyrightOrSpecialChars(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 저작권/특수문자 건너뛰기: "$trimmedLine"');
        }
        continue;
      }

      // 저작권 키워드가 포함된 줄 건너뛰기 (중국어 포함 여부와 관계없이)
      if (_isCopyrightKeywordLine(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 저작권 키워드 줄 건너뛰기: "$trimmedLine"');
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

      // 중국어가 아닌 단어만 있을 경우 제거 (영어만 등)
      if (_isNonChineseOnly(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 중국어가 아닌 텍스트만 있는 줄 건너뛰기: "$trimmedLine"');
        }
        continue;
      }

      // 모든 검사를 통과한 줄은 유지
      if (kDebugMode) {
        debugPrint('🧹 ✅ 줄 유지: "$trimmedLine"');
      }
      cleanedLines.add(trimmedLine);
    }

    // 4. 결과 조합 및 캐시 저장
    final result = cleanedLines.join('\n');

    if (kDebugMode) {
      debugPrint('🧹 텍스트 정리 완료: "${originalText}" → "$result"');
    }

    // 캐시에 저장 (FIFO 방식으로 크기 제한)
    _saveToCache(_cleanTextCache, originalText, result);

    return result;
  }

  /// **중국어 포함 여부 확인**
  /// 
  /// 주어진 텍스트에 중국어 문자가 포함되어 있는지 확인합니다.
  /// 
  /// **매개변수:**
  /// - `text`: 검사할 텍스트
  /// 
  /// **반환값:**
  /// - `true`: 중국어 문자 포함
  /// - `false`: 중국어 문자 없음
  /// 
  /// **예시:**
  /// ```dart
  /// cleaner.containsChinese("你好"); // true
  /// cleaner.containsChinese("hello"); // false
  /// ```
  bool containsChinese(String text) {
    return chineseCharPattern.hasMatch(text);
  }

  /// **중국어 문자만 추출**
  /// 
  /// 텍스트에서 중국어 문자만 추출하여 반환합니다.
  /// 다른 언어나 기호는 모두 제거됩니다.
  /// 
  /// **매개변수:**
  /// - `text`: 원본 텍스트
  /// 
  /// **반환값:**
  /// - 중국어 문자만 포함된 문자열
  /// 
  /// **예시:**
  /// ```dart
  /// cleaner.extractChineseChars("你好123world世界"); // "你好世界"
  /// ```
  String extractChineseChars(String text) {
    if (text.isEmpty) return '';

    final matches = chineseCharPattern.allMatches(text);
    final buffer = StringBuffer();

    for (final match in matches) {
      buffer.write(match.group(0));
    }

    return buffer.toString();
  }

  // ========== 핀인 관련 메서드 ==========

  /// **핀인 줄 감지**
  /// 
  /// 주어진 줄이 핀인(병음)인지 확인합니다.
  /// 중국어 문자가 없고 핀인 패턴과 일치하는 경우 핀인으로 판단합니다.
  /// 
  /// **판단 기준:**
  /// - 중국어 문자가 없음
  /// - 영문자 + 성조 기호로만 구성
  /// - 공백으로 구분된 단어들이 모두 핀인 패턴과 일치
  /// 
  /// **매개변수:**
  /// - `line`: 검사할 텍스트 줄
  /// 
  /// **반환값:**
  /// - `true`: 핀인 줄
  /// - `false`: 일반 텍스트 줄
  /// 
  /// **예시:**
  /// ```dart
  /// cleaner.isPinyinLine("Nǐ hǎo shì jiè"); // true
  /// cleaner.isPinyinLine("你好世界"); // false
  /// ```
  bool isPinyinLine(String line) {
    // 중국어 문자가 없고, 핀인 패턴과 일치하는 경우
    return !containsChinese(line) &&
        pinyinPattern.allMatches(line).length > 0 &&
        line.trim().split(' ').every(
            (word) => pinyinPattern.hasMatch(word) || word.trim().isEmpty);
  }

  /// **핀인 줄 제거**
  /// 
  /// 텍스트에서 핀인(병음) 줄을 모두 제거합니다.
  /// 결과는 캐시되어 동일한 입력에 대해 빠른 응답을 제공합니다.
  /// 
  /// **매개변수:**
  /// - `text`: 원본 텍스트
  /// 
  /// **반환값:**
  /// - 핀인 줄이 제거된 텍스트
  /// 
  /// **예시:**
  /// ```dart
  /// final input = "你好\nNǐ hǎo\n世界";
  /// final output = cleaner.removePinyinLines(input); // "你好\n世界"
  /// ```
  String removePinyinLines(String text) {
    if (text.isEmpty) return text;

    // 캐시 확인
    if (_pinyinRemovalCache.containsKey(text)) {
      return _pinyinRemovalCache[text]!;
    }

    final lines = text.split('\n');
    final filteredLines = lines.where((line) => !isPinyinLine(line)).toList();
    final result = filteredLines.join('\n');

    // 캐시에 저장
    _saveToCache(_pinyinRemovalCache, text, result);

    return result;
  }

  /// **핀인 줄 추출**
  /// 
  /// 텍스트에서 핀인(병음) 줄만 추출하여 리스트로 반환합니다.
  /// 
  /// **매개변수:**
  /// - `text`: 원본 텍스트
  /// 
  /// **반환값:**
  /// - 핀인 줄들의 리스트
  /// 
  /// **예시:**
  /// ```dart
  /// final input = "你好\nNǐ hǎo\n世界\nShì jiè";
  /// final pinyins = cleaner.extractPinyinLines(input); // ["Nǐ hǎo", "Shì jiè"]
  /// ```
  List<String> extractPinyinLines(String text) {
    final lines = text.split('\n');
    return lines.where((line) => isPinyinLine(line)).toList();
  }

  // ========== 내부 검증 메서드 ==========

  /// 숫자만 있는지 확인 (예: "123", "45")
  bool _isOnlyNumbers(String text) {
    return onlyNumbersPattern.hasMatch(text);
  }

  /// 페이지 번호인지 확인 (예: "page 12", "12", "第12页")
  bool _isPageNumber(String text) {
    return pageNumberPattern.hasMatch(text);
  }

  /// 저작권 및 특수 문자만 있는지 확인
  /// 중국어가 포함되지 않은 특수 문자 줄을 감지
  bool _isCopyrightOrSpecialChars(String text) {
    return copyrightPattern.hasMatch(text) && !containsChinese(text);
  }

  /// 저작권 관련 키워드가 포함된 줄인지 확인
  /// 중국어가 포함되어 있어도 저작권 관련 키워드가 있으면 제거
  bool _isCopyrightKeywordLine(String text) {
    if (kDebugMode) {
      debugPrint('🔍 저작권 키워드 검사: "$text"');
    }
    
    final hasCopyrightKeywords = copyrightKeywordsPattern.hasMatch(text);
    
    if (kDebugMode) {
      if (hasCopyrightKeywords) {
        final matches = copyrightKeywordsPattern.allMatches(text);
        for (final match in matches) {
          debugPrint('🎯 매칭된 저작권 키워드: "${match.group(0)}"');
        }
        debugPrint('❌ 저작권 키워드 포함 - 제거: "$text"');
      } else {
        debugPrint('✅ 저작권 키워드 없음 - 통과: "$text"');
      }
    }
    
    return hasCopyrightKeywords;
  }

  /// 문장부호만 있는지 확인 (공백 + 구두점만)
  bool _isOnlyPunctuation(String text) {
    return onlyPunctuationPattern.hasMatch(text);
  }

  /// 중국어가 아닌 단어만 있는지 확인
  /// 
  /// **판단 기준:**
  /// - 중국어 문자가 포함되어 있으면 유지 (false 반환)
  /// - 중국어가 없고 영어나 기타 알파벳만 있으면 제거 (true 반환)
  bool _isNonChineseOnly(String text) {
    if (kDebugMode) {
      debugPrint('🔍 _isNonChineseOnly 검사: "$text"');
    }
    
    // 중국어가 포함되어 있으면 유지
    if (containsChinese(text)) {
      if (kDebugMode) {
        debugPrint('✅ 중국어 포함 - 유지: "$text"');
      }
      return false;
    }
    
    // 중국어가 없고, 영어나 기타 알파벳만 있는 경우 제거
    final hasAlphabets = RegExp(r'[a-zA-Z]').hasMatch(text);
    if (kDebugMode) {
      debugPrint('🔍 영어 알파벳 포함: $hasAlphabets, 텍스트: "$text"');
      if (hasAlphabets) {
        debugPrint('❌ 영어만 있는 텍스트 - 제거: "$text"');
      } else {
        debugPrint('✅ 영어가 아닌 텍스트 - 유지: "$text"');
      }
    }
    return hasAlphabets;
  }

  // ========== 캐시 관리 ==========

  /// **캐시 저장 헬퍼 메서드**
  /// 
  /// FIFO 방식으로 캐시 크기를 제한하면서 결과를 저장합니다.
  /// 캐시가 가득 차면 가장 오래된 항목을 제거합니다.
  /// 
  /// **매개변수:**
  /// - `cache`: 대상 캐시 맵
  /// - `key`: 캐시 키
  /// - `value`: 캐시 값
  void _saveToCache(Map<String, String> cache, String key, String value) {
    // 캐시 크기 제한 (FIFO 방식)
    if (cache.length >= _maxCacheSize) {
      // 가장 오래된 항목 제거
      final oldestKey = cache.keys.first;
      cache.remove(oldestKey);
    }
    cache[key] = value;
  }
}
