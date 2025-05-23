import 'package:cloud_firestore/cloud_firestore.dart';

/// 노트 모델: 노트의 메타데이터를 나타냅니다.
class Note {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final bool isFavorite;
  final int flashcardCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Note({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.isFavorite = false,
    this.flashcardCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  /// Firestore 문서에서 Note 객체 생성
  factory Note.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // 날짜 필드 변환 로직 (Timestamp 또는 String 처리)
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.parse(value);
      return null;
    }
    
    return Note(
      id: doc.id,
      userId: data['userId'] as String,
      title: data['title'] as String,
      description: data['description'] as String?,
      isFavorite: data['isFavorite'] as bool? ?? false,
      flashcardCount: data['flashcardCount'] as int? ?? 0,
      createdAt: parseDate(data['createdAt']),
      updatedAt: parseDate(data['updatedAt']),
    );
  }

  /// JSON에서 Note 객체 생성
  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      flashcardCount: json['flashcardCount'] as int? ?? 0,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt'] as String) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
    );
  }

  /// Note 객체를 JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'description': description,
      'isFavorite': isFavorite,
      'flashcardCount': flashcardCount,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  /// Note 객체 복사
  Note copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    bool? isFavorite,
    int? flashcardCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      isFavorite: isFavorite ?? this.isFavorite,
      flashcardCount: flashcardCount ?? this.flashcardCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
