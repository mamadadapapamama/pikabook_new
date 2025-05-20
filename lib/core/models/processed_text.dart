import 'text_segment.dart';
import 'text_full.dart';
import 'package:flutter/foundation.dart';

/// 텍스트 처리 모드
enum TextProcessingMode {
  segment,  // 문장 단위 처리
  full,     // 문단 단위 처리
}

/// 텍스트 표시 모드
enum TextDisplayMode {
  all,       // 원문 + 병음 + 번역 표시
  nopinyin,  // 원문 + 번역만 표시 (병음 없음)
}

/// OCR로 추출된 텍스트를 처리하고 관리하는 모델
class ProcessedText {
  /// 전체 원문
  final String fullOriginalText;
  
  /// 전체 번역문
  final String fullTranslatedText;
  
  /// 텍스트 세그먼트 목록 (문장 단위 처리 시 사용)
  final List<TextSegment> segments;
  
  /// 텍스트 처리 모드
  final TextProcessingMode mode;
  
  /// 텍스트 표시 모드
  final TextDisplayMode displayMode;
  
  /// 소스 언어
  final String sourceLanguage;
  
  /// 타겟 언어
  final String targetLanguage;

  ProcessedText({
    required this.fullOriginalText,
    required this.fullTranslatedText,
    required this.segments,
    required this.mode,
    this.displayMode = TextDisplayMode.all,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  /// JSON에서 생성
  factory ProcessedText.fromJson(Map<String, dynamic> json) {
    return ProcessedText(
      fullOriginalText: json['fullOriginalText'] as String,
      fullTranslatedText: json['fullTranslatedText'] as String,
      segments: (json['segments'] as List<dynamic>)
          .map((e) => TextSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      mode: TextProcessingMode.values.firstWhere(
        (e) => e.toString() == 'TextProcessingMode.${json['mode']}',
        orElse: () => TextProcessingMode.segment,
      ),
      displayMode: TextDisplayMode.values.firstWhere(
        (e) => e.toString() == 'TextDisplayMode.${json['displayMode']}',
        orElse: () => TextDisplayMode.all,
      ),
      sourceLanguage: json['sourceLanguage'] as String,
      targetLanguage: json['targetLanguage'] as String,
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'fullOriginalText': fullOriginalText,
      'fullTranslatedText': fullTranslatedText,
      'segments': segments.map((e) => e.toJson()).toList(),
      'mode': mode.toString().split('.').last,
      'displayMode': displayMode.toString().split('.').last,
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
    };
  }

  /// 복사본 생성 (일부 필드 업데이트)
  ProcessedText copyWith({
    String? fullOriginalText,
    String? fullTranslatedText,
    List<TextSegment>? segments,
    TextProcessingMode? mode,
    TextDisplayMode? displayMode,
    String? sourceLanguage,
    String? targetLanguage,
  }) {
    return ProcessedText(
      fullOriginalText: fullOriginalText ?? this.fullOriginalText,
      fullTranslatedText: fullTranslatedText ?? this.fullTranslatedText,
      segments: segments ?? this.segments,
      mode: mode ?? this.mode,
      displayMode: displayMode ?? this.displayMode,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
    );
  }

  /// 빈 인스턴스 생성
  factory ProcessedText.empty() {
    return ProcessedText(
      fullOriginalText: '',
      fullTranslatedText: '',
      segments: [],
      mode: TextProcessingMode.segment,
      displayMode: TextDisplayMode.all,
      sourceLanguage: 'zh-CN',
      targetLanguage: 'ko',
    );
  }

  /// 복사본 생성 (일부 필드 업데이트) - 디버그 로그 추가
  ProcessedText copyWithDebug({
    String? fullOriginalText,
    String? fullTranslatedText,
    List<TextSegment>? segments,
    TextProcessingMode? mode,
    TextDisplayMode? displayMode,
    String? sourceLanguage,
    String? targetLanguage,
  }) {
    // 디버그 로그 추가
    if (kDebugMode && (fullOriginalText != this.fullOriginalText || 
                       fullTranslatedText != this.fullTranslatedText || 
                       segments != this.segments || 
                       mode != this.mode || 
                       displayMode != this.displayMode || 
                       sourceLanguage != this.sourceLanguage || 
                       targetLanguage != this.targetLanguage)) {
      debugPrint('ProcessedText.copyWith - 필드 변경:');
      if (fullOriginalText != null && fullOriginalText != this.fullOriginalText) {
        debugPrint(' - fullOriginalText: ${this.fullOriginalText} -> $fullOriginalText');
      }
      if (fullTranslatedText != null && fullTranslatedText != this.fullTranslatedText) {
        debugPrint(' - fullTranslatedText: ${this.fullTranslatedText} -> $fullTranslatedText');
      }
      if (segments != null && segments != this.segments) {
        debugPrint(' - segments: ${this.segments.length} -> ${segments.length}');
      }
      if (mode != null && mode != this.mode) {
        debugPrint(' - mode: ${this.mode} -> $mode');
      }
      if (displayMode != null && displayMode != this.displayMode) {
        debugPrint(' - displayMode: ${this.displayMode} -> $displayMode');
      }
      if (sourceLanguage != null && sourceLanguage != this.sourceLanguage) {
        debugPrint(' - sourceLanguage: ${this.sourceLanguage} -> $sourceLanguage');
      }
      if (targetLanguage != null && targetLanguage != this.targetLanguage) {
        debugPrint(' - targetLanguage: ${this.targetLanguage} -> $targetLanguage');
      }
    }
    
    return ProcessedText(
      fullOriginalText: fullOriginalText ?? this.fullOriginalText,
      fullTranslatedText: fullTranslatedText ?? this.fullTranslatedText,
      segments: segments ?? this.segments,
      mode: mode ?? this.mode,
      displayMode: displayMode ?? this.displayMode,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
    );
  }

  /// 표시 모드 전환
  ProcessedText toggleDisplayMode() {
    return copyWith(
      displayMode: displayMode == TextDisplayMode.all ? TextDisplayMode.nopinyin : TextDisplayMode.all,
    );
  }
  
  /// 디버그 정보 문자열 반환
  @override
  String toString() {
    return 'ProcessedText(hashCode=$hashCode, '
        'mode=$mode, '
        'segments=${segments.length}, '
        'displayMode=$displayMode, '
        'sourceLanguage=$sourceLanguage, '
        'targetLanguage=$targetLanguage)';
  }
}
