import '../utils/language_constants.dart';

/// 세그먼트 타입 (Paragraph 모드용)
enum SegmentType {
  title,        // 제목 또는 섹션 헤더
  instruction,  // 지시사항 (예: "아래 대화를 읽어보세요")
  passage,      // 본문 읽기 텍스트
  vocabulary,   // 핵심 단어나 구문
  question,     // 퀴즈 문제
  choices,      // 객관식 선택지 (A/B/C/D...)
  answer,       // 정답 또는 해답
  dialogue,     // 대화문
  example,      // 예문 또는 사용 예시
  explanation,  // 문법 설명이나 해설
  unknown,      // 타입 불명 (기본값)
}

/// 텍스트 단위 모델 (문장 또는 문단)
/// 원문, 핀인, 번역을 함께 관리합니다.

class TextUnit {
  /// 원문 텍스트
  final String originalText;

  /// 핀인 (또는 다른 발음 표기, 없을 수 있음)
  final String? pinyin;

  /// 번역 텍스트 
  final String? translatedText;
  
  /// 언어 관련 필드
  final String sourceLanguage; // 원문 언어
  final String targetLanguage; // 번역 언어

  /// 세그먼트 타입 (Paragraph 모드용)
  final SegmentType segmentType;

  TextUnit({
    required this.originalText,
    this.pinyin,
    this.translatedText,
    String? sourceLanguage,
    String? targetLanguage,
    this.segmentType = SegmentType.unknown,
  }) : 
    this.sourceLanguage = sourceLanguage ?? SourceLanguage.DEFAULT,
    this.targetLanguage = targetLanguage ?? TargetLanguage.DEFAULT;

  /// JSON에서 생성
  factory TextUnit.fromJson(Map<String, dynamic> json) {
    return TextUnit(
      originalText: (json['originalText'] as String?) ?? '',
      pinyin: json['pinyin'] as String?,
      translatedText: json['translatedText'] as String?,
      sourceLanguage: json['sourceLanguage'] as String? ?? SourceLanguage.DEFAULT,
      targetLanguage: json['targetLanguage'] as String? ?? TargetLanguage.DEFAULT,
      segmentType: _parseSegmentType(json['segmentType'] as String?),
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
      'segmentType': segmentType.name,
    };
  }

  /// 복사본 생성 (일부 필드 업데이트)
  TextUnit copyWith({
    String? originalText,
    String? pinyin,
    String? translatedText,
    String? sourceLanguage,
    String? targetLanguage,
    SegmentType? segmentType,
  }) {
    return TextUnit(
      originalText: originalText ?? this.originalText,
      pinyin: pinyin ?? this.pinyin,
      translatedText: translatedText ?? this.translatedText,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      segmentType: segmentType ?? this.segmentType,
    );
  }

  /// 문자열에서 SegmentType 파싱
  static SegmentType _parseSegmentType(String? typeString) {
    if (typeString == null) return SegmentType.unknown;
    
    try {
      return SegmentType.values.firstWhere(
        (e) => e.name == typeString.toLowerCase()
      );
    } catch (e) {
      return SegmentType.unknown;
    }
  }

  /// 세그먼트 타입별 한국어 라벨
  String get segmentTypeLabel {
    switch (segmentType) {
      case SegmentType.title:
        return '제목';
      case SegmentType.instruction:
        return '지시사항';
      case SegmentType.passage:
        return '본문';
      case SegmentType.vocabulary:
        return '어휘';
      case SegmentType.question:
        return '문제';
      case SegmentType.choices:
        return '선택지';
      case SegmentType.answer:
        return '정답';
      case SegmentType.dialogue:
        return '대화';
      case SegmentType.example:
        return '예문';
      case SegmentType.explanation:
        return '설명';
      case SegmentType.unknown:
        return '';
    }
  }
} 