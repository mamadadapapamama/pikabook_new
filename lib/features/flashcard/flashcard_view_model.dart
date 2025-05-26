import 'package:flutter/foundation.dart';
import '../../core/models/flash_card.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import 'flashcard_repository.dart';

/// 플래시카드 UI 상태 관리 및 비즈니스 로직을 담당하는 ViewModel
class FlashCardViewModel extends ChangeNotifier {
  // 서비스 인스턴스
  final FlashCardRepository _repository;
  final TTSService _ttsService;
  final UsageLimitService _usageLimitService;
  
  // 상태 변수
  bool _isLoading = false;
  String? _error;
  List<FlashCard> _flashCards = [];
  String _noteId = '';
  
  // UI 상태 변수
  bool _isSpeaking = false;      // TTS 실행 중 상태
  int _currentCardIndex = 0;     // 현재 플래시카드 인덱스
  bool _isCardFlipped = false;   // 카드 뒤집힘 상태
  
  // 플래시카드 단어 목록 (캐시)
  Set<String> _flashcardWords = {};
  
  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<FlashCard> get flashCards => _flashCards;
  int get count => _flashCards.length;
  bool get hasFlashcards => _flashCards.isNotEmpty;
  bool get isSpeaking => _isSpeaking;
  int get currentCardIndex => _currentCardIndex;
  bool get isCardFlipped => _isCardFlipped;
  Set<String> get flashcardWords => _flashcardWords;
  
  // 노트 ID 설정 (초기화 시 필요)
  FlashCardViewModel({
    String noteId = '', 
    List<FlashCard>? initialFlashcards,
    FlashCardRepository? repository,
    TTSService? ttsService,
    UsageLimitService? usageLimitService
  }) : 
    _repository = repository ?? FlashCardRepository(),
    _ttsService = ttsService ?? TTSService(),
    _usageLimitService = usageLimitService ?? UsageLimitService() {
    
    if (initialFlashcards != null && initialFlashcards.isNotEmpty) {
      _flashCards = initialFlashcards;
      _isLoading = false;
    }
    
    if (noteId.isNotEmpty) {
      _noteId = noteId;
      loadFlashCards();
    }
    
    _initTts();
  }
  
