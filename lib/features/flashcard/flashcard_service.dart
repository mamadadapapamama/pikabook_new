import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/flash_card.dart';
import '../../core/models/dictionary.dart';
import '../../core/models/note.dart';
import '../dictionary/dictionary_service.dart';
import '../dictionary/cc_cedict_service.dart';
import '../../core/services/common/usage_limit_service.dart';
import '../../core/services/cache/cache_manager.dart';

/// 플래시카드 생성 및 관리 기능(CRUD)을 제공합니다

class FlashCardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();
  final DictionaryService _dictionaryService = DictionaryService();
  final CcCedictService _ccCedictService = CcCedictService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  final CacheManager _cacheManager = CacheManager();
  
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
      // 1. LLM 캐시 및 내부 사전에서 단어 검색 (lookupWord가 모두 처리)
      final dictResult = await _dictionaryService.lookupWord(front);
      String pinyinValue = pinyin ?? '';
      String meaningValue = back;
      if (dictResult['success'] == true && dictResult['entry'] != null) {
        final dictEntry = dictResult['entry'];
        // 캐시에 추가
        _wordCache[front] = dictEntry;
        // 뜻이 비어있으면 사전의 뜻 사용 (다국어 포함)
        if (meaningValue.isEmpty) {
          meaningValue = dictEntry.displayMeaning;
        }
        // 병음이 비어있으면 사전의 병음 사용
        if (pinyinValue.isEmpty && dictEntry.pinyin.isNotEmpty) {
          pinyinValue = dictEntry.pinyin;
        }
      }
      // 2. 병음이 여전히 비어있으면 CC-CEDICT 서비스 사용
      if (pinyinValue.isEmpty) {
        final ccCedictEntry = await _ccCedictService.lookup(front);
        if (ccCedictEntry != null) {
          pinyinValue = ccCedictEntry.pinyin;
          if (kDebugMode) debugPrint('CC-CEDICT 서비스로 병음 생성: $front -> $pinyinValue');
        }
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
        ...flashCard.toFirestoreJson(),
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
      _wordCache[word] = DictionaryEntry.multiLanguage(
        word: word,
        pinyin: pinyin,
        meaningKo: meaning,
        source: 'flashcard',
      );
      
      // 사전 서비스를 통해 단어 검색
      final existingEntry = await _dictionaryService.lookup(word);

      // 사전에 없는 단어라면 추가
      if (existingEntry == null) {
        final newEntry = DictionaryEntry.multiLanguage(
          word: word,
          pinyin: pinyin,
          meaningKo: meaning,
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
        'flashCards': flashCards.map((card) => card.toFirestoreJson()).toList(),
      });

      // 캐시된 노트 메타데이터도 업데이트
      await _updateCachedNoteMetadata(noteId, count);

      debugPrint('노트 $noteId의 플래시카드 카운터 업데이트: $count개');
    } catch (e) {
      debugPrint('노트 플래시카드 카운터 업데이트 중 오류 발생: $e');
    }
  }

  /// 캐시된 노트 메타데이터의 플래시카드 카운터 업데이트
  Future<void> _updateCachedNoteMetadata(String noteId, int newFlashcardCount) async {
    try {
      // 캐시에서 기존 노트 메타데이터 조회
      final cachedNote = await _cacheManager.getNoteMetadata(noteId);
      if (cachedNote != null) {
        // 플래시카드 카운터만 업데이트된 새로운 노트 객체 생성
        final updatedNote = cachedNote.copyWith(
          flashcardCount: newFlashcardCount,
          updatedAt: DateTime.now(),
        );
        
        // 캐시에 업데이트된 노트 저장
        await _cacheManager.cacheNoteMetadata(noteId, updatedNote);
        
        if (kDebugMode) {
          debugPrint('📋 노트 캐시 메타데이터 업데이트: $noteId (플래시카드: $newFlashcardCount개)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 캐시 메타데이터 업데이트 실패: $e');
      }
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
          .update(updatedFlashCard.toFirestoreJson());

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
