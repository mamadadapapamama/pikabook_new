import 'dart:async';
import 'package:flutter/foundation.dart' as flutter_foundation;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/note.dart';
import '../../core/models/page.dart' as page_model;
import '../../core/models/flash_card.dart';
import '../../core/services/content/page_service.dart';
import '../../core/services/media/image_service.dart';
import 'managers/note_options_manager.dart';
import '../../core/services/content/note_service.dart';
import '../flashcard/flashcard_service.dart';
import 'dart:io';
import 'note_detail_state.dart';
import 'page_processing_state.dart';
import 'view_model/text_view_model.dart';

/// 노트 상세 화면의 ViewModel (리팩토링 버전)
class NoteDetailViewModelNew extends ChangeNotifier {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final FlashCardService _flashCardService = FlashCardService();
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  
  // 매니저 인스턴스
  final NoteOptionsManager _noteOptionsManager = NoteOptionsManager();
  
  // 텍스트 처리를 위한 ViewModel
  final TextViewModel textViewModel;
  
  // 상태 관리 클래스
  late NoteDetailState _state;
  
  // PageController (페이지 스와이프)
  final PageController pageController = PageController();
  
  // 노트 ID (불변)
  final String _noteId;
  
  // 현재 페이지 인덱스
  int _currentPageIndex = 0;
  
  // 페이지 목록
  List<page_model.Page>? _pages;
  
  // 이미지 파일 캐시
  final Map<String, File> _imageFileCache = {};
  
  // 플래시카드 목록
  List<FlashCard> _flashcards = [];
  
  // 페이지 처리 콜백
  Function(int)? _pageProcessedCallback;
  
  // Getters
  String get noteId => _noteId;
  List<page_model.Page>? get pages => _pages;
  bool get isLoading => _state.isLoading;
  String? get error => _state.error;
  Note? get note => _state.note;
  int get currentPageIndex => _currentPageIndex;
  int get flashcardCount => _state.note?.flashcardCount ?? 0;
  
  // TextViewModel에서 위임받는 getter들
  bool get isFullTextMode => textViewModel.isFullTextMode;
  
  // 현재 페이지 getter
  page_model.Page? get currentPage {
    if (_pages == null || _pages!.isEmpty || _currentPageIndex >= _pages!.length) {
      return null;
    }
    return _pages![_currentPageIndex];
  }
  
  /// 생성자
  NoteDetailViewModelNew({
    required String noteId,
    Note? initialNote,
    int totalImageCount = 0,
    TextViewModel? textViewModel,
  }) : 
    _noteId = noteId,
    textViewModel = textViewModel ?? TextViewModel() {
    // 상태 초기화
    _state = NoteDetailState();
    _state.note = initialNote;
    _state.expectedTotalPages = totalImageCount;
    
    // 초기 노트 정보 로드
    if (initialNote == null && noteId.isNotEmpty) {
      _loadNoteInfo();
    }
    
    // 페이지 처리 상태 모니터 초기화
    _state.initPageProcessingState(noteId, _handlePageProcessed);
    
    // 초기 데이터 로드 (비동기)
    Future.microtask(() async {
      await loadInitialPages();
      await loadFlashcardsForNote();
    });
  }
  
  /// 노트 정보 로드
  Future<void> _loadNoteInfo() async {
    _state.setLoading(true);
    
    try {
      final loadedNote = await _noteService.getNoteById(_noteId);
      if (loadedNote != null) {
        _state.updateNote(loadedNote);
        _state.setLoading(false);
        notifyListeners();
      } else {
        _state.setLoading(false);
        _state.setError("노트를 찾을 수 없습니다.");
        notifyListeners();
      }
    } catch (e) {
      _state.setLoading(false);
      _state.setError("노트 로드 중 오류가 발생했습니다: $e");
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
    
    _state.setLoading(true);
    notifyListeners();
    
    try {
      // 페이지 로드 - PageManager 대신 PageService 직접 사용
      final pages = await _pageService.getPagesForNote(_noteId);
      _pages = pages;
      _state.setLoading(false);
      
      // 페이지 처리 상태 모니터링 시작
      if (_pages != null && _pages!.isNotEmpty) {
        _state.pageProcessingState?.startMonitoring(_pages!);
      }
      
      notifyListeners();
      
      // 백그라운드에서 이미지 로드
      _loadPageImages();
      
      // 현재 페이지 텍스트 처리 - TextViewModel에 위임
      _initCurrentPageText();
      
    } catch (e) {
      _state.setLoading(false);
      _state.setError("페이지 로드 중 오류가 발생했습니다: $e");
      notifyListeners();
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 페이지 로드 중 오류: $e");
      }
    }
  }
  
