import 'dart:async';
import 'package:flutter/foundation.dart' as flutter_foundation;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/note.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/flash_card.dart';
import '../../../core/services/content/page_service.dart';
import '../../../core/services/media/image_service.dart';
import '../managers/note_options_manager.dart';
import '../../../core/services/content/note_service.dart';
import '../../flashcard/flashcard_service.dart';
import 'dart:io';
import 'text_view_model.dart';

/// 노트 상세 화면의 ViewModel (리팩토링 버전)
class NoteDetailViewModelNew extends ChangeNotifier {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final FlashCardService _flashCardService = FlashCardService();
  final ImageService _imageService = ImageService();
  
  // PageService에 접근하기 위한 게터 추가
  PageService get _pageService => _noteService.pageService;
  
  // 매니저 인스턴스
  final NoteOptionsManager noteOptionsManager = NoteOptionsManager();
  
  // TextViewModel 관리 (페이지 ID를 키로 사용)
  final Map<String, TextViewModel> _textViewModels = {};
  
  // 상태 변수들 (NoteDetailState 내부 구현)
  Note? _note;
  bool _isLoading = true;
  String? _error;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _expectedTotalPages = 0;
  final Map<String, bool> _processedPageStatus = {};
  List<StreamSubscription<DocumentSnapshot>?> _pageListeners = [];
  StreamSubscription? _pagesSubscription;
  
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
  
  // 현재 페이지의 TextViewModel 얻기
  TextViewModel? get currentTextViewModel {
    if (currentPage == null || currentPage!.id.isEmpty) {
      return null;
    }
    return getTextViewModel(currentPage!.id);
  }
  
  // 현재 텍스트 뷰 상태 (간소화된 상태)
  TextViewState? get currentTextViewState {
    return currentTextViewModel?.state;
  }
  
  // 전체 텍스트 모드 getter (현재 텍스트 뷰모델에서 위임)
  bool get isFullTextMode => currentTextViewModel?.isFullTextMode ?? false;
  
  /// 생성자
  NoteDetailViewModelNew({
    required String noteId,
    Note? initialNote,
    int totalImageCount = 0,
  }) : _noteId = noteId {
    // 상태 초기화
    _note = initialNote;
    _expectedTotalPages = totalImageCount;
    
    // 초기 노트 정보 로드
    if (initialNote == null && noteId.isNotEmpty) {
      _loadNoteInfo();
    }
    
    // 페이지 처리 상태 모니터 초기화
    _initPageProcessingState();
    
    // 초기 데이터 로드 (비동기)
    Future.microtask(() async {
      await loadInitialPages();
      await loadFlashcardsForNote();
    });
  }
  
