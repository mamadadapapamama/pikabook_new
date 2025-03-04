import 'package:cloud_firestore/cloud_firestore.dart';

class FlashCard {
  final String id;
  final String front; // 원문 (중국어)
  final String back; // 번역 (한국어)
  final String pinyin; // 병음
  final DateTime createdAt;
  final DateTime? lastReviewedAt;
  final int reviewCount;
  final String? noteId;

  const FlashCard({
    required this.id,
    required this.front,
    required this.back,
    required this.pinyin,
    required this.createdAt,
    this.lastReviewedAt,
    this.reviewCount = 0,
    this.noteId,
  });

  factory FlashCard.fromJson(Map<String, dynamic> json) {
    return FlashCard(
      id: json['id'] ?? '',
      front: json['front'] ?? '',
      back: json['back'] ?? '',
      pinyin: json['pinyin'] ?? '',
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : (json['createdAt'] is String
              ? DateTime.parse(json['createdAt'])
              : DateTime.now()),
      lastReviewedAt: json['lastReviewedAt'] is Timestamp
          ? (json['lastReviewedAt'] as Timestamp).toDate()
          : (json['lastReviewedAt'] is String
              ? DateTime.parse(json['lastReviewedAt'])
              : null),
      reviewCount: json['reviewCount'] ?? 0,
      noteId: json['noteId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'front': front,
      'back': back,
      'pinyin': pinyin,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastReviewedAt':
          lastReviewedAt != null ? Timestamp.fromDate(lastReviewedAt!) : null,
      'reviewCount': reviewCount,
      'noteId': noteId,
    };
  }

  FlashCard copyWith({
    String? id,
    String? front,
    String? back,
    String? pinyin,
    DateTime? createdAt,
    DateTime? lastReviewedAt,
    int? reviewCount,
    String? noteId,
  }) {
    return FlashCard(
      id: id ?? this.id,
      front: front ?? this.front,
      back: back ?? this.back,
      pinyin: pinyin ?? this.pinyin,
      createdAt: createdAt ?? this.createdAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      reviewCount: reviewCount ?? this.reviewCount,
      noteId: noteId ?? this.noteId,
    );
  }
}
