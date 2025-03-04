import 'package:cloud_firestore/cloud_firestore.dart';
import 'flash_card.dart';
import 'page.dart';

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
  final List<Page> pages;
  final String extractedText;
  final int flashcardCount;
  final int reviewCount;
  final String? userId;

  Note({
    this.id,
    required this.originalText,
    required this.translatedText,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.imageUrl,
    List<String>? tags,
    this.isFavorite = false,
    List<FlashCard>? flashCards,
    List<Page>? pages,
    required this.extractedText,
    int? flashcardCount,
    int? reviewCount,
    this.userId,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        tags = tags ?? [],
        flashCards = flashCards ?? [],
        pages = pages ?? [],
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
      userId: userId,
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

    // pages 필드 처리 개선 - 이제 Page 객체 리스트로 변환
    List<Page> pages = [];
    if (data['pages'] != null && data['pages'] is List) {
      try {
        pages = (data['pages'] as List)
            .map((pageData) => Page.fromFirestore(pageData))
            .toList();
      } catch (e) {
        // 기존 문자열 리스트 형식의 pages 필드 처리 (하위 호환성)
        List<String> pageIds = (data['pages'] as List)
            .map((page) => page?.toString() ?? '')
            .toList();

        // 여기서는 빈 Page 객체 리스트를 생성하고,
        // 실제 데이터는 나중에 별도로 로드해야 함
        pages = [];
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
      userId: data['userId'],
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
      'pages': pages.map((page) => page.id).toList(), // 페이지 ID 리스트로 저장
      'extractedText': extractedText,
      'flashcardCount': flashcardCount,
      'reviewCount': reviewCount,
      'userId': userId,
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
    List<Page>? pages, // Page 객체 리스트로 변경
    String? extractedText,
    int? flashcardCount,
    int? reviewCount,
    String? userId,
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
      userId: userId ?? this.userId,
    );
  }

  // 첫 번째 페이지의 원문 텍스트 가져오기
  String get firstPageOriginalText {
    if (pages.isNotEmpty) {
      return pages.first.originalText;
    }
    return originalText;
  }

  // 첫 번째 페이지의 번역 텍스트 가져오기
  String get firstPageTranslatedText {
    if (pages.isNotEmpty) {
      return pages.first.translatedText;
    }
    return translatedText;
  }

  // 모든 페이지의 원문 텍스트 합치기
  String get allPagesOriginalText {
    if (pages.isEmpty) {
      return originalText;
    }
    return pages.map((page) => page.originalText).join('\n\n');
  }

  // 모든 페이지의 번역 텍스트 합치기
  String get allPagesTranslatedText {
    if (pages.isEmpty) {
      return translatedText;
    }
    return pages.map((page) => page.translatedText).join('\n\n');
  }
}
