import 'package:flutter/foundation.dart' hide debugPrint;
import 'package:flutter/material.dart' hide debugPrint;
import 'dart:async';
import '../../core/models/flash_card.dart';
import '../../core/services/content/flashcard_service.dart';
import '../../core/services/media/tts_service.dart';
import '../../core/services/storage/unified_cache_service.dart';
import 'dart:developer' as dev;

/// 플래시카드 관련 로직을 담당하는 ViewModel
class FlashcardViewModel extends ChangeNotifier {
  // 서비스 참조
  final FlashCardService _flashCardService = FlashCardService();
  final TtsService _ttsService = TtsService();
  
  // 상태 변수
  String _noteId = "";                  // 노트 ID
  List<FlashCard> _flashCards = [];     // 플래시카드 목록
  bool _loadingFlashcards = true;       // 플래시카드 로딩 상태
  bool _isSpeaking = false;             // TTS 실행 중 상태
  String? _error;                       // 오류 메시지
  int _currentCardIndex = 0;            // 현재 플래시카드 인덱스
  bool _isCardFlipped = false;          // 카드 뒤집힘 상태
  
  // 게터
  String get noteId => _noteId;
  List<FlashCard> get flashCards => _flashCards;
  bool get loadingFlashcards => _loadingFlashcards;
  bool get isSpeaking => _isSpeaking;
  String? get error => _error;
  int get currentCardIndex => _currentCardIndex;
  bool get isCardFlipped => _isCardFlipped;
  int get flashcardCount => _flashCards.length;
  bool get hasFlashcards => _flashCards.isNotEmpty;
  
  // 생성자
  FlashcardViewModel({
    String? noteId,
    List<FlashCard>? initialFlashcards,
  }) {
    _noteId = noteId ?? "";
    
    // 초기 플래시카드가 있으면 설정
    if (initialFlashcards != null && initialFlashcards.isNotEmpty) {
      _flashCards = initialFlashcards;
      _loadingFlashcards = false;
    } else if (noteId != null && noteId.isNotEmpty) {
      // 노트 ID가 있으면 플래시카드 로드
      loadFlashcards();
    }
    
    _initTts();
  }
  
  // TTS 초기화
  Future<void> _initTts() async {
    try {
      await _ttsService.init();
      debugPrint("[FlashcardViewModel] TTS 서비스 초기화됨");
    } catch (e) {
      debugPrint("[FlashcardViewModel] TTS 초기화 오류: $e");
    }
  }
  
  // 리소스 정리
  @override
  void dispose() {
    _ttsService.stop();
    _ttsService.dispose();
    
    // 앱 종료 전 플래시카드 저장
    if (_noteId.isNotEmpty && _flashCards.isNotEmpty) {
      debugPrint("[FlashcardViewModel] dispose - ${_flashCards.length}개의 플래시카드 캐시에 저장");
      UnifiedCacheService().cacheFlashcards(_flashCards);
    }
    
    super.dispose();
  }
  
