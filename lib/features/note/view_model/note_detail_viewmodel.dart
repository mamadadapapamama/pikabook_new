import 'dart:async';
import 'package:flutter/foundation.dart' as flutter_foundation;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/note.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import '../../../core/models/processing_status.dart';
import '../services/page_service.dart';
import '../managers/note_options_manager.dart';
import '../services/note_service.dart';
import '../../../core/services/text_processing/text_processing_service.dart';

/// 단순화된 노트 상세 화면 ViewModel
/// UI 상태만 관리하고 비즈니스 로직은 Service Layer에 위임
class NoteDetailViewModel extends ChangeNotifier {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final TextProcessingService _textProcessingService = TextProcessingService();
  
  // PageService에 접근하기 위한 게터
  PageService get _pageService => _noteService.pageService;
  
  // 매니저 인스턴스
  final NoteOptionsManager noteOptionsManager = NoteOptionsManager();
  
  // === UI 상태 변수들 ===
  Note? _note;
  bool _isLoading = true;
  String? _error;
  
  // 페이지 관련 UI 상태
  List<page_model.Page>? _pages;
  int _currentPageIndex = 0;
  
  // 텍스트 관련 UI 상태 (페이지별)
  final Map<String, ProcessedText> _processedTexts = {};
  final Map<String, bool> _textLoadingStates = {};
  final Map<String, String?> _textErrors = {};
  
  // 페이지 처리 상태 UI
  final Map<String, ProcessingStatus> _pageStatuses = {};
  
  // PageController (페이지 스와이프)
  final PageController pageController = PageController();
  
  // 노트 ID (불변)
  final String _noteId;
  
  // 페이지 처리 콜백
  Function(int)? _pageProcessedCallback;
  
  // 실시간 리스너들
  final Map<String, StreamSubscription<DocumentSnapshot>> _pageListeners = {};
  
  // Getters
  String get noteId => _noteId;
  List<page_model.Page>? get pages => _pages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Note? get note => _note;
  int get currentPageIndex => _currentPageIndex;
  int get flashcardCount => _note?.flashcardCount ?? 0;
  
  // 현재 페이지 getter
  page_model.Page? get currentPage {
    if (_pages == null || _pages!.isEmpty || _currentPageIndex >= _pages!.length) {
      return null;
    }
    return _pages![_currentPageIndex];
  }
  
  // 현재 페이지의 텍스트 처리 상태
  ProcessedText? get currentProcessedText {
    if (currentPage == null) return null;
    return _processedTexts[currentPage!.id];
  }
  
  // 현재 페이지의 텍스트 세그먼트
  List<TextUnit> get currentSegments {
    return currentProcessedText?.units ?? [];
  }

