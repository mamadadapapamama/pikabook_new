import 'dart:async';
import 'package:flutter/foundation.dart' hide debugPrint;
import '../../core/models/note.dart';
import '../../core/models/page.dart' as pika_page;
import '../../core/models/flash_card.dart';
import 'managers/page_manager.dart';
import 'managers/segment_manager.dart';
import 'managers/note_options_manager.dart';
import '../../core/services/content/note_service.dart';
import '../../core/services/media/tts_service.dart';
import '../../core/services/content/flashcard_service.dart';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'page_processing_monitor.dart';

// debugPrint 함수 - 커스텀 구현
void debugPrint(String message) {
  developer.log(message);
}

/// 노트 상세 화면의 ViewModel
class NoteDetailViewModel extends ChangeNotifier {
  // 모델 및 매니저 참조
  late PageManager _pageManager;
  late SegmentManager _segmentManager;
  final NoteOptionsManager _noteOptionsManager = NoteOptionsManager();
  late NoteService _noteService;
  final TtsService _ttsService = TtsService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
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
  int? _flashcardCount;               // 플래시카드 개수 (로드하지 않고 개수만 추적)
  bool _isFullTextMode = false;       // 전체 텍스트 모드 상태
  // 페이지 처리 상태는 PageProcessingMonitor로 이관
  Timer? _processingTimer;            // 처리 타이머
  bool _shouldUpdateUI = true;        // UI 업데이트 제어 플래그
  bool _isProcessingBackground = false; // 백그라운드 처리 상태
  int _totalImageCount = 0;           // 총 이미지 수
  StreamSubscription? _pagesSubscription; // Firestore 페이지 리스너
  
  // 플래시카드 목록 저장용 멤버 변수
  List<FlashCard> _flashcards = [];
  
  // 게터
  Note? get note => _note;
  String get noteId => _noteId;
  List<pika_page.Page>? get pages => _pages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get currentPageIndex => _currentPageIndex;
  bool get isProcessingSegments => _isProcessingSegments;
  int get flashcardCount => _flashcardCount ?? 0;
  bool get isFullTextMode => _isFullTextMode;
  bool get isProcessingBackground => _isProcessingBackground;
  int get totalImageCount => _totalImageCount;
  
  // TTS 재생 상태 확인을 위한 getter 추가
  bool get isTtsPlaying => _segmentManager.ttsService.state.toString().contains('playing');
  
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
    
    // 페이지 처리 모니터 초기화
    _pageMonitor = PageProcessingMonitor(
      noteId: _noteId,
      onPageProcessed: _handlePageProcessed,
    );
    
    // 초기화 로직 수행
    if (_note == null && _noteId.isNotEmpty) {
      loadNoteFromFirestore();
    } else if (_note != null) {
      // 초기 노트가 있는 경우 플래시카드 카운트 설정
      _flashcardCount = _note!.flashcardCount;
    }
    
