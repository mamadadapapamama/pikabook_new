import 'package:flutter/foundation.dart';
import '../../../core/models/processed_text.dart';

/// 텍스트 모드별 분리 서비스 (클라이언트 측 처리)
/// 
/// 사용 시나리오:
/// 1. 노트 생성 시: segment 모드만 클라이언트에서 처리 (paragraph는 LLM에서 처리)
/// 2. 설정 변경 후: 사용자가 텍스트 모드를 변경한 후 기존 노트를 새로운 모드로 재처리할 때
/// 
/// 주의: 일반적인 노트 로딩에서는 이미 처리된 캐시 데이터를 사용하므로 이 서비스를 사용하지 않음
/// 
class TextModeSeparationService {
  // 싱글톤 패턴
  static final TextModeSeparationService _instance = TextModeSeparationService._internal();
  factory TextModeSeparationService() => _instance;
  TextModeSeparationService._internal();

  /// 모드에 따라 텍스트 분리 (클라이언트 측)
  /// 
  /// [context] 사용 컨텍스트:
  /// - 'creation': 노트 생성 시 (segment 모드만 사용)
  /// - 'settings': 설정 변경 후 재처리 시 (모든 모드 사용)
  List<String> separateByMode(String text, TextProcessingMode mode, {String context = 'loading'}) {
    if (text.isEmpty) {
      if (kDebugMode) {
        debugPrint('TextModeSeparationService: 빈 텍스트 입력');
      }
      return [];
    }

    if (kDebugMode) {
      debugPrint('TextModeSeparationService: 텍스트 분리 시작 - 모드: $mode, 컨텍스트: $context, 길이: ${text.length}자');
    }

    List<String> result = [];
    
    switch (mode) {
      case TextProcessingMode.segment:
        result = splitIntoSentences(text);
        if (kDebugMode) {
          debugPrint('📝 문장 단위 분리 완료: ${result.length}개 문장');
        }
        break;
      case TextProcessingMode.paragraph:
        // 노트 생성 시에는 서버에서 처리하므로 경고 표시
        if (context == 'creation') {
          if (kDebugMode) {
            debugPrint('⚠️ 노트 생성 시 paragraph 모드는 서버에서 처리됩니다. 클라이언트 처리를 건너뜁니다.');
          }
          result = [text]; // 전체 텍스트를 그대로 반환
        } else {
          result = splitIntoParagraphs(text);
          if (kDebugMode) {
            debugPrint('📄 문단 단위 분리 완료: ${result.length}개 문단 (설정 변경 후 재처리)');
          }
        }
        break;
    }

    // 분리 실패시 전체 텍스트를 하나의 단위로 처리
    if (result.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ 분리 실패, 전체 텍스트를 하나의 단위로 처리');
      }
      result = [text];
    }

    if (kDebugMode) {
      debugPrint('✅ 텍스트 분리 완료: ${result.length}개 단위');
      for (int i = 0; i < result.length && i < 3; i++) {
        final preview = result[i].length > 30 
            ? '${result[i].substring(0, 30)}...' 
            : result[i];
        debugPrint('  ${i+1}: "$preview"');
      }
    }