  /// 생성자
  NoteDetailViewModel({
    required String noteId,
    Note? initialNote,
    int totalImageCount = 0,
  }) : _noteId = noteId {
    // 상태 초기화
    _note = initialNote;
    
    // 초기 노트 정보 로드
    if (initialNote == null && noteId.isNotEmpty) {
      _loadNoteInfo();
    }
    
    // 초기 데이터 로드 (비동기)
    Future.microtask(() async {
      await loadInitialPages();
    });
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
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 노트 로드 중 오류: $e");
      }
    }
  }

  /// 초기 페이지 로드
  Future<void> loadInitialPages() async {
    if (flutter_foundation.kDebugMode) {
      debugPrint("🔄 페이지 로드 시작");
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // 페이지 로드
      final pages = await _pageService.getPagesForNote(_noteId);
      _pages = pages;
      _isLoading = false;
      
      notifyListeners();
      
      // 현재 페이지 텍스트 로드
      if (currentPage != null) {
        await loadCurrentPageText();
      }
      
    } catch (e) {
      _isLoading = false;
      _error = "페이지 로드 중 오류가 발생했습니다: $e";
      notifyListeners();
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 페이지 로드 중 오류: $e");
      }
    }
  }

  /// 현재 페이지의 텍스트 데이터 로드 (Service Layer 사용)
  Future<void> loadCurrentPageText() async {
    if (currentPage == null) return;
    
    final pageId = currentPage!.id;
    if (pageId.isEmpty) return;
    
    // 이미 로드된 경우 스킵
    if (_processedTexts.containsKey(pageId)) return;
    
    _textLoadingStates[pageId] = true;
    _textErrors[pageId] = null;
    notifyListeners();
    
    try {
      // TextProcessingService 사용
      final processedText = await _textProcessingService.getProcessedText(pageId);
      
      if (processedText != null) {
        _processedTexts[pageId] = processedText;
        _pageStatuses[pageId] = ProcessingStatus.completed;
        
        // 실시간 리스너 설정
        _setupPageListener(pageId);
      } else {
        // 처리된 텍스트가 없으면 상태 확인
        final status = await _textProcessingService.getProcessingStatus(pageId);
        _pageStatuses[pageId] = status;
      }
      
      _textLoadingStates[pageId] = false;
      notifyListeners();
      
    } catch (e) {
      _textLoadingStates[pageId] = false;
      _textErrors[pageId] = '텍스트 로드 중 오류: $e';
      _pageStatuses[pageId] = ProcessingStatus.failed;
      notifyListeners();
      
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 텍스트 로드 중 오류: $e");
      }
    }
  }

  /// 페이지 실시간 리스너 설정
  void _setupPageListener(String pageId) {
    // 기존 리스너 정리
    _pageListeners[pageId]?.cancel();
    
    // 새 리스너 설정
    final listener = _textProcessingService.listenToPageChanges(
      pageId,
      (processedText) {
        if (processedText != null) {
          _processedTexts[pageId] = processedText;
          _pageStatuses[pageId] = ProcessingStatus.completed;
          notifyListeners();
          
          if (flutter_foundation.kDebugMode) {
            debugPrint("🔔 페이지 텍스트 업데이트: $pageId");
          }
        }
      },
    );
    
    if (listener != null) {
      _pageListeners[pageId] = listener;
    }
  }

  /// 페이지 스와이프 이벤트 핸들러
  void onPageChanged(int index) {
    if (_pages == null || index < 0 || index >= _pages!.length || _currentPageIndex == index) return;
    
    _currentPageIndex = index;
    notifyListeners();
    
    // 현재 페이지 텍스트 로드
    Future.microtask(() async {
      await loadCurrentPageText();
    });
    
    if (flutter_foundation.kDebugMode) {
      debugPrint("📄 페이지 변경됨: ${index + 1}");
    }
  }

  /// 프로그램적으로 페이지 이동
  void navigateToPage(int index) {
    if (_pages == null || _pages!.isEmpty) return;
    
    // 유효한 인덱스인지 확인
    if (index < 0 || index >= _pages!.length) return;
    
    // 이미 해당 페이지인지 확인
    if (_currentPageIndex == index) return;
    
    // 페이지 컨트롤러로 애니메이션 적용하여 이동
    pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  /// 지정된 페이지 ID에 대한 텍스트 데이터 가져오기 (호환성 유지)
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

  /// 노트 제목 업데이트
  Future<bool> updateNoteTitle(String newTitle) async {
    if (_note == null) return false;
    
    final success = await noteOptionsManager.updateNoteTitle(_note!.id, newTitle);
    
    if (success && _note != null) {
      notifyListeners();
    }
    
    return success;
  }

  /// 노트 삭제
  Future<bool> deleteNote(BuildContext context) async {
    if (_note == null) return false;
    
    final String id = _note!.id;
    if (id.isEmpty) return false;
    
    try {
      return await noteOptionsManager.deleteNote(context, id);
    } catch (e) {
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 노트 삭제 중 오류: $e");
      }
      return false;
    }
  }

  /// 페이지 처리 상태 확인
  List<bool> getProcessedPagesStatus() {
    if (_pages == null || _pages!.isEmpty) {
      return [];
    }
    
    List<bool> processedStatus = List.filled(_pages!.length, false);
    
    for (int i = 0; i < _pages!.length; i++) {
      final page = _pages![i];
      if (page.id != null) {
        final status = _pageStatuses[page.id] ?? ProcessingStatus.created;
        processedStatus[i] = status.isCompleted;
      }
    }
    
    return processedStatus;
  }

  /// 페이지 처리 완료 콜백 설정
  void setPageProcessedCallback(Function(int) callback) {
    _pageProcessedCallback = callback;
  }

  /// 페이지가 처리 중인지 확인
  bool isPageProcessing(page_model.Page page) {
    if (page.id.isEmpty) return false;
    
    final status = _pageStatuses[page.id] ?? ProcessingStatus.created;
    return status.isProcessing;
  }

  /// 노트 정보 다시 로드
  Future<void> loadNote() async {
    await _loadNoteInfo();
  }

  /// 리소스 정리
  @override
  void dispose() {
    pageController.dispose();
    
    // 페이지 리스너 정리
    for (var listener in _pageListeners.values) {
      listener.cancel();
    }
    _pageListeners.clear();
    
    // TextProcessingService 리스너 정리
    _textProcessingService.cancelAllListeners();
    
    super.dispose();
  }
}

// 내부 debugging 함수
void debugPrint(String message) {
  if (flutter_foundation.kDebugMode) {
    print(message);
  }
}
