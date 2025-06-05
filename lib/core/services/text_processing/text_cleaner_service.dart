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



  /// 숫자와 특수문자 혼합 패턴 (시간, 점수, 비율 등)
  /// 예: 10:30, 90/100, 3.5, 85%, 1-5, 2022.03.15, 12:00-13:00
  static final RegExp numberSpecialCharPattern = RegExp(
    r'^[\d\s]*[\d]+[\s]*[:/\-%.]+[\s]*[\d]+[\s]*[:/\-%.]*[\d]*[\s]*$|'  // 시간, 점수, 비율 패턴
    r'^[\d]+[%]+$|'                                                      // 퍼센트 패턴 (85%)
    r'^[\d]+\.[\d]+$|'                                                   // 소수점 패턴 (3.5)
    r'^[\d]{4}\.[\d]{2}\.[\d]{2}$|'                                     // 날짜 패턴 (2022.03.15)
    r'^[\d]{1,2}:[\d]{2}(-[\d]{1,2}:[\d]{2})?$'                        // 시간 범위 패턴 (12:00-13:00)
  );

  /// 단순 숫자 조합 패턴 (예: "1 2 3", "123 456")
  static final RegExp simpleNumberCombinationPattern = RegExp(r'^[\d\s]+$');

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

      // 숫자와 특수문자 혼합 패턴 건너뛰기 (시간, 점수 등)
      if (_isNumberSpecialCharMix(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 숫자+특수문자 혼합 패턴 건너뛰기: "$trimmedLine"');
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

      // 의미없는 혼재 문장 제거 (OCR 오류 등)
      if (_isMeaninglessMixedText(trimmedLine)) {
        if (kDebugMode) {
          debugPrint('🧹 의미없는 혼재 문장 건너뛰기: "$trimmedLine"');
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
  /// - 중국어가 없고 영어, 한국어, 일본어만 있으면 제거 (true 반환)
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
    
    // 중국어가 없는 상태에서 다른 언어만 있는지 확인
    final hasEnglish = RegExp(r'[a-zA-Z]').hasMatch(text);
    final hasKorean = RegExp(r'[가-힣ㄱ-ㅎㅏ-ㅣ]').hasMatch(text);
    final hasJapanese = RegExp(r'[\u3040-\u309F\u30A0-\u30FF]').hasMatch(text);
    
    final hasOtherLanguages = hasEnglish || hasKorean || hasJapanese;
    
    if (kDebugMode) {
      debugPrint('🔍 언어 분석:');
      debugPrint('   영어: $hasEnglish');
      debugPrint('   한국어: $hasKorean');
      debugPrint('   일본어: $hasJapanese');
      debugPrint('   다른 언어 포함: $hasOtherLanguages');
      
      if (hasOtherLanguages) {
        final languages = <String>[];
        if (hasEnglish) languages.add('영어');
        if (hasKorean) languages.add('한국어');
        if (hasJapanese) languages.add('일본어');
        debugPrint('❌ ${languages.join(', ')}만 있는 텍스트 - 제거: "$text"');
      } else {
        debugPrint('✅ 중국어 학습 관련 텍스트 - 유지: "$text"');
      }
    }
    
    return hasOtherLanguages;
  }

  /// 숫자와 특수문자 혼합 패턴인지 확인 (시간, 점수, 비율 등)
  /// 
  /// **제거되는 패턴들:**
  /// - 시간: 10:30, 12:00-13:00
  /// - 점수/비율: 90/100, 85%
  /// - 소수점: 3.5, 12.8
  /// - 날짜: 2022.03.15
  /// - 범위: 1-5, 10-20
  /// - 단순 숫자 조합: "1 2 3", "123 456"
  bool _isNumberSpecialCharMix(String text) {
    if (kDebugMode) {
      debugPrint('🔍 숫자+특수문자 혼합 패턴 검사: "$text"');
    }
    
    // 중국어가 포함되어 있으면 혼재 문장 검사는 다른 함수에서 처리
    // 순수한 중국어 문장은 여기서 유지
    if (containsChinese(text)) {
      // 중국어만 있거나 중국어가 주를 이루는 경우는 유지
      final chineseCharCount = chineseCharPattern.allMatches(text).length;
      final totalLength = text.replaceAll(RegExp(r'\s+'), '').length;
      
      // 중국어 비율이 50% 이상이면 유지 (혼재 문장은 다른 함수에서 처리)
      if (chineseCharCount / totalLength >= 0.5) {
        if (kDebugMode) {
          debugPrint('✅ 중국어 주도 문장 - 유지: "$text"');
        }
        return false;
      }
    }
    
    // 숫자와 특수문자 혼합 패턴 확인
    final isNumberSpecialMix = numberSpecialCharPattern.hasMatch(text);
    
    // 단순 숫자 조합 패턴 확인
    final isSimpleNumberCombo = simpleNumberCombinationPattern.hasMatch(text);
    
    final shouldRemove = isNumberSpecialMix || isSimpleNumberCombo;
    
    if (kDebugMode) {
      if (shouldRemove) {
        if (isNumberSpecialMix) {
          debugPrint('❌ 숫자+특수문자 혼합 패턴 - 제거: "$text"');
        }
        if (isSimpleNumberCombo) {
          debugPrint('❌ 단순 숫자 조합 패턴 - 제거: "$text"');
        }
      } else {
        debugPrint('✅ 숫자+특수문자 패턴 아님 - 유지: "$text"');
      }
    }
    
    return shouldRemove;
  }

  /// 의미없는 혼재 문장인지 확인 (OCR 오류 등)
  /// 
  /// **제거 조건:**
  /// - 15자 이하에서 중국어 + 영어 + 숫자가 동시에 있는 경우
  /// - 중국어 1-2자 + 영어가 더 많은 경우 (OCR 오류)
  /// - 예: "让tol translate 8", "学a1", "好test 2"
  bool _isMeaninglessMixedText(String text) {
    if (kDebugMode) {
      debugPrint('🔍 의미없는 혼재 문장 검사: "$text"');
    }
    
    // 중국어가 없으면 다른 규칙에서 처리
    if (!containsChinese(text)) {
      return false;
    }
    
    // 공백 제외한 총 문자 수
    final cleanText = text.replaceAll(RegExp(r'\s+'), '');
    final totalChars = cleanText.length;
    
    // 문자 분석
    final chineseCharCount = chineseCharPattern.allMatches(text).length;
    final englishCharCount = RegExp(r'[a-zA-Z]').allMatches(text).length;
    final hasDigits = RegExp(r'[0-9]').hasMatch(text);
    
    // 패턴 1: 15자 이하 + 중국어 + 영어 + 숫자 모두 존재
    if (totalChars <= 15 && chineseCharCount >= 1 && englishCharCount >= 1 && hasDigits) {
      if (kDebugMode) {
        debugPrint('❌ 패턴1 - 짧은 혼재 문장 제거: "$text" (길이: $totalChars, 중: ${chineseCharCount}개, 영: ${englishCharCount}개, 숫자: $hasDigits)');
      }
      return true;
    }
    
    // 패턴 2: 중국어 1-2자 + 영어가 중국어의 2배 이상
    if (chineseCharCount <= 2 && englishCharCount >= chineseCharCount * 2) {
      if (kDebugMode) {
        debugPrint('❌ 패턴2 - OCR 오류 문장 제거: "$text" (중: ${chineseCharCount}개, 영: ${englishCharCount}개)');
      }
      return true;
    }
    
    if (kDebugMode) {
      debugPrint('✅ 정상 문장 - 유지: "$text" (중: ${chineseCharCount}개, 영: ${englishCharCount}개, 숫자: $hasDigits)');
    }
    
    return false;
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
