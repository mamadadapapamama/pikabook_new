import 'dart:convert';
import 'text_segment.dart';
import 'text_full.dart';
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
  final String original;
  final String translated;
  final String? pinyin;
  final String? ttsPath;
  final DateTime processedAt;
  final TextDisplayMode displayMode;

  ProcessedText({
    required this.original,
    required this.translated,
    this.pinyin,
    this.ttsPath,
    DateTime? processedAt,
    TextDisplayMode? displayMode,
  })  : processedAt = processedAt ?? DateTime.now(),
        displayMode = displayMode ?? TextDisplayMode.full;

  /// JSON에서 ProcessedText 생성
  factory ProcessedText.fromJson(Map<String, dynamic> json) {
    return ProcessedText(
      original: json['original'] as String,
      translated: json['translated'] as String,
      pinyin: json['pinyin'] as String?,
      ttsPath: json['ttsPath'] as String?,
      processedAt: json['processedAt'] != null
          ? DateTime.parse(json['processedAt'] as String)
          : null,
      displayMode: json['displayMode'] != null
          ? TextDisplayMode.values.firstWhere(
              (e) => e.toString() == json['displayMode'],
              orElse: () => TextDisplayMode.full,
            )
          : null,
    );
  }

  /// ProcessedText를 JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'original': original,
      'translated': translated,
      'pinyin': pinyin,
      'ttsPath': ttsPath,
      'processedAt': processedAt.toIso8601String(),
      'displayMode': displayMode.toString(),
    };
  }

  /// ProcessedText 복사
  ProcessedText copyWith({
    String? original,
    String? translated,
    String? pinyin,
    String? ttsPath,
    DateTime? processedAt,
    TextDisplayMode? displayMode,
  }) {
    return ProcessedText(
      original: original ?? this.original,
      translated: translated ?? this.translated,
      pinyin: pinyin ?? this.pinyin,
      ttsPath: ttsPath ?? this.ttsPath,
      processedAt: processedAt ?? this.processedAt,
      displayMode: displayMode ?? this.displayMode,
    );
  }

  /// 복사본 생성 (일부 필드 업데이트) - 디버그 로그 추가
  ProcessedText copyWithDebug({
    String? original,
    String? translated,
    String? pinyin,
    String? ttsPath,
    DateTime? processedAt,
    TextDisplayMode? displayMode,
  }) {
    // 디버그 로그 추가
    if (kDebugMode && (original != this.original || 
                       translated != this.translated || 
                       pinyin != this.pinyin || 
                       ttsPath != this.ttsPath || 
                       processedAt != this.processedAt ||
                       displayMode != this.displayMode)) {
      debugPrint('ProcessedText.copyWith - 필드 변경:');
      if (original != null && original != this.original) {
        debugPrint(' - original: ${this.original} -> $original');
      }
      if (translated != null && translated != this.translated) {
        debugPrint(' - translated: ${this.translated} -> $translated');
      }
      if (pinyin != null && pinyin != this.pinyin) {
        debugPrint(' - pinyin: ${this.pinyin} -> $pinyin');
      }
      if (ttsPath != null && ttsPath != this.ttsPath) {
        debugPrint(' - ttsPath: ${this.ttsPath} -> $ttsPath');
      }
      if (processedAt != null && processedAt != this.processedAt) {
        debugPrint(' - processedAt: ${this.processedAt} -> $processedAt');
      }
      if (displayMode != null && displayMode != this.displayMode) {
        debugPrint(' - displayMode: ${this.displayMode} -> $displayMode');
      }
    }
    
    return ProcessedText(
      original: original ?? this.original,
      translated: translated ?? this.translated,
      pinyin: pinyin ?? this.pinyin,
      ttsPath: ttsPath ?? this.ttsPath,
      processedAt: processedAt ?? this.processedAt,
      displayMode: displayMode ?? this.displayMode,
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
    return 'ProcessedText(hashCode=$hashCode, '
        'original=$original, '
        'translated=$translated, '
        'pinyin=$pinyin, '
        'ttsPath=$ttsPath, '
        'processedAt=$processedAt, '
        'displayMode=$displayMode)';
  }
}
