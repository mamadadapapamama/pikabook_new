import 'processed_text.dart';

/// 페이지 처리 데이터 (전처리 → 후처리 전달용)
class PageProcessingData {
  final String pageId;
  final String imageUrl;
  final List<String> textSegments;
  final TextProcessingMode mode;
  final String sourceLanguage;
  final String targetLanguage;
  final int imageFileSize; // 이미지 파일 크기 (바이트)
  final bool ocrSuccess; // OCR 성공 여부
  final List<String> detectedTitles; // 감지된 제목들
  final String originalText; // OCR 원본 텍스트
  final String cleanedText; // 정리된 텍스트
  final String reorderedText; // 재배열된 텍스트

  PageProcessingData({
    required this.pageId,
    required this.imageUrl,
    required this.textSegments,
    required this.mode,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.imageFileSize,
    required this.ocrSuccess,
    this.detectedTitles = const [],
    this.originalText = '',
    this.cleanedText = '',
    this.reorderedText = '',
  });

  Map<String, dynamic> toJson() => {
    'pageId': pageId,
    'imageUrl': imageUrl,
    'textSegments': textSegments,
    'mode': mode.toString(),
    'sourceLanguage': sourceLanguage,
    'targetLanguage': targetLanguage,
    'imageFileSize': imageFileSize,
    'ocrSuccess': ocrSuccess,
    'detectedTitles': detectedTitles,
    'originalText': originalText,
    'cleanedText': cleanedText,
    'reorderedText': reorderedText,
  };

  factory PageProcessingData.fromJson(Map<String, dynamic> json) {
    return PageProcessingData(
      pageId: json['pageId'],
      imageUrl: json['imageUrl'],
      textSegments: List<String>.from(json['textSegments']),
      mode: TextProcessingMode.values.firstWhere(
        (e) => e.toString() == json['mode']
      ),
      sourceLanguage: json['sourceLanguage'],
      targetLanguage: json['targetLanguage'],
      imageFileSize: json['imageFileSize'] ?? 0,
      ocrSuccess: json['ocrSuccess'] ?? false,
      detectedTitles: List<String>.from(json['detectedTitles'] ?? []),
      originalText: json['originalText'] ?? '',
      cleanedText: json['cleanedText'] ?? '',
      reorderedText: json['reorderedText'] ?? '',
    );
  }
} 