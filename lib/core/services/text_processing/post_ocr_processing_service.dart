import 'package:flutter/foundation.dart';

/// **OCR 후처리 서비스**
/// 
/// OCR 결과를 정리하고 재구성하는 포괄적인 서비스입니다.
/// 
/// **주요 기능:**
/// 1. **텍스트 정리**: 불필요한 텍스트 제거 및 중국어 텍스트만 추출
/// 2. **제목 감지**: 글꼴 크기/두께/정렬 정보를 기반으로 제목 후보 식별
/// 3. **문장 재배열**: 제목을 상단으로 이동하고 논리적 순서로 재구성
/// 4. **핀인 처리**: 병음 줄 자동 감지 및 제거
/// 
/// **처리 순서:**
/// 1. 핀인 줄 제거
/// 2. 불필요한 텍스트 필터링
/// 3. 제목 후보 감지
/// 4. 문장 재배열 (제목 → 본문)
/// 
/// **사용 예시:**
/// ```dart
/// final processor = PostOcrProcessingService();
/// final result = processor.processOcrResult(ocrText, ocrMetadata);
/// final reorderedText = result.reorderedText;
/// final titleCandidates = result.titleCandidates;
/// ```
class PostOcrProcessingService {
  // ========== 싱글톤 패턴 ==========
  static final PostOcrProcessingService _instance = PostOcrProcessingService._internal();
  factory PostOcrProcessingService() => _instance;
  PostOcrProcessingService._internal();

  // ========== 정규식 패턴 상수 ==========
  
  /// 중국어 문자 범위 (유니코드 4E00-9FFF)
  static final RegExp chineseCharPattern = RegExp(r'[\u4e00-\u9fff]');

  /// 핀인(병음) 성조 기호 목록
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
  
  /// 숫자만 있는 패턴
  static final RegExp onlyNumbersPattern = RegExp(r'^[0-9]+$');
  
  /// 문장부호만 있는 패턴
  static final RegExp onlyPunctuationPattern = RegExp(r'^[\s\p{P}]+$', unicode: true);
  
  /// 페이지 번호 패턴
  static final RegExp pageNumberPattern = RegExp(r'^(?:page\s*)?[0-9]+(?:\s*页)?$', caseSensitive: false);
  
  /// 저작권 및 특수 문자 패턴
  static final RegExp copyrightPattern = RegExp(r'^[^a-zA-Z\u4e00-\u9fff]*[©®™@#$%^&*+-]+[^a-zA-Z\u4e00-\u9fff]*$');

  /// 저작권 관련 키워드 패턴
  static final RegExp copyrightKeywordsPattern = RegExp(
    r'(copyright|all rights reserved|版权所有|保留所有权利|ltd\.?|inc\.?|corp\.?|company|pte\.?\s*ltd\.?|limited|international.*\(\d{4}\)|rights?\s+reserved)',
    caseSensitive: false,
  );

  /// 숫자와 특수문자 혼합 패턴
  static final RegExp numberSpecialCharPattern = RegExp(
    r'^[\d\s]*[\d]+[\s]*[:/\-%.]+[\s]*[\d]+[\s]*[:/\-%.]*[\d]*[\s]*$|'
    r'^[\d]+[%]+$|'
    r'^[\d]+\.[\d]+$|'
    r'^[\d]{4}\.[\d]{2}\.[\d]{2}$|'
    r'^[\d]{1,2}:[\d]{2}(-[\d]{1,2}:[\d]{2})?$'
  );

  /// 단순 숫자 조합 패턴
  static final RegExp simpleNumberCombinationPattern = RegExp(r'^[\d\s]+$');

  // ========== 제목 감지 관련 패턴 ==========
  
  /// 제목 가능성이 높은 문장 길이 범위 (중국어 기준)
  static const int titleMinLength = 2;
  static const int titleMaxLength = 20;
  
  /// 제목에서 흔히 사용되는 중국어 키워드
  static final RegExp titleKeywordsPattern = RegExp(
    r'(第.*章|第.*节|第.*课|第.*部分|第.*单元|.*的.*|.*与.*|.*和.*|如何.*|为什么.*|什么是.*|关于.*|论.*|.*研究|.*分析|.*概述|.*简介)',
  );
  
  /// 문장 끝 구두점 패턴
  static final RegExp sentenceEndPattern = RegExp(r'[。！？]$');

  // ========== 캐시 시스템 ==========
  final Map<String, OcrProcessingResult> _processingCache = {};
  final int _maxCacheSize = 50;

  // ========== 주요 공개 메서드 ==========