    // 초기 데이터 로드 (지연 실행)
    Future.microtask(() async {
      await loadInitialPages();
      
      // 플래시카드 목록도 로드 (하이라이트를 위해)
      await loadFlashcardsForNote();
    });
  }
  
  // 의존성 초기화
  void _initializeDependencies() {
    _noteService = NoteService();
    _segmentManager = SegmentManager();
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
    
    // 타이머 정리
    if (_processingTimer != null) {
      _processingTimer!.cancel();
      _processingTimer = null;
      if (kDebugMode) {
      debugPrint("⏱️ 처리 타이머 취소됨");
      }
    }
    
    // Firestore 리스너 정리
    _pagesSubscription?.cancel();
    
    // 페이지 처리 모니터 정리
    _pageMonitor.dispose();
    
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
        _flashcardCount = loadedNote.flashcardCount;
        _isLoading = false;
        _error = null;
        notifyListeners();
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
      
      if (kDebugMode) {
        debugPrint("📊 전체 페이지 개수: ${pages.length}개 / 총 이미지: $_totalImageCount개");
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
              final processedText = await _segmentManager.getProcessedText(page.id!);
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
          
          if (kDebugMode) {
            debugPrint("📄 페이지 ${pages.indexOf(page) + 1} (ID: ${page.id}): ${isProcessed ? "✅ 처리됨" : "⏳ 처리중"}");
          }
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
      
        // 실시간 페이지 상태 모니터링 시작
  _startRealtimePageMonitoring();
  
  // 페이지 이미지 미리 로드 - 로딩이 완료된 후에만 수행
  Future.delayed(Duration(milliseconds: 300), () {
    loadAllPageImages();
  });
  
  // 페이지 처리 상태 변경 리스너 추가
  if (_pages != null && _pages!.isNotEmpty) {
    _pageMonitor.startMonitoring(_pages!);
  }
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
  
  // 페이지 변경 처리
  void onPageChanged(int index) {
    if (_pages == null || index >= _pages!.length || _currentPageIndex == index) return;
    
    _currentPageIndex = index;
    notifyListeners();
    if (kDebugMode) {
      debugPrint("📄 페이지 변경됨: $_currentPageIndex");
    }
    
    // 페이지가 변경될 때마다 플래시카드 하이라이트 효과 적용 위해 항상 UI 갱신
    notifyListeners();
    
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
  
  // 특정 페이지의 세그먼트 처리 필요 여부 확인 및 처리
  void _checkAndProcessPageIfNeeded(pika_page.Page page) async {
    if (page.id == null) return;
    
    // 이미 처리 상태를 알고 있는 경우 체크 스킵
    if (_pageMonitor.isPageProcessed(page.id!)) {
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
      final processedText = await _segmentManager.getProcessedText(page.id!);
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
        _segmentManager.processPageText(
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
      final processedText = await _segmentManager.processPageText(
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
        final processedText = await _segmentManager.getProcessedText(currentPage.id!);
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
      // 병렬 로드를 위한 Future 추가
      final loadFuture = _pageManager.loadPageImage(pageIndex);
      
      // 주요 페이지(현재, 이전, 다음)는 실제로 완료 대기
      if (pageIndex == _currentPageIndex || 
          pageIndex == _currentPageIndex - 1 ||
          pageIndex == _currentPageIndex + 1) {
        await loadFuture;
        
        // 이미지 로드 완료 후 UI 갱신 - 현재 페이지일 때만 UI 갱신
        if (_currentPageIndex == pageIndex && _shouldUpdateUI) {
          notifyListeners();
        }
      } else {
        // 나머지 페이지는 백그라운드로 로드 (완료 대기 안함)
        // UI 차단 방지 및 캐싱 처리를 위한 목적
        loadFuture.then((_) {
          // 비동기 완료 후 처리 없음 (백그라운드 캐싱만 목적)
          if (kDebugMode) {
            debugPrint("📄 페이지 ${pageIndex + 1} 이미지 백그라운드 로드 완료");
          }
        }).catchError((e) {
          if (kDebugMode) {
            debugPrint("⚠️ 페이지 ${pageIndex + 1} 이미지 백그라운드 로드 오류: $e");
          }
        });
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
  SegmentManager getContentManager() {
    return _segmentManager;
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
      final updatedPage = await _segmentManager.deleteSegment(
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
    
    // PageProcessingMonitor를 통해 처리 상태 가져오기
    return _pageMonitor.getProcessedPagesStatus(_pages!);
  }
  
  // 페이지 처리 상태 업데이트 메서드 추가
  Future<void> updatePageProcessingStatus(int pageIndex, bool isProcessed) async {
    if (_pages == null || pageIndex < 0 || pageIndex >= _pages!.length) {
      return;
    }
    
    final page = _pages![pageIndex];
    if (page.id == null) return;
    
    // 상태가 변경된 경우에만 업데이트
    if (_pageMonitor.isPageProcessed(page.id!) != isProcessed) {
      _pageMonitor.updatePageStatus(page.id!, isProcessed);
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
  
  // Firestore 실시간 리스너로 페이지 상태 모니터링
  void _startRealtimePageMonitoring() {
    // 기존 타이머나 리스너가 있으면 취소
    _processingTimer?.cancel();
    _processingTimer = null;
    _pagesSubscription?.cancel();
    
    if (_noteId.isEmpty) return;
    
    // 실시간 모니터링을 위해 UI 업데이트 항상 활성화
    _shouldUpdateUI = true;
    
    if (kDebugMode) {
      debugPrint("🔄 Firestore 페이지 실시간 모니터링 시작: $_noteId");
      
      // 페이지 처리 상태 요약 로그
      final processedCount = _processedPageStatus.entries.where((e) => e.value).length;
      final totalCount = _processedPageStatus.length;
      debugPrint("📊 현재 페이지 처리 상태: $processedCount/$totalCount개 처리됨");
      
      // 전체 페이지 개수와 이미지 수 정보 명시적 출력
      if (_pages != null) {
        debugPrint("📊 전체 페이지 개수: ${_pages!.length}개 / 총 이미지: $_totalImageCount개");
        
        // 디버그 모드에서만 모든 페이지 상태 출력
        for (int i = 0; i < _pages!.length; i++) {
          final page = _pages![i];
          final bool isProcessed = page.id != null ? (_processedPageStatus[page.id!] ?? false) : false;
          debugPrint("📄 페이지 ${i + 1} (ID: ${page.id}): ${isProcessed ? "✅ 처리됨" : "⏳ 처리중"}");
        }
      }
    }
    
    // 초기 상태 강제 확인
    _checkAllPagesStatus();
    
    // Firestore에서 페이지 변경 감지 (특정 노트의 모든 페이지 구독)
    _pagesSubscription = _firestore
        .collection('pages')
        .where('noteId', isEqualTo: _noteId)
        .snapshots(includeMetadataChanges: true)
        .listen(
      (snapshot) {
        if (kDebugMode) {
          final hasNewData = snapshot.docs.any((doc) => !doc.metadata.hasPendingWrites);
          debugPrint("📱 Firestore 페이지 업데이트 감지: ${snapshot.docs.length}개 문서 (새 데이터: $hasNewData)");
        }
        _handlePagesUpdate(snapshot);
      }, 
      onError: (error) {
        if (kDebugMode) {
          debugPrint("⚠️ Firestore 페이지 리스너 오류: $error");
        }
        // 오류 시 백업으로 타이머 방식 사용
        _startFallbackTimerCheck();
      }
    );
    
    // 백업 안전장치: 실시간 리스너가 놓칠 수 있는 업데이트를 위한 주기적 폴링
    if (_processingTimer == null) {
      _processingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        // 모든 페이지가 처리되었으면 타이머 중단
        final allProcessed = _processedPageStatus.values.every((v) => v);
        if (allProcessed) {
          if (kDebugMode) {
            debugPrint("✅ 모든 페이지 처리 완료 - 백업 타이머 중단");
          }
          timer.cancel();
          _processingTimer = null;
          return;
        }
        
        // 상태 로그 출력 간소화
        if (kDebugMode) {
          final processed = _processedPageStatus.values.where((v) => v).length;
          final total = _processedPageStatus.length;
          debugPrint("⏱️ 백업 타이머: 페이지 상태 확인 중 ($processed/$total개 처리됨)");
        }
        
        // 모든 페이지 상태 확인
        _checkAllPagesStatus();
      });
    }
  }
  
  // 모든 페이지 상태 직접 확인
  void _checkAllPagesStatus() async {
    if (_pages == null || _pages!.isEmpty || _noteId.isEmpty) return;
    
    try {
      // 모든 페이지 정보를 한 번에 가져오기
      final snapshot = await _firestore
          .collection('pages')
          .where('noteId', isEqualTo: _noteId)
          .get();
      
      if (kDebugMode) {
        debugPrint("📥 모든 페이지 상태 직접 확인: ${snapshot.docs.length}개 문서");
      }
      
      _handlePagesUpdate(snapshot);
    } catch (e) {
      if (kDebugMode) {
        debugPrint("⚠️ 페이지 상태 직접 확인 중 오류: $e");
      }
    }
  }
  
  // 페이지 상태 업데이트 처리
  void _handlePagesUpdate(QuerySnapshot snapshot) {
    if (_pages == null || _pages!.isEmpty) return;
    
    bool anyStatusChanged = false;
    
    if (kDebugMode) {
      debugPrint("🔍 페이지 업데이트 처리 시작: ${snapshot.docs.length}개 문서");
    }
    
    // 스냅샷에서 페이지 정보 처리
    for (final doc in snapshot.docs) {
      final pageData = doc.data() as Map<String, dynamic>;
      final pageId = doc.id;
      
      // 현재 페이지 목록에서 해당 ID의 페이지 찾기
      int pageIndex = -1;
      for (int i = 0; i < _pages!.length; i++) {
        if (_pages![i].id == pageId) {
          pageIndex = i;
          break;
        }
      }
      
      // 페이지를 찾지 못했으면 다음으로
      if (pageIndex == -1) continue;
      
      // 페이지 텍스트 확인하여 처리 상태 업데이트
      final originalText = pageData['originalText'] as String? ?? '';
      final isProcessed = originalText != '___PROCESSING___' && originalText.isNotEmpty;
      
      if (kDebugMode && originalText.isNotEmpty && originalText != '___PROCESSING___') {
        final shortText = originalText.length > 30 
          ? "${originalText.substring(0, 30)}..." 
          : originalText;
        debugPrint("📄 페이지 #$pageIndex (ID:$pageId) 텍스트: $shortText");
      }
      
      // 현재 상태 체크
      final currentStatus = _processedPageStatus[pageId] ?? false;
      
      // 기존 상태와 다르면 업데이트
      if (currentStatus != isProcessed) {
        _processedPageStatus[pageId] = isProcessed;
        anyStatusChanged = true;
        
        if (kDebugMode) {
          debugPrint("🔄 페이지 #$pageIndex (ID:$pageId) 상태 변경: $currentStatus → $isProcessed");
        }
        
        // 페이지가 처리 완료된 경우 콜백 호출 및 페이지 업데이트
        if (isProcessed && _pageProcessedCallback != null) {
          _pageProcessedCallback!(pageIndex);
          
          // 페이지 객체 업데이트
          if (pageIndex < _pages!.length) {
            // 기존 ID를 유지하고 업데이트된 데이터로 페이지 객체 갱신
            final updatedPage = pika_page.Page.fromJson({
              'id': pageId,
              ...pageData,
              // timestamp를 날짜 문자열로 변환
              'createdAt': (pageData['createdAt'] as Timestamp?)?.toDate().toIso8601String() ?? DateTime.now().toIso8601String(),
              'updatedAt': (pageData['updatedAt'] as Timestamp?)?.toDate().toIso8601String() ?? DateTime.now().toIso8601String(),
            });
            _pages![pageIndex] = updatedPage;
            
            if (kDebugMode) {
              debugPrint("✅ 페이지 #$pageIndex 객체 업데이트 완료");
            }
          }
        }
      }
    }
    
    // 변경 사항이 있으면 항상 UI 업데이트 (조건 제거)
    if (anyStatusChanged) {
      if (kDebugMode) {
        debugPrint("🔄 실시간 페이지 업데이트로 UI 갱신됨");
      }
      // 항상 UI 갱신 
      notifyListeners();
    }
  }
  
  // 백업용 타이머 체크 (리스너가 실패할 경우)
  void _startFallbackTimerCheck() {
    if (_processingTimer != null) return;
    
    if (kDebugMode) {
      debugPrint("⏱️ 백업용 타이머 모니터링 시작 (리스너 실패 대응)");
    }
    
    _processingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (kDebugMode) {
        debugPrint("⏱️ 백업 타이머: 페이지 상태 확인 중 (fallback)");
      }
      _checkAllPagesStatus();
    });
  }
  
  // 페이지 텍스트 업데이트 가져오기 (페이지 처리 완료 후)
  Future<String> _getUpdatedPageText(String pageId) async {
    try {
      // 먼저 처리된 텍스트 확인
      final processedText = await _segmentManager.getProcessedText(pageId);
      if (processedText != null && processedText.fullOriginalText.isNotEmpty) {
        return processedText.fullOriginalText;
      }
    
      // 서버에서 페이지 다시 로드
      if (kDebugMode) {
        debugPrint("⚠️ 페이지 정보 확인 (임시 처리)");
      }
      
      try {
        final doc = await _firestore.collection('pages').doc(pageId).get();
        if (doc.exists) {
          final data = doc.data();
          final originalText = data?['originalText'] as String? ?? '';
          if (originalText != '___PROCESSING___' && originalText.isNotEmpty) {
            return originalText;
          }
        }
      } catch (e) {
        debugPrint("⚠️ Firestore에서 페이지 텍스트 로드 실패: $e");
      }
      
      // Firestore 실패 시 ContentManager 사용
      final pageProcessedText = await _segmentManager.getProcessedText(pageId);
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

  // 플래시카드 카운트 업데이트
  void updateFlashcardCount(int count) {
    _flashcardCount = count;
    
    // 노트 객체의 플래시카드 카운트 업데이트
    if (_note != null && _note!.id != null) {
      _note = _note!.copyWith(flashcardCount: count);
      
      // UI 차단 방지를 위해 백그라운드에서 Firestore 업데이트
      Future.microtask(() async {
        await _noteService.updateNote(_note!.id!, _note!);
        if (kDebugMode) {
          debugPrint("✅ 노트 플래시카드 카운트 업데이트: $count");
        }
      });
    }
    
    notifyListeners();
  }
  
  // 플래시카드 목록 업데이트
  void updateFlashcards(List<FlashCard> flashcards) {
    _flashcards = flashcards;
    notifyListeners();
  }
  
  // 현재 페이지에 해당하는 플래시카드 목록 반환
  List<FlashCard> getFlashcardsForCurrentPage() {
    return _flashcards;
  }
  
  // 플래시카드 목록 로드
  Future<void> loadFlashcardsForNote() async {
    if (_noteId.isEmpty) return;
    
    if (kDebugMode) {
      debugPrint("🔄 노트의 플래시카드 로드 시작: $_noteId");
    }
    
    try {
      // FlashCardService 인스턴스 생성
      final flashCardService = FlashCardService();
      final List<FlashCard> cards = await flashCardService.getFlashCardsForNote(_noteId);
      
      if (kDebugMode) {
        debugPrint("✅ 플래시카드 ${cards.length}개 로드 완료");
      }
      
      // 상태 업데이트
      _flashcards = cards;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 플래시카드 로드 중 오류: $e");
      }
    }
  }
  
  // 페이지 처리 모니터링 클래스
  late PageProcessingMonitor _pageMonitor;
  
  // 페이지 처리 완료 핸들러
  void _handlePageProcessed(int pageIndex, pika_page.Page updatedPage) {
    if (_pages == null || pageIndex < 0 || pageIndex >= _pages!.length) return;
    
    // 페이지 업데이트
    _pages![pageIndex] = updatedPage;
    
    // UI 업데이트
    notifyListeners();
    
    // 콜백 호출 (처리 완료 알림)
    if (_pageProcessedCallback != null) {
      _pageProcessedCallback!(pageIndex);
    }
    
    // 캐시된 처리 텍스트 확인
    if (updatedPage.id != null) {
      _segmentManager.getProcessedText(updatedPage.id!).then((processedText) {
        if (processedText == null && pageIndex == _currentPageIndex) {
          // 현재 페이지가 처리되었지만 세그먼트 정보가 없는 경우 새로고침
          loadInitialPages();
        }
      });
    }
  }
} 