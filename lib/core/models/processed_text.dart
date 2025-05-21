import 'dart:convert';
import 'text_unit.dart';
import 'package:flutter/foundation.dart';

/// 텍스트 처리 모드
enum TextProcessingMode {
  segment,   // 문장 단위 처리
  paragraph, // 문단 단위 처리
}

/// 텍스트 표시 모드
enum TextDisplayMode {
  full,      // 원문 + 병음 + 번역 표시
  noPinyin,  // 원문 + 번역만 표시 (병음 없음)
}

/// 처리된 텍스트를 나타내는 모델입니다.
class ProcessedText {
  final TextProcessingMode mode;
  final TextDisplayMode displayMode;
  final String fullOriginalText;
  final String fullTranslatedText;
  final List<TextUnit> units;
  final String sourceLanguage;
  final String targetLanguage;

  ProcessedText({
    required this.mode,
    required this.displayMode,
    required this.fullOriginalText,
    required this.fullTranslatedText,
    required this.units,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  /// JSON에서 ProcessedText 생성
  factory ProcessedText.fromJson(Map<String, dynamic> json) {
    return ProcessedText(
      mode: TextProcessingMode.values[json['mode'] as int],
      displayMode: TextDisplayMode.values[json['displayMode'] as int],
      fullOriginalText: json['fullOriginalText'] as String,
      fullTranslatedText: json['fullTranslatedText'] as String,
      units: (json['units'] as List)
          .map((e) => TextUnit.fromJson(e as Map<String, dynamic>))
          .toList(),
      sourceLanguage: json['sourceLanguage'] as String,
      targetLanguage: json['targetLanguage'] as String,
    );
  }

  /// ProcessedText를 JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.index,
      'displayMode': displayMode.index,
      'fullOriginalText': fullOriginalText,
      'fullTranslatedText': fullTranslatedText,
      'units': units.map((e) => e.toJson()).toList(),
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
    };
  }

  /// ProcessedText 복사
  ProcessedText copyWith({
    TextProcessingMode? mode,
    TextDisplayMode? displayMode,
    String? fullOriginalText,
    String? fullTranslatedText,
    List<TextUnit>? units,
    String? sourceLanguage,
    String? targetLanguage,
  }) {
    return ProcessedText(
      mode: mode ?? this.mode,
      displayMode: displayMode ?? this.displayMode,
      fullOriginalText: fullOriginalText ?? this.fullOriginalText,
      fullTranslatedText: fullTranslatedText ?? this.fullTranslatedText,
      units: units ?? this.units,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
    );
  }

  /// 표시 모드 전환
  ProcessedText toggleDisplayMode() {
    return copyWith(
      displayMode: displayMode == TextDisplayMode.full ? TextDisplayMode.noPinyin : TextDisplayMode.full,
    );
  }
  
  /// 디버그 정보 문자열 반환
  @override
  String toString() {
    return 'ProcessedText(mode=$mode, '
        'displayMode=$displayMode, '
        'fullOriginalText=$fullOriginalText, '
        'fullTranslatedText=$fullTranslatedText, '
        'units=${units.length} items, '
        'sourceLanguage=$sourceLanguage, '
        'targetLanguage=$targetLanguage)';
  }
}
