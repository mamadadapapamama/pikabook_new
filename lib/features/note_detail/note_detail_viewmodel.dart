import 'dart:async';
import 'package:flutter/foundation.dart' hide debugPrint;
import '../../core/models/note.dart';
import '../../core/models/page.dart' as pika_page;
import '../../core/models/flash_card.dart';
import '../../core/models/processed_text.dart';
import 'managers/page_manager.dart';
import 'managers/content_manager.dart';
import 'managers/note_options_manager.dart';
import '../../core/services/content/note_service.dart';
import '../../core/services/content/flashcard_service.dart';
import '../../core/services/storage/unified_cache_service.dart';
import '../../core/services/media/tts_service.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// debugPrint 함수 - 커스텀 구현
void debugPrint(String message) {
  developer.log(message);
}

/// 노트 상세 화면의 ViewModel
class NoteDetailViewModel extends ChangeNotifier {
  // 모델 및 매니저 참조
  late PageManager _pageManager;
  late ContentManager _contentManager;
  final NoteOptionsManager _noteOptionsManager = NoteOptionsManager();
  late NoteService _noteService;
  final TtsService _ttsService = TtsService();
  
  // PageController 추가
  final PageController pageController = PageController();
  
  // 상태 변수
  Note? _note;                        // 현재 노트
  String _noteId = "";                // 노트 ID
  List<pika_page.Page>? _pages;       // 페이지 목록
  bool _isLoading = true;             // 로딩 상태
  String? _error;                     // 오류 메시지
  int _currentPageIndex = 0;          // 현재 페이지 인덱스
  bool _isProcessingSegments = false; // 텍스트 처리 상태
  List<FlashCard> _flashCards = [];   // 플래시카드 목록
  bool _loadingFlashcards = true;     // 플래시카드 로딩 상태
  bool _isFullTextMode = false;       // 전체 텍스트 모드 상태
  Map<String, bool> _processedPageStatus = {}; // 페이지 처리 상태
  Timer? _processingTimer;            // 처리 타이머
  bool _shouldUpdateUI = true;        // UI 업데이트 제어 플래그
  bool _isProcessingBackground = false; // 백그라운드 처리 상태
  int _totalImageCount = 0;           // 총 이미지 수
  
  // 게터
  Note? get note => _note;
  String get noteId => _noteId;
  List<pika_page.Page>? get pages => _pages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get currentPageIndex => _currentPageIndex;
  bool get isProcessingSegments => _isProcessingSegments;
  List<FlashCard> get flashCards => _flashCards;
  bool get loadingFlashcards => _loadingFlashcards;
  bool get isFullTextMode => _isFullTextMode;
  bool get isProcessingBackground => _isProcessingBackground;
  int get totalImageCount => _totalImageCount;
  
  // 현재 페이지 (nullable)
  pika_page.Page? get currentPage {
    if (_pages == null || _pages!.isEmpty || _currentPageIndex >= _pages!.length) {
      return null;
    }
    return _pages![_currentPageIndex];
  }
  
  // 생성자
  NoteDetailViewModel({
    required String noteId,
    Note? initialNote,
    bool isProcessingBackground = false,
    int totalImageCount = 0,
  }) {
    _noteId = noteId;
    _note = initialNote;
    _isProcessingBackground = isProcessingBackground;
    _totalImageCount = totalImageCount;
    
    _initializeDependencies();
    
    // 초기화 로직 수행
    if (_note == null && _noteId.isNotEmpty) {
      loadNoteFromFirestore();
    }
    
    // 초기 데이터 로드 (지연 실행)
    Future.microtask(() {
      loadFlashcards();
      loadInitialPages();
    });
  }
  
  // 의존성 초기화
  void _initializeDependencies() {
    _noteService = NoteService();
    _contentManager = ContentManager();
    _pageManager = PageManager(
      noteId: _noteId,
      initialNote: _note,
      useCacheFirst: false,
    );
    _initializeTts();
  }
  
  // TTS 초기화
  void _initializeTts() {
    _ttsService.init();
    if (kDebugMode) {
      debugPrint("[NoteDetailViewModel] TTS 서비스 초기화됨");
    }
  }
  
  // 리소스 정리
  void dispose() {
    _ttsService.stop();
    _ttsService.dispose();
    
    // PageController 정리
    pageController.dispose();
    
    // 앱 종료 전 플래시카드 저장
    if (_noteId.isNotEmpty && _flashCards.isNotEmpty) {
      debugPrint("[NoteDetailViewModel] dispose - ${_flashCards.length}개의 플래시카드 캐시에 저장");
      UnifiedCacheService().cacheFlashcards(_flashCards);
    }
    
    // 타이머 정리
    if (_processingTimer != null) {
      _processingTimer!.cancel();
      _processingTimer = null;
      if (kDebugMode) {
        debugPrint("⏱️ 처리 타이머 취소됨");
      }
    }
    
    super.dispose();
  }
  
