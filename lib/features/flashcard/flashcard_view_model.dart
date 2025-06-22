import 'package:flutter/foundation.dart';
import '../../core/models/flash_card.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../core/services/cache/cache_manager.dart';
import '../../core/services/authentication/auth_service.dart';
import '../sample/sample_data_service.dart';
import 'flashcard_repository.dart';

/// 플래시카드 UI 상태 관리 및 비즈니스 로직을 담당하는 ViewModel
class FlashCardViewModel extends ChangeNotifier {
  // 서비스 인스턴스
  final FlashCardRepository _repository;
  final TTSService _ttsService;
  final UsageLimitService _usageLimitService;
  final CacheManager _cacheManager;
  final AuthService _authService;
  final SampleDataService _sampleDataService;
  
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
    UsageLimitService? usageLimitService,
    CacheManager? cacheManager,
    bool isNoteCreation = false,  // 노트 생성 중인지 여부
  }) : 
    _noteId = noteId,
    _repository = repository ?? FlashCardRepository(cacheManager: cacheManager ?? CacheManager()),
    _ttsService = ttsService ?? TTSService(),
    _usageLimitService = usageLimitService ?? UsageLimitService(),
    _cacheManager = cacheManager ?? CacheManager(),
    _authService = AuthService(),
    _sampleDataService = SampleDataService() {
    
    // 초기 플래시카드가 제공된 경우 설정
    if (initialFlashcards != null) {
      _flashCards = initialFlashcards;
      extractFlashcardWords();
    }
    
    _initTts();
    
    // 노트 생성 중이 아니고 노트 ID가 설정된 경우에만 플래시카드 로드
    if (noteId.isNotEmpty && !isNoteCreation) {
      if (kDebugMode) {
        debugPrint('FlashCardViewModel: 기존 노트 플래시카드 로드 시작');
      }
      loadFlashCards();
    } else if (isNoteCreation && kDebugMode) {
      debugPrint('FlashCardViewModel: 노트 생성 중 - 플래시카드 로드 건너뜀');
    }
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
      // 로그아웃 상태이고 샘플 노트인 경우 샘플 플래시카드 로드
      if (_authService.currentUser == null && _noteId == 'sample_note_1') {
        await _sampleDataService.loadSampleData();
        _flashCards = _sampleDataService.getSampleFlashCards(_noteId);
        if (kDebugMode) {
          debugPrint('🃏 [FlashCard] 샘플 플래시카드 로드됨: ${_flashCards.length}개');
        }
      } else {
        _flashCards = await _repository.loadFlashCards(_noteId);
      }
      
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
    // 로그인 체크 - 로그아웃 상태에서는 플래시카드 생성 불가
    if (_authService.currentUser == null) {
      setError('플래시카드 생성은 로그인이 필요한 프리미엄 기능입니다');
      return false;
    }
    
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
    // 로그인 체크 - 로그아웃 상태에서는 플래시카드 삭제 불가
    if (_authService.currentUser == null) {
      setError('플래시카드 삭제는 샘플 모드에서는 지원되지 않습니다.');
      return false;
    }
    
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
    // 로그인 체크 - 로그아웃 상태에서는 플래시카드 삭제 불가
    if (_authService.currentUser == null) {
      setError('플래시카드 삭제는 샘플 모드에서는 지원되지 않습니다.');
      return false;
    }
    
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
      
      // 🔧 수정: 인덱스 조정 로직 개선
      if (_flashCards.isEmpty) {
        // 모든 카드가 삭제된 경우
        _currentCardIndex = 0;
      } else if (_currentCardIndex >= _flashCards.length) {
        // 마지막 카드를 삭제한 경우, 이전 카드로 이동
        _currentCardIndex = _flashCards.length - 1;
      }
      // 중간 카드를 삭제한 경우는 현재 인덱스 유지 (다음 카드가 자동으로 현재 위치로 이동)
      
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
  
  // 학습 진행 상태 업데이트
  Future<bool> updateReviewCount(String cardId) async {
    // 로그인 체크 - 로그아웃 상태에서는 복습 횟수 업데이트 건너뜀
    if (_authService.currentUser == null) {
      if (kDebugMode) {
        debugPrint('🃏 [FlashCard] 로그아웃 상태 - 복습 횟수 업데이트 건너뜀');
      }
      return true; // 오류 없이 성공으로 처리
    }
    
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
  
  // 현재 카드 인덱스 설정 (안전한 범위 보장)
  void setCurrentCardIndex(int index) {
    if (_flashCards.isNotEmpty) {
      _currentCardIndex = index.clamp(0, _flashCards.length - 1);
      _isCardFlipped = false;
      notifyListeners();
    } else {
      _currentCardIndex = 0;
      _isCardFlipped = false;
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

    if (_flashCards.isNotEmpty) {
      for (final card in _flashCards) {
        if (card.front.isNotEmpty) {
          newFlashcardWords.add(card.front);
        }
      }
    }

    // 변경 사항이 있는 경우에만 업데이트
    if (_flashcardWords.length != newFlashcardWords.length ||
        !_flashcardWords.containsAll(newFlashcardWords) ||
        !newFlashcardWords.containsAll(_flashcardWords)) {
      
      if (kDebugMode) {
        debugPrint('FlashCardViewModel: 플래시카드 단어 목록 업데이트: ${_flashcardWords.length} → ${newFlashcardWords.length}개');
      }

      _flashcardWords = newFlashcardWords;
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _ttsService.stop();
    _ttsService.dispose();
    
    // 앱 종료 전 플래시카드 저장
    if (_noteId.isNotEmpty && _flashCards.isNotEmpty) {
      _cacheManager.cacheFlashcards(_noteId, _flashCards);
    }
    
    super.dispose();
  }
}