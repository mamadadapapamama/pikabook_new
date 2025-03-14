import 'text_segment.dart';

/// OCR 결과를 처리한 텍스트 모델. text_segment의 리스트를 담을 수 있음

class ProcessedText {
  /// 전체 원문 텍스트
  final String fullOriginalText;

  /// 전체 번역 텍스트 (없을 수 있음)
  final String? fullTranslatedText;

  /// 문장별 세그먼트 목록 (언어 학습 모드에서 사용)
  final List<TextSegment>? segments;

  /// 현재 표시 모드 (전체 텍스트 또는 세그먼트별)
  bool showFullText;

  ProcessedText({
    required this.fullOriginalText,
    this.fullTranslatedText,
    this.segments,
    this.showFullText = false,
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
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'fullOriginalText': fullOriginalText,
      'fullTranslatedText': fullTranslatedText,
      'segments': segments?.map((e) => e.toJson()).toList(),
      'showFullText': showFullText,
    };
  }

  /// 복사본 생성 (일부 필드 업데이트)
  ProcessedText copyWith({
    String? fullOriginalText,
    String? fullTranslatedText,
    List<TextSegment>? segments,
    bool? showFullText,
  }) {
    return ProcessedText(
      fullOriginalText: fullOriginalText ?? this.fullOriginalText,
      fullTranslatedText: fullTranslatedText ?? this.fullTranslatedText,
      segments: segments ?? this.segments,
      showFullText: showFullText ?? this.showFullText,
    );
  }

  /// 표시 모드 전환
  ProcessedText toggleDisplayMode() {
    return copyWith(showFullText: !showFullText);
  }
}
