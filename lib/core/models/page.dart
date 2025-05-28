import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/language_constants.dart';

/// 페이지 모델: 노트의 각 페이지를 나타냅니다.
class Page {
  final String id;
  final String noteId;
  final int pageNumber;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String sourceLanguage;
  final String targetLanguage;
  final String? originalText;      // 원본 텍스트
  final String? translatedText;    // 번역된 텍스트
  final String? pinyin;            // 병음
  final Map<String, dynamic>? processedText; // 처리된 텍스트 전체 데이터
  final bool showTypewriterEffect; // 타이프라이터 효과 플래그
  final List<String>? textSegments; // 분리된 텍스트 세그먼트들 (Pre-LLM에서 저장)

  Page({
    required this.id,
    required this.noteId,
    required this.pageNumber,
    this.imageUrl,
    DateTime? createdAt,
    this.updatedAt,
    String? sourceLanguage,
    String? targetLanguage,
    this.originalText,
    this.translatedText,
    this.pinyin,
    this.processedText,
    this.showTypewriterEffect = false,
    this.textSegments,
  })  : this.createdAt = createdAt ?? DateTime.now(),
        this.sourceLanguage = sourceLanguage ?? SourceLanguage.DEFAULT,
        this.targetLanguage = targetLanguage ?? TargetLanguage.DEFAULT;

  /// Firestore 문서에서 Page 객체 생성
  factory Page.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // 날짜 필드 변환 로직 (Timestamp 또는 String 처리)
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.parse(value);
      return null;
    }
    
    return Page(
      id: doc.id,
      noteId: data['noteId'] as String,
      pageNumber: data['pageNumber'] as int,
      imageUrl: data['imageUrl'] as String?,
      createdAt: parseDate(data['createdAt']) ?? DateTime.now(),
      updatedAt: parseDate(data['updatedAt']),
      sourceLanguage: data['sourceLanguage'] ?? SourceLanguage.DEFAULT,
      targetLanguage: data['targetLanguage'] ?? TargetLanguage.DEFAULT,
      originalText: data['originalText'] as String?,
      translatedText: data['translatedText'] as String?,
      pinyin: data['pinyin'] as String?,
      processedText: data['processedText'] != null 
          ? Map<String, dynamic>.from(data['processedText'] as Map<String, dynamic>) 
          : null,
      showTypewriterEffect: data['showTypewriterEffect'] ?? false,
      textSegments: data['textSegments'] != null 
          ? List<String>.from(data['textSegments'] as List<dynamic>) 
          : null,
    );
  }

  /// JSON에서 Page 객체 생성
  factory Page.fromJson(Map<String, dynamic> json) {
    return Page(
      id: json['id'] as String,
      noteId: json['noteId'] as String,
      pageNumber: json['pageNumber'] as int,
      imageUrl: json['imageUrl'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
      sourceLanguage: json['sourceLanguage'] ?? SourceLanguage.DEFAULT,
      targetLanguage: json['targetLanguage'] ?? TargetLanguage.DEFAULT,
      originalText: json['originalText'] as String?,
      translatedText: json['translatedText'] as String?,
      pinyin: json['pinyin'] as String?,
      processedText: json['processedText'] != null 
          ? Map<String, dynamic>.from(json['processedText'] as Map<String, dynamic>) 
          : null,
      showTypewriterEffect: json['showTypewriterEffect'] ?? false,
      textSegments: json['textSegments'] != null 
          ? List<String>.from(json['textSegments'] as List<dynamic>) 
          : null,
    );
  }

  /// Page 객체를 JSON으로 변환
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'id': id,
      'noteId': noteId,
      'pageNumber': pageNumber,
      'imageUrl': imageUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'showTypewriterEffect': showTypewriterEffect,
    };
    
    // 선택적 필드 추가
    if (originalText != null) data['originalText'] = originalText;
    if (translatedText != null) data['translatedText'] = translatedText;
    if (pinyin != null) data['pinyin'] = pinyin;
    if (processedText != null) data['processedText'] = processedText;
    if (textSegments != null) data['textSegments'] = textSegments;
    
    return data;
  }

  /// Page 객체 복사
  Page copyWith({
    String? id,
    String? noteId,
    int? pageNumber,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? sourceLanguage,
    String? targetLanguage,
    String? originalText,
    String? translatedText,
    String? pinyin,
    Map<String, dynamic>? processedText,
    bool? showTypewriterEffect,
    List<String>? textSegments,
  }) {
    return Page(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      pageNumber: pageNumber ?? this.pageNumber,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      originalText: originalText ?? this.originalText,
      translatedText: translatedText ?? this.translatedText,
      pinyin: pinyin ?? this.pinyin,
      processedText: processedText ?? this.processedText,
      showTypewriterEffect: showTypewriterEffect ?? this.showTypewriterEffect,
      textSegments: textSegments ?? this.textSegments,
    );
  }
}
