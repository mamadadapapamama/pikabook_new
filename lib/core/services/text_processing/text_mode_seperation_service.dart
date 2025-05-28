import 'package:flutter/foundation.dart';
import '../../../core/models/processed_text.dart';

/// 텍스트 모드별 분리 서비스
/// 사용자 설정에 따라 텍스트를 문장 단위 또는 문단 단위로 분리
/// 
class TextModeSeparationService {
  // 싱글톤 패턴
  static final TextModeSeparationService _instance = TextModeSeparationService._internal();
  factory TextModeSeparationService() => _instance;
  TextModeSeparationService._internal();

  /// 모드에 따라 텍스트 분리
  List<String> separateByMode(String text, TextProcessingMode mode) {
    if (text.isEmpty) {
      if (kDebugMode) {
        debugPrint('TextModeSeparationService: 빈 텍스트 입력');
      }
      return [];
    }

    if (kDebugMode) {
      debugPrint('TextModeSeparationService: 텍스트 분리 시작 - 모드: $mode, 길이: ${text.length}자');
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
        result = splitIntoParagraphs(text);
        if (kDebugMode) {
          debugPrint('📄 문단 단위 분리 완료: ${result.length}개 문단');
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

    if (kDebugMode) {
      debugPrint('문장 분리 결과: ${filteredSentences.length}개 문장');
      for (int i = 0; i < filteredSentences.length; i++) {
        final preview = filteredSentences[i].length > 30 
            ? '${filteredSentences[i].substring(0, 30)}...' 
            : filteredSentences[i];
        debugPrint('  문장 ${i+1}: "$preview"');
      }
    }

    return filteredSentences;
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

  /// 제목인지 확인 (휴리스틱 방법)
  bool _isTitle(String line) {
    // 제목 판단 기준:
    // 1. 길이가 적당히 짧음 (1-15자)
    // 2. 문장 구분자가 없음
    // 3. 숫자나 특수문자로만 이루어지지 않음
    
    if (line.length > 15 || line.length < 2) return false;
    
    // 문장 구분자가 있으면 제목이 아님
    if (RegExp(r'[。？！.!?，,]').hasMatch(line)) return false;
    
    // 숫자나 특수문자만 있으면 제목이 아님
    if (RegExp(r'^[\d\s\p{P}]+$', unicode: true).hasMatch(line)) return false;
    
    // 중국어 문자가 포함되어 있어야 함
    if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(line)) return false;
    
    return true;
  }

  /// 한 줄을 문장으로 분리
  List<String> _splitLineIntoSentences(String line) {
    if (line.isEmpty) return [];
    
    final List<String> sentences = [];
    
    // 긴 문장에서 쉼표로 분리 (배열문 처리)
    if (_shouldSplitByComma(line)) {
      final commaSplit = _splitByFirstComma(line);
      sentences.addAll(commaSplit);
    } else {
      // 일반적인 문장 구분자로 분리
      sentences.addAll(_splitBySentenceDelimiters(line));
    }
    
    return sentences;
  }

  /// 쉼표로 분리해야 하는지 판단
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

  /// 문단 단위로 텍스트 분리
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
