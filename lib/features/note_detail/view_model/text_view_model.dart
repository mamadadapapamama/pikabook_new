import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import '../../../core/services/cache/unified_cache_service.dart';
import '../../../core/services/text_processing/llm_text_processing.dart';
import '../../../core/services/text_processing/enhanced_ocr_service.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/flash_card.dart';

/// TextViewModel 상태를 나타내는 클래스
/// 복잡한 내부 상태를 외부에 간단히 노출하기 위한 데이터 구조
class TextViewState {
  final bool isReady;      // 텍스트 처리가 완료되었는지 여부
  final bool hasError;     // 오류가 발생했는지 여부
  final String? errorMsg;  // 오류 메시지
  final List<TextUnit> segments; // 텍스트 세그먼트
  final bool isFullTextMode; // 전체 텍스트 모드 여부
  final Set<String> flashcardWords; // 플래시카드 단어 목록
  
  const TextViewState({
    this.isReady = false,
    this.hasError = false,
    this.errorMsg,
    this.segments = const [],
    this.isFullTextMode = false,
    this.flashcardWords = const {},
  });
  
  // 복사 메서드
  TextViewState copyWith({
    bool? isReady,
    bool? hasError,
    String? errorMsg,
    List<TextUnit>? segments,
    bool? isFullTextMode,
    Set<String>? flashcardWords,
  }) {
    return TextViewState(
      isReady: isReady ?? this.isReady,
      hasError: hasError ?? this.hasError,
      errorMsg: errorMsg ?? this.errorMsg,
      segments: segments ?? this.segments,
      isFullTextMode: isFullTextMode ?? this.isFullTextMode,
      flashcardWords: flashcardWords ?? this.flashcardWords,
    );
  }
}

/// TTS 상태를 나타내는 열거형
enum AudioState {
  idle,    // 재생 중이 아님
  playing, // 재생 중
  paused,  // 일시 중지됨
  error    // 오류 발생
}

/// 텍스트 처리 및 세그먼트 관리를 담당하는 ViewModel
class TextViewModel extends ChangeNotifier {
  // 서비스 인스턴스
  final LLMTextProcessing _textProcessingService = LLMTextProcessing();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();

  // 상태 변수
  bool _isLoading = false;
  String? _error;
  bool _isFullTextMode = false;
  ProcessedText? _processedText;
  String _currentPageId = '';
  
  // 플래시카드 관련 변수
  Set<String> _flashcardWords = {};
  
  // TTS 관련 상태
  int? _playingSegmentIndex;
  AudioState _audioState = AudioState.idle;
  
  // ID - 여러 뷰모델 인스턴스를 구분하기 위한 식별자
  final String id;
  
  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasError => _error != null;
  bool get isReady => _processedText != null && !_isLoading;
  bool get isFullTextMode => _isFullTextMode;
  ProcessedText? get processedText => _processedText;
  List<TextUnit> get segments => _processedText?.units ?? [];
  
  // 플래시카드 관련 getter
  Set<String> get flashcardWords => _flashcardWords;
  
  // TTS 관련 getter
  int? get playingSegmentIndex => _playingSegmentIndex;
  AudioState get audioState => _audioState;
  
  // 간소화된 상태 getter
  TextViewState get state => TextViewState(
    isReady: isReady,
    hasError: hasError,
    errorMsg: _error,
    segments: segments,
    isFullTextMode: _isFullTextMode,
    flashcardWords: _flashcardWords,
  );
  
  /// 생성자
  /// [id]는 여러 TextViewModel 인스턴스를 구분하기 위한 식별자 (기본값: 빈 문자열)
  TextViewModel({this.id = ''});
  
