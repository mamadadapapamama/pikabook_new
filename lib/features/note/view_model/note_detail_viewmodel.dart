import 'dart:async';
import 'package:flutter/foundation.dart';
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

/// 노트 상세 화면 ViewModel - 핵심 기능만 관리
class NoteDetailViewModel extends ChangeNotifier {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final TextProcessingService _textProcessingService = TextProcessingService();
  final NoteOptionsManager noteOptionsManager = NoteOptionsManager();
  
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
  
  // 텍스트 관련 상태 (페이지별)
  final Map<String, ProcessedText> _processedTexts = {};
  final Map<String, bool> _textLoadingStates = {};
  final Map<String, String?> _textErrors = {};
  final Map<String, ProcessingStatus> _pageStatuses = {};
  
  // PageController
  final PageController pageController = PageController();
  
  // 노트 ID
  final String _noteId;
  
  // 실시간 리스너들
  final Map<String, StreamSubscription<DocumentSnapshot>> _pageListeners = {};
  
  // === Getters ===
  String get noteId => _noteId;
  List<page_model.Page>? get pages => _pages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Note? get note => _note;
  int get currentPageIndex => _currentPageIndex;
  
  // 현재 페이지
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

  /// 생성자
  NoteDetailViewModel({
    required String noteId,
    Note? initialNote,
  }) : _noteId = noteId {
    _note = initialNote;
    
    // 초기 데이터 로드
    Future.microtask(() async {
      if (initialNote == null && noteId.isNotEmpty) {
        await _loadNoteInfo();
      }
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
    }
  }

  /// 초기 페이지 로드
  Future<void> loadInitialPages() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // 페이지 로드
      final pages = await _pageService.getPagesForNote(_noteId);
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

  /// 모든 페이지 리스너 설정
  void _setupAllPageListeners() {
    if (_disposed || _pages == null) return;
    
    for (final page in _pages!) {
      if (page.id.isNotEmpty) {
        _setupPageListener(page.id);
        _loadPageInitialStatus(page.id);
      }
    }
  }

  /// 페이지 초기 상태 로드
  Future<void> _loadPageInitialStatus(String pageId) async {
    if (_disposed) return;
    
    try {
      final processedText = await _textProcessingService.getProcessedText(pageId);
      
      if (_disposed) return;
      
      if (processedText != null) {
        _processedTexts[pageId] = processedText;
        _pageStatuses[pageId] = ProcessingStatus.completed;
      } else {
        final status = await _textProcessingService.getProcessingStatus(pageId);
        if (_disposed) return;
        _pageStatuses[pageId] = status;
      }
      
      if (!_disposed) notifyListeners();
      
    } catch (e) {
      if (_disposed) return;
      _pageStatuses[pageId] = ProcessingStatus.failed;
      if (!_disposed) notifyListeners();
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
    
    _setupPageListener(pageId);
    
    try {
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
      final processedText = await _textProcessingService.getProcessedText(pageId);
      
      if (_disposed) return;
      
      if (processedText != null) {
        _processedTexts[pageId] = processedText;
        _pageStatuses[pageId] = ProcessingStatus.completed;
      } else {
        final status = await _textProcessingService.getProcessingStatus(pageId);
        if (_disposed) return;
        _pageStatuses[pageId] = status;
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
    if (_pages == null || index < 0 || index >= _pages!.length || _currentPageIndex == index) return;
    
    _currentPageIndex = index;
    notifyListeners();
    
    Future.microtask(() async {
      await loadCurrentPageText();
    });
  }

  /// 프로그램적 페이지 이동
  void navigateToPage(int index) {
    if (_pages == null || _pages!.isEmpty) return;
    if (index < 0 || index >= _pages!.length) return;
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
      return false;
    }
  }

  /// 페이지 에러 상태 초기화
  void clearPageError(String pageId) {
    if (_disposed) return;
    
    _textErrors.remove(pageId);
    _textLoadingStates[pageId] = false;
    
    if (!_disposed) notifyListeners();
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
    
    // TextProcessingService 리스너 정리
    _textProcessingService.cancelAllListeners();
    
    super.dispose();
  }
}