  // 플래시카드 로드
  Future<void> loadFlashcards() async {
    if (_noteId.isEmpty) {
      debugPrint("[FlashcardViewModel] 플래시카드 로드 실패: noteId가 없음");
      return;
    }

    debugPrint("[FlashcardViewModel] 플래시카드 로드 시작: noteId = $_noteId");
    
    _loadingFlashcards = true;
    _error = null;
    notifyListeners();
  
    try {
      // 먼저 Firestore에서 플래시카드 로드 시도
      var firestoreFlashcards = await _flashCardService.getFlashCardsForNote(_noteId);
      if (firestoreFlashcards.isNotEmpty) {
        debugPrint("[FlashcardViewModel] Firestore에서 ${firestoreFlashcards.length}개의 플래시카드 로드 성공");
        _flashCards = firestoreFlashcards;
        _loadingFlashcards = false;
        
        // Firestore에서 로드된 플래시카드를 캐시에 저장
        await UnifiedCacheService().cacheFlashcards(firestoreFlashcards);
        
        notifyListeners();
        return;
      }

      // Firestore에서 로드 실패한 경우 캐시에서 로드 시도
      debugPrint("[FlashcardViewModel] Firestore에서 플래시카드를 찾지 못함, 캐시 확인 중");
      var cachedFlashcards = await UnifiedCacheService().getFlashcardsByNoteId(_noteId);
      if (cachedFlashcards.isNotEmpty) {
        debugPrint("[FlashcardViewModel] 캐시에서 ${cachedFlashcards.length}개의 플래시카드 로드 성공");
        _flashCards = cachedFlashcards;
        _loadingFlashcards = false;
        
        // 캐시에서 로드된 플래시카드를 Firestore에 동기화
        for (var card in cachedFlashcards) {
          await _flashCardService.updateFlashCard(card);
        }
        
        notifyListeners();
        return;
      }

      // 모든 시도 실패시 빈 리스트로 초기화
      debugPrint("[FlashcardViewModel] 플래시카드를 찾지 못함 (Firestore 및 캐시 모두)");
      _flashCards = [];
      _loadingFlashcards = false;
      notifyListeners();
    } catch (e) {
      debugPrint("[FlashcardViewModel] 플래시카드 로드 중 오류 발생: $e");
      _error = "플래시카드 로드 중 오류 발생: $e";
      _flashCards = [];
      _loadingFlashcards = false;
      notifyListeners();
    }
  }
  
  // 모든 플래시카드 로드 
  Future<void> loadAllFlashcards() async {
    debugPrint("[FlashcardViewModel] 모든 플래시카드 로드 시작");
    
    _loadingFlashcards = true;
    _error = null;
    notifyListeners();
    
    try {
      final allFlashcards = await _flashCardService.getAllFlashCards();
      
      debugPrint("[FlashcardViewModel] ${allFlashcards.length}개의 플래시카드 로드 성공");
      _flashCards = allFlashcards;
      _loadingFlashcards = false;
      notifyListeners();
    } catch (e) {
      debugPrint("[FlashcardViewModel] 모든 플래시카드 로드 중 오류: $e");
      _error = "플래시카드 로드 중 오류: $e";
      _flashCards = [];
      _loadingFlashcards = false;
      notifyListeners();
    }
  }
  
  // 플래시카드 생성
  Future<bool> createFlashCard(String front, String back, {String? pinyin}) async {
    debugPrint("[FlashcardViewModel] 플래시카드 생성 시작: $front - $back (병음: $pinyin)");
    
    try {
      // 플래시카드 서비스 사용
      final newFlashCard = await _flashCardService.createFlashCard(
        front: front,
        back: back,
        noteId: _noteId,
        pinyin: pinyin,
      );
      
      // 상태 업데이트
      _flashCards.add(newFlashCard);
      notifyListeners();
      
      debugPrint("[FlashcardViewModel] 플래시카드 생성 완료: ${newFlashCard.front} - ${newFlashCard.back} (병음: ${newFlashCard.pinyin})");
      debugPrint("[FlashcardViewModel] 현재 플래시카드 수: ${_flashCards.length}");
      
      return true;
    } catch (e) {
      debugPrint("[FlashcardViewModel] 플래시카드 생성 중 오류: $e");
      _error = "플래시카드 생성 중 오류: $e";
      notifyListeners();
      return false;
    }
  }
  
  // 플래시카드 목록 업데이트
  void updateFlashcards(List<FlashCard> updatedFlashcards) {
    _flashCards = updatedFlashcards;
    notifyListeners();
    debugPrint("[FlashcardViewModel] 플래시카드 목록 업데이트됨: ${_flashCards.length}개");
  }
  
  // 현재 카드 인덱스 변경
  void setCurrentCardIndex(int index) {
    if (index >= 0 && index < _flashCards.length) {
      _currentCardIndex = index;
      _isCardFlipped = false;
      notifyListeners();
      debugPrint("[FlashcardViewModel] 현재 카드 인덱스 변경: $_currentCardIndex");
    }
  }
  