  // TTS 초기화
  Future<void> _initTts() async {
    try {
      await _ttsService.init();
      if (kDebugMode) {
        print('TTS 서비스 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        print('TTS 초기화 중 오류 발생: $e');
      }
    }
  }
  
  // 노트 ID 변경 및 카드 로드
  void setNoteId(String noteId) {
    _noteId = noteId;
    loadFlashCards();
  }
  
  // 플래시카드 로드
  Future<void> loadFlashCards() async {
    setLoading(true);
    setError(null);
    
    try {
      _flashCards = await _repository.loadFlashCards(_noteId);
      extractFlashcardWords(); // 단어 목록 업데이트
      setLoading(false);
      notifyListeners();
    } catch (e) {
      setError(e.toString().replaceAll('Exception: ', ''));
      setLoading(false);
    }
  }
  
  // 모든 플래시카드 로드
  Future<void> loadAllFlashCards() async {
    setLoading(true);
    setError(null);
    
    try {
      _flashCards = await _repository.loadAllFlashCards();
      extractFlashcardWords(); // 단어 목록 업데이트
      setLoading(false);
      notifyListeners();
    } catch (e) {
      setError(e.toString().replaceAll('Exception: ', ''));
      setLoading(false);
    }
  }
  
  // 플래시카드 추가
  Future<bool> addFlashCard(String word, String meaning, {String? pinyin}) async {
    setLoading(true);
    setError(null);
    
    try {
      // 이미 존재하는 플래시카드인지 확인
      final existingCardIndex = _flashCards.indexWhere((c) => c.front == word);
      
      if (existingCardIndex >= 0) {
        // 기존 카드 업데이트
        final card = _flashCards[existingCardIndex];
        final updatedCard = card.copyWith(
          back: meaning,
          pinyin: pinyin ?? card.pinyin,
        );
        
        final result = await _repository.updateFlashCard(updatedCard);
        _flashCards[existingCardIndex] = result;
      } else {
        // 새 카드 추가
        final createdCard = await _repository.addFlashCard(
          front: word,
          back: meaning,
          noteId: _noteId,
          pinyin: pinyin,
        );
        _flashCards.add(createdCard);
      }
      
      extractFlashcardWords(); // 단어 목록 업데이트
      setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      setError(e.toString().replaceAll('Exception: ', ''));
      setLoading(false);
      return false;
    }
  }
  
  // 플래시카드 삭제
  Future<bool> deleteFlashCard(String cardId) async {
    setLoading(true);
    setError(null);
    
    try {
      // 노트 ID 가져오기
      final cardIndex = _flashCards.indexWhere((card) => card.id == cardId);
      final String? noteIdForCard = cardIndex >= 0 ? _flashCards[cardIndex].noteId : _noteId;
      
      // Repository 메서드 호출
      await _repository.deleteFlashCard(cardId, noteId: noteIdForCard);
      
      // 로컬 상태 업데이트
      _flashCards.removeWhere((card) => card.id == cardId);
      extractFlashcardWords(); // 단어 목록 업데이트
      setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      setError(e.toString().replaceAll('Exception: ', ''));
      setLoading(false);
      return false;
    }
  }
  
  // 현재 카드 삭제
  Future<bool> deleteCurrentCard() async {
    if (_flashCards.isEmpty || _currentCardIndex >= _flashCards.length) {
      setError('삭제할 카드가 없습니다');
      return false;
    }
    
    // 현재 카드의 ID를 사용하여 삭제
    final cardId = _flashCards[_currentCardIndex].id;
    final cardIndex = _currentCardIndex;
    final noteIdForCard = _flashCards[cardIndex].noteId;
    
    setLoading(true);
    setError(null);
    
    try {
      // 카드 삭제
      await _repository.deleteFlashCard(cardId, noteId: noteIdForCard);
      
      // 로컬 상태 업데이트
      _flashCards.removeWhere((card) => card.id == cardId);
      
      // 인덱스 조정이 필요한지 확인
      if (cardIndex >= _flashCards.length && _flashCards.isNotEmpty) {
        _currentCardIndex = _flashCards.length - 1;
      }
      
      setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      setError(e.toString().replaceAll('Exception: ', ''));
      setLoading(false);
      return false;
    }
  }
  
  // 학습 진행 상태 업데이트
  Future<bool> updateReviewCount(String cardId) async {
    final index = _flashCards.indexWhere((card) => card.id == cardId);
    if (index < 0) {
      setError('존재하지 않는 카드입니다');
      return false;
    }
    
    setLoading(true);
    setError(null);
    
    try {
      // 카드 업데이트 준비
      final card = _flashCards[index];
      final updatedCard = card.copyWith(
        reviewCount: card.reviewCount + 1,
        lastReviewedAt: DateTime.now(),
      );
      
      // Repository를 통해 업데이트
      final result = await _repository.updateFlashCard(updatedCard);
      
      // 로컬 상태 업데이트
      _flashCards[index] = result;
      
      setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      setError(e.toString().replaceAll('Exception: ', ''));
      setLoading(false);
      return false;
    }
  }
  
  // 특정 단어가 플래시카드로 등록되어 있는지 확인
  bool isWordInFlashCards(String word) {
    return _repository.isWordInFlashCards(word, _flashCards);
  }
  
  // 단어에 해당하는 플래시카드 가져오기
  FlashCard? getFlashCardForWord(String word) {
    return _repository.getFlashCardForWord(word, _flashCards);
  }

  // 로딩 상태 변경
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  // 오류 설정
  void setError(String? errorMessage) {
    _error = errorMessage;
    notifyListeners();
  }
  
  // 현재 카드 인덱스 설정
  void setCurrentCardIndex(int index) {
    if (index >= 0 && index < _flashCards.length) {
      _currentCardIndex = index;
      _isCardFlipped = false;
      notifyListeners();
    }
  }
  
  // 카드 뒤집기 상태 토글
  void toggleCardFlip() {
    _isCardFlipped = !_isCardFlipped;
    notifyListeners();
  }
  
  // 다음 카드 정보 가져오기
  String? getNextCardInfo() {
    if (_currentCardIndex < _flashCards.length - 1) {
      return _flashCards[_currentCardIndex + 1].front;
    }
    return null;
  }

  // 이전 카드 정보 가져오기
  String? getPreviousCardInfo() {
    if (_currentCardIndex > 0) {
      return _flashCards[_currentCardIndex - 1].front;
    }
    return null;
  }
  
  // 단어를 사전에서 검색
  Future<void> searchWordInDictionary(String word, Function(bool) onLoadingChanged, 
      Function(String) showMessage) async {
    if (word.isEmpty) return;

    onLoadingChanged(true);
    
    // TODO: 실제 사전 검색 API 호출 구현
    // 임시로 지연 시간만 추가
    await Future.delayed(const Duration(milliseconds: 500));
    
    onLoadingChanged(false);
    showMessage('사전 검색 기능은 현재 개발 중입니다: $word');
  }
  
  /// 플래시카드 단어 목록 추출
  void extractFlashcardWords() {
    final Set<String> newFlashcardWords = {};

    if (kDebugMode) {
      debugPrint('FlashCardViewModel: extractFlashcardWords 호출');
    }

    if (_flashCards.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('FlashCardViewModel: 플래시카드 목록 수: ${_flashCards.length}개');
      }

      for (final card in _flashCards) {
        if (card.front.isNotEmpty) {
          newFlashcardWords.add(card.front);
        }
      }

      if (_flashCards.isNotEmpty && kDebugMode) {
        debugPrint(
            'FlashCardViewModel: 첫 5개 플래시카드: ${_flashCards.take(5).map((card) => card.front).join(', ')}');
      }
    } else if (kDebugMode) {
      debugPrint('FlashCardViewModel: 플래시카드 목록이 비어있음');
    }

    // 변경 사항이 있는 경우에만 업데이트
    if (_flashcardWords.length != newFlashcardWords.length ||
        !_flashcardWords.containsAll(newFlashcardWords) ||
        !newFlashcardWords.containsAll(_flashcardWords)) {
      if (kDebugMode) {
        debugPrint('FlashCardViewModel: 플래시카드 단어 목록 변경 감지:');
        debugPrint('  이전: ${_flashcardWords.length}개');
        debugPrint('  새로운: ${newFlashcardWords.length}개');
      }

      _flashcardWords = newFlashcardWords;
      notifyListeners();

      if (kDebugMode) {
        debugPrint('FlashCardViewModel: 플래시카드 단어 목록 업데이트 완료: ${_flashcardWords.length}개');
        if (_flashcardWords.isNotEmpty) {
          debugPrint('FlashCardViewModel: 첫 5개 단어: ${_flashcardWords.take(5).join(', ')}');
        }
      }
    } else if (kDebugMode) {
      debugPrint('FlashCardViewModel: 플래시카드 단어 목록 변경 없음: ${_flashcardWords.length}개');
    }
  }
  
  @override
  void dispose() {
    _ttsService.stop();
    _ttsService.dispose();
    
    // 앱 종료 전 플래시카드 저장
    if (_noteId.isNotEmpty && _flashCards.isNotEmpty) {
      _repository.cacheFlashcards(_noteId, _flashCards);
    }
    
    super.dispose();
  }
}