import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/models/note.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import '../../../core/models/processing_status.dart';
import '../services/page_service.dart';
import '../managers/note_options_manager.dart';
import '../services/note_service.dart';
import '../../../core/services/text_processing/text_processing_service.dart';
import '../../sample/sample_data_service.dart';
import '../../flashcard/flashcard_service.dart' hide debugPrint;
import '../../../core/models/flash_card.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../sample/sample_tts_service.dart';
import '../services/dynamic_page_loader_service.dart';

/// 노트 상세 화면 ViewModel - 핵심 기능만 관리
class NoteDetailViewModel extends ChangeNotifier {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final TextProcessingService _textProcessingService = TextProcessingService();
  final NoteOptionsManager noteOptionsManager = NoteOptionsManager();
  final SampleDataService _sampleDataService = SampleDataService();
  
  // 추가된 서비스들
  late FlashCardService _flashCardService;
  late TTSService _ttsService;
  late SampleTtsService _sampleTtsService;
  
  // PageService 접근
  PageService get _pageService => _noteService.pageService;
  
  // dispose 상태 추적
  bool _disposed = false;
  
  // === 핵심 UI 상태 ===
  Note? _note;
  bool _isLoading = true;
  String? _error;
  List<page_model.Page>? _pages;
  int _currentPageIndex = 0;
  
  // 백그라운드 처리 상태
  bool _isProcessingBackground = false;
  
  // 텍스트 관련 상태 (페이지별)
  final Map<String, ProcessedText> _processedTexts = {};
  final Map<String, bool> _textLoadingStates = {};
  final Map<String, String?> _textErrors = {};
  // TODO: ProcessedText의 StreamingStatus로 통합 예정
  final Map<String, ProcessingStatus> _pageStatuses = {};
  
  // 플래시카드 상태
  List<FlashCard> _flashcards = [];
  
  // PageController
  final PageController pageController = PageController();
  
  // 노트 ID
  final String _noteId;
  
  // 실시간 리스너들
  final Map<String, StreamSubscription<DocumentSnapshot>> _pageListeners = {};
  
  // 샘플 모드 여부 확인
  bool get _isSampleMode => FirebaseAuth.instance.currentUser == null && _noteId == 'sample_note_1';
  
  // 동적 페이지 로더 서비스
  DynamicPageLoaderService? _dynamicPageLoaderService;
  
  // === Getters ===
  String get noteId => _noteId;
  List<page_model.Page>? get pages => _pages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Note? get note => _note;
  int get currentPageIndex => _currentPageIndex;
  bool get isProcessingBackground => _isProcessingBackground;
  List<FlashCard> get flashcards => _flashcards;
  
  // 현재 페이지 (실제 로드된 페이지만 반환, 아직 로드되지 않은 페이지는 null)
  page_model.Page? get currentPage {
    if (_pages == null || _pages!.isEmpty || _currentPageIndex >= _pages!.length) {
      return null;
    }
    return _pages![_currentPageIndex];
  }
  
  // 현재 페이지의 텍스트
  ProcessedText? get currentProcessedText {
    if (currentPage == null) return null;
    return _processedTexts[currentPage!.id];
  }

  // 전체 페이지 수 (업로드된 이미지 수)
  int get totalPages => _note?.pageCount ?? 0;

  // 현재 노트의 실제 텍스트 처리 모드 (첫 번째 페이지 기준)
  TextProcessingMode? get currentNoteMode {
    if (_processedTexts.isEmpty) return null;
    
    // 첫 번째 완료된 페이지의 모드를 반환
    for (final processedText in _processedTexts.values) {
      if (processedText != null) {
        return processedText.mode;
      }
    }
    
    return null;
  }

  // 현재 노트가 세그먼트 모드인지 확인
  bool get isCurrentNoteSegmentMode => currentNoteMode == TextProcessingMode.segment;

  // 페이지별 처리 상태 배열 생성 (ProcessedText의 스트리밍 상태 활용)
  List<bool> get processedPages {
    final total = totalPages;
    final result = <bool>[];
    
    for (int i = 0; i < total; i++) {
      if (i < (_pages?.length ?? 0)) {
        // 실제 로드된 페이지 - ProcessedText의 스트리밍 상태 확인
        final page = _pages![i];
        final processedText = _processedTexts[page.id];
        result.add(processedText?.isCompleted ?? false);
      } else {
        // 아직 로드되지 않은 페이지
        result.add(false);
      }
    }
    
    return result;
  }
  
