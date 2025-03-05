import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/flash_card.dart';
import 'package:pinyin/pinyin.dart';

class FlashCardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  // 싱글톤 패턴 구현
  static final FlashCardService _instance = FlashCardService._internal();
  factory FlashCardService() => _instance;
  FlashCardService._internal();

  // 사용자 ID 가져오기
  String? get _userId => _auth.currentUser?.uid;

  // 플래시카드 컬렉션 참조 가져오기
  CollectionReference get _flashCardsCollection =>
      _firestore.collection('flashcards');

  // 플래시카드 생성
  Future<FlashCard> createFlashCard({
    required String front,
    required String back,
    String? noteId,
    String? pinyin,
  }) async {
    if (_userId == null) {
      throw Exception('사용자가 로그인되어 있지 않습니다.');
    }

    try {
      // 병음 생성 (제공된 경우 사용, 아니면 자동 생성)
      final finalPinyin = pinyin ?? PinyinHelper.getPinyin(front);

      // 플래시카드 ID 생성
      final id = _uuid.v4();

      // 플래시카드 객체 생성
      final flashCard = FlashCard(
        id: id,
        front: front,
        back: back,
        pinyin: finalPinyin,
        createdAt: DateTime.now(),
        noteId: noteId,
      );

      // Firestore에 저장
      await _flashCardsCollection.doc(id).set({
        ...flashCard.toJson(),
        'userId': _userId,
      });

      // 노트의 플래시카드 카운터 업데이트
      if (noteId != null) {
        await _updateNoteFlashCardCounter(noteId);
      }

      return flashCard;
    } catch (e) {
      debugPrint('플래시카드 생성 중 오류 발생: $e');
      throw Exception('플래시카드를 생성할 수 없습니다: $e');
    }
  }

  // 노트의 플래시카드 카운터 업데이트
  Future<void> _updateNoteFlashCardCounter(String noteId) async {
    try {
      // 노트에 연결된 플래시카드 수 계산
      final querySnapshot = await _flashCardsCollection
          .where('userId', isEqualTo: _userId)
          .where('noteId', isEqualTo: noteId)
          .get();

      final count = querySnapshot.docs.length;

      // 플래시카드 목록 가져오기
      final flashCards = querySnapshot.docs
          .map((doc) => FlashCard.fromJson(doc.data() as Map<String, dynamic>))
          .toList();

      // 노트 문서 업데이트
      await _firestore.collection('notes').doc(noteId).update({
        'flashcardCount': count,
        'flashCards': flashCards.map((card) => card.toJson()).toList(),
      });

      debugPrint('노트 $noteId의 플래시카드 카운터 업데이트: $count개');
    } catch (e) {
      debugPrint('노트 플래시카드 카운터 업데이트 중 오류 발생: $e');
    }
  }

  // 사용자의 모든 플래시카드 가져오기
  Future<List<FlashCard>> getAllFlashCards() async {
    if (_userId == null) {
      throw Exception('사용자가 로그인되어 있지 않습니다.');
    }

    try {
      // 방법 1: 인덱스 없이 쿼리하기 (userId만 필터링)
      final querySnapshot =
          await _flashCardsCollection.where('userId', isEqualTo: _userId).get();

      // 클라이언트 측에서 정렬
      final flashCards = querySnapshot.docs
          .map((doc) => FlashCard.fromJson(doc.data() as Map<String, dynamic>))
          .toList();

      // createdAt 기준으로 내림차순 정렬
      flashCards.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return flashCards;
    } catch (e) {
      debugPrint('플래시카드 목록 조회 중 오류 발생: $e');
      throw Exception('플래시카드 목록을 가져올 수 없습니다: $e');
    }
  }

  // 특정 노트의 플래시카드 가져오기
  Future<List<FlashCard>> getFlashCardsForNote(String noteId) async {
    if (_userId == null) {
      throw Exception('사용자가 로그인되어 있지 않습니다.');
    }

    try {
      // 방법 1: 인덱스 없이 쿼리하기 (userId와 noteId만 필터링)
      final querySnapshot = await _flashCardsCollection
          .where('userId', isEqualTo: _userId)
          .where('noteId', isEqualTo: noteId)
          .get();

      // 클라이언트 측에서 정렬
      final flashCards = querySnapshot.docs
          .map((doc) => FlashCard.fromJson(doc.data() as Map<String, dynamic>))
          .toList();

      // createdAt 기준으로 내림차순 정렬
      flashCards.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return flashCards;
    } catch (e) {
      debugPrint('노트 플래시카드 조회 중 오류 발생: $e');
      throw Exception('노트의 플래시카드를 가져올 수 없습니다: $e');
    }
  }

  // 플래시카드 업데이트 (복습 시간 및 횟수 업데이트)
  Future<FlashCard> updateFlashCard(FlashCard flashCard) async {
    if (_userId == null) {
      throw Exception('사용자가 로그인되어 있지 않습니다.');
    }

    try {
      // 업데이트된 플래시카드 객체
      final updatedFlashCard = flashCard.copyWith(
        lastReviewedAt: DateTime.now(),
        reviewCount: flashCard.reviewCount + 1,
      );

      // Firestore 업데이트
      await _flashCardsCollection
          .doc(flashCard.id)
          .update(updatedFlashCard.toJson());

      return updatedFlashCard;
    } catch (e) {
      debugPrint('플래시카드 업데이트 중 오류 발생: $e');
      throw Exception('플래시카드를 업데이트할 수 없습니다: $e');
    }
  }

  // 플래시카드 삭제
  Future<void> deleteFlashCard(String flashCardId, {String? noteId}) async {
    if (_userId == null) {
      throw Exception('사용자가 로그인되어 있지 않습니다.');
    }

    try {
      // Firestore에서 삭제
      await _flashCardsCollection.doc(flashCardId).delete();

      // 노트의 플래시카드 카운터 업데이트
      if (noteId != null) {
        await _updateNoteFlashCardCounter(noteId);
      }
    } catch (e) {
      debugPrint('플래시카드 삭제 중 오류 발생: $e');
      throw Exception('플래시카드를 삭제할 수 없습니다: $e');
    }
  }
}

// 디버그 프린트 함수
void debugPrint(String message) {
  // ignore: avoid_print
  print(message);
}
