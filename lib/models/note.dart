import 'package:cloud_firestore/cloud_firestore.dart';
import 'flash_card.dart';

class Note {
  final String id;
  final String spaceId;
  final String userId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<FlashCard> flashCards;
  final List<String> pages;
  final String imageUrl;
  final String extractedText;
  final String translatedText;
  final bool isDeleted;
  final int flashcardCount;
  final int reviewCount;

  const Note({
    required this.id,
    required this.spaceId,
    required this.userId,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.flashCards,
    required this.pages,
    required this.imageUrl,
    required this.extractedText,
    required this.translatedText,
    required this.isDeleted,
    required this.flashcardCount,
    required this.reviewCount,
  });

  factory Note.create({
    required String userId,
    required String title,
    String content = '',
  }) {
    final now = DateTime.now();
    return Note(
      id: '',
      spaceId: '',
      userId: userId,
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
      flashCards: [],
      pages: [],
      imageUrl: '',
      extractedText: '',
      translatedText: '',
      isDeleted: false,
      flashcardCount: 0,
      reviewCount: 0,
    );
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] ?? '',
      spaceId: json['spaceId'] ?? '',
      userId: json['userId'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : (json['createdAt'] is String
              ? DateTime.parse(json['createdAt'])
              : DateTime.now()),
      updatedAt: json['updatedAt'] is Timestamp
          ? (json['updatedAt'] as Timestamp).toDate()
          : (json['updatedAt'] is String
              ? DateTime.parse(json['updatedAt'])
              : DateTime.now()),
      flashCards: (json['flashCards'] as List<dynamic>?)
              ?.map((card) => FlashCard.fromJson(card))
              .toList() ??
          [],
      pages: (json['pages'] as List<dynamic>?)
              ?.map((page) => page as String)
              .toList() ??
          [],
      imageUrl: json['imageUrl'] ?? '',
      extractedText: json['extractedText'] ?? '',
      translatedText: json['translatedText'] ?? '',
      isDeleted: json['isDeleted'] ?? false,
      flashcardCount: json['flashcardCount'] ?? 0,
      reviewCount: json['reviewCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'spaceId': spaceId,
      'userId': userId,
      'title': title,
      'content': content,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'flashCards': flashCards.map((card) => card.toJson()).toList(),
      'pages': pages,
      'imageUrl': imageUrl,
      'extractedText': extractedText,
      'translatedText': translatedText,
      'isDeleted': isDeleted,
      'flashcardCount': flashcardCount,
      'reviewCount': reviewCount,
    };
  }

  Note copyWith({
    String? id,
    String? spaceId,
    String? userId,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<FlashCard>? flashCards,
    List<String>? pages,
    String? imageUrl,
    String? extractedText,
    String? translatedText,
    bool? isDeleted,
    int? flashcardCount,
    int? reviewCount,
  }) {
    return Note(
      id: id ?? this.id,
      spaceId: spaceId ?? this.spaceId,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      flashCards: flashCards ?? this.flashCards,
      pages: pages ?? this.pages,
      imageUrl: imageUrl ?? this.imageUrl,
      extractedText: extractedText ?? this.extractedText,
      translatedText: translatedText ?? this.translatedText,
      isDeleted: isDeleted ?? this.isDeleted,
      flashcardCount: flashcardCount ?? this.flashcardCount,
      reviewCount: reviewCount ?? this.reviewCount,
    );
  }
}