  /// **메인 OCR 후처리 메서드**
  /// 
  /// OCR 결과를 정리하고 재구성합니다.
  /// 
  /// **매개변수:**
  /// - `ocrText`: OCR로 추출된 원본 텍스트
  /// - `ocrMetadata`: OCR 메타데이터 (글꼴 정보, 위치 정보 등) - 선택사항
  /// 
  /// **반환값:**
  /// - `OcrProcessingResult`: 처리된 결과 객체
  OcrProcessingResult processOcrResult(String ocrText, {Map<String, dynamic>? ocrMetadata}) {
    if (ocrText.isEmpty) {
      return OcrProcessingResult.empty();
    }

    // 캐시 확인
    final cacheKey = _generateCacheKey(ocrText, ocrMetadata);
    if (_processingCache.containsKey(cacheKey)) {
      if (kDebugMode) {
        debugPrint('📋 캐시에서 결과 반환: $cacheKey');
      }
      return _processingCache[cacheKey]!;
    }

    if (kDebugMode) {
      debugPrint('🔄 OCR 후처리 시작');
      debugPrint('📄 원본 텍스트: "$ocrText"');
    }

    // 1단계: 기본 텍스트 정리
    String cleanedText = _cleanText(ocrText);
    
    if (cleanedText.isEmpty) {
      final emptyResult = OcrProcessingResult.empty();
      _saveToCache(cacheKey, emptyResult);
      return emptyResult;
    }

    // 2단계: 문장 분리 및 분석
    final sentences = _splitIntoSentences(cleanedText);
    
    // 3단계: 제목 후보 감지
    final titleAnalysis = _analyzeTitleCandidates(sentences, ocrMetadata);
    
    // 4단계: 문장 재배열 (제목 → 본문)
    final reorderedSentences = _reorderSentences(sentences, titleAnalysis.titleIndices);
    
    // 5단계: 결과 생성
    final result = OcrProcessingResult(
      originalText: ocrText,
      cleanedText: cleanedText,
      reorderedText: reorderedSentences.join('\n'),
      titleCandidates: titleAnalysis.titleCandidates,
      bodyText: titleAnalysis.bodyText,
      processingSteps: titleAnalysis.processingSteps,
    );

    if (kDebugMode) {
      debugPrint('✅ OCR 후처리 완료');
      debugPrint('📋 제목 후보: ${result.titleCandidates.length}개');
      debugPrint('📄 재배열된 텍스트: "${result.reorderedText}"');
    }

    // 캐시 저장
    _saveToCache(cacheKey, result);
    
    return result;
  }

  /// **레거시 호환: 기본 텍스트 정리만 수행**
  String cleanText(String text) {
    return _cleanText(text);
  }

  /// **중국어 포함 여부 확인**
  bool containsChinese(String text) {
    return chineseCharPattern.hasMatch(text);
  }

  /// **중국어 문자만 추출**
  String extractChineseChars(String text) {
    if (text.isEmpty) return '';
    final matches = chineseCharPattern.allMatches(text);
    final buffer = StringBuffer();
    for (final match in matches) {
      buffer.write(match.group(0));
    }
    return buffer.toString();
  }

  // ========== 내부 처리 메서드 ==========

  /// 기본 텍스트 정리 (기존 cleanText 로직)
  String _cleanText(String text) {
    if (text.isEmpty) return text;

    // 핀인 줄 제거
    text = _removePinyinLines(text);

    // 줄 단위로 분리하여 각각 검사
    final lines = text.split('\n');
    final cleanedLines = <String>[];

    for (final line in lines) {
      final trimmedLine = line.trim();

      if (trimmedLine.isEmpty) continue;
      if (_isOnlyNumbers(trimmedLine)) continue;
      if (_isNumberSpecialCharMix(trimmedLine)) continue;
      if (_isPageNumber(trimmedLine)) continue;
      if (_isCopyrightOrSpecialChars(trimmedLine)) continue;
      if (_isCopyrightKeywordLine(trimmedLine)) continue;
      if (_isOnlyPunctuation(trimmedLine)) continue;
      if (_isMeaninglessMixedText(trimmedLine)) continue;
      if (_isNonChineseOnly(trimmedLine)) continue;

      cleanedLines.add(trimmedLine);
    }

    return cleanedLines.join('\n');
  }

  /// 문장 분리
  List<String> _splitIntoSentences(String text) {
    return text.split('\n').where((s) => s.trim().isNotEmpty).toList();
  }

