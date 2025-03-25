import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/flash_card.dart';
import '../models/dictionary_entry.dart';
import 'dictionary_service.dart';
import 'chinese_dictionary_service.dart';
import 'pinyin_creation_service.dart';

/// 플래시카드 생성 및 관리 기능(CRUD)을 제공합니다
class FlashCardService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();
  final DictionaryService _dictionaryService = DictionaryService();
  final ChineseDictionaryService _chineseDictionaryService = ChineseDictionaryService();
  final PinyinCreationService _pinyinService = PinyinCreationService();

  // 싱글톤 패턴 구현
  static final FlashCardService _instance = FlashCardService._internal();
  factory FlashCardService() => _instance;
  FlashCardService._internal();

  // 사용자 ID 가져오기
  String? get _userId => _auth.currentUser?.uid;

  // 플래시카드 컬렉션 참조 가져오기
  CollectionReference get _flashCardsCollection => _firestore.collection('flashcards');

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
      // 병음 생성 (제공된 경우에도 빈 문자열이면 생성)
      String pinyinValue = pinyin ?? '';

      // 1. 먼저 사전에서 단어 검색
      final dictEntry = await _dictionaryService.lookupWordWithFallback(front);
      
      // 2. 사전에서 찾은 경우
      if (dictEntry != null) {
        // 뜻이 비어있으면 사전의 뜻 사용
        if (back.isEmpty) {
          back = dictEntry.meaning;
          debugPrint('사전에서 뜻 찾음: $front -> $back');
        }
        
        // 병음이 비어있으면 사전의 병음 사용
        if (pinyinValue.isEmpty && dictEntry.pinyin.isNotEmpty) {
          pinyinValue = dictEntry.pinyin;
          debugPrint('사전에서 핀인 찾음: $front -> $pinyinValue');
        }
      } else if (back.isEmpty) {
        // 사전에서 찾지 못하고 뜻도 없는 경우
        back = '뜻을 찾을 수 없습니다';
        debugPrint('사전에서 뜻을 찾을 수 없음: $front');
      }

      // 3. 병음이 여전히 비어있으면 직접 생성
      if (pinyinValue.isEmpty) {
        pinyinValue = await _pinyinService.generatePinyin(front);
        debugPrint('핀인 생성됨: $front -> $pinyinValue');
      }

      // 플래시카드 ID 생성
      final id = _uuid.v4();

      // 플래시카드 객체 생성
      final flashCard = FlashCard(
        id: id,
        front: front,
        back: back,
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
      await _addToDictionaryIfNeeded(front, back, pinyinValue);

      return flashCard;
    } catch (e) {
      debugPrint('플래시카드 생성 중 오류 발생: $e');
      throw Exception('플래시카드 생성에 실패했습니다.');
    }
  }

  // 노트의 플래시카드 카운터 업데이트
  Future<void> _updateNoteFlashCardCounter(String noteId) async {
    try {
      final noteRef = _firestore.collection('notes').doc(noteId);
      final flashcards = await _flashCardsCollection
          .where('noteId', isEqualTo: noteId)
          .get();
      
      await noteRef.update({
        'flashCardCount': flashcards.docs.length,
      });
    } catch (e) {
      debugPrint('플래시카드 카운터 업데이트 중 오류 발생: $e');
    }
  }

  // 사전에 단어 추가
  Future<void> _addToDictionaryIfNeeded(String word, String meaning, String pinyin) async {
    try {
      final entry = DictionaryEntry(
        word: word,
        pinyin: pinyin,
        meaning: meaning,
        examples: [],
        source: 'user',
      );
      _dictionaryService.addToDictionary(entry);
      _chineseDictionaryService.addEntry(entry);
    } catch (e) {
      debugPrint('사전에 단어 추가 중 오류 발생: $e');
    }
  }
} 