    return result;
  }

  /// 문장 단위로 텍스트 분리
  List<String> splitIntoSentences(String text) {
    if (text.isEmpty) return [];

    if (kDebugMode) {
      debugPrint('문장 단위 분리 시작: ${text.length}자');
    }

    // 1단계: 줄바꿈으로 먼저 분리 (단원, 제목 등을 개별 처리하기 위해)
    final lines = text.split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final List<String> sentences = [];
    
    for (final line in lines) {
      if (kDebugMode) {
        debugPrint('🔍 줄 처리: "$line"');
      }
      
      // 단원/과 표시 패턴 감지 (예: "小一预备 第二课", "第一课", "Unit 1" 등)
      if (_isUnitOrLessonTitle(line)) {
        sentences.add(line);
        if (kDebugMode) {
          debugPrint('📚 단원/과 제목으로 분리: "$line"');
        }
        continue;
      }
      
      // 제목 패턴 감지 (짧고 구두점이 없는 줄)
      if (_isTitle(line)) {
        sentences.add(line);
        if (kDebugMode) {
          debugPrint('📝 제목으로 분리: "$line"');
        }
        continue;
      }
      
      // 일반 문장 처리
      final lineSentences = _splitLineIntoSentences(line);
      sentences.addAll(lineSentences);
    }

    // 빈 문장들 제거
    final filteredSentences = sentences
        .where((sentence) => sentence.trim().isNotEmpty)
        .toList();

    // 제목 재배치 수행
    final reorderedSentences = _reorderTitlesToTop(filteredSentences);

    if (kDebugMode) {
      debugPrint('문장 분리 및 제목 재배치 결과: ${reorderedSentences.length}개 문장');
      for (int i = 0; i < reorderedSentences.length; i++) {
        final preview = reorderedSentences[i].length > 30 
            ? '${reorderedSentences[i].substring(0, 30)}...' 
            : reorderedSentences[i];
        final isTitle = _isTitle(reorderedSentences[i]) || _isUnitOrLessonTitle(reorderedSentences[i]);
        debugPrint('  ${isTitle ? "📋" : "📝"} ${i+1}: "$preview"');
      }
    }

    return reorderedSentences;
  }

  /// 단원/과 제목인지 확인
  bool _isUnitOrLessonTitle(String line) {
    // 단원/과 관련 키워드 패턴
    final unitPatterns = [
      RegExp(r'第[一二三四五六七八九十\d]+课'),  // 第一课, 第2课 등
      RegExp(r'第[一二三四五六七八九十\d]+单元'), // 第一单元 등
      RegExp(r'小[一二三四五六\d]+预备'),      // 小一预备 등
      RegExp(r'Unit\s*\d+', caseSensitive: false), // Unit 1 등
      RegExp(r'Lesson\s*\d+', caseSensitive: false), // Lesson 1 등
      RegExp(r'Chapter\s*\d+', caseSensitive: false), // Chapter 1 등
    ];
    
    return unitPatterns.any((pattern) => pattern.hasMatch(line));
  }

  /// 제목인지 확인 (개선된 휴리스틱 방법)
  bool _isTitle(String line) {
    // 제목 판단 기준:
    // 1. 길이가 적당히 짧음 (1-20자) - 범위 확장
    // 2. 문장 구분자가 없음
    // 3. 숫자나 특수문자로만 이루어지지 않음
    // 4. 중국어 문자 포함
    // 5. 특별한 괄호나 기호로 둘러싸인 경우 (<<>>, <>, [], 등)
    
    if (line.length > 20 || line.length < 2) return false;
    
    // 특별한 제목 패턴 감지 (우선순위 높음)
    if (_hasSpecialTitleMarkers(line)) {
      if (kDebugMode) {
        debugPrint('📋 특별 제목 마커 감지: "$line"');
      }
      return true;
    }
    
    // 폰트 변화를 암시하는 패턴 (대문자, 반복 문자 등)
    if (_hasFontStyleIndicators(line)) {
      if (kDebugMode) {
        debugPrint('🔤 폰트 스타일 인디케이터 감지: "$line"');
      }
      return true;
    }
    
    // 문장 구분자가 있으면 제목이 아님
    if (RegExp(r'[。？！.!?，,]').hasMatch(line)) return false;
    
    // 숫자나 특수문자만 있으면 제목이 아님
    if (RegExp(r'^[\d\s\p{P}]+$', unicode: true).hasMatch(line)) return false;
    
    // 중국어 문자가 포함되어 있어야 함
    if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(line)) return false;
    
    return true;
  }
  
  /// 제목들을 적절한 위치로 재배치
  List<String> _reorderTitlesToTop(List<String> sentences) {
    if (sentences.isEmpty) return sentences;
    
    final List<String> result = [];
    final List<String> currentSection = [];
    String? currentTitle;
    
    if (kDebugMode) {
      debugPrint('🔄 제목 재배치 시작: ${sentences.length}개 문장');
    }
    
    for (int i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      final isTitle = _isTitle(sentence) || _isUnitOrLessonTitle(sentence);
      
      if (isTitle) {
        // 이전 섹션이 있으면 결과에 추가
        if (currentTitle != null || currentSection.isNotEmpty) {
          _addSectionToResult(result, currentTitle, currentSection);
        }
        
        // 새로운 제목 설정
        currentTitle = sentence;
        currentSection.clear();
        
        if (kDebugMode) {
          debugPrint('📋 새 제목 감지: "$sentence"');
        }
      } else {
        // 일반 문장을 현재 섹션에 추가
        currentSection.add(sentence);
      }
    }
    
    // 마지막 섹션 추가
    if (currentTitle != null || currentSection.isNotEmpty) {
      _addSectionToResult(result, currentTitle, currentSection);
    }
    
    if (kDebugMode) {
      debugPrint('✅ 제목 재배치 완료: ${result.length}개 문장');
    }
    
    return result;
  }
  
  /// 섹션을 결과에 추가 (제목을 맨 위로)
  void _addSectionToResult(List<String> result, String? title, List<String> content) {
    // 제목이 있으면 먼저 추가
    if (title != null) {
      result.add(title);
      if (kDebugMode) {
        debugPrint('📋 제목 추가: "$title"');
      }
    }
    
    // 내용 추가
    for (final sentence in content) {
      result.add(sentence);
      if (kDebugMode) {
        final preview = sentence.length > 20 ? '${sentence.substring(0, 20)}...' : sentence;
        debugPrint('📝 내용 추가: "$preview"');
      }
    }
    
    // 섹션 구분을 위한 로그
    if (title != null && content.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('📦 섹션 완료: "$title" (${content.length}개 문장)');
      }
    }
  }

  /// 특별한 제목 마커가 있는지 확인
  bool _hasSpecialTitleMarkers(String line) {
    // <<내용>>, <내용>, [내용], 【내용】, 《내용》 등의 패턴
    final titleMarkerPatterns = [
      RegExp(r'^<<.*>>$'),           // <<제목>>
      RegExp(r'^<.*>$'),             // <제목>
      RegExp(r'^\[.*\]$'),           // [제목]
      RegExp(r'^【.*】$'),            // 【제목】
      RegExp(r'^《.*》$'),            // 《제목》
      RegExp(r'^〈.*〉$'),            // 〈제목〉
      RegExp(r'^\*.*\*$'),           // *제목*
      RegExp(r'^=.*=$'),             // =제목=
    ];
    
    return titleMarkerPatterns.any((pattern) => pattern.hasMatch(line.trim()));
  }
  
  /// 폰트 스타일 인디케이터가 있는지 확인
  bool _hasFontStyleIndicators(String line) {
    final trimmed = line.trim();
    
    // 전체가 대문자인 경우 (영어)
    if (RegExp(r'^[A-Z\s\d]+$').hasMatch(trimmed) && trimmed.length > 2) {
      return true;
    }
    
    // 동일한 문자의 반복 (예: ======, -------)
    if (RegExp(r'^(.)\1{3,}$').hasMatch(trimmed)) {
      return true;
    }
    
    // 숫자와 점으로 시작하는 제목 (예: 1. 제목, 第一章. 등)
    if (RegExp(r'^[\d一二三四五六七八九十]+[.．、]\s*[\u4e00-\u9fff]').hasMatch(trimmed)) {
      return true;
    }
    
    return false;
  }

  /// 한 줄을 문장으로 분리 (정교한 분리 로직)
  List<String> _splitLineIntoSentences(String line) {
    if (line.isEmpty) return [];
    
    // OCR 줄바꿈 제거 (연속된 공백과 줄바꿈을 하나의 공백으로 처리)
    line = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    if (kDebugMode) {
      debugPrint('🔍 문장 분리 대상: "$line"');
    }
    
    final List<String> sentences = [];
    
    // 정교한 문장부호 분리 적용
    sentences.addAll(_splitByPunctuationMarks(line));
    
    // 빈 문장 제거
    final filteredSentences = sentences
        .where((s) => s.trim().isNotEmpty)
        .toList();
    
    if (kDebugMode) {
      debugPrint('📝 분리된 문장들: ${filteredSentences.length}개');
      for (int i = 0; i < filteredSentences.length; i++) {
        debugPrint('  ${i+1}: "${filteredSentences[i]}"');
      }
    }
    
    return filteredSentences;
  }

  /// 정교한 문장부호 기반 분리 (수정된 로직)
  List<String> _splitByPunctuationMarks(String text) {
    if (text.isEmpty) return [];
    
    if (kDebugMode) {
      debugPrint('🔪 문장부호 분리 시작: "$text"');
    }
    
    final List<String> segments = [];
    int currentStart = 0;
    
    // 문장부호별로 순차 처리
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      
      // 문장 끝 부호 (무조건 분리)
      if (RegExp(r'[。．.？！?!]').hasMatch(char)) {
        final segment = text.substring(currentStart, i + 1).trim();
        if (segment.isNotEmpty) {
          segments.add(segment);
          if (kDebugMode) {
            debugPrint('✂️ 문장끝 분리: "$segment"');
          }
        }
        currentStart = i + 1;
      }
      // 쉼표 (조건부 분리)
      else if (RegExp(r'[，,]').hasMatch(char)) {
        final segment = text.substring(currentStart, i + 1).trim();
        
        // 쉼표 분리 조건: 5글자 이상이거나 다음에 공백이 있는 경우
        final hasSpaceAfter = i + 1 < text.length && text[i + 1] == ' ';
        final isLongEnough = segment.length >= 5;
        
        if (segment.isNotEmpty && (isLongEnough || hasSpaceAfter)) {
          segments.add(segment);
          if (kDebugMode) {
            debugPrint('🔪 쉼표 분리: "$segment" (길이: ${segment.length}, 공백: $hasSpaceAfter)');
          }
          currentStart = i + 1;
        }
      }
      // 인용부호 시작 (짝 찾아서 처리)
      else if (RegExp(r'[""''「『【《〈]').hasMatch(char)) {
        final quoteEnd = _findMatchingQuote(text, i, char);
        if (quoteEnd != -1) {
          // 인용부호 앞부분이 있으면 먼저 추가
          if (i > currentStart) {
            final beforeQuote = text.substring(currentStart, i).trim();
            if (beforeQuote.isNotEmpty) {
              segments.add(beforeQuote);
              if (kDebugMode) {
                debugPrint('📝 인용부호 앞: "$beforeQuote"');
              }
            }
          }
          
          // 인용부호 포함 부분 추가
          final quoteSegment = text.substring(i, quoteEnd + 1).trim();
          if (quoteSegment.isNotEmpty) {
            segments.add(quoteSegment);
            if (kDebugMode) {
              debugPrint('💬 인용부호: "$quoteSegment"');
            }
          }
          
          currentStart = quoteEnd + 1;
          i = quoteEnd; // for 루프에서 i++되므로
        }
      }
    }
    
    // 남은 텍스트 처리
    if (currentStart < text.length) {
      final remaining = text.substring(currentStart).trim();
      if (remaining.isNotEmpty) {
        // 마지막 세그먼트가 너무 짧으면 이전과 합치기
        if (remaining.length <= 3 && segments.isNotEmpty) {
          segments[segments.length - 1] = '${segments.last}$remaining';
          if (kDebugMode) {
            debugPrint('🔗 마지막 세그먼트 합치기: "${segments.last}"');
          }
        } else {
          segments.add(remaining);
          if (kDebugMode) {
            debugPrint('📝 마지막 세그먼트: "$remaining"');
          }
        }
      }
    }
    
    if (kDebugMode) {
      debugPrint('✅ 문장부호 분리 완료: ${segments.length}개 세그먼트');
    }
    
    return segments;
  }
  
  /// 인용부호 짝 찾기 (간단한 로직)
  int _findMatchingQuote(String text, int startPos, String openQuote) {
    // 닫는 인용부호 결정
    String closeQuote;
    
    switch (openQuote) {
      case '"':
        closeQuote = '"';
        break;
      case '「':
        closeQuote = '」';
        break;
      case '『':
        closeQuote = '』';
        break;
      case '【':
        closeQuote = '】';
        break;
      case '《':
        closeQuote = '》';
        break;
      case '〈':
        closeQuote = '〉';
        break;
      default:
        // 기본적으로 동일한 문자로 닫기 (예: ' → ')
        closeQuote = openQuote;
        break;
    }
    
    // 닫는 인용부호 찾기
    for (int i = startPos + 1; i < text.length; i++) {
      if (text[i] == closeQuote) {
        if (kDebugMode) {
          debugPrint('💬 인용부호 짝 찾음: $openQuote → $closeQuote (${startPos} → ${i})');
        }
        return i;
      }
    }
    
    // 짝을 찾지 못한 경우 문장 끝까지
    if (kDebugMode) {
      debugPrint('⚠️ 인용부호 짝 없음: $openQuote, 문장 끝까지 처리');
    }
    return text.length - 1;
  }

  /// 쉼표로 분리해야 하는지 판단 (기존 로직 - 호환성 유지)
  bool _shouldSplitByComma(String line) {
    // 조건:
    // 1. 쉼표가 2개 이상 있음
    // 2. 문장이 충분히 길음 (20자 이상)
    // 3. 문장 구분자가 마지막에만 있거나 없음
    
    final commaCount = ',，'.split('').map((c) => line.split(c).length - 1).reduce((a, b) => a + b);
    
    if (commaCount < 2 || line.length < 20) return false;
    
    // 문장 구분자가 중간에 있으면 쉼표 분리 안함
    final sentenceDelimiters = RegExp(r'[。？！.!?]');
    final matches = sentenceDelimiters.allMatches(line).toList();
    
    // 문장 구분자가 마지막 3글자 안에만 있어야 함
    if (matches.isNotEmpty) {
      final lastMatch = matches.last;
      if (lastMatch.start < line.length - 3) return false;
    }
    
    return true;
  }

  /// 첫 번째 쉼표에서 분리
  List<String> _splitByFirstComma(String line) {
    final commaPattern = RegExp(r'[,，]');
    final match = commaPattern.firstMatch(line);
    
    if (match == null) return [line];
    
    final firstPart = line.substring(0, match.end).trim();
    final secondPart = line.substring(match.end).trim();
    
    final List<String> result = [];
    
    if (firstPart.isNotEmpty) {
      result.add(firstPart);
      if (kDebugMode) {
        debugPrint('🔪 쉼표 분리 1: "$firstPart"');
      }
    }
    
    if (secondPart.isNotEmpty) {
      // 두 번째 부분도 재귀적으로 처리
      final secondPartSentences = _splitBySentenceDelimiters(secondPart);
      result.addAll(secondPartSentences);
      if (kDebugMode) {
        debugPrint('🔪 쉼표 분리 2: "$secondPart"');
      }
    }
    
    return result;
  }

  /// 문장 구분자로 분리
  List<String> _splitBySentenceDelimiters(String text) {
    // 중국어 문장 구분자 (마침표, 물음표, 느낌표 등)
    final sentenceDelimiters = RegExp(r'[。？！.!?]');
    
    final List<String> sentences = [];
    int startIndex = 0;
    
    // 구분자로 분리
    for (int i = 0; i < text.length; i++) {
      if (i == text.length - 1 || sentenceDelimiters.hasMatch(text[i])) {
        final endIndex = i + 1;
        if (endIndex > startIndex) {
          final sentence = text.substring(startIndex, endIndex).trim();
          if (sentence.isNotEmpty) {
            sentences.add(sentence);
          }
          startIndex = endIndex;
        }
      }
    }
    
    // 남은 부분이 있으면 추가
    if (startIndex < text.length) {
      final remaining = text.substring(startIndex).trim();
      if (remaining.isNotEmpty) {
        sentences.add(remaining);
      }
    }
    
    return sentences;
  }

  /// 문단 단위로 텍스트 분리 (설정 변경 후 재처리 시 사용)
  /// 
  /// 노트 생성 시에는 LLM에서 의미 단위로 분리하므로 이 메서드는 사용하지 않음
  /// 사용자가 설정에서 텍스트 모드를 변경한 후 기존 노트를 재처리할 때만 사용
  List<String> splitIntoParagraphs(String text) {
    if (text.isEmpty) return [];

    if (kDebugMode) {
      debugPrint('문단 단위 분리 시작: ${text.length}자');
    }

    // 방법 1: 연속된 줄바꿈으로 문단 구분
    List<String> paragraphs = text.split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    // 방법 1이 실패한 경우 방법 2: 단일 줄바꿈으로 분리
    if (paragraphs.length <= 1) {
      paragraphs = text.split('\n')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
    }

    // 방법 2도 실패한 경우 방법 3: 문장 구분자 기반으로 긴 단위로 분리
    if (paragraphs.length <= 1) {
      final sentences = splitIntoSentences(text);
      
      // 문장들을 적절한 크기의 문단으로 그룹화 (3-5문장씩)
      paragraphs = [];
      const int sentencesPerParagraph = 3;
      
      for (int i = 0; i < sentences.length; i += sentencesPerParagraph) {
        final endIndex = (i + sentencesPerParagraph < sentences.length) 
            ? i + sentencesPerParagraph 
            : sentences.length;
        
        final paragraphSentences = sentences.sublist(i, endIndex);
        final paragraph = paragraphSentences.join(' ');
        
        if (paragraph.trim().isNotEmpty) {
          paragraphs.add(paragraph.trim());
        }
      }
    }

    if (kDebugMode) {
      debugPrint('문단 분리 결과: ${paragraphs.length}개 문단');
    }

    return paragraphs;
  }

  /// 노트 생성 시 사용 (segment 모드만)
  List<String> separateForCreation(String text, TextProcessingMode mode) {
    if (mode == TextProcessingMode.paragraph) {
      if (kDebugMode) {
        debugPrint('⚠️ 노트 생성 시 paragraph 모드는 서버에서 처리됩니다.');
      }
      return [text]; // 서버에서 처리할 전체 텍스트 반환
    }
    
    return separateByMode(text, mode, context: 'creation');
  }
  
  /// 설정 변경 후 재처리 시 사용 (모든 모드)
  List<String> separateForSettingsChange(String text, TextProcessingMode mode) {
    return separateByMode(text, mode, context: 'settings');
  }

  /// 텍스트 분리 미리보기 (디버깅용)
  Map<String, dynamic> previewSeparation(String text) {
    if (text.isEmpty) {
      return {
        'sentences': [],
        'paragraphs': [],
        'summary': '빈 텍스트'
      };
    }

    final sentences = splitIntoSentences(text);
    final paragraphs = splitIntoParagraphs(text);

    return {
      'sentences': sentences,
      'paragraphs': paragraphs,
      'summary': {
        'originalLength': text.length,
        'sentenceCount': sentences.length,
        'paragraphCount': paragraphs.length,
      }
    };
  }
}