  /// 제목 후보 분석
  TitleAnalysisResult _analyzeTitleCandidates(List<String> sentences, Map<String, dynamic>? metadata) {
    final titleCandidates = <TitleCandidate>[];
    final titleIndices = <int>[];
    final bodyText = <String>[];
    final processingSteps = <String>[];

    processingSteps.add('제목 후보 분석 시작: ${sentences.length}개 문장');

    for (int i = 0; i < sentences.length; i++) {
      final sentence = sentences[i].trim();
      final titleScore = _calculateTitleScore(sentence, i, sentences.length, metadata);
      
      if (titleScore.isTitle) {
        titleCandidates.add(TitleCandidate(
          text: sentence,
          originalIndex: i,
          confidence: titleScore.confidence,
          reasons: titleScore.reasons,
        ));
        titleIndices.add(i);
        processingSteps.add('제목 감지: "$sentence" (신뢰도: ${titleScore.confidence.toStringAsFixed(2)})');
      } else {
        bodyText.add(sentence);
      }
    }

    processingSteps.add('제목 후보: ${titleCandidates.length}개, 본문: ${bodyText.length}개');

    return TitleAnalysisResult(
      titleCandidates: titleCandidates,
      titleIndices: titleIndices,
      bodyText: bodyText,
      processingSteps: processingSteps,
    );
  }

  /// 제목 점수 계산
  TitleScoreResult _calculateTitleScore(String sentence, int index, int totalSentences, Map<String, dynamic>? metadata) {
    double score = 0.0;
    final reasons = <String>[];
    
    // 1. 문장 길이 점수 (적당한 길이의 제목 선호)
    final length = sentence.length;
    if (length >= titleMinLength && length <= titleMaxLength) {
      final lengthScore = 1.0 - (length - titleMinLength) / (titleMaxLength - titleMinLength);
      score += lengthScore * 0.3;
      reasons.add('적절한 길이 (${length}자)');
    }

    // 2. 위치 점수 (상단 위치 선호)
    if (index == 0) {
      score += 0.4;
      reasons.add('첫 번째 문장');
    } else if (index == 1) {
      score += 0.3;
      reasons.add('두 번째 문장');
    } else if (index <= 2) {
      score += 0.2;
      reasons.add('상단 위치');
    }

    // 3. 제목 키워드 점수
    if (titleKeywordsPattern.hasMatch(sentence)) {
      score += 0.2;
      reasons.add('제목 키워드 포함');
    }

    // 4. 문장 끝 구두점 점수 (제목은 보통 구두점이 없음)
    if (!sentenceEndPattern.hasMatch(sentence)) {
      score += 0.15;
      reasons.add('문장 끝 구두점 없음');
    }

    // 5. 중국어 포함 여부 (필수)
    if (!containsChinese(sentence)) {
      score = 0.0;
      reasons.clear();
      reasons.add('중국어 미포함');
    }

    // 6. OCR 메타데이터 기반 점수 (향후 확장)
    if (metadata != null) {
      // TODO: 글꼴 크기, 두께, 정렬 정보 활용
      // final fontMetadata = _extractFontMetadata(metadata, index);
      // score += _calculateFontScore(fontMetadata);
    }

    final isTitle = score >= 0.6; // 임계값

    return TitleScoreResult(
      confidence: score,
      isTitle: isTitle,
      reasons: reasons,
    );
  }

  /// 문장 재배열 (제목 후보를 상단으로)
  List<String> _reorderSentences(List<String> sentences, List<int> titleIndices) {
    final reordered = <String>[];
    final titleSet = titleIndices.toSet();

    // 1. 제목들을 먼저 추가 (원래 순서 유지)
    for (int i = 0; i < sentences.length; i++) {
      if (titleSet.contains(i)) {
        reordered.add(sentences[i]);
      }
    }

    // 2. 본문들을 추가 (원래 순서 유지)
    for (int i = 0; i < sentences.length; i++) {
      if (!titleSet.contains(i)) {
        reordered.add(sentences[i]);
      }
    }

    return reordered;
  }

  // ========== 핀인 관련 메서드 (기존 로직 유지) ==========

  bool _isPinyinLine(String line) {
    return !containsChinese(line) &&
        pinyinPattern.allMatches(line).length > 0 &&
        line.trim().split(' ').every(
            (word) => pinyinPattern.hasMatch(word) || word.trim().isEmpty);
  }

  String _removePinyinLines(String text) {
    if (text.isEmpty) return text;
    final lines = text.split('\n');
    final filteredLines = lines.where((line) => !_isPinyinLine(line)).toList();
    return filteredLines.join('\n');
  }

  // ========== 검증 메서드들 (기존 로직 유지) ==========

