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
    
    // 빈 문장들 제거
    final filteredSentences = sentences
        .where((sentence) => sentence.trim().isNotEmpty)
        .toList();

    if (kDebugMode) {
      debugPrint('문장 분리 결과: ${filteredSentences.length}개 문장');
    }

    return filteredSentences;
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
