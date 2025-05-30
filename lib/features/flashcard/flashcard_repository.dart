import 'package:flutter/foundation.dart';
import '../../core/models/flash_card.dart';
import 'flashcard_service.dart';
import '../../core/services/cache/cache_manager.dart';

/// 플래시카드 데이터 관리를 담당하는 Repository
/// 기본적인 CRUD 작업만 수행하고 비즈니스 로직은 담당하지 않음
class FlashCardRepository {
  // 서비스 인스턴스
  final FlashCardService _flashCardService;
  final CacheManager _cacheManager;
  
  // 의존성 주입을 통한 생성자
  FlashCardRepository({
    FlashCardService? flashCardService,
    CacheManager? cacheManager
  }) : 
    _flashCardService = flashCardService ?? FlashCardService(),
    _cacheManager = cacheManager ?? CacheManager();
    
  /// 공통 유효성 검사 메서드
  void _validateNoteId(String noteId) {
    if (noteId.isEmpty) {
      throw Exception('노트 ID가 설정되지 않았습니다');
    }
  }
  
  void _validateCardId(String cardId) {
    if (cardId.isEmpty) {
      throw Exception('카드 ID가 비어있습니다');
    }
  }
  
  void _validateFlashCardContent(String front, String back) {
    if (front.isEmpty || back.isEmpty) {
      throw Exception('단어와 뜻은 필수 입력 사항입니다');
    }
  }
  
  /// 노트 ID에 따른 플래시카드 로드
  Future<List<FlashCard>> loadFlashCards(String noteId) async {
    _validateNoteId(noteId);
    
    try {
      // 먼저 Firestore에서 로드 시도
      final cards = await _flashCardService.getFlashCardsForNote(noteId);
      
      if (cards.isNotEmpty) {
        // Firestore에서 가져온 카드를 캐시에 저장
        await _cacheManager.cacheFlashcards(noteId, cards);
        return cards;
      }
      
      // Firestore에서 찾지 못한 경우, 캐시 확인
      final cachedCards = await _cacheManager.getFlashcards(noteId);
      if (cachedCards != null && cachedCards.isNotEmpty) {
        // 캐시에서 가져온 카드를 Firestore에 동기화
        for (var card in cachedCards) {
          await _flashCardService.updateFlashCard(card);
        }
        return cachedCards;
      }
      
      // 둘 다 실패하면 빈 리스트 반환
      return [];
    } catch (e) {
      if (kDebugMode) {
        print('플래시카드 로드 중 오류 발생: $e');
      }
      throw Exception('플래시카드 로드 중 오류 발생: $e');
    }
  }
  
  /// 모든 플래시카드 로드
  Future<List<FlashCard>> loadAllFlashCards() async {
    try {
      return await _flashCardService.getAllFlashCards();
    } catch (e) {
      if (kDebugMode) {
        print('모든 플래시카드 로드 중 오류 발생: $e');
      }
      throw Exception('모든 플래시카드 로드 중 오류 발생: $e');
    }
  }
  
  /// 플래시카드 추가
  Future<FlashCard> addFlashCard({
    required String front, 
    required String back, 
    required String noteId, 
    String? pinyin
  }) async {
    _validateNoteId(noteId);
    _validateFlashCardContent(front, back);
    
    try {
      final newCard = await _flashCardService.createFlashCard(
        front: front,
        back: back,
        noteId: noteId,
        pinyin: pinyin,
      );
      
      // 새로 생성된 카드를 캐시에 추가
      await _cacheManager.cacheFlashcard(noteId, newCard);
      
      return newCard;
    } catch (e) {
      if (kDebugMode) {
        print('플래시카드 생성 실패: $e');
      }
      throw Exception('플래시카드 생성 실패: $e');
    }
  }
  
  /// 플래시카드 업데이트
  Future<FlashCard> updateFlashCard(FlashCard card) async {
    _validateCardId(card.id);
    
    try {
      final updatedCard = await _flashCardService.updateFlashCard(card);
      
      // 업데이트된 카드를 캐시에 반영
      if (card.noteId != null) {
        await _cacheManager.cacheFlashcard(card.noteId!, updatedCard);
      }
      
      return updatedCard;
    } catch (e) {
      if (kDebugMode) {
        print('플래시카드 업데이트 실패: $e');
      }
      throw Exception('플래시카드 업데이트 실패: $e');
    }
  }
  
  /// 플래시카드 삭제
  Future<bool> deleteFlashCard(String cardId, {String? noteId}) async {
    _validateCardId(cardId);
    
    try {
      await _flashCardService.deleteFlashCard(cardId, noteId: noteId);
      
      // 캐시에서도 삭제
      if (noteId != null) {
        await _cacheManager.removeFlashcard(noteId, cardId);
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('플래시카드 삭제 실패: $e');
      }
      throw Exception('플래시카드 삭제 실패: $e');
    }
  }
  
  /// 특정 단어가 플래시카드로 등록되어 있는지 확인
  bool isWordInFlashCards(String word, List<FlashCard> flashCards) {
    return flashCards.any((card) => card.front == word);
  }
  
  /// 단어에 해당하는 플래시카드 가져오기
  FlashCard? getFlashCardForWord(String word, List<FlashCard> flashCards) {
    final index = flashCards.indexWhere((card) => card.front == word);
    return index >= 0 ? flashCards[index] : null;
  }
  
  /// 플래시카드 캐싱
  Future<void> cacheFlashcards(String noteId, List<FlashCard> flashCards) async {
    if (noteId.isNotEmpty && flashCards.isNotEmpty) {
      await _cacheManager.cacheFlashcards(noteId, flashCards);
    }
  }
}
