import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../models/flash_card.dart';
import '../../models/dictionary.dart';
import 'package:pinyin/pinyin.dart';
import '../dictionary/dictionary_service.dart';
import '../content/pinyin_creation_service.dart';
import '../common/usage_limit_service.dart';

/// 플래시카드 생성 및 관리 기능(CRUD)을 제공합니다

class FlashCardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();
  final DictionaryService _dictionaryService = DictionaryService();
  final PinyinCreationService _pinyinService = PinyinCreationService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // 캐시 추가
  final Map<String, DictionaryEntry> _wordCache = {};

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
      // 사용량 제한 확인 - 플래시카드는 제한이 없으므로 관련 코드 제거
      // final canAddFlashcard = await _usageLimitService.incrementFlashcardCount();
      // if (!canAddFlashcard) {
      //   throw Exception('무료 플래시카드 사용량 한도를 초과했습니다.');
      // }
      
      // 병음 생성 (항상 병음을 생성하도록 처리)
      String pinyinValue = pinyin ?? '';
      String meaningValue = back;

      // 1. 먼저 캐시에서 단어 검색
      if (_wordCache.containsKey(front)) {
        final cachedEntry = _wordCache[front]!;
        if (kDebugMode) debugPrint('캐시에서 단어 정보 가져옴: $front');
        
        // 뜻이 비어있으면 캐시의 뜻 사용
        if (meaningValue.isEmpty) {
          meaningValue = cachedEntry.meaning;
        }
        
        // 병음이 비어있으면 캐시의 병음 사용
        if (pinyinValue.isEmpty && cachedEntry.pinyin.isNotEmpty) {
          pinyinValue = cachedEntry.pinyin;
        }
      } 
      // 2. 캐시에 없으면 사전에서 단어 검색
      else {
      final dictResult = await _dictionaryService.lookupWord(front);
      
      if (dictResult['success'] == true && dictResult['entry'] != null) {
        final dictEntry = dictResult['entry'];
          
          // 캐시에 추가
          _wordCache[front] = dictEntry;
          
        // 뜻이 비어있으면 사전의 뜻 사용
          if (meaningValue.isEmpty) {
            meaningValue = dictEntry.meaning;
            if (kDebugMode) debugPrint('사전에서 뜻 찾음: $front -> $meaningValue');
        }
        
        // 사전의 병음 사용 (있는 경우)
        if (dictEntry.pinyin.isNotEmpty) {
          pinyinValue = dictEntry.pinyin;
            if (kDebugMode) debugPrint('사전에서 핀인 찾음: $front -> $pinyinValue');
        }
        } else if (meaningValue.isEmpty) {
        // 사전에서 찾지 못하고 뜻도 없는 경우
          meaningValue = '뜻을 찾을 수 없습니다';
          if (kDebugMode) debugPrint('사전에서 뜻을 찾을 수 없음: $front');
        }
      }

      // 3. 병음이 여전히 비어있으면 직접 생성
      if (pinyinValue.isEmpty) {
        pinyinValue = await _pinyinService.generatePinyin(front);
        if (kDebugMode) debugPrint('핀인 생성됨: $front -> $pinyinValue');
      }

      // 플래시카드 ID 생성
      final id = _uuid.v4();

      // 플래시카드 객체 생성
      final flashCard = FlashCard(
        id: id,
        front: front,
        back: meaningValue,
        pinyin: pinyinValue,
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

      // 플래시카드 생성 후 사전에 없는 단어라면 사전에 추가
      await _addToDictionaryIfNeeded(front, meaningValue, pinyinValue);

      return flashCard;
    } catch (e) {
      // 오류 발생 시 사용량 감소 로직 제거
      if (kDebugMode) debugPrint('플래시카드 생성 중 오류 발생: $e');
      throw Exception('플래시카드를 생성할 수 없습니다: $e');
    }
  }

  // 캐시 비우기
  void clearCache() {
    _wordCache.clear();
    if (kDebugMode) debugPrint('플래시카드 서비스 캐시 정리됨');
  }

  // 사전에 단어 추가 (필요한 경우)
  Future<void> _addToDictionaryIfNeeded(
      String word, String meaning, String pinyin) async {
    try {
      // 캐시에 추가
      _wordCache[word] = DictionaryEntry(
        word: word,
        pinyin: pinyin,
        meaning: meaning,
        source: 'flashcard',
      );
      
      // 사전 서비스를 통해 단어 검색
      final existingEntry = await _dictionaryService.lookup(word);

      // 사전에 없는 단어라면 추가
      if (existingEntry == null) {
        final newEntry = DictionaryEntry(
          word: word,
          pinyin: pinyin,
          meaning: meaning,
          source: 'flashcard',
        );

        // 사전 서비스를 통해 단어 추가
        await _dictionaryService.addEntry(newEntry);
        debugPrint('플래시카드에서 사전에 단어 추가됨: $word');
      }
    } catch (e) {
      debugPrint('사전에 단어 추가 중 오류 발생: $e');
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
      // 삭제할 플래시카드 정보 가져오기
      final flashCardDoc = await _flashCardsCollection.doc(flashCardId).get();
      String? deletedWord;

      if (flashCardDoc.exists) {
        final data = flashCardDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          deletedWord = data['front'] as String?;
          debugPrint('삭제할 플래시카드 단어: $deletedWord');
        }
      }

      // Firestore에서 삭제
      await _flashCardsCollection.doc(flashCardId).delete();

      // 노트의 플래시카드 카운터 업데이트
      if (noteId != null) {
        await _updateNoteFlashCardCounter(noteId);

        // 노트 문서에서 하이라이트 정보 업데이트
        if (deletedWord != null && deletedWord.isNotEmpty) {
          await _updateNoteHighlights(noteId, deletedWord);
        }
      }
    } catch (e) {
      debugPrint('플래시카드 삭제 중 오류 발생: $e');
      throw Exception('플래시카드를 삭제할 수 없습니다: $e');
    }
  }

  // 노트 문서의 하이라이트 정보 업데이트
  Future<void> _updateNoteHighlights(String noteId, String deletedWord) async {
    try {
      // 노트 문서 가져오기
      final noteDoc = await _firestore.collection('notes').doc(noteId).get();

      if (!noteDoc.exists) {
        debugPrint('노트 문서가 존재하지 않습니다: $noteId');
        return;
      }

      final data = noteDoc.data();
      if (data == null) {
        debugPrint('노트 데이터가 없습니다: $noteId');
        return;
      }

      // 페이지 정보 가져오기
      final pageIds = data['pages'] as List<dynamic>? ?? [];

      // 각 페이지의 하이라이트 정보 업데이트
      for (final pageId in pageIds) {
        await _updatePageHighlights(pageId.toString(), deletedWord);
      }

      debugPrint('노트 $noteId의 하이라이트 정보 업데이트 완료');
    } catch (e) {
      debugPrint('노트 하이라이트 정보 업데이트 중 오류 발생: $e');
    }
  }

  // 페이지 문서의 하이라이트 정보 업데이트
  Future<void> _updatePageHighlights(String pageId, String deletedWord) async {
    try {
      // 페이지 문서 가져오기
      final pageDoc = await _firestore.collection('pages').doc(pageId).get();

      if (!pageDoc.exists) {
        debugPrint('페이지 문서가 존재하지 않습니다: $pageId');
        return;
      }

      final data = pageDoc.data();
      if (data == null) {
        debugPrint('페이지 데이터가 없습니다: $pageId');
        return;
      }

      // 하이라이트된 단어 목록 가져오기
      final highlightedWords = data['highlightedWords'] as List<dynamic>? ?? [];

      // 삭제된 단어 제거
      final updatedHighlightedWords = highlightedWords
          .where((word) => word.toString() != deletedWord)
          .toList();

      // 변경된 경우에만 업데이트
      if (updatedHighlightedWords.length != highlightedWords.length) {
        await _firestore.collection('pages').doc(pageId).update({
          'highlightedWords': updatedHighlightedWords,
        });
        debugPrint('페이지 $pageId의 하이라이트 정보 업데이트 완료');
      }
    } catch (e) {
      debugPrint('페이지 하이라이트 정보 업데이트 중 오류 발생: $e');
    }
  }
}

// 디버그 프린트 함수
void debugPrint(String message) {
  // ignore: avoid_print
  print(message);
}