  // 페이지별 처리 중 상태 배열 생성 (ProcessedText의 스트리밍 상태 활용)
  List<bool> get processingPages {
    final total = totalPages;
    final result = <bool>[];
    
    for (int i = 0; i < total; i++) {
      if (i < (_pages?.length ?? 0)) {
        // 실제 로드된 페이지 - ProcessedText의 스트리밍 상태 확인
        final page = _pages![i];
        final processedText = _processedTexts[page.id];
        final isLoading = _textLoadingStates[page.id] ?? false;
        result.add(processedText?.isStreaming == true || isLoading);
      } else {
        // 아직 로드되지 않은 페이지 (처리 중으로 간주)
        result.add(true);
      }
    }
    
    return result;
  }

  /// 생성자
  NoteDetailViewModel({
    required String noteId,
    Note? initialNote,
    bool isProcessingBackground = false,
  }) : _noteId = noteId, _isProcessingBackground = isProcessingBackground {
    _note = initialNote;
    
    // 초기 데이터 로드
    Future.microtask(() async {
      // 서비스 초기화
      await _initializeServices();
      
      if (initialNote == null && noteId.isNotEmpty) {
        await _loadNoteInfo();
      }
      await loadInitialPages();
      
      // 동적 페이지 로더 서비스 시작 (샘플 모드 제외)
      if (!_isSampleMode) {
        _dynamicPageLoaderService = DynamicPageLoaderService(
          noteId: _noteId,
          onNewOrUpdatedPage: _onNewOrUpdatedPage,
        );
        await _dynamicPageLoaderService!.start();
      }
      // 플래시카드 로드
      await loadFlashcards();
    });
  }

  /// 서비스 초기화
  Future<void> _initializeServices() async {
    try {
      _flashCardService = FlashCardService();
      _ttsService = TTSService();
      _sampleTtsService = SampleTtsService();
      
      if (!_isSampleMode) {
        await _ttsService.init();
      }
      
      if (kDebugMode) {
        print('TTS 서비스 초기화 완료 (샘플 모드: $_isSampleMode)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('서비스 초기화 중 오류: $e');
      }
    }
  }

  /// 플래시카드 로드
  Future<void> loadFlashcards() async {
    try {
      List<FlashCard> cards;
      
      if (_isSampleMode) {
        // 샘플 모드: SampleDataService 사용
        await _sampleDataService.loadSampleData();
        cards = _sampleDataService.getSampleFlashCards(_noteId);
        if (kDebugMode) {
          print('🃏 샘플 플래시카드 로드됨: ${cards.length}개');
        }
      } else {
        // 일반 모드: FlashCardService 사용
        cards = await _flashCardService.getFlashCardsForNote(_noteId);
      }
      
      _flashcards = cards;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('플래시카드 로드 실패: $e');
      }
    }
  }

  /// 노트 정보 로드
  Future<void> _loadNoteInfo() async {
    _isLoading = true;
    
    try {
      final loadedNote = await _noteService.getNoteById(_noteId);
      if (loadedNote != null) {
        _note = loadedNote;
        _isLoading = false;
        notifyListeners();
      } else {
        _isLoading = false;
        _error = "노트를 찾을 수 없습니다.";
        notifyListeners();
      }
    } catch (e) {
      _isLoading = false;
      _error = "노트 로드 중 오류가 발생했습니다: $e";
      notifyListeners();
    }
  }

  /// 노트 정보 새로고침 (제목 변경 등 후 호출)
  Future<void> refreshNoteInfo() async {
    try {
      final loadedNote = await _noteService.getNoteById(_noteId);
      if (loadedNote != null) {
        _note = loadedNote;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('노트 정보 새로고침 실패: $e');
      }
    }
  }

  /// 초기 페이지 로드
  Future<void> loadInitialPages() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      List<page_model.Page> pages;
      
