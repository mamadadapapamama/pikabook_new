
/// 텍스트 세그먼트 모델
/// 원문, 핀인, 번역을 함께 관리합니다.


class TextSegment {
  /// 원문 텍스트 (중국어)
  final String originalText;

  /// 핀인 (없을 수 있음)
  final String? pinyin;

  /// 번역 텍스트 (없을 수 있음)
  final String? translatedText;

  TextSegment({
    required this.originalText,
    this.pinyin,
    this.translatedText,
  });

  /// JSON에서 생성
  factory TextSegment.fromJson(Map<String, dynamic> json) {
    return TextSegment(
      originalText: json['originalText'] as String,
      pinyin: json['pinyin'] as String?,
      translatedText: json['translatedText'] as String?,
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'originalText': originalText,
      'pinyin': pinyin,
      'translatedText': translatedText,
    };
  }

  /// 복사본 생성 (일부 필드 업데이트)
  TextSegment copyWith({
    String? originalText,
    String? pinyin,
    String? translatedText,
  }) {
    return TextSegment(
      originalText: originalText ?? this.originalText,
      pinyin: pinyin ?? this.pinyin,
      translatedText: translatedText ?? this.translatedText,
    );
  }
}