  /// ProcessedText로 직접 초기화
  void initialize(ProcessedText processedText) {
    _processedText = processedText;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
  
  // 페이지 설정 및 초기화
  Future<void> setPageId(String pageId) async {
    if (_currentPageId == pageId && _processedText != null) return;
    
    _currentPageId = pageId;
    _processedText = null;
    
    notifyListeners();
    
    if (pageId.isNotEmpty) {
      await loadProcessedText(pageId);
    }
  }
  
  // 처리된 텍스트 로드
  Future<ProcessedText?> loadProcessedText(String pageId) async {
    if (pageId.isEmpty) {
      setError('페이지 ID가 비어있습니다');
      return null;
    }
    
    setLoading(true);
    setError(null);
    
    try {
      // 캐시에서 처리된 텍스트 가져오기
      final cachedText = await getProcessedText(pageId);
      
      if (cachedText != null) {
        _processedText = cachedText;
        setLoading(false);
        notifyListeners();
        return cachedText;
      }
      
      setLoading(false);
      return null;
    } catch (e) {
      setError('처리된 텍스트 로드 중 오류 발생: $e');
      setLoading(false);
      return null;
    }
  }

  // 텍스트 처리 (OCR, 번역, 분할 등)
  Future<ProcessedText?> processPageText(page_model.Page page, {File? imageFile}) async {
    if (page.id.isEmpty) {
      setError('페이지 ID가 없습니다');
      return null;
    }
    
    setLoading(true);
    setError(null);
    
    try {
      // 이미 처리된 텍스트가 있는지 확인
      final cachedText = await getProcessedText(page.id);
      if (cachedText != null) {
        _processedText = cachedText;
        setLoading(false);
        notifyListeners();
        return cachedText;
      }
      
      // 원본 텍스트 가져오기 - Page 모델에는 text 필드가 없으므로 이미지만 처리
      String textToProcess = '';
      if (imageFile != null) {
        // OCR 서비스의 recognizeText 메서드 사용
        textToProcess = await _ocrService.recognizeText(imageFile);
        
        if (textToProcess.isEmpty) {
          setError('이미지에서 텍스트를 추출할 수 없습니다');
          setLoading(false);
          return null;
        }
      }
      
      if (textToProcess.isEmpty) {
        setError('처리할 텍스트가 없습니다');
        setLoading(false);
        return null;
      }
      
      // LLM 처리 (텍스트 분할, 번역, 병음 등)
      final processedText = await _textProcessingService.processText(
        textToProcess,
        sourceLanguage: page.sourceLanguage,
        targetLanguage: page.targetLanguage,
        needPinyin: true,
      );
      
      if (processedText == null) {
        setError('텍스트 처리 실패');
        setLoading(false);
        return null;
      }
      
      // 캐시에 저장
      await setProcessedText(page.id, processedText);
      
      _processedText = processedText;
      setLoading(false);
      notifyListeners();
      return processedText;
    } catch (e) {
      setError('텍스트 처리 중 오류 발생: $e');
      setLoading(false);
      return null;
    }
  }
  
  // 전체 텍스트 모드 전환
  void toggleFullTextMode() {
    _isFullTextMode = !_isFullTextMode;
    notifyListeners();
  }
  
  // 텍스트 표시 모드 전환 (병음 표시 여부 등)
  void toggleDisplayMode() {
    if (_processedText == null) return;
    
    final currentMode = _processedText!.displayMode;
    final newMode = currentMode == TextDisplayMode.full 
        ? TextDisplayMode.noPinyin 
        : TextDisplayMode.full;
    
    _processedText = _processedText!.copyWith(displayMode: newMode);
    notifyListeners();
  }
  
  // 세그먼트 삭제
  Future<bool> deleteSegment(int segmentIndex, String pageId, page_model.Page page) async {
    if (_processedText == null || 
        _processedText!.units.isEmpty || 
        segmentIndex < 0 || 
        segmentIndex >= _processedText!.units.length) {
      setError('유효하지 않은 세그먼트 인덱스');
      return false;
    }
    
    try {
      // 유닛 목록 복사
      final updatedUnits = List<TextUnit>.from(_processedText!.units);
      
      // 세그먼트 삭제
      updatedUnits.removeAt(segmentIndex);
      
      // 전체 텍스트 다시 조합
      String updatedFullOriginalText = '';
      String updatedFullTranslatedText = '';
      
      for (final unit in updatedUnits) {
        updatedFullOriginalText += unit.originalText;
        if (unit.translatedText != null) {
          updatedFullTranslatedText += unit.translatedText!;
        }
      }
      
      // 업데이트된 ProcessedText 생성
      final updatedProcessedText = _processedText!.copyWith(
        units: updatedUnits,
        fullOriginalText: updatedFullOriginalText,
        fullTranslatedText: updatedFullTranslatedText,
      );
      
      // 캐시 업데이트
      await setProcessedText(pageId, updatedProcessedText);
      
      _processedText = updatedProcessedText;
      notifyListeners();
      
      return true;
    } catch (e) {
      setError('세그먼트 삭제 중 오류 발생: $e');
      return false;
    }
  }
  
  // 캐시 관련 메서드
  Future<ProcessedText?> getProcessedText(String pageId) async {
    try {
      // 세그먼트 캐싱 사용
      final segments = await _cacheService.getSegments(pageId, TextProcessingMode.paragraph);
      
      if (segments == null || segments.isEmpty) return null;
      
      // 세그먼트를 TextUnit 리스트로 변환
      final units = segments.map((segment) => TextUnit(
        originalText: segment['original'] ?? '',
        translatedText: segment['translated'] ?? '',
        pinyin: segment['pinyin'] ?? '',
        sourceLanguage: 'zh-CN', // 기본값 사용
        targetLanguage: 'ko',    // 기본값 사용
      )).toList();
      
      // 전체 텍스트 구성
      String fullOriginalText = '';
      String fullTranslatedText = '';
      
      for (final unit in units) {
        fullOriginalText += unit.originalText;
        if (unit.translatedText != null) {
          fullTranslatedText += unit.translatedText!;
        }
      }
      
      // ProcessedText 객체 생성
      return ProcessedText(
        mode: TextProcessingMode.segment,
        displayMode: TextDisplayMode.full,
        fullOriginalText: fullOriginalText,
        fullTranslatedText: fullTranslatedText,
        units: units,
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
      );
    } catch (e) {
      if (kDebugMode) {
        print('캐시에서 처리된 텍스트 가져오기 실패: $e');
      }
      return null;
    }
  }
  
  Future<void> setProcessedText(String pageId, ProcessedText processedText) async {
    try {
      // TextUnit을 세그먼트 맵으로 변환
      final segments = processedText.units.map((unit) => {
        'original': unit.originalText,
        'translated': unit.translatedText ?? '',
        'pinyin': unit.pinyin ?? '',
      }).toList();
      
      // 세그먼트 캐싱 사용
      await _cacheService.cacheSegments(pageId, TextProcessingMode.paragraph, segments);
    } catch (e) {
      if (kDebugMode) {
        print('캐시에 처리된 텍스트 저장 실패: $e');
      }
    }
  }
  
  Future<void> clearCache() async {
    try {
      await _cacheService.clear();
    } catch (e) {
      if (kDebugMode) {
        print('캐시 정리 실패: $e');
      }
    }
  }
  
  // 플래시카드 관련 메서드
  // 플래시카드 단어 추출
  Future<void> extractFlashcardWords(List<FlashCard>? flashCards) async {
    if (flashCards == null) {
      _flashcardWords = {};
      notifyListeners();
      return;
    }
    
    final Set<String> newFlashcardWords = {};
    
    for (final card in flashCards) {
      if (card.front.isNotEmpty) {
        newFlashcardWords.add(card.front);
      }
    }
    
    // 변경 사항이 있는 경우에만 상태 업데이트
    if (_flashcardWords.length != newFlashcardWords.length ||
        !_flashcardWords.containsAll(newFlashcardWords) ||
        !newFlashcardWords.containsAll(_flashcardWords)) {
      
      _flashcardWords = newFlashcardWords;
      notifyListeners();
    }
  }
  
  // 플래시카드 생성 처리
  Future<void> createFlashCard(String word, String meaning, {String? pinyin}) async {
    // 중복 체크
    if (_flashcardWords.contains(word)) return;
    
    // 플래시카드 목록에 추가
    _flashcardWords.add(word);
    notifyListeners();
  }
  
  // TTS 재생 처리
  Future<void> playTts(String text, {int? segmentIndex}) async {
    // 현재 재생 중인 세그먼트 설정
    _playingSegmentIndex = segmentIndex;
    _audioState = AudioState.playing;
    notifyListeners();
    
    try {
      // TTS 재생 로직 (실제 구현은 TTSService에서 처리)
      // 이 메서드는 주로 현재 재생 중인 세그먼트 상태를 관리합니다.
      
      // 실제 TTS 서비스 호출 로직은 여기서 구현하거나,
      // 외부 TTS 서비스/뷰모델에 위임할 수 있습니다.
    } catch (e) {
      setError('TTS 재생 중 오류 발생: $e');
      _audioState = AudioState.error;
      notifyListeners();
    }
  }
  
  // TTS 일시 중지
  void pauseTts() {
    if (_audioState == AudioState.playing) {
      _audioState = AudioState.paused;
      notifyListeners();
    }
  }
  
  // TTS 재생 종료
  void stopTts() {
    _playingSegmentIndex = null;
    _audioState = AudioState.idle;
    notifyListeners();
  }
  
  // 상태 관리 메서드
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  void setError(String? errorMessage) {
    _error = errorMessage;
    if (errorMessage != null && kDebugMode) {
      print('TextViewModel 오류: $errorMessage');
    }
    notifyListeners();
  }
  
  /// 상태 초기화 - 여러 TextViewModel 인스턴스를 관리할 때 유용
  void reset() {
    _isLoading = false;
    _error = null;
    _processedText = null;
    _currentPageId = '';
    _flashcardWords = {};
    _playingSegmentIndex = null;
    _audioState = AudioState.idle;
    notifyListeners();
  }
  
  @override
  void dispose() {
    // 리소스 정리
    super.dispose();
  }
}