  // 카드 뒤집기 상태 토글
  void toggleCardFlip() {
    _isCardFlipped = !_isCardFlipped;
    notifyListeners();
    debugPrint("[FlashcardViewModel] 카드 뒤집기 상태 변경: $_isCardFlipped");
  }
  
  // TTS 기능 - 현재 카드의 텍스트 읽기
  Future<void> speakCurrentCardText() async {
    if (_flashCards.isEmpty || _currentCardIndex >= _flashCards.length) {
      debugPrint("[FlashcardViewModel] 읽을 카드가 없습니다");
      return;
    }
    
    if (_isSpeaking) {
      await stopSpeaking();
      return;
    }
    
    try {
      await _ttsService.stop(); // 기존 음성 중지
      
      // 카드의 앞면 텍스트 가져오기 (중국어)
      final textToSpeak = _flashCards[_currentCardIndex].front;
      
      if (textToSpeak.isNotEmpty) {
        // 중국어 설정
        await _ttsService.setLanguage('zh-CN');
        
        _isSpeaking = true;
        notifyListeners();
        
        debugPrint("[FlashcardViewModel] TTS 시작: $textToSpeak");
        await _ttsService.speak(textToSpeak);
        
        // 완료 콜백 등록
        _ttsService.setOnPlayingCompleted(() {
          if (_isSpeaking) {
            _isSpeaking = false;
            notifyListeners();
          }
        });
        
        // 안전장치로 10초 후 상태 리셋
        Future.delayed(Duration(seconds: 10), () {
          if (_isSpeaking) {
            _isSpeaking = false;
            notifyListeners();
            debugPrint("[FlashcardViewModel] TTS 타임아웃으로 상태 리셋");
          }
        });
      } else {
        debugPrint("[FlashcardViewModel] 읽을 텍스트가 없습니다");
      }
    } catch (e) {
      debugPrint("[FlashcardViewModel] TTS 중 오류 발생: $e");
      _isSpeaking = false;
      notifyListeners();
    }
  }
  
  // TTS 중지
  Future<void> stopSpeaking() async {
    if (!_isSpeaking) return;
    
    try {
      await _ttsService.stop();
      _isSpeaking = false;
      notifyListeners();
      debugPrint("[FlashcardViewModel] TTS 중지됨");
    } catch (e) {
      debugPrint("[FlashcardViewModel] TTS 중지 중 오류 발생: $e");
    }
  }
  
  // 현재 카드 삭제
  Future<bool> deleteCurrentCard() async {
    if (_flashCards.isEmpty || _currentCardIndex >= _flashCards.length) {
      debugPrint("[FlashcardViewModel] 삭제할 카드가 없습니다");
      return false;
    }
    
    try {
      final flashCardId = _flashCards[_currentCardIndex].id;
      
      // Firestore에서 삭제
      await _flashCardService.deleteFlashCard(flashCardId, noteId: _noteId);
      
      // 로컬 상태 업데이트
      final indexToRemove = _currentCardIndex;
      _flashCards.removeAt(indexToRemove);
      
      // 인덱스 조정
      if (_flashCards.isNotEmpty) {
        // 마지막 카드였다면 이전 카드로 인덱스 이동
        if (indexToRemove >= _flashCards.length) {
          _currentCardIndex = _flashCards.length - 1;
        }
        // 그 외에는 현재 인덱스 유지 (자동으로 다음 카드가 보임)
      } else {
        // 카드가 모두 삭제된 경우 인덱스를 0으로 설정
        _currentCardIndex = 0;
      }
      
      notifyListeners();
      debugPrint("[FlashcardViewModel] 카드 삭제 완료. 남은 카드 수: ${_flashCards.length}");
      return true;
    } catch (e) {
      debugPrint("[FlashcardViewModel] 카드 삭제 중 오류 발생: $e");
      _error = "카드 삭제 중 오류 발생: $e";
      notifyListeners();
      return false;
    }
  }
} 