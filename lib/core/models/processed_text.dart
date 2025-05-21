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
  final List<TextSegment> contentList;
  final bool showFullText;
  final bool showPinyin;
  final bool showTranslation;

  ProcessedText({
    required this.original,
    required this.translated,
    this.pinyin,
    this.ttsPath,
    DateTime? processedAt,
    TextDisplayMode? displayMode,
    List<TextSegment>? contentList,
    this.showFullText = false,
    this.showPinyin = true,
    this.showTranslation = true,
  })  : processedAt = processedAt ?? DateTime.now(),
        displayMode = displayMode ?? TextDisplayMode.full,
        contentList = contentList ?? [];

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
      contentList: (json['contentList'] as List<dynamic>?)
          ?.map((e) => TextSegment.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      showFullText: json['showFullText'] as bool? ?? false,
      showPinyin: json['showPinyin'] as bool? ?? true,
      showTranslation: json['showTranslation'] as bool? ?? true,
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
      'contentList': contentList.map((e) => e.toJson()).toList(),
      'showFullText': showFullText,
      'showPinyin': showPinyin,
      'showTranslation': showTranslation,
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
    List<TextSegment>? contentList,
    bool? showFullText,
    bool? showPinyin,
    bool? showTranslation,
  }) {
    return ProcessedText(
      original: original ?? this.original,
      translated: translated ?? this.translated,
      pinyin: pinyin ?? this.pinyin,
      ttsPath: ttsPath ?? this.ttsPath,
      processedAt: processedAt ?? this.processedAt,
      displayMode: displayMode ?? this.displayMode,
      contentList: contentList ?? this.contentList,
      showFullText: showFullText ?? this.showFullText,
      showPinyin: showPinyin ?? this.showPinyin,
      showTranslation: showTranslation ?? this.showTranslation,
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
    List<TextSegment>? contentList,
    bool? showFullText,
    bool? showPinyin,
    bool? showTranslation,
  }) {
    // 디버그 로그 추가
    if (kDebugMode && (original != this.original || 
                       translated != this.translated || 
                       pinyin != this.pinyin || 
                       ttsPath != this.ttsPath || 
                       processedAt != this.processedAt ||
                       displayMode != this.displayMode ||
                       contentList != this.contentList ||
                       showFullText != this.showFullText ||
                       showPinyin != this.showPinyin ||
                       showTranslation != this.showTranslation)) {
      
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
      if (contentList != null && contentList != this.contentList) {
        debugPrint(' - contentList: ${this.contentList.length} -> ${contentList.length}');
      }
      if (showFullText != null && showFullText != this.showFullText) {
        debugPrint(' - showFullText: ${this.showFullText} -> $showFullText');
      }
      if (showPinyin != null && showPinyin != this.showPinyin) {
        debugPrint(' - showPinyin: ${this.showPinyin} -> $showPinyin');
      }
      if (showTranslation != null && showTranslation != this.showTranslation) {
        debugPrint(' - showTranslation: ${this.showTranslation} -> $showTranslation');
      }
    }
    
    return ProcessedText(
      original: original ?? this.original,
      translated: translated ?? this.translated,
      pinyin: pinyin ?? this.pinyin,
      ttsPath: ttsPath ?? this.ttsPath,
      processedAt: processedAt ?? this.processedAt,
      displayMode: displayMode ?? this.displayMode,
      contentList: contentList ?? this.contentList,
      showFullText: showFullText ?? this.showFullText,
      showPinyin: showPinyin ?? this.showPinyin,
      showTranslation: showTranslation ?? this.showTranslation,
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
        'displayMode=$displayMode, '
        'contentList=${contentList.length} items, '
        'showFullText=$showFullText, '
        'showPinyin=$showPinyin, '
        'showTranslation=$showTranslation)';
  }
}