  /// 현재 페이지 텍스트 초기화 - TextViewModel에 위임
  void _initCurrentPageText() {
    if (currentPage != null && currentPage!.id.isNotEmpty) {
      textViewModel.setPageId(currentPage!.id);
    }
  }
  
  /// 페이지 이미지 로드
  Future<void> _loadPageImages() async {
    if (_pages == null || _pages!.isEmpty) return;
    
    // 우선 현재 페이지 이미지 로드
    if (_currentPageIndex >= 0 && _currentPageIndex < _pages!.length) {
      await _loadPageImage(_currentPageIndex);
    }
    
    // 인접 페이지 로드 (다음 & 이전)
    List<Future<void>> priorityLoads = [];
    
    if (_currentPageIndex + 1 < _pages!.length) {
      priorityLoads.add(_loadPageImage(_currentPageIndex + 1));
    }
    
    if (_currentPageIndex - 1 >= 0) {
      priorityLoads.add(_loadPageImage(_currentPageIndex - 1));
    }
    
    await Future.wait(priorityLoads);
    
    // 나머지 페이지 이미지 로드
    for (int i = 0; i < _pages!.length; i++) {
      if (i != _currentPageIndex && i != _currentPageIndex + 1 && i != _currentPageIndex - 1) {
        await _loadPageImage(i);
      }
    }
  }
  
