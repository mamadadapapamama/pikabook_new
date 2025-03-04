import 'package:cloud_firestore/cloud_firestore.dart';

class Page {
  final String? id;
  final String? imageUrl;
  final String originalText;
  final String translatedText;
  final int pageNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  Page({
    this.id,
    this.imageUrl,
    required this.originalText,
    required this.translatedText,
    required this.pageNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : this.createdAt = createdAt ?? DateTime.now(),
        this.updatedAt = updatedAt ?? DateTime.now();

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
    };
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
  }) {
    return Page(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      originalText: originalText ?? this.originalText,
      translatedText: translatedText ?? this.translatedText,
      pageNumber: pageNumber ?? this.pageNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