      if (_isSampleMode) {
        // 샘플 모드: SampleDataService 사용
        await _sampleDataService.loadSampleData();
        pages = _sampleDataService.getSamplePages(_noteId);
        if (kDebugMode) {
          debugPrint('📄 샘플 페이지 로드됨: ${pages.length}개');
        }
      } else {
        // 일반 모드: PageService 사용
        pages = await _pageService.getPagesForNote(_noteId);
      }
      
      _pages = pages;
      _isLoading = false;
      notifyListeners();
      
      // 모든 페이지에 대한 실시간 리스너 설정
      _setupAllPageListeners();
      
      // 현재 페이지 텍스트 로드
      if (currentPage != null) {
        await loadCurrentPageText();
      }
      
    } catch (e) {
      _isLoading = false;
      _error = "페이지 로드 중 오류가 발생했습니다: $e";
      notifyListeners();
    }
  }

  /// 동적으로 새로운 페이지가 감지되거나 변경될 때 호출되는 콜백
  void _onNewOrUpdatedPage(page_model.Page page) {
    if (_disposed) return;
    final exists = _pages?.any((p) => p.id == page.id) ?? false;
    if (!exists) {
      // 새 페이지 추가
      final updatedPages = List<page_model.Page>.from(_pages ?? []);
      updatedPages.add(page);
      updatedPages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
      _pages = updatedPages;
      if (kDebugMode) {
        debugPrint('✅ [동적 로드] 페이지 목록 업데이트: \\${_pages!.length}개 페이지');
      }
      notifyListeners();
    } else {
      // 기존 페이지 정보 갱신
      final updatedPages = List<page_model.Page>.from(_pages ?? []);
      final idx = updatedPages.indexWhere((p) => p.id == page.id);
      if (idx != -1) {
        updatedPages[idx] = page;
        _pages = updatedPages;
        notifyListeners();
      }
    }
  }

  /// 모든 페이지 리스너 설정
  void _setupAllPageListeners() {
    if (_disposed) return;
    // 모든 페이지의 초기 상태를 배치로 로드 (UI 리빌드 최소화)
    _loadAllPagesInitialStatus();
    if (_isSampleMode) {
      // 샘플 모드: 로드된 페이지에만 리스너 설정
      if (_pages != null) {
        for (final page in _pages!) {
          if (page.id.isNotEmpty) {
            _setupPageListener(page.id);
          }
        }
      }
    }
    // 일반 모드에서는 동적 페이지 로더 서비스가 리스너 관리
  }

  /// 모든 페이지 초기 상태 배치 로드 (UI 리빌드 최소화)
  Future<void> _loadAllPagesInitialStatus() async {
    if (_disposed || _pages == null) return;
    
    bool hasAnyUpdate = false;
    
    // 모든 페이지의 상태를 병렬로 로드
    final futures = _pages!.map((page) => _loadSinglePageInitialStatus(page.id)).toList();
    final results = await Future.wait(futures);
    
    // 결과를 한 번에 적용
    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      if (result != null) {
        final pageId = _pages![i].id;
        _processedTexts[pageId] = result['processedText'];
        _pageStatuses[pageId] = result['status'];
        hasAnyUpdate = true;
      }
    }
    
    // 한 번만 UI 업데이트
    if (hasAnyUpdate && !_disposed) {
      notifyListeners();
    }
  }

  /// 단일 페이지 초기 상태 로드 (UI 업데이트 없음)
  Future<Map<String, dynamic>?> _loadSinglePageInitialStatus(String pageId) async {
    if (_disposed) return null;
    
    try {
      ProcessedText? processedText;
      
      if (_isSampleMode) {
        // 샘플 모드: SampleDataService 사용
        processedText = _sampleDataService.getProcessedText(pageId);
      } else {
        // 일반 모드: TextProcessingService 사용
        processedText = await _textProcessingService.getProcessedText(pageId);
      }
      
      if (_disposed) return null;
      
      if (processedText != null) {
        return {
          'processedText': processedText,
          'status': ProcessingStatus.completed,
        };
      } else {
        ProcessingStatus status;
        if (_isSampleMode) {
          // 샘플 모드에서는 텍스트가 없으면 실패로 간주
          status = ProcessingStatus.failed;
        } else {
          status = await _textProcessingService.getProcessingStatus(pageId);
        }
        
        if (_disposed) return null;
        
        return {
          'processedText': null,
          'status': status,
        };
      }
    } catch (e) {
      if (_disposed) return null;
      
      return {
        'processedText': null,
        'status': ProcessingStatus.failed,
      };
    }
  }

  /// 현재 페이지 텍스트 로드
  Future<void> loadCurrentPageText() async {
    if (_disposed || currentPage == null) return;
    
    final pageId = currentPage!.id;
    if (pageId.isEmpty || _processedTexts.containsKey(pageId)) return;
    
    _textLoadingStates[pageId] = true;
    _textErrors[pageId] = null;
    if (!_disposed) notifyListeners();
    
    // 샘플 모드가 아닌 경우에만 리스너 설정
    if (!_isSampleMode) {
      _setupPageListener(pageId);
    }
    
    try {
      ProcessedText? processedText;
      
      if (_isSampleMode) {
        // 샘플 모드: SampleDataService 사용
        processedText = _sampleDataService.getProcessedText(pageId);
        
        if (processedText != null) {
          _processedTexts[pageId] = processedText;
          _pageStatuses[pageId] = ProcessingStatus.completed;
          if (kDebugMode) {
            debugPrint('📝 샘플 텍스트 로드됨: $pageId');
          }
        } else {
          _pageStatuses[pageId] = ProcessingStatus.failed;
          _textErrors[pageId] = '샘플 텍스트를 찾을 수 없습니다';
        }
      } else {
        // 일반 모드: Firebase 및 TextProcessingService 사용
        // 페이지 에러 상태 확인
        final pageDoc = await FirebaseFirestore.instance
            .collection('pages')
            .doc(pageId)
            .get();
        
        if (pageDoc.exists) {
          final pageData = pageDoc.data() as Map<String, dynamic>;
          final status = pageData['status'] as String?;
          final errorMessage = pageData['errorMessage'] as String?;
          
          if (status == ProcessingStatus.failed.toString() && errorMessage != null) {
            if (_disposed) return;
            
            _textLoadingStates[pageId] = false;
            _textErrors[pageId] = errorMessage;
            _pageStatuses[pageId] = ProcessingStatus.failed;
            
            if (!_disposed) notifyListeners();
            return;
          }
        }
        
        // 텍스트 처리 서비스 사용
        processedText = await _textProcessingService.getProcessedText(pageId);
        
        if (_disposed) return;
        
        if (processedText != null) {
          _processedTexts[pageId] = processedText;
          _pageStatuses[pageId] = ProcessingStatus.completed;
        } else {
          final status = await _textProcessingService.getProcessingStatus(pageId);
          if (_disposed) return;
          _pageStatuses[pageId] = status;
        }
      }
      
      _textLoadingStates[pageId] = false;
      if (!_disposed) notifyListeners();
      
    } catch (e) {
      if (_disposed) return;
      
      _textLoadingStates[pageId] = false;
      _textErrors[pageId] = '텍스트 로드 중 오류: $e';
      _pageStatuses[pageId] = ProcessingStatus.failed;
      if (!_disposed) notifyListeners();
    }
  }

  /// 페이지 실시간 리스너 설정
  void _setupPageListener(String pageId) {
    if (_disposed) return;
    
    // 기존 리스너 정리
    _pageListeners[pageId]?.cancel();
    
    // 새 리스너 설정
    final listener = _textProcessingService.listenToPageChanges(
      pageId,
      (processedText) {
        if (_disposed || processedText == null) return;
        
        final previousProcessedText = _processedTexts[pageId];
        
        // 실제 변경이 있는 경우에만 업데이트
        bool hasChange = false;
        if (previousProcessedText == null) {
          hasChange = true;
        } else {
          if (previousProcessedText.units.length != processedText.units.length ||
              previousProcessedText.fullTranslatedText != processedText.fullTranslatedText) {
            hasChange = true;
          }
        }
        
        if (hasChange) {
          _processedTexts[pageId] = processedText;
          _pageStatuses[pageId] = ProcessingStatus.completed;
          
          if (!_disposed) notifyListeners();
        }
      },
    );
    
    if (listener != null) {
      _pageListeners[pageId] = listener;
    }
  }

  /// 페이지 변경 이벤트
  void onPageChanged(int index) {
    if (index < 0 || index >= totalPages || _currentPageIndex == index) return;
    
    _currentPageIndex = index;
    notifyListeners();
    
    // 실제 페이지가 로드되어 있으면 텍스트 로드 시도
    if (_pages != null && index < _pages!.length) {
      Future.microtask(() async {
        await loadCurrentPageText();
      });
    }
  }

  /// 프로그램적 페이지 이동
  void navigateToPage(int index) {
    if (index < 0 || index >= totalPages) return;
    if (_currentPageIndex == index) return;
    
    pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 페이지별 텍스트 데이터 가져오기
  Map<String, dynamic> getTextViewModel(String pageId) {
    if (pageId.isEmpty) {
      throw ArgumentError('페이지 ID가 비어있습니다');
    }
    
    return {
      'processedText': _processedTexts[pageId],
      'segments': _processedTexts[pageId]?.units ?? <TextUnit>[],
      'isLoading': _textLoadingStates[pageId] ?? false,
      'error': _textErrors[pageId],
      'status': _pageStatuses[pageId] ?? ProcessingStatus.created,
    };
  }

  /// 페이지 에러 상태 초기화
  void clearPageError(String pageId) {
    if (_disposed) return;
    
    _textErrors.remove(pageId);
    _textLoadingStates[pageId] = false;
    
    if (!_disposed) notifyListeners();
  }

  /// TTS 재생 처리 (개별 세그먼트)
  Future<void> playTts(String text, BuildContext? context, {int? segmentIndex}) async {
    if (kDebugMode) {
      print('TTS 재생 상태 업데이트: $text (세그먼트: $segmentIndex)');
    }
    
    if (_isSampleMode) {
      // 샘플 모드: SampleTtsService 사용
      await _sampleTtsService.speak(text, context: context);
    } else {
      // 일반 모드: TTSService 사용 (세그먼트 인덱스가 있으면 speakSegment 호출)
      if (segmentIndex != null) {
        await _ttsService.speakSegment(text, segmentIndex);
      } else {
        await _ttsService.speak(text);
      }
    }
  }
  
  /// 바텀바 TTS 재생 처리 (전체 텍스트)
  Future<void> playBottomBarTts(String ttsText, BuildContext? context) async {
    if (ttsText.isEmpty) return;
    
    if (_isSampleMode) {
      // 샘플 모드: SampleTtsService 사용
      if (_sampleTtsService.isPlaying) {
        await _sampleTtsService.stop();
      } else {
        await _sampleTtsService.speak(ttsText, context: context);
      }
    } else {
      // 일반 모드: TTSService 사용
      if (_ttsService.state == TtsState.playing) {
        await _ttsService.stop();
      } else {
        await _ttsService.speak(ttsText);
      }
    }
  }
  
  /// 플래시카드 생성 처리
  Future<bool> createFlashCard(String front, String back, {String? pinyin}) async {
    try {
      final newFlashCard = await _flashCardService.createFlashCard(
        front: front,
        back: back,
        noteId: _noteId,
        pinyin: pinyin,
      );
      
      _flashcards.add(newFlashCard);
      notifyListeners();
      
      if (kDebugMode) {
        print("✅ 새 플래시카드 추가 완료: ${newFlashCard.front}");
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print("❌ 플래시카드 생성 중 오류: $e");
      }
      return false;
    }
  }
  
  /// 플래시카드 목록 업데이트 (다른 화면에서 돌아올 때)
  void updateFlashcards(List<FlashCard> flashcards) {
    _flashcards = flashcards;
    notifyListeners();
  }

  /// 리소스 정리
  @override
  void dispose() {
    _disposed = true;
    
    pageController.dispose();
    
    // 페이지 리스너 정리
    for (var listener in _pageListeners.values) {
      listener.cancel();
    }
    _pageListeners.clear();
    
    // 동적 페이지 로더 서비스 정리
    _dynamicPageLoaderService?.dispose();
    
    // TextProcessingService 리스너 정리
    _textProcessingService.cancelAllListeners();
    
    super.dispose();
  }
}