  /// 특정 페이지 이미지 로드
  Future<void> _loadPageImage(int pageIndex) async {
    if (_pages == null || pageIndex < 0 || pageIndex >= _pages!.length) return;
    
    final page = _pages![pageIndex];
    
    // null 체크 개선
    if (page.id.isEmpty) return;
    if (page.imageUrl == null) return; // imageUrl은 nullable 필드임
    
    try {
      // 페이지 이미지 로드 - ImageService 직접 사용
      // String? 타입을 String으로 변환 (null 아님이 확인되었으므로 안전함)
      final imageFile = await _imageService.getImageFile(page.imageUrl);
      
      if (imageFile != null) {
        // 이미지 파일 캐싱
        _imageFileCache[page.imageUrl] = imageFile;
        
        // 현재 페이지인 경우 텍스트 처리 시작 - TextViewModel에 위임
        if (pageIndex == _currentPageIndex) {
          // TextViewModel에 텍스트 처리 요청 위임
          textViewModel.processPageText(page, imageFile: imageFile);
          notifyListeners();
        }
      }
    } catch (e) {
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 페이지 이미지 로드 중 오류: $e");
      }
    }
  }
  
  /// 페이지 처리 완료 핸들러
  void _handlePageProcessed(int pageIndex, page_model.Page updatedPage) {
    if (_pages == null || pageIndex < 0 || pageIndex >= _pages!.length) return;
    
    // 페이지 업데이트
    _pages![pageIndex] = updatedPage;
    
    // UI 갱신
    notifyListeners();
    
    // 콜백 호출
    if (_pageProcessedCallback != null) {
      _pageProcessedCallback!(pageIndex);
    }
    
    if (flutter_foundation.kDebugMode) {
      debugPrint("✅ 페이지 ${pageIndex + 1} 처리 완료");
    }
  }
  
  /// 페이지 스와이프 이벤트 핸들러
  void onPageChanged(int index) {
    if (_pages == null || index < 0 || index >= _pages!.length || _currentPageIndex == index) return;
    
    _currentPageIndex = index;
    notifyListeners();
    
    // 전방/후방 이미지 프리로드
    _preloadAdjacentImages(index);
    
    // 현재 페이지의 텍스트 처리 시작 - TextViewModel에 위임
    _initCurrentPageText();
    
    if (flutter_foundation.kDebugMode) {
      debugPrint("📄 페이지 변경됨: ${index + 1}");
    }
  }
  
  /// 인접 이미지 프리로드
  void _preloadAdjacentImages(int currentIndex) {
    if (_pages == null) return;
    
    // 다음 페이지 이미지 로드
    if (currentIndex + 1 < _pages!.length) {
      _loadPageImage(currentIndex + 1);
    }
    
    // 이전 페이지 이미지 로드
    if (currentIndex - 1 >= 0) {
      _loadPageImage(currentIndex - 1);
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
  
  /// 전체 텍스트 모드 토글 - TextViewModel에 위임
  void toggleFullTextMode() {
    textViewModel.toggleFullTextMode();
    notifyListeners();
  }
  
  /// 즐겨찾기 토글
  Future<bool> toggleFavorite() async {
    if (_state.note == null || _state.note!.id == null) return false;
    
    final newValue = !(_state.note!.isFavorite);
    final success = await _noteOptionsManager.toggleFavorite(_state.note!.id!, newValue);
    
    if (success) {
      _state.note = _state.note!.copyWith(isFavorite: newValue);
      _state.toggleFavorite();
      notifyListeners();
    }
    
    return success;
  }
  
  /// 노트 제목 업데이트
  Future<bool> updateNoteTitle(String newTitle) async {
    if (_state.note == null || _state.note!.id == null) return false;
    
    final success = await _noteOptionsManager.updateNoteTitle(_state.note!.id!, newTitle);
    
    if (success) {
      // 노트 새로 로드
      final updatedNote = await _noteService.getNoteById(_state.note!.id!);
      if (updatedNote != null) {
        _state.updateNote(updatedNote);
        notifyListeners();
      }
    }
    
    return success;
  }
  
  /// 노트 삭제
  Future<bool> deleteNote() async {
    if (_state.note == null || _state.note!.id == null) return false;
    
    try {
      await _noteService.deleteNote(_state.note!.id!);
      return true;
    } catch (e) {
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 노트 삭제 중 오류: $e");
      }
      return false;
    }
  }
  
  /// 현재 페이지 이미지 파일 가져오기
  File? getCurrentPageImageFile() {
    // null 체크 개선
    if (currentPage == null) return null;
    if (currentPage!.imageUrl == null) return null; // imageUrl은 nullable 필드임
    
    // 캐시에서 이미지 파일 가져오기
    return _imageFileCache[currentPage!.imageUrl];
  }
  
  /// 페이지 처리 상태 확인
  List<bool> getProcessedPagesStatus() {
    if (_pages == null || _pages!.isEmpty || _state.pageProcessingState == null) {
      return [];
    }
    
    return _state.pageProcessingState!.getProcessedPagesStatus(_pages!);
  }
  
  /// 페이지 처리 완료 콜백 설정
  void setPageProcessedCallback(Function(int) callback) {
    _pageProcessedCallback = callback;
  }
  
  /// 플래시카드 목록 로드
  Future<void> loadFlashcardsForNote() async {
    try {
      final cards = await _flashCardService.getFlashCardsForNote(_noteId);
      _flashcards = cards;
      
      // 텍스트 뷰모델에 플래시카드 단어 전달
      textViewModel.extractFlashcardWords(_flashcards);
      
      notifyListeners();
    } catch (e) {
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 플래시카드 로드 중 오류: $e");
      }
    }
  }
  
  /// 플래시카드 카운트 업데이트
  void updateFlashcardCount(int count) {
    if (_state.note == null) return;
    
    // 노트 객체의 플래시카드 카운트 업데이트
    _state.note = _state.note!.copyWith(flashcardCount: count);
    
    // UI 차단 방지를 위해 백그라운드에서 Firestore 업데이트
    Future.microtask(() async {
      await _noteService.updateNote(_state.note!.id!, _state.note!);
    });
    
    notifyListeners();
  }
  
  /// 플래시카드 목록 업데이트
  void updateFlashcards(List<FlashCard> flashcards) {
    _flashcards = flashcards;
    
    // 텍스트 뷰모델에 플래시카드 단어 전달
    textViewModel.extractFlashcardWords(_flashcards);
    
    notifyListeners();
  }
  
  /// 현재 페이지에 해당하는 플래시카드 목록 반환
  List<FlashCard> getFlashcardsForCurrentPage() {
    return _flashcards;
  }
  
  /// 리소스 정리
  @override
  void dispose() {
    pageController.dispose();
    // 노트: textViewModel은 여기서 dispose하지 않습니다. 외부에서 관리됩니다.
    _state.dispose();
    super.dispose();
  }
}

// 내부 debugging 함수
void debugPrint(String message) {
  if (flutter_foundation.kDebugMode) {
    print(message);
  }
}
