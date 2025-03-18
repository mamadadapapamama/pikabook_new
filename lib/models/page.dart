import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/language_constants.dart';

/// Straight forward! Page 의 모델

class Page {
  final String? id;
  final String? imageUrl;
  final String originalText;
  final String translatedText;
  final int pageNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  // 언어 관련 필드 추가
  final String sourceLanguage; // 원문 언어
  final String targetLanguage; // 번역 언어
  final String? noteId; // 페이지가 속한 노트 ID

  Page({
    this.id,
    this.imageUrl,
    required this.originalText,
    required this.translatedText,
    required this.pageNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    // 언어 관련 필드
    String? sourceLanguage,
    String? targetLanguage,
    this.noteId,
  })  : this.createdAt = createdAt ?? DateTime.now(),
        this.updatedAt = updatedAt ?? DateTime.now(),
        // 언어 기본값 설정
        this.sourceLanguage = sourceLanguage ?? SourceLanguage.DEFAULT,
        this.targetLanguage = targetLanguage ?? TargetLanguage.DEFAULT;

  // Firestore에서 데이터 가져오기
  factory Page.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Page(
      id: doc.id,
      imageUrl: data['imageUrl'],
      originalText: data['originalText'] ?? '',
      translatedText: data['translatedText'] ?? '',
      pageNumber: data['pageNumber'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      // 언어 관련 필드
      sourceLanguage: data['sourceLanguage'] ?? SourceLanguage.DEFAULT,
      targetLanguage: data['targetLanguage'] ?? TargetLanguage.DEFAULT,
      noteId: data['noteId'],
    );
  }

  // Firestore에 저장할 데이터 맵 생성
  Map<String, dynamic> toFirestore() {
    return {
      'imageUrl': imageUrl,
      'originalText': originalText,
      'translatedText': translatedText,
      'pageNumber': pageNumber,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      // 언어 관련 필드
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'noteId': noteId,
    };
  }

  // JSON으로 변환 (캐싱용)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'originalText': originalText,
      'translatedText': translatedText,
      'pageNumber': pageNumber,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      // 언어 관련 필드
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'noteId': noteId,
    };
  }

  // JSON에서 생성 (캐싱용)
  factory Page.fromJson(Map<String, dynamic> json) {
    return Page(
      id: json['id'],
      imageUrl: json['imageUrl'],
      originalText: json['originalText'] ?? '',
      translatedText: json['translatedText'] ?? '',
      pageNumber: json['pageNumber'] ?? 0,
      createdAt:
          json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      updatedAt:
          json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      // 언어 관련 필드
      sourceLanguage: json['sourceLanguage'] ?? SourceLanguage.DEFAULT,
      targetLanguage: json['targetLanguage'] ?? TargetLanguage.DEFAULT,
      noteId: json['noteId'],
    );
  }

  // 페이지 복사본 생성 (필드 업데이트용)
  Page copyWith({
    String? id,
    String? imageUrl,
    String? originalText,
    String? translatedText,
    int? pageNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    // 언어 관련 필드
    String? sourceLanguage,
    String? targetLanguage,
    String? noteId,
  }) {
    return Page(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      originalText: originalText ?? this.originalText,
      translatedText: translatedText ?? this.translatedText,
      pageNumber: pageNumber ?? this.pageNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      // 언어 관련 필드
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      noteId: noteId ?? this.noteId,
    );
  }
}