  /// 지정된 페이지 ID에 대한 TextViewModel 가져오기
  /// 없으면 새로 생성하여 반환
  TextViewModel getTextViewModel(String pageId) {
    if (pageId.isEmpty) {
      throw ArgumentError('페이지 ID가 비어있습니다');
    }
    
    // 이미 존재하는 경우 반환
    if (_textViewModels.containsKey(pageId)) {
      return _textViewModels[pageId]!;
    }
    
    // 새로 생성
    final textViewModel = TextViewModel(id: pageId);
    _textViewModels[pageId] = textViewModel;
    
    // 필요한 초기화 작업
    if (_flashcards.isNotEmpty) {
      textViewModel.extractFlashcardWords(_flashcards);
    }
    
    // 현재 페이지에 해당하면 텍스트 처리 시작
    if (currentPage != null && currentPage!.id == pageId) {
      _initCurrentPageText(textViewModel);
    }
    
    return textViewModel;
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
      // 페이지 로드 - PageManager 대신 PageService 직접 사용
      final pages = await _pageService.getPagesForNote(_noteId);
      _pages = pages;
      _isLoading = false;
      
      // 페이지 처리 상태 모니터링 시작
      if (_pages != null && _pages!.isNotEmpty) {
        _startMonitoring(_pages!);
      }
      
      notifyListeners();
      
      // 백그라운드에서 이미지 로드
      _loadPageImages();
      
      // 현재 페이지 텍스트 처리 시작
      if (currentPage != null) {
        final textViewModel = getTextViewModel(currentPage!.id);
        _initCurrentPageText(textViewModel);
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
  
  /// 페이지 처리 상태 초기화
  void _initPageProcessingState() {
    // 기존 페이지 처리 상태 모니터링 취소
    _cancelMonitoring();
  }
  
  /// 페이지 처리 상태 모니터링 시작
  void _startMonitoring(List<page_model.Page> pages) {
    // 기존 리스너 정리
    _cancelMonitoring();
    
    if (flutter_foundation.kDebugMode) {
      debugPrint('📱 페이지 처리 상태 리스너 설정: ${pages.length}개 페이지');
    }
    
    // 초기 상태 설정
    for (var page in pages) {
      if (page.id != null) {
        _processedPageStatus[page.id!] = true; // 기본적으로 모든 페이지는 처리됨으로 간주
      }
    }
    
    // 각 페이지에 대한 리스너 설정
    for (var page in pages) {
      if (page.id == null) continue;
      
      // 페이지 문서 변경 감지 리스너
      final listener = _firestore
          .collection('pages')
          .doc(page.id)
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.exists) return;
        
        final updatedPage = page_model.Page.fromFirestore(snapshot);
        final pageIndex = pages.indexWhere((p) => p.id == page.id);
        if (pageIndex < 0) return;
        
        // 텍스트가 처리되었는지 확인
        final wasProcessing = _processedPageStatus[page.id!] == false;
        final isNowProcessed = true; // 모든 페이지는 처리된 것으로 간주
        
        // 처리 상태가 변경된 경우에만 업데이트
        if (wasProcessing && isNowProcessed) {
          if (flutter_foundation.kDebugMode) {
            debugPrint('✅ 페이지 처리 완료 감지됨: ${page.id}');
          }
          
          _processedPageStatus[page.id!] = true;
          
          // 콜백 호출 (처리 완료 알림)
          _handlePageProcessed(pageIndex, updatedPage);
          
          // 상태 변경 알림
          notifyListeners();
        }
      });
      
      _pageListeners.add(listener);
    }
  }
  
  /// 페이지 처리 상태 모니터링 중지
  void _cancelMonitoring() {
    for (var listener in _pageListeners) {
      listener?.cancel();
    }
    _pageListeners.clear();
    
    _pagesSubscription?.cancel();
    _pagesSubscription = null;
  }
  
  /// 현재 페이지 텍스트 초기화
  void _initCurrentPageText(TextViewModel textViewModel) {
    if (currentPage != null && currentPage!.id.isNotEmpty) {
      textViewModel.setPageId(currentPage!.id);
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
    
    // 현재 페이지의 텍스트 처리 시작
    if (currentPage != null) {
      final textViewModel = getTextViewModel(currentPage!.id);
      _initCurrentPageText(textViewModel);
    }
    
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
  
  
  /// 노트 제목 업데이트
  Future<bool> updateNoteTitle(String newTitle) async {
    if (_note == null) return false;
    
    final success = await noteOptionsManager.updateNoteTitle(_note!.id, newTitle);
    
    if (success && _note != null) {
      // 성공 후 상태 업데이트만 담당
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
    if (_pages == null || _pages!.isEmpty) {
      return [];
    }
    
    List<bool> processedStatus = List.filled(_pages!.length, false);
    
    // 각 페이지의 처리 상태 설정
    for (int i = 0; i < _pages!.length; i++) {
      final page = _pages![i];
      if (page.id != null && _processedPageStatus.containsKey(page.id!)) {
        processedStatus[i] = _processedPageStatus[page.id!] ?? false;
      } else {
        // 상태 정보가 없는 경우, 처리된 것으로 간주
        processedStatus[i] = true;
      }
    }
    
    return processedStatus;
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
      
      // 모든 텍스트 뷰모델에 플래시카드 단어 전달
      for (final textViewModel in _textViewModels.values) {
        textViewModel.extractFlashcardWords(_flashcards);
      }
      
      notifyListeners();
    } catch (e) {
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 플래시카드 로드 중 오류: $e");
      }
    }
  }
  
  /// 플래시카드 카운트 업데이트
  void updateFlashcardCount(int count) {
    if (_note == null) return;
    
    // 노트 객체의 플래시카드 카운트 업데이트
    _note = _note!.copyWith(flashcardCount: count);
    
    // UI 차단 방지를 위해 백그라운드에서 Firestore 업데이트
    Future.microtask(() async {
      await _noteService.updateNote(_note!.id!, _note!);
    });
    
    notifyListeners();
  }
  
  /// 플래시카드 목록 업데이트
  void updateFlashcards(List<FlashCard> flashcards) {
    _flashcards = flashcards;
    
    // 모든 텍스트 뷰모델에 플래시카드 단어 전달
    for (final textViewModel in _textViewModels.values) {
      textViewModel.extractFlashcardWords(_flashcards);
    }
    
    notifyListeners();
  }
  
  /// 현재 페이지에 해당하는 플래시카드 목록 반환
  List<FlashCard> getFlashcardsForCurrentPage() {
    return _flashcards;
  }
  
  /// 페이지가 처리 중인지 확인
  bool isPageProcessing(page_model.Page page) {
    // 실제 구현에서는 페이지 상태를 확인해야 합니다.
    // 현재는 페이지 상태를 확인할 방법이 없으므로, 항상 false를 반환합니다.
    return false;
  }
  
  /// TTS 재생 메서드
  Future<void> playTts(String text, {int? segmentIndex}) async {
    if (currentTextViewModel == null) return;
    await currentTextViewModel!.playTts(text, segmentIndex: segmentIndex);
  }
  
  /// 세그먼트 삭제
  Future<bool> deleteSegment(int segmentIndex) async {
    if (currentPage == null || currentTextViewModel == null) return false;
    
    return await currentTextViewModel!.deleteSegment(
      segmentIndex, 
      currentPage!.id, 
      currentPage!
    );
  }
  
  /// TTS 관련 메서드
  bool get isTtsPlaying => currentTextViewModel?.audioState == AudioState.playing;
  
  void stopTts() {
    currentTextViewModel?.stopTts();
  }
  
  void pauseTts() {
    currentTextViewModel?.pauseTts();
  }
  
  Future<void> speakText(String text, {int? segmentIndex}) async {
    if (currentTextViewModel == null) return;
    await currentTextViewModel!.playTts(text, segmentIndex: segmentIndex);
  }
  
  /// 현재 페이지의 전체 텍스트 읽기
  Future<void> speakCurrentPageText() async {
    if (currentPage == null || currentTextViewModel == null) return;
    
    final fullText = currentTextViewModel!.processedText?.fullOriginalText ?? '';
    await speakText(fullText);
  }
  
  /// 리소스 정리
  @override
  void dispose() {
    pageController.dispose();
    
    // 모든 TextViewModel 정리
    for (final textViewModel in _textViewModels.values) {
      textViewModel.dispose();
    }
    _textViewModels.clear();
    
    // 모니터링 리스너 정리
    _cancelMonitoring();
    
    super.dispose();
  }
  
  /// 노트 정보 다시 로드
  Future<void> loadNote() async {
    await _loadNoteInfo();
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
      final imageFile = await _imageService.getImageFile(page.imageUrl!);
      
      if (imageFile != null) {
        // 이미지 파일 캐싱
        _imageFileCache[page.imageUrl!] = imageFile;
        
        // 현재 페이지인 경우 텍스트 처리 시작
        if (pageIndex == _currentPageIndex) {
          final textViewModel = getTextViewModel(page.id);
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
}

// 내부 debugging 함수
void debugPrint(String message) {
  if (flutter_foundation.kDebugMode) {
    print(message);
  }
}
