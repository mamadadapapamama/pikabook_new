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

  Page({
    required this.id,
    required this.noteId,
    required this.pageNumber,
    this.imageUrl,
    DateTime? createdAt,
    this.updatedAt,
    String? sourceLanguage,
    String? targetLanguage,
  })  : this.createdAt = createdAt ?? DateTime.now(),
        this.sourceLanguage = sourceLanguage ?? SourceLanguage.DEFAULT,
        this.targetLanguage = targetLanguage ?? TargetLanguage.DEFAULT;

  /// Firestore 문서에서 Page 객체 생성
  factory Page.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Page(
      id: doc.id,
      noteId: data['noteId'] as String,
      pageNumber: data['pageNumber'] as int,
      imageUrl: data['imageUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      sourceLanguage: data['sourceLanguage'] ?? SourceLanguage.DEFAULT,
      targetLanguage: data['targetLanguage'] ?? TargetLanguage.DEFAULT,
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
    );
  }

  /// Page 객체를 JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'noteId': noteId,
      'pageNumber': pageNumber,
      'imageUrl': imageUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
    };
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
    );
  }
}
