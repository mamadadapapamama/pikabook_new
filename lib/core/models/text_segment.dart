import '../utils/language_constants.dart';

/// 텍스트 세그먼트 모델 (문장별 모드에서 사용)
/// 원문, 핀인, 번역을 함께 관리합니다.

class TextSegment {
  /// 원문 텍스트
  final String originalText;

  /// 핀인 (또는 다른 발음 표기, 없을 수 있음)
  final String? pinyin;

  /// 번역 텍스트 (없을 수 있음)
  final String? translatedText;
  
  /// 언어 관련 필드
  final String sourceLanguage; // 원문 언어
  final String targetLanguage; // 번역 언어

  TextSegment({
    required this.originalText,
    this.pinyin,
    this.translatedText,
    String? sourceLanguage,
    String? targetLanguage,
  }) : 
    this.sourceLanguage = sourceLanguage ?? SourceLanguage.DEFAULT,
    this.targetLanguage = targetLanguage ?? TargetLanguage.DEFAULT;

  /// JSON에서 생성
  factory TextSegment.fromJson(Map<String, dynamic> json) {
    return TextSegment(
      originalText: json['originalText'] as String,
      pinyin: json['pinyin'] as String?,
      translatedText: json['translatedText'] as String?,
      sourceLanguage: json['sourceLanguage'] as String? ?? SourceLanguage.DEFAULT,
      targetLanguage: json['targetLanguage'] as String? ?? TargetLanguage.DEFAULT,
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'originalText': originalText,
      'pinyin': pinyin,
      'translatedText': translatedText,
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
    };
  }

  /// 복사본 생성 (일부 필드 업데이트)
  TextSegment copyWith({
    String? originalText,
    String? pinyin,
    String? translatedText,
    String? sourceLanguage,
    String? targetLanguage,
  }) {
    return TextSegment(
      originalText: originalText ?? this.originalText,
      pinyin: pinyin ?? this.pinyin,
      translatedText: translatedText ?? this.translatedText,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
    );
  }
}
