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

  // 상수 정의
  static const _sentenceDelimitersPattern = r'[。？！.!?]';
  static const _commaPattern = r'[，,]';
  static const _quotationPattern = r'[""]';
  
  static final _sentenceDelimiters = RegExp(_sentenceDelimitersPattern);
  static final _commaRegex = RegExp(_commaPattern);
  static final _quotationRegex = RegExp(_quotationPattern);

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

  /// 문장 단위로 텍스트 분리 (순차적 4단계 처리)
  List<String> splitIntoSentences(String text) {
    if (text.isEmpty) return [];

    if (kDebugMode) {
      debugPrint('📋 문장 단위 분리 시작: ${text.length}자');
    }

    // 줄바꿈으로 먼저 분리
    final lines = text.split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (kDebugMode) {
      debugPrint('📄 총 ${lines.length}개 줄 감지');
    }

    // === 1단계: 첫 3줄 분석 후 제목 확정 ===
    final titleLines = <String>[];
    final contentLines = <String>[];
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (i < 3 && (_isUnitOrLessonTitle(line) || _isTitle(line))) {
        titleLines.add(line);
        if (kDebugMode) {
          debugPrint('📋 1단계 제목 확정: "$line"');
        }
      } else {
        contentLines.add(line);
      }
    }

    // === 2단계: 나머지 줄 분석 - 문장 부호로 분리 ===
    final rawSegments = <String>[];
    
    for (final line in contentLines) {
      if (kDebugMode) {
        debugPrint('🔍 2단계 줄 처리: "$line"');
      }
      
      final lineSegments = _splitLineIntoSentences(line);
      rawSegments.addAll(lineSegments);
    }

    if (kDebugMode) {
      debugPrint('📝 2단계 완료: ${rawSegments.length}개 원시 세그먼트');
    }

    // === 3단계: 4자 미만 세그먼트를 뒷 문장과 조합 후 재분리 ===
    final mergedSegments = _mergeShortSegmentsAndResplit(rawSegments);

    if (kDebugMode) {
      debugPrint('🔗 3단계 완료: ${mergedSegments.length}개 병합 세그먼트');
    }

    // === 4단계: 세그먼트 리스팅 (제목 + 내용) ===
    final finalSegments = <String>[];
    finalSegments.addAll(titleLines);
    finalSegments.addAll(mergedSegments);

    // 빈 문장들 제거
    final filteredSegments = finalSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList();

    if (kDebugMode) {
      debugPrint('✅ 4단계 최종 완료: ${filteredSegments.length}개 세그먼트');
      for (int i = 0; i < filteredSegments.length; i++) {
        final preview = filteredSegments[i].length > 30 
            ? '${filteredSegments[i].substring(0, 30)}...' 
            : filteredSegments[i];
        final isTitle = titleLines.contains(filteredSegments[i]);
        debugPrint('  ${isTitle ? "📋" : "📝"} ${i+1}: "$preview"');
      }
    }

    return filteredSegments;
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

  /// 제목인지 확인 (엄격한 기준 적용)
  bool _isTitle(String line) {
    // 제목 판단 기준 (더 엄격하게):
    // 1. 길이가 짧음 (2-8자로 제한) - 긴 문장은 제목이 아님
    // 2. 문장 구분자가 전혀 없음 (쉼표, 마침표 등)
    // 3. 숫자나 특수문자로만 이루어지지 않음
    // 4. 중국어 문자 포함
    // 5. 특별한 괄호나 기호로 둘러싸인 경우
    
    if (line.length > 8 || line.length < 2) return false;
    
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
    
    // 문장 구분자가 있으면 제목이 아님 (엄격하게)
    if (RegExp(r'[。？！.!?，,、；;：:]').hasMatch(line)) return false;
    
    // 숫자나 특수문자만 있으면 제목이 아님
    if (RegExp(r'^[\d\s\p{P}]+$', unicode: true).hasMatch(line)) return false;
    
    // 중국어 문자가 포함되어 있어야 함
    if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(line)) return false;
    
    return true;
  }
  
  /// 3단계: 4자 미만 세그먼트를 뒷 문장과 조합 후 재분리
  List<String> _mergeShortSegmentsAndResplit(List<String> segments) {
    if (segments.isEmpty) return segments;

    if (kDebugMode) {
      debugPrint('🔗 3단계 시작: 짧은 세그먼트 병합 및 재분리');
    }

    final result = <String>[];
    
    for (int i = 0; i < segments.length; i++) {
      final current = segments[i];
      
      // 현재 세그먼트가 6자 미만이고 다음 세그먼트가 있는 경우
      if (current.length < 6 && i + 1 < segments.length) {
        final next = segments[i + 1];
        final combined = '$current$next';
        
        if (kDebugMode) {
          debugPrint('🔗 짧은 세그먼트 병합: "$current" (${current.length}자) + "$next" = "$combined"');
        }
        
        // 병합된 문장을 다시 문장부호로 분리
        final resplitSegments = _splitByPunctuationMarks(combined);
        result.addAll(resplitSegments);
        
        if (kDebugMode) {
          debugPrint('🔪 재분리 결과: ${resplitSegments.length}개 세그먼트');
          for (int j = 0; j < resplitSegments.length; j++) {
            debugPrint('    ${j+1}: "${resplitSegments[j]}"');
          }
        }
        
        // 다음 세그먼트는 이미 처리했으므로 건너뛰기
        i++;
      } else {
        // 4자 이상이거나 마지막 세그먼트인 경우 그대로 추가
        result.add(current);
        if (kDebugMode) {
          debugPrint('📝 정상 길이 세그먼트 유지: "$current" (${current.length}자)');
        }
      }
    }

    if (kDebugMode) {
      debugPrint('✅ 3단계 완료: ${result.length}개 최종 세그먼트');
    }

    return result;
  }

  /// 끊어진 문장 재구성 (쉼표 뒤 짧은 세그먼트를 다음 줄과 합치기)
  List<String> _reconstructBrokenSentences(List<String> sentences) {
    if (sentences.isEmpty) return sentences;
    
    final List<String> result = [];
    
    if (kDebugMode) {
      debugPrint('🔧 끊어진 문장 재구성 시작: ${sentences.length}개 문장');
    }
    
    for (int i = 0; i < sentences.length; i++) {
      final current = sentences[i];
      
      // 쉼표로 끝나고 다음 문장이 있는 경우
      if (current.endsWith(',') || current.endsWith('，')) {
        result.add(current);
        if (kDebugMode) {
          debugPrint('✅ 쉼표로 끝나는 완성 문장: "$current"');
        }
      }
      // 쉼표 뒤의 짧은 세그먼트 (5글자 이하)이고 다음 문장이 있는 경우
      // 단, 제목인 경우는 합치지 않음
      else if (current.length <= 5 && i + 1 < sentences.length && 
               !_isTitle(current) && !_isUnitOrLessonTitle(current)) {
        final next = sentences[i + 1];
        final combined = '$current$next';
        result.add(combined);
        
        if (kDebugMode) {
          debugPrint('🔗 짧은 세그먼트를 다음과 합치기: "$current" + "$next" = "$combined"');
        }
        
        // 다음 문장은 건너뛰기
        i++;
      }
      // 일반 문장 (또는 제목이어서 합치지 않은 짧은 세그먼트)
      else {
        result.add(current);
        if (kDebugMode) {
          if (current.length <= 5 && (_isTitle(current) || _isUnitOrLessonTitle(current))) {
            debugPrint('📋 제목이므로 합치지 않음: "$current"');
          } else {
            debugPrint('📝 일반 문장 유지: "$current"');
          }
        }
      }
    }
    
    if (kDebugMode) {
      debugPrint('✅ 문장 재구성 완료: ${result.length}개 문장');
    }
    
    return result;
  }

  /// 제목들을 적절한 위치로 재배치
  List<String> _reorderTitlesToTop(List<String> sentences) {
    if (sentences.isEmpty) return sentences;
    
    // 첫 3개 세그먼트에서 제목이 있는지 확인
    final hasEarlyTitle = _hasEarlyTitle(sentences);
    
    if (kDebugMode) {
      debugPrint('🔄 제목 재배치 시작: ${sentences.length}개 문장');
      debugPrint('📋 첫 3개 세그먼트에 제목 존재: $hasEarlyTitle');
    }
    
    // 제목이 없으면 모든 문장을 본문으로 처리
    if (!hasEarlyTitle) {
      if (kDebugMode) {
        debugPrint('📄 제목 없는 본문으로 처리');
      }
      return sentences;
    }
    
    final List<String> result = [];
    final List<String> currentSection = [];
    String? currentTitle;
    
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
  
  /// 첫 3개 세그먼트에 제목이 있는지 확인
  bool _hasEarlyTitle(List<String> sentences) {
    final checkCount = sentences.length < 3 ? sentences.length : 3;
    
    for (int i = 0; i < checkCount; i++) {
      final sentence = sentences[i];
      if (_isTitle(sentence) || _isUnitOrLessonTitle(sentence)) {
        if (kDebugMode) {
          debugPrint('📋 첫 3개 세그먼트에서 제목 발견: "$sentence" (위치: ${i+1})');
        }
        return true;
      }
    }
    
    if (kDebugMode) {
      debugPrint('📄 첫 3개 세그먼트에 제목 없음 - 본문 전용으로 판단');
    }
    return false;
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
      if (_sentenceDelimiters.hasMatch(char)) {
        final segment = text.substring(currentStart, i + 1).trim();
        if (segment.isNotEmpty) {
          segments.add(segment);
          if (kDebugMode) {
            debugPrint('✂️ 문장끝 분리: "$segment"');
          }
        }
        currentStart = i + 1;
      }
             // 쉼표 (간단한 분리)
       else if (_commaRegex.hasMatch(char)) {
         final segment = text.substring(currentStart, i + 1).trim();
         
         // 쉼표 분리 조건: 3글자 이상이면 분리 (중국어는 대부분 짧은 구문)
         if (segment.isNotEmpty && segment.length >= 3) {
           segments.add(segment);
           if (kDebugMode) {
             debugPrint('🔪 쉼표 분리: "$segment" (길이: ${segment.length})');
           }
           currentStart = i + 1;
         }
       }
             // 인용부호 시작 (간단한 처리)
       else if (_quotationRegex.hasMatch(char)) {
         // 현재까지의 부분이 있으면 먼저 추가
         if (i > currentStart) {
           final beforeQuote = text.substring(currentStart, i).trim();
           if (beforeQuote.isNotEmpty) {
             segments.add(beforeQuote);
             if (kDebugMode) {
               debugPrint('📝 인용부호 앞: "$beforeQuote"');
             }
           }
         }
         
         // 인용부호 닫기 찾기 (가장 가까운 닫는 인용부호)
         final quoteEnd = _findClosingQuote(text, i);
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
    
    // 남은 텍스트 처리 (중국어는 짧은 세그먼트도 의미가 있으므로 합치지 않음)
    if (currentStart < text.length) {
      final remaining = text.substring(currentStart).trim();
      if (remaining.isNotEmpty) {
        segments.add(remaining);
        if (kDebugMode) {
          debugPrint('📝 마지막 세그먼트: "$remaining"');
        }
      }
    }
    
    if (kDebugMode) {
      debugPrint('✅ 문장부호 분리 완료: ${segments.length}개 세그먼트');
    }
    
    return segments;
  }
  
  /// 닫는 인용부호 찾기 (간단한 로직)
  int _findClosingQuote(String text, int startPos) {
    final char = text[startPos];
    
    // 닫는 인용부호 찾기 (가장 가까운 것)
    for (int i = startPos + 1; i < text.length; i++) {
      // 모든 종류의 닫는 인용부호를 찾기
      if (RegExp(r'[""'']').hasMatch(text[i])) {
        if (kDebugMode) {
          debugPrint('💬 인용부호 짝 찾음: $char → ${text[i]} (${startPos} → ${i})');
        }
        return i;
      }
    }
    
    // 짝을 찾지 못한 경우 문장 끝까지
    if (kDebugMode) {
      debugPrint('⚠️ 인용부호 짝 없음: $char, 문장 끝까지 처리');
    }
    return text.length - 1;
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