  // 노트 로드 메서드
  Future<void> loadNoteFromFirestore() async {
    if (kDebugMode) {
      debugPrint("[NoteDetailViewModel] Firestore에서 노트 로드 시작: $_noteId");
    }
    
    try {
      Note? loadedNote = await _noteService.getNoteById(_noteId);
      if (loadedNote != null) {
        if (kDebugMode) {
          debugPrint("[NoteDetailViewModel] 노트 로드 성공: ${loadedNote.id}, 플래시카드 수: ${loadedNote.flashcardCount}");
        }
        
        _note = loadedNote;
        _isLoading = false;
        _error = null;
        notifyListeners();
        
        // 플래시카드 카운트가 있으면 플래시카드 로드
        if (loadedNote.flashcardCount != null && loadedNote.flashcardCount! > 0) {
          loadFlashcards();
        }
      } else {
        if (kDebugMode) {
          debugPrint("[NoteDetailViewModel] 노트를 찾을 수 없음: $_noteId");
        }
        _isLoading = false;
        _error = "노트를 찾을 수 없습니다.";
        notifyListeners();
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint("[NoteDetailViewModel] 노트 로드 중 오류 발생: $e");
        debugPrint(stackTrace.toString());
      }
      _isLoading = false;
      _error = "노트 로드 중 오류가 발생했습니다: $e";
      notifyListeners();
    }
  }
  
