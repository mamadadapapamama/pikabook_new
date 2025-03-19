import 'text_segment.dart';
import 'package:flutter/foundation.dart';

/// OCR 결과를 처리한 텍스트 모델. text_segment의 리스트를 담을 수 있음

class ProcessedText {
  /// 전체 원문 텍스트
  final String fullOriginalText;

  /// 전체 번역 텍스트 (없을 수 있음)
  final String? fullTranslatedText;

  /// 문장별 세그먼트 목록 (언어 학습 모드에서 사용)
  final List<TextSegment>? segments;

  /// 표시 모드 관련 설정
  final bool showFullText;
  final bool showPinyin;
  final bool showTranslation;

  ProcessedText({
    required this.fullOriginalText,
    this.fullTranslatedText,
    this.segments,
    this.showFullText = false,
    this.showPinyin = true,
    this.showTranslation = true,
  });

  /// JSON에서 생성
  factory ProcessedText.fromJson(Map<String, dynamic> json) {
    return ProcessedText(
      fullOriginalText: json['fullOriginalText'] as String,
      fullTranslatedText: json['fullTranslatedText'] as String?,
      segments: json['segments'] != null
          ? (json['segments'] as List)
              .map((e) => TextSegment.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      showFullText: json['showFullText'] as bool? ?? false,
      showPinyin: json['showPinyin'] as bool? ?? true,
      showTranslation: json['showTranslation'] as bool? ?? true,
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'fullOriginalText': fullOriginalText,
      'fullTranslatedText': fullTranslatedText,
      'segments': segments?.map((e) => e.toJson()).toList(),
      'showFullText': showFullText,
      'showPinyin': showPinyin,
      'showTranslation': showTranslation,
    };
  }

  /// 복사본 생성 (일부 필드 업데이트) - 디버그 로그 추가
  ProcessedText copyWith({
    String? fullOriginalText,
    String? fullTranslatedText,
    List<TextSegment>? segments,
    bool? showFullText,
    bool? showPinyin,
    bool? showTranslation,
  }) {
    // 디버그 로그 추가
    if (kDebugMode && (showFullText != this.showFullText || 
                       showPinyin != this.showPinyin || 
                       showTranslation != this.showTranslation)) {
      debugPrint('ProcessedText.copyWith - 표시 설정 변경:');
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
      fullOriginalText: fullOriginalText ?? this.fullOriginalText,
      fullTranslatedText: fullTranslatedText ?? this.fullTranslatedText,
      segments: segments ?? this.segments,
      showFullText: showFullText ?? this.showFullText,
      showPinyin: showPinyin ?? this.showPinyin,
      showTranslation: showTranslation ?? this.showTranslation,
    );
  }

  /// 표시 모드 전환
  ProcessedText toggleDisplayMode() {
    return copyWith(showFullText: !showFullText);
  }
  
  /// 디버그 정보 문자열 반환
  @override
  String toString() {
    return 'ProcessedText(hashCode=$hashCode, '
        'segments=${segments?.length ?? 0}, '
        'showFullText=$showFullText, '
        'showPinyin=$showPinyin, '
        'showTranslation=$showTranslation)';
  }
}
