/// 전체 텍스트 모드에서 사용되는 텍스트 모델
/// 문단 단위로 텍스트를 처리합니다.

class TextFull {
  /// 원문 텍스트 (문단 단위)
  final List<String> originalParagraphs;

  /// 번역 텍스트 (문단 단위)
  final List<String> translatedParagraphs;

  /// 원문 언어
  final String sourceLanguage;

  /// 번역 언어
  final String targetLanguage;

  TextFull({
    required this.originalParagraphs,
    required this.translatedParagraphs,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  factory TextFull.fromJson(Map<String, dynamic> json) {
    return TextFull(
      originalParagraphs: List<String>.from(json['originalParagraphs'] as List),
      translatedParagraphs: List<String>.from(json['translatedParagraphs'] as List),
      sourceLanguage: json['sourceLanguage'] as String,
      targetLanguage: json['targetLanguage'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'originalParagraphs': originalParagraphs,
      'translatedParagraphs': translatedParagraphs,
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
    };
  }

  /// 복사본 생성 (일부 필드 업데이트)
  TextFull copyWith({
    List<String>? originalParagraphs,
    List<String>? translatedParagraphs,
    String? sourceLanguage,
    String? targetLanguage,
  }) {
    return TextFull(
      originalParagraphs: originalParagraphs ?? this.originalParagraphs,
      translatedParagraphs: translatedParagraphs ?? this.translatedParagraphs,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
    );
  }

  /// 전체 원문 텍스트를 하나의 문자열로 반환
  String get fullOriginalText => originalParagraphs.join('\n\n');

  /// 전체 번역 텍스트를 하나의 문자열로 반환
  String get fullTranslatedText => translatedParagraphs.join('\n\n');
} 