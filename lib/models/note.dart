import 'package:cloud_firestore/cloud_firestore.dart';
import 'flash_card.dart';

class Note {
  final String? id;
  final String originalText;
  final String translatedText;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? imageUrl;
  final List<String> tags;
  final bool isFavorite;
  final List<FlashCard> flashCards;
  final List<String> pages;
  final String extractedText;
  final int flashcardCount;
  final int reviewCount;

  Note({
    this.id,
    required this.originalText,
    required this.translatedText,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.imageUrl,
    List<String>? tags,
    this.isFavorite = false,
    required this.flashCards,
    required this.pages,
    required this.extractedText,
    int? flashcardCount,
    int? reviewCount,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        tags = tags ?? [],
        flashcardCount = flashcardCount ?? 0,
        reviewCount = reviewCount ?? 0;

  factory Note.create({
    required String userId,
    required String title,
    String content = '',
  }) {
    final now = DateTime.now();
    return Note(
      id: '',
      originalText: title,
      translatedText: '',
      createdAt: now,
      updatedAt: now,
      imageUrl: '',
      tags: [],
      isFavorite: false,
      flashCards: [],
      pages: [],
      extractedText: '',
      flashcardCount: 0,
      reviewCount: 0,
    );
  }

  factory Note.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Timestamp 변환 처리
    DateTime createdAt;
    if (data['createdAt'] is Timestamp) {
      createdAt = (data['createdAt'] as Timestamp).toDate();
    } else if (data['createdAt'] is String) {
      createdAt = DateTime.parse(data['createdAt'] as String);
    } else {
      createdAt = DateTime.now();
    }

    DateTime updatedAt;
    if (data['updatedAt'] is Timestamp) {
      updatedAt = (data['updatedAt'] as Timestamp).toDate();
    } else if (data['updatedAt'] is String) {
      updatedAt = DateTime.parse(data['updatedAt'] as String);
    } else {
      updatedAt = DateTime.now();
    }

    // pages 필드 처리 개선
    List<String> pages = [];
    if (data['pages'] != null) {
      if (data['pages'] is List) {
        pages = (data['pages'] as List)
            .map((page) => page?.toString() ?? '')
            .toList();
      }
    }

    return Note(
      id: doc.id,
      originalText: data['originalText'] ?? '',
      translatedText: data['translatedText'] ?? '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      imageUrl: data['imageUrl'],
      tags: List<String>.from(data['tags'] ?? []),
      isFavorite: data['isFavorite'] ?? false,
      flashCards: (data['flashCards'] as List<dynamic>?)
              ?.map((card) => FlashCard.fromJson(card))
              .toList() ??
          [],
      pages: pages,
      extractedText: data['extractedText'] ?? '',
      flashcardCount: data['flashcardCount'] ?? 0,
      reviewCount: data['reviewCount'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'originalText': originalText,
      'translatedText': translatedText,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'imageUrl': imageUrl,
      'tags': tags,
      'isFavorite': isFavorite,
      'flashCards': flashCards.map((card) => card.toJson()).toList(),
      'pages': pages,
      'extractedText': extractedText,
      'flashcardCount': flashcardCount,
      'reviewCount': reviewCount,
    };
  }

  Note copyWith({
    String? id,
    String? originalText,
    String? translatedText,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? imageUrl,
    List<String>? tags,
    bool? isFavorite,
    List<FlashCard>? flashCards,
    List<String>? pages,
    String? extractedText,
    int? flashcardCount,
    int? reviewCount,
  }) {
    return Note(
      id: id ?? this.id,
      originalText: originalText ?? this.originalText,
      translatedText: translatedText ?? this.translatedText,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      imageUrl: imageUrl ?? this.imageUrl,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      flashCards: flashCards ?? this.flashCards,
      pages: pages ?? this.pages,
      extractedText: extractedText ?? this.extractedText,
      flashcardCount: flashcardCount ?? this.flashcardCount,
      reviewCount: reviewCount ?? this.reviewCount,
    );
  }
}