  bool _isOnlyNumbers(String text) => onlyNumbersPattern.hasMatch(text);
  bool _isPageNumber(String text) => pageNumberPattern.hasMatch(text);
  bool _isCopyrightOrSpecialChars(String text) => copyrightPattern.hasMatch(text) && !containsChinese(text);
  bool _isCopyrightKeywordLine(String text) => copyrightKeywordsPattern.hasMatch(text);
  bool _isOnlyPunctuation(String text) => onlyPunctuationPattern.hasMatch(text);

  bool _isNonChineseOnly(String text) {
    if (containsChinese(text)) return false;
    final hasOtherLanguages = RegExp(r'[a-zA-Z가-힣ㄱ-ㅎㅏ-ㅣ\u3040-\u309F\u30A0-\u30FF]').hasMatch(text);
    return hasOtherLanguages;
  }

  bool _isNumberSpecialCharMix(String text) {
    if (containsChinese(text)) {
      final chineseCharCount = chineseCharPattern.allMatches(text).length;
      final totalLength = text.replaceAll(RegExp(r'\s+'), '').length;
      if (chineseCharCount / totalLength >= 0.5) return false;
    }
    return numberSpecialCharPattern.hasMatch(text) || simpleNumberCombinationPattern.hasMatch(text);
  }

  bool _isMeaninglessMixedText(String text) {
    if (!containsChinese(text)) return false;
    
    final cleanText = text.replaceAll(RegExp(r'\s+'), '');
    final totalChars = cleanText.length;
    final chineseCharCount = chineseCharPattern.allMatches(text).length;
    final englishCharCount = RegExp(r'[a-zA-Z]').allMatches(text).length;
    final hasDigits = RegExp(r'[0-9]').hasMatch(text);
    
    // 짧은 혼재 문장
    if (totalChars <= 15 && chineseCharCount >= 1 && englishCharCount >= 1 && hasDigits) {
      return true;
    }
    
    // OCR 오류 패턴
    if (chineseCharCount <= 2 && englishCharCount >= chineseCharCount * 2) {
      return true;
    }
    
    return false;
  }

  // ========== 캐시 관리 ==========

  String _generateCacheKey(String text, Map<String, dynamic>? metadata) {
    final metaKey = metadata?.toString() ?? '';
    return '${text.hashCode}_${metaKey.hashCode}';
  }

  void _saveToCache(String key, OcrProcessingResult result) {
    if (_processingCache.length >= _maxCacheSize) {
      final oldestKey = _processingCache.keys.first;
      _processingCache.remove(oldestKey);
    }
    _processingCache[key] = result;
  }
}

// ========== 결과 클래스들 ==========

/// OCR 후처리 결과
class OcrProcessingResult {
  final String originalText;
  final String cleanedText;
  final String reorderedText;
  final List<TitleCandidate> titleCandidates;
  final List<String> bodyText;
  final List<String> processingSteps;

  OcrProcessingResult({
    required this.originalText,
    required this.cleanedText,
    required this.reorderedText,
    required this.titleCandidates,
    required this.bodyText,
    required this.processingSteps,
  });

  factory OcrProcessingResult.empty() {
    return OcrProcessingResult(
      originalText: '',
      cleanedText: '',
      reorderedText: '',
      titleCandidates: [],
      bodyText: [],
      processingSteps: ['빈 텍스트 - 처리 없음'],
    );
  }

  bool get hasTitle => titleCandidates.isNotEmpty;
  bool get hasContent => bodyText.isNotEmpty;
}

/// 제목 후보
class TitleCandidate {
  final String text;
  final int originalIndex;
  final double confidence;
  final List<String> reasons;

  TitleCandidate({
    required this.text,
    required this.originalIndex,
    required this.confidence,
    required this.reasons,
  });

  @override
  String toString() => 'TitleCandidate("$text", confidence: ${confidence.toStringAsFixed(2)})';
}

/// 제목 분석 결과 (내부용)
class TitleAnalysisResult {
  final List<TitleCandidate> titleCandidates;
  final List<int> titleIndices;
  final List<String> bodyText;
  final List<String> processingSteps;

  TitleAnalysisResult({
    required this.titleCandidates,
    required this.titleIndices,
    required this.bodyText,
    required this.processingSteps,
  });
}

/// 제목 점수 계산 결과 (내부용)
class TitleScoreResult {
  final double confidence;
  final bool isTitle;
  final List<String> reasons;

  TitleScoreResult({
    required this.confidence,
    required this.isTitle,
    required this.reasons,
  });
} 