  // 초기 페이지 로드
  Future<void> loadInitialPages() async {
    if (kDebugMode) {
      debugPrint("🔄 NoteDetailViewModel: loadInitialPages 시작");
    }
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // forceRefresh: true로 항상 서버/캐시에서 로드 시도
      final pages = await _pageManager.loadPagesFromServer(forceRefresh: true);
      
      // 로드된 페이지가 없으면 빈 리스트로 설정하여 로딩 상태 해제
      if (pages.isEmpty) {
        if (kDebugMode) {
          debugPrint("⚠️ NoteDetailViewModel: 로드된 페이지가 없습니다.");
        }
        _pages = pages;
        _isLoading = false;
        notifyListeners();
        return;
      }
      
      // 페이지를 로드하면서 각 페이지의 처리 상태 파악
      for (var page in pages) {
        if (page.id != null) {
          bool isProcessed = false;
          
          // 텍스트가 이미 있으면 처리된 것으로 간주
          if (page.originalText != '___PROCESSING___' && page.originalText.isNotEmpty) {
            isProcessed = true;
          } else {
            try {
              // ContentManager를 통해 처리된 텍스트가 있는지 확인
              final processedText = await _contentManager.getProcessedText(page.id!);
              isProcessed = processedText != null && 
                           processedText.fullOriginalText != '___PROCESSING___' &&
                           processedText.fullOriginalText.isNotEmpty;
            } catch (e) {
              if (kDebugMode) {
                debugPrint("⚠️ 페이지 처리 상태 확인 중 오류: $e");
              }
            }
          }
          
          // 페이지 처리 상태 기록
          _processedPageStatus[page.id!] = isProcessed;
        }
      }
      
      _pauseUIUpdates(); // 불필요한 UI 업데이트 방지 시작
      
      _pages = pages;
      _isLoading = false;
      notifyListeners();
      
      if (kDebugMode) {
        debugPrint("✅ NoteDetailViewModel: 페이지 로드 완료 (${pages.length}개)");
      }
      
      // UI 업데이트 재개를 지연시켜 불필요한 업데이트 방지
      Future.delayed(Duration(milliseconds: 500), () {
        _resumeUIUpdates();
      });
      
      // 백그라운드 처리 상태 확인 시작
      _startPageProcessingCheck();
      
      // 페이지 이미지 미리 로드 - 로딩이 완료된 후에만 수행
      Future.delayed(Duration(milliseconds: 300), () {
        loadAllPageImages();
      });
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint("❌ NoteDetailViewModel: 페이지 로드 중 오류 발생: $e");
        debugPrint(stackTrace.toString());
      }
      _isLoading = false;
      _error = "페이지를 로드하는 중 오류가 발생했습니다: $e";
      notifyListeners();
    }
  }
  
  // 백그라운드에서 모든 페이지 이미지 로드
  Future<void> loadAllPageImages() async {
    if (_pages == null || _pages!.isEmpty) return;
    
    if (kDebugMode) {
      debugPrint("🔄 페이지 이미지 백그라운드 로드 시작: ${_pages!.length}개 페이지");
    }
    
    // 현재 페이지의 이미지 우선 로드
    if (_currentPageIndex >= 0 && _currentPageIndex < _pages!.length) {
      await _loadPageImage(_currentPageIndex);
      
      // UI 업데이트를 최소화하기 위해 현재 페이지 로드 후 한 번만 업데이트
      if (_shouldUpdateUI) {
        notifyListeners();
      }
    }
    
    // 다음 페이지와 이전 페이지를 두 번째로 로드 (빠른 페이지 전환 위해)
    List<Future<void>> priorityLoads = [];
    
    if (_currentPageIndex + 1 < _pages!.length) {
      priorityLoads.add(_loadPageImage(_currentPageIndex + 1));
    }
    
    if (_currentPageIndex - 1 >= 0) {
      priorityLoads.add(_loadPageImage(_currentPageIndex - 1));
    }
    
    // 우선순위 로드 동시 실행
    if (priorityLoads.isNotEmpty) {
      await Future.wait(priorityLoads);
    }
    
    // 나머지 모든 페이지 이미지 순차적으로 로드 - 딜레이를 늘리고 UI 업데이트를 줄임
    for (int i = 0; i < _pages!.length; i++) {
      if (i != _currentPageIndex && 
          i != _currentPageIndex + 1 && 
          i != _currentPageIndex - 1) {
        await _loadPageImage(i);
        
        // 로드 간 딜레이 추가 (시스템 부하 방지)
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
    
    if (kDebugMode) {
      debugPrint("✅ 모든 페이지 이미지 로드 완료");
    }
  }
  
  // 백그라운드 처리 시작
  void _startBackgroundProcessing() {
    if (_pages == null || _pages!.isEmpty) return;
    
    if (kDebugMode) {
      debugPrint("🔄 백그라운드 처리 시작: ${_pages!.length}개 페이지");
    }
    
    // 첫 번째 페이지부터 순차적으로 세그먼트 처리
    _isProcessingSegments = true;
    _processPageSegments(0);
    
    // 이미지 로드는 약간 지연시켜 실행 (로딩 화면에서의 처리 부하 분산)
    Future.delayed(Duration(milliseconds: 500), () {
      loadAllPageImages();
    });
  }
  
  // 플래시카드 로드
  Future<void> loadFlashcards() async {
    if (_noteId.isEmpty) {
      if (kDebugMode) {
        debugPrint("[NoteDetailViewModel] 플래시카드 로드 실패: noteId가 없음");
      }
      return;
    }

    if (kDebugMode) {
      debugPrint("[NoteDetailViewModel] 플래시카드 로드 시작: noteId = $_noteId");
    }
  
    final flashCardService = FlashCardService();
  
    try {
      // 먼저 Firestore에서 플래시카드 로드 시도
      var firestoreFlashcards = await flashCardService.getFlashCardsForNote(_noteId);
      if (firestoreFlashcards != null && firestoreFlashcards.isNotEmpty) {
        if (kDebugMode) {
          debugPrint("[NoteDetailViewModel] Firestore에서 ${firestoreFlashcards.length}개의 플래시카드 로드 성공");
        }
        _flashCards = firestoreFlashcards;
        _loadingFlashcards = false;
        
        // Firestore에서 로드된 플래시카드를 캐시에 저장
        await UnifiedCacheService().cacheFlashcards(firestoreFlashcards);
        
        // 노트 객체의 flashcardCount 업데이트
        if (_note != null) {
          _note = _note!.copyWith(flashcardCount: _flashCards.length);
        }
        if (kDebugMode) {
          debugPrint("[NoteDetailViewModel] 노트 객체의 flashcardCount 업데이트: ${_flashCards.length}");
        }
        notifyListeners();
        return;
      }

      // Firestore에서 로드 실패한 경우 캐시에서 로드 시도
      if (kDebugMode) {
        debugPrint("[NoteDetailViewModel] Firestore에서 플래시카드를 찾지 못함, 캐시 확인 중");
      }
      var cachedFlashcards = await UnifiedCacheService().getFlashcardsByNoteId(_noteId);
      if (cachedFlashcards.isNotEmpty) {
        if (kDebugMode) {
          debugPrint("[NoteDetailViewModel] 캐시에서 ${cachedFlashcards.length}개의 플래시카드 로드 성공");
        }
        _flashCards = cachedFlashcards;
        _loadingFlashcards = false;
        
        // 캐시에서 로드된 플래시카드를 Firestore에 동기화 - 백그라운드로 처리하여 UI 차단 방지
        Future.microtask(() async {
          for (var card in cachedFlashcards) {
            await flashCardService.updateFlashCard(card);
          }
        });
        
        // 노트 객체의 flashcardCount 업데이트
        if (_note != null) {
          _note = _note!.copyWith(flashcardCount: _flashCards.length);
        }
        if (kDebugMode) {
          debugPrint("[NoteDetailViewModel] 노트 객체의 flashcardCount 업데이트: ${_flashCards.length}");
        }
        notifyListeners();
        return;
      }

      // 모든 시도 실패시 빈 리스트로 초기화
      if (kDebugMode) {
        debugPrint("[NoteDetailViewModel] 플래시카드를 찾지 못함 (Firestore 및 캐시 모두)");
      }
      _flashCards = [];
      _loadingFlashcards = false;
      notifyListeners();
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint("[NoteDetailViewModel] 플래시카드 로드 중 오류 발생: $e");
        debugPrint(stackTrace.toString());
      }
      _flashCards = [];
      _loadingFlashcards = false;
      notifyListeners();
    }
  }
  
  // 페이지 변경 처리
  void onPageChanged(int index) {
    if (_pages == null || index >= _pages!.length || _currentPageIndex == index) return;
    
    _currentPageIndex = index;
    notifyListeners();
    if (kDebugMode) {
      debugPrint("📄 페이지 변경됨: $_currentPageIndex");
    }
    
    // 페이지가 변경될 때 해당 페이지의 세그먼트가 처리되지 않았다면 처리 시작
    if (_pages != null && index < _pages!.length) {
      final page = _pages![index];
      _checkAndProcessPageIfNeeded(page);
      
      // 현재 페이지의 이미지 로드
      _loadPageImage(index);
      
      // 다음 페이지의 이미지도 미리 로드 (있는 경우)
      if (index + 1 < _pages!.length) {
        _loadPageImage(index + 1);
      }
      
      // 이전 페이지의 이미지도 유지 (있는 경우)
      if (index - 1 >= 0) {
        _loadPageImage(index - 1);
      }
    }
  }
  
  // 프로그램적으로 페이지 이동
  void navigateToPage(int index) {
    if (_pages == null || _pages!.isEmpty) return;
    
    // 유효한 인덱스인지 확인
    if (index < 0 || index >= _pages!.length) return;
    
    // 이미 해당 페이지에 있는지 확인
    if (_currentPageIndex == index) return;
    
    // PageController를 사용하여 애니메이션과 함께 페이지 이동
    pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    
    // UI 변경을 기다리지 않고 바로 상태 업데이트 (UX 향상)
    _currentPageIndex = index;
    notifyListeners();
    
    debugPrint("📄 프로그램적으로 페이지 이동: $index");
  }
  
  // 전체 텍스트 모드 토글
  void toggleFullTextMode() {
    _isFullTextMode = !_isFullTextMode;
    notifyListeners();
    if (kDebugMode) {
      debugPrint("🔤 전체 텍스트 모드 변경: $_isFullTextMode");
    }
  }
  
  // 즐겨찾기 토글
  Future<bool> toggleFavorite() async {
    if (_note == null || _note!.id == null) return false;
    
    final newValue = !(_note?.isFavorite ?? false);
    final success = await _noteOptionsManager.toggleFavorite(_note!.id!, newValue);
    
    if (success) {
      _note = _note!.copyWith(isFavorite: newValue);
      notifyListeners();
      if (kDebugMode) {
        debugPrint("⭐ 즐겨찾기 상태 변경: $newValue");
      }
    }
    
    return success;
  }
  
  // 플래시카드 생성
  Future<bool> createFlashCard(String front, String back, {String? pinyin}) async {
    if (kDebugMode) {
      debugPrint("📝 플래시카드 생성 시작: $front - $back (병음: $pinyin)");
    }
    
    try {
      // FlashCardService를 사용하여 플래시카드 생성
      final flashCardService = FlashCardService();
      final newFlashCard = await flashCardService.createFlashCard(
        front: front,
        back: back,
        noteId: _noteId,
        pinyin: pinyin,
      );
      
      // 상태 업데이트
      _flashCards.add(newFlashCard);
      notifyListeners();
      
      if (kDebugMode) {
        debugPrint("✅ 플래시카드 생성 완료: ${newFlashCard.front} - ${newFlashCard.back} (병음: ${newFlashCard.pinyin})");
        debugPrint("📊 현재 플래시카드 수: ${_flashCards.length}");
      }
      
      // 노트의 플래시카드 카운터 업데이트
      _updateNoteFlashcardCount();
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 플래시카드 생성 중 오류: $e");
      }
      return false;
    }
  }
  
  // 플래시카드 업데이트 (플래시카드 화면에서 돌아올 때)
  void updateFlashcards(List<FlashCard> updatedFlashcards) {
    _flashCards = updatedFlashcards;
    _updateNoteFlashcardCount();
    notifyListeners();
    if (kDebugMode) {
      debugPrint("🔄 플래시카드 목록 업데이트됨: ${_flashCards.length}개");
    }
  }
  
  // 노트 제목 업데이트
  Future<bool> updateNoteTitle(String newTitle) async {
    if (_note == null || _note!.id == null) return false;
    
    final success = await _noteOptionsManager.updateNoteTitle(_note!.id!, newTitle);
    if (success) {
      // 노트 정보 다시 로드
      final updatedNote = await _noteService.getNoteById(_note!.id!);
      _note = updatedNote;
      notifyListeners();
      if (kDebugMode) {
        debugPrint("✏️ 노트 제목 변경: $newTitle");
      }
    }
    
    return success;
  }
  
  // 노트 삭제
  Future<bool> deleteNote() async {
    if (_note == null || _note!.id == null) return false;
    
    try {
      await _noteService.deleteNote(_note!.id!);
      if (kDebugMode) {
        debugPrint("🗑️ 노트 삭제 완료");
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 노트 삭제 중 오류: $e");
      }
      return false;
    }
  }
  
  // 플래시카드 카운트 업데이트
  Future<void> _updateNoteFlashcardCount() async {
    if (_note == null || _note!.id == null) return;
    
    try {
      // 현재 노트 정보 가져오기
      final note = await _noteService.getNoteById(_note!.id!);
      if (note == null) return;
      
      // 플래시카드 카운트 업데이트
      final updatedNote = note.copyWith(flashcardCount: _flashCards.length);
      
      // UI 차단 방지를 위해 백그라운드에서 처리
      Future.microtask(() async {
        await _noteService.updateNote(updatedNote.id!, updatedNote);
      });
      
      // 현재 노트 정보 업데이트
      _note = updatedNote;
      notifyListeners();
      
      if (kDebugMode) {
        debugPrint("✅ 노트 플래시카드 카운트 업데이트: ${_flashCards.length}");
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 노트 플래시카드 카운트 업데이트 실패: $e");
      }
    }
  }
  
  // 특정 페이지의 세그먼트 처리 필요 여부 확인 및 처리
  void _checkAndProcessPageIfNeeded(pika_page.Page page) async {
    if (page.id == null) return;
    
    // 이미 처리 상태를 알고 있는 경우 체크 스킵
    if (_processedPageStatus.containsKey(page.id!) && _processedPageStatus[page.id!] == true) {
      if (kDebugMode) {
        debugPrint("✅ 페이지 ${page.id}는 이미 처리되어 있어 다시 처리하지 않습니다.");
      }
      return;
    }
    
    // 특수 처리 마커가 있는지 확인하고 건너뛰기
    if (page.originalText == "___PROCESSING___") {
      if (kDebugMode) {
        debugPrint("⚠️ 페이지 ${page.id}에 특수 처리 마커가 있습니다");
      }
      return;
    }
    
    try {
      final processedText = await _contentManager.getProcessedText(page.id!);
      if (processedText != null) {
        if (kDebugMode) {
          debugPrint("✅ 페이지 ${page.id}의 처리된 텍스트가 있습니다: ${processedText.segments?.length ?? 0}개 세그먼트");
        }
        
        // 세그먼트가 비어있는지 확인
        if (processedText.segments == null || processedText.segments!.isEmpty) {
          if (kDebugMode) {
            debugPrint("⚠️ 페이지 ${page.id}의 세그먼트가 비어 있습니다. 처리 다시 시도");
          }
          // 처리 상태 기록 안함 (빈 세그먼트는 제대로 처리되지 않은 것으로 간주)
        } else {
          // 정상적으로 처리된 페이지 기록
          _processedPageStatus[page.id!] = true;
        }
      } else {
        if (kDebugMode) {
          debugPrint("❌ 페이지 ${page.id}의 처리된 텍스트가 없습니다 - 세그먼트 처리 필요");
        }
        
        // 현재 UI 업데이트가 일시 중지된 상태인지 확인
        bool wasUpdatesPaused = !_shouldUpdateUI;
        
        if (!wasUpdatesPaused) {
          _pauseUIUpdates(); // UI 업데이트 일시 중지
        }
        
        // 처리된 텍스트가 없으면 처리 시작
        _contentManager.processPageText(
          page: page,
          imageFile: null,
        ).then((result) {
          if (result != null) {
            if (kDebugMode) {
              debugPrint("✅ 처리 완료: ${result.segments?.length ?? 0}개 세그먼트");
            }
            // 처리 상태 기록
            _processedPageStatus[page.id!] = true;
            
            // 업데이트를 일시 중지한 경우만 재개
            if (!wasUpdatesPaused) {
              Future.delayed(Duration(milliseconds: 300), () {
                _resumeUIUpdates();
                notifyListeners();
              });
            }
          } else {
            if (kDebugMode) {
              debugPrint("❌ 처리 결과가 null입니다");
            }
            // 업데이트를 일시 중지한 경우만 재개
            if (!wasUpdatesPaused) {
              _resumeUIUpdates();
            }
          }
        }).catchError((e) {
          if (kDebugMode) {
            debugPrint("❌ 처리 중 오류 발생: $e");
          }
          // 업데이트를 일시 중지한 경우만 재개
          if (!wasUpdatesPaused) {
            _resumeUIUpdates();
          }
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 처리된 텍스트 확인 중 오류 발생: $e");
      }
    }
  }
  
  // 세그먼트 처리를 주기적으로 확인하는 타이머 시작
  void _startSegmentProcessing() {
    // 기존 타이머가 있으면 취소
    if (_processingTimer != null) {
      _processingTimer!.cancel();
      _processingTimer = null;
      if (kDebugMode) {
        debugPrint('🛑 세그먼트 처리 타이머 취소됨');
      }
    }

    // 현재 페이지나 선택된 세그먼트가 없으면 시작하지 않음
    if (currentPage == null) return;

    if (kDebugMode) {
      debugPrint('⏱️ 세그먼트 처리 상태 체크 타이머 시작됨 (3초 간격)');
      
      _processingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        _checkAndProcessPageIfNeeded(currentPage!);
      });
    }
  }
  
  // 페이지 세그먼트 처리
  Future<void> _processPageSegments(int pageIndex) async {
    if (_pages == null || pageIndex >= _pages!.length) {
      _isProcessingSegments = false;
      return;
    }
    
    try {
      final page = _pages![pageIndex];
      if (kDebugMode) {
        debugPrint("🔄 페이지 ${pageIndex + 1} 세그먼트 처리 시작: ${page.id}");
      }
      
      // 이미 처리된 페이지인지 확인
      if (page.id != null && _processedPageStatus[page.id!] == true) {
        if (kDebugMode) {
          debugPrint("✅ 페이지 ${pageIndex + 1}는 이미 처리되어 있어 건너뜁니다.");
        }
        // 다음 페이지로 진행
        if (pageIndex < _pages!.length - 1) {
          _processPageSegments(pageIndex + 1);
        } else {
          _isProcessingSegments = false;
        }
        return;
      }
      
      // ContentManager를 통해 페이지 텍스트 처리
      final processedText = await _contentManager.processPageText(
        page: page,
        imageFile: null,
      );
      
      // 세그먼트 처리 결과 확인
      if (processedText != null) {
        if (kDebugMode) {
          debugPrint("✅ 페이지 ${pageIndex + 1} 세그먼트 처리 완료 - 결과: ${processedText.segments?.length ?? 0}개 세그먼트");
        }
        // 페이지 처리 상태 업데이트
        if (page.id != null) {
          _processedPageStatus[page.id!] = true;
        }
      } else {
        if (kDebugMode) {
          debugPrint("⚠️ 페이지 ${pageIndex + 1} 세그먼트 처리 결과가 null입니다");
        }
      }
      
      if (kDebugMode) {
        debugPrint("✅ 페이지 ${pageIndex + 1} 세그먼트 처리 완료");
      }
      
      // 다음 페이지 처리 (필요한 경우)
      if (pageIndex < _pages!.length - 1) {
        _processPageSegments(pageIndex + 1);
      } else {
        _isProcessingSegments = false;
        
        // 모든 페이지 처리 완료 후 UI 갱신
        if (_currentPageIndex == 0 && _shouldUpdateUI) {
          Future.delayed(Duration(milliseconds: 500), () {
            notifyListeners();
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 페이지 세그먼트 처리 중 오류: $e");
      }
      _isProcessingSegments = false;
    }
  }
  
  // UI 업데이트 일시 중지
  void _pauseUIUpdates() {
    _shouldUpdateUI = false;
  }
  
  // UI 업데이트 재개
  void _resumeUIUpdates() {
    _shouldUpdateUI = true;
  }
  
  // TTS 기능 - 현재 페이지 텍스트 읽기
  Future<void> speakCurrentPageText() async {
    final currentPage = this.currentPage;
    if (currentPage == null) {
      if (kDebugMode) {
        debugPrint("⚠️ speakCurrentPageText: 현재 페이지가 없습니다");
      }
      return;
    }
    
    try {
      await _ttsService.stop(); // 기존 음성 중지
      
      // 페이지 텍스트 가져오기
      String textToSpeak = "";
      
      // 세그먼트 모드인 경우 세그먼트 텍스트 사용, 아니면 원본 텍스트 사용
      if (!_isFullTextMode && currentPage.id != null) {
        final processedText = await _contentManager.getProcessedText(currentPage.id!);
        if (processedText?.segments != null && processedText!.segments!.isNotEmpty) {
          // 모든 세그먼트 텍스트 합치기
          textToSpeak = processedText.segments!
              .map((segment) => segment.originalText)
              .join(" ");
        } else {
          textToSpeak = currentPage.originalText;
        }
      } else {
        textToSpeak = currentPage.originalText;
      }
      
      if (textToSpeak.isNotEmpty) {
        if (kDebugMode) {
          debugPrint("🔊 TTS 시작: ${textToSpeak.substring(0, textToSpeak.length > 50 ? 50 : textToSpeak.length)}...");
        }
        await _ttsService.speak(textToSpeak);
      } else {
        if (kDebugMode) {
          debugPrint("⚠️ TTS: 읽을 텍스트가 없습니다");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ TTS 중 오류 발생: $e");
      }
    }
  }
  
  // TTS 중지
  void stopTts() {
    _ttsService.stop();
    if (kDebugMode) {
      debugPrint("🔴 TTS 중지됨");
    }
  }
  
  // 특정 페이지의 이미지 파일 로드
  Future<void> _loadPageImage(int pageIndex) async {
    if (_pages == null || pageIndex < 0 || pageIndex >= _pages!.length) return;
    
    final page = _pages![pageIndex];
    if (page.id == null || page.imageUrl == null || page.imageUrl!.isEmpty) return;
    
    try {
      await _pageManager.loadPageImage(pageIndex);
      // 이미지 로드 완료 후 UI 갱신 - 현재 페이지일 때만 UI 갱신하도록 수정
      if (_currentPageIndex == pageIndex && _shouldUpdateUI) {
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 페이지 이미지 로드 중 오류: $e");
      }
    }
  }
  
  // 특정 페이지의 이미지 파일 가져오기
  File? getImageFileForPage(pika_page.Page? page) {
    if (page == null || page.id == null) return null;
    
    try {
      // PageManager에서 이미지 파일 가져오기
      return _pageManager.getImageFileForPage(page);
    } catch (e) {
      debugPrint("❌ 이미지 파일 가져오기 중 오류: $e");
      return null;
    }
  }
  
  // 현재 페이지의 이미지 파일 가져오기
  File? getCurrentPageImageFile() {
    if (currentPage == null) return null;
    return getImageFileForPage(currentPage);
  }
  
  // ContentManager 객체 가져오기
  ContentManager getContentManager() {
    return _contentManager;
  }
  
  // 세그먼트 삭제 메서드
  Future<bool> deleteSegment(int segmentIndex) async {
    if (kDebugMode) {
      debugPrint("🗑️ 세그먼트 삭제 시작: 인덱스=$segmentIndex");
    }
    
    if (currentPage == null || currentPage!.id == null) {
      if (kDebugMode) {
        debugPrint("⚠️ 세그먼트 삭제 실패: 현재 페이지가 없거나 ID가 없습니다");
      }
      return false;
    }
    
    try {
      // ContentManager의 deleteSegment 메서드 호출
      final updatedPage = await _contentManager.deleteSegment(
        noteId: _noteId,
        page: currentPage!,
        segmentIndex: segmentIndex,
      );
      
      if (updatedPage == null) {
        if (kDebugMode) {
          debugPrint("⚠️ 세그먼트 삭제 실패: 페이지 업데이트 결과가 null입니다");
        }
        return false;
      }
      
      // 현재 페이지 업데이트
      if (_pages != null && _currentPageIndex < _pages!.length) {
        _pages![_currentPageIndex] = updatedPage;
      }
      
      // 화면 갱신
      notifyListeners();
      
      if (kDebugMode) {
        debugPrint("✅ 세그먼트 삭제 완료");
      }
      return true;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint("❌ 세그먼트 삭제 중 오류 발생: $e");
        debugPrint(stackTrace.toString());
      }
      return false;
    }
  }
  
  // 페이지 처리 상태 확인 및 반환 메서드 추가
  List<bool> getProcessedPagesStatus() {
    // pages가 없으면 빈 리스트 반환
    if (_pages == null || _pages!.isEmpty) {
      return [];
    }
    
    List<bool> processedStatus = List.filled(_totalImageCount > 0 ? _totalImageCount : _pages!.length, false);
    
    // 현재 pages 목록에 있는 페이지들의 상태 설정
    for (int i = 0; i < _pages!.length; i++) {
      final page = _pages![i];
      if (page.id != null && _processedPageStatus.containsKey(page.id!)) {
        processedStatus[i] = _processedPageStatus[page.id!] ?? false;
      } else {
        // 상태 정보가 없는 경우, 처리 중인지 여부로 판단
        processedStatus[i] = page.originalText != '___PROCESSING___' && 
                             page.originalText.isNotEmpty;
      }
    }
    
    return processedStatus;
  }
  
  // 페이지 처리 상태 업데이트 메서드 추가
  Future<void> updatePageProcessingStatus(int pageIndex, bool isProcessed) async {
    if (_pages == null || pageIndex < 0 || pageIndex >= _pages!.length) {
      return;
    }
    
    final page = _pages![pageIndex];
    if (page.id == null) return;
    
    // 상태가 변경된 경우에만 업데이트
    if (_processedPageStatus[page.id] != isProcessed) {
      _processedPageStatus[page.id!] = isProcessed;
      notifyListeners();
      
      // 페이지가 처리 완료된 경우 스낵바 표시 (콜백 함수 호출)
      if (isProcessed && _pageProcessedCallback != null) {
        _pageProcessedCallback!(pageIndex);
      }
    }
  }
  
  // 페이지 처리 완료 시 호출될 콜백 함수
  Function(int)? _pageProcessedCallback;
  
  // 페이지 처리 완료 콜백 설정 메서드
  void setPageProcessedCallback(Function(int) callback) {
    _pageProcessedCallback = callback;
  }
  
  // 백그라운드에서 페이지 처리 상태 주기적 체크
  void _startPageProcessingCheck() {
    // 이미 타이머가 실행 중이면 취소
    if (_processingTimer != null) {
      _processingTimer!.cancel();
      _processingTimer = null;
    }
    
    // 페이지가 없으면 실행하지 않음
    if (_pages == null || _pages!.isEmpty) return;
    
    // 모든 페이지가 이미 처리되었는지 빠르게 확인
    bool allAlreadyProcessed = true;
    for (final page in _pages!) {
      if (page.id == null) continue;
      
      // 아직 처리되지 않은 페이지가 있으면 체크 필요
      final bool isProcessed = _processedPageStatus[page.id!] == true || 
                             (page.originalText != '___PROCESSING___' && 
                              page.originalText.isNotEmpty);
      
      if (!isProcessed) {
        allAlreadyProcessed = false;
        break;
      }
    }
    
    // 모든 페이지가 이미 처리되었으면 타이머 시작하지 않음
    if (allAlreadyProcessed) {
      if (kDebugMode) {
        debugPrint("✅ 모든 페이지가 이미 처리되어 있어 처리 체크 타이머를 시작하지 않습니다");
      }
      return;
    }
    
    if (kDebugMode) {
      // 타이머 간격을 15초로 늘림 (성능 향상 및 불필요한 체크 감소)
      debugPrint("⏱️ 페이지 처리 상태 체크 타이머 시작됨 (15초 간격)");
      
      _processingTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
        debugPrint("🔄 페이지 처리 상태 주기적 체크 실행 중...");
        
        bool allProcessed = true;
        bool anyStatusChanged = false;
        bool currentPageChanged = false;
        
        // 처리되지 않은 페이지만 체크하기 위한 목록
        final List<int> unprocessedPageIndices = [];
        
        // 먼저 처리가 필요한 페이지만 식별
        for (int i = 0; i < _pages!.length; i++) {
          final page = _pages![i];
          if (page.id == null) continue;
          
          // 이미 처리된 페이지는 스킵
          if (_processedPageStatus[page.id!] == true) continue;
          
          unprocessedPageIndices.add(i);
          allProcessed = false;
        }
        
        // 처리가 필요한 페이지만 체크 (불필요한 체크 없이 최적화)
        for (final index in unprocessedPageIndices) {
          final page = _pages![index];
          
          try {
            // 페이지 상태 확인
            bool isProcessed = false;
            
            // 텍스트가 이미 처리되어 있는지 확인
            if (page.originalText != '___PROCESSING___' && page.originalText.isNotEmpty) {
              isProcessed = true;
            } else {
              // 캐시된 페이지 체크로 성능 개선 (Firestore 호출 최소화)
              debugPrint("⚠️ 캐시된 페이지 확인 (임시 처리)");
              // NoteService에 getCachedPage 메서드가 없으므로 대체 로직 사용
              isProcessed = false; // 처리되지 않았다고 가정하고 나중에 ContentManager로 체크
            }
            
            // 상태가 변경된 경우에만 업데이트
            if (_processedPageStatus[page.id!] != isProcessed) {
              _processedPageStatus[page.id!] = isProcessed;
              anyStatusChanged = true;
              
              // 현재 페이지의 상태가 변경되었는지 확인
              if (index == _currentPageIndex) {
                currentPageChanged = true;
              }
              
              // 페이지가 처리 완료된 경우 스낵바 표시 (콜백 함수 호출)
              if (isProcessed && _pageProcessedCallback != null) {
                _pageProcessedCallback!(index);
                
                // 모든 프로세스를 페이지 정보 업데이트
                _pages![index] = _pages![index].copyWith(
                  originalText: await _getUpdatedPageText(page.id!),
                );
              }
            }
          } catch (e) {
            debugPrint("⚠️ 페이지 처리 상태 확인 중 오류: $e");
          }
        }
        
        // 상태 변경이 있고 현재 페이지에 변경이 있을 때만 UI 갱신
        // 또는 모든 페이지가 처리완료된 경우도 UI 갱신
        if ((anyStatusChanged && currentPageChanged && _shouldUpdateUI) || 
            (anyStatusChanged && unprocessedPageIndices.isEmpty)) {
          notifyListeners();
          debugPrint("🔄 페이지 처리 상태 변경으로 UI 갱신됨");
        }
        
        // 모든 페이지가 처리되었으면 타이머 중지
        if (unprocessedPageIndices.isEmpty) {
          debugPrint("✅ 모든 페이지 처리 완료, 타이머 중지");
          timer.cancel();
          _processingTimer = null;
        }
      });
    } else {
      // 디버그 모드가 아닐 때는 타이머 없이 1회 체크만 수행
      _checkProcessingStatus();
    }
  }
  
  // 디버그 모드가 아닐 때 사용할 간단한 체크 메서드
  void _checkProcessingStatus() async {
    // 처리가 필요한 페이지만 식별하고 상태 업데이트
    if (_pages == null || _pages!.isEmpty) return;
    
    for (int i = 0; i < _pages!.length; i++) {
      final page = _pages![i];
      if (page.id == null) continue;
      
      // 이미 처리된 페이지는 스킵
      if (_processedPageStatus[page.id!] == true) continue;
      
      // 텍스트가 이미 처리되어 있는지 확인
      if (page.originalText != '___PROCESSING___' && page.originalText.isNotEmpty) {
        _processedPageStatus[page.id!] = true;
        
        // 페이지가 처리 완료된 경우 콜백 함수 호출
        if (_pageProcessedCallback != null) {
          _pageProcessedCallback!(i);
        }
      }
    }
  }
  
  // 페이지 텍스트 업데이트 가져오기 (페이지 처리 완료 후)
  Future<String> _getUpdatedPageText(String pageId) async {
    try {
      // 먼저 처리된 텍스트 확인
      final processedText = await _contentManager.getProcessedText(pageId);
      if (processedText != null && processedText.fullOriginalText.isNotEmpty) {
        return processedText.fullOriginalText;
      }
      
      // 서버에서 페이지 다시 로드
      if (kDebugMode) {
        debugPrint("⚠️ 페이지 정보 확인 (임시 처리)");
      }
      // NoteService에 getPageById 메서드가 없으므로 ContentManager를 통해 텍스트 확인
      final pageProcessedText = await _contentManager.getProcessedText(pageId);
      if (pageProcessedText != null && pageProcessedText.fullOriginalText.isNotEmpty && 
          pageProcessedText.fullOriginalText != '___PROCESSING___') {
        return pageProcessedText.fullOriginalText;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("⚠️ 업데이트된 페이지 텍스트 가져오기 실패: $e");
      }
    }
    
    return ''; // 빈 텍스트 반환 (실패 시)
  }
} 