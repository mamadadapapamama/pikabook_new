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
import '../services/pending_job_recovery_service.dart';

/// 단순화된 노트 상세 화면 ViewModel
/// UI 상태만 관리하고 비즈니스 로직은 Service Layer에 위임
class NoteDetailViewModel extends ChangeNotifier {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final TextProcessingService _textProcessingService = TextProcessingService();
  final PendingJobRecoveryService _pendingJobRecoveryService = PendingJobRecoveryService();
  
  // PageService에 접근하기 위한 게터
  PageService get _pageService => _noteService.pageService;
  
  // 매니저 인스턴스
  final NoteOptionsManager noteOptionsManager = NoteOptionsManager();
  
  // dispose 상태 추적
  bool _disposed = false;
  
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
      // 1. 미완료 작업 복구 (노트 상세페이지 진입시에만)
      await _recoverPendingJobsForThisNote();
      
      // 2. 페이지 로드
      final pages = await _pageService.getPagesForNote(_noteId);
      _pages = pages;
      _isLoading = false;
      
      notifyListeners();
      
      // 3. 모든 페이지에 대한 실시간 리스너 설정
      _setupAllPageListeners();
      
      // 4. 현재 페이지 텍스트 로드
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

  /// 현재 노트의 미완료 작업 복구 (수동 복구)
  Future<void> _recoverPendingJobsForThisNote() async {
    try {
      if (flutter_foundation.kDebugMode) {
        debugPrint("🔍 노트 $_noteId 미완료 작업 확인 중...");
      }
      
      final hasRecovered = await _pendingJobRecoveryService.recoverPendingJobsForNote(_noteId);
      
      if (hasRecovered && flutter_foundation.kDebugMode) {
        debugPrint("✅ 노트 $_noteId 미완료 작업 복구 완료");
      }
    } catch (e) {
      if (flutter_foundation.kDebugMode) {
        debugPrint("⚠️ 노트 $_noteId 미완료 작업 복구 실패: $e");
      }
      // 복구 실패는 전체 페이지 로딩을 막지 않음
    }
  }

  /// 모든 페이지에 대한 실시간 리스너 설정
  void _setupAllPageListeners() {
    if (_disposed || _pages == null) return;
    
    for (final page in _pages!) {
      if (page.id.isNotEmpty) {
        _setupPageListener(page.id);
        // 각 페이지의 초기 상태도 로드
        _loadPageInitialStatus(page.id);
      }
    }
    
    if (flutter_foundation.kDebugMode) {
      debugPrint("🔔 모든 페이지 리스너 설정 완료: ${_pages!.length}개");
    }
  }

  /// 페이지의 초기 처리 상태 로드
  Future<void> _loadPageInitialStatus(String pageId) async {
    if (_disposed) return;
    
    try {
      // 이미 처리된 텍스트가 있는지 확인
      final processedText = await _textProcessingService.getProcessedText(pageId);
      
      if (_disposed) return;
      
      if (processedText != null) {
        _processedTexts[pageId] = processedText;
        _pageStatuses[pageId] = ProcessingStatus.completed;
        
        if (flutter_foundation.kDebugMode) {
          debugPrint("✅ 페이지 초기 상태: $pageId - 처리 완료");
        }
      } else {
        // 처리된 텍스트가 없으면 상태 확인
        final status = await _textProcessingService.getProcessingStatus(pageId);
        if (_disposed) return;
        _pageStatuses[pageId] = status;
        
        if (flutter_foundation.kDebugMode) {
          debugPrint("📊 페이지 초기 상태: $pageId - ${status.displayName}");
        }
      }
      
      if (!_disposed) notifyListeners();
      
    } catch (e) {
      if (_disposed) return;
      
      _pageStatuses[pageId] = ProcessingStatus.failed;
      if (!_disposed) notifyListeners();
      
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 페이지 초기 상태 로드 실패: $pageId, 오류: $e");
      }
    }
  }

  /// 현재 페이지의 텍스트 데이터 로드 (Service Layer 사용)
  Future<void> loadCurrentPageText() async {
    if (_disposed || currentPage == null) return;
    
    final pageId = currentPage!.id;
    if (pageId.isEmpty) return;
    
    // 이미 로드된 경우 스킵
    if (_processedTexts.containsKey(pageId)) return;
    
    _textLoadingStates[pageId] = true;
    _textErrors[pageId] = null;
    if (!_disposed) notifyListeners();
    
    // 항상 실시간 리스너 설정 (후처리 완료 시 즉시 업데이트 받기 위해)
    _setupPageListener(pageId);
    
    try {
      // TextProcessingService 사용
      final processedText = await _textProcessingService.getProcessedText(pageId);
      
      if (_disposed) return; // dispose 체크
      
      if (processedText != null) {
        _processedTexts[pageId] = processedText;
        _pageStatuses[pageId] = ProcessingStatus.completed;
      } else {
        // 처리된 텍스트가 없으면 상태 확인
        final status = await _textProcessingService.getProcessingStatus(pageId);
        if (_disposed) return; // dispose 체크
        _pageStatuses[pageId] = status;
      }
      
      _textLoadingStates[pageId] = false;
      if (!_disposed) notifyListeners();
      
    } catch (e) {
      if (_disposed) return; // dispose 체크
      
      _textLoadingStates[pageId] = false;
      _textErrors[pageId] = '텍스트 로드 중 오류: $e';
      _pageStatuses[pageId] = ProcessingStatus.failed;
      if (!_disposed) notifyListeners();
      
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 텍스트 로드 중 오류: $e");
      }
    }
  }

  /// 페이지 실시간 리스너 설정
  void _setupPageListener(String pageId) {
    if (_disposed) return;
    
    if (flutter_foundation.kDebugMode) {
      debugPrint("🔔 [ViewModel] 페이지 리스너 설정 시작: $pageId");
    }
    
    // 기존 리스너 정리
    _pageListeners[pageId]?.cancel();
    
    // 새 리스너 설정
    final listener = _textProcessingService.listenToPageChanges(
      pageId,
      (processedText) {
        if (_disposed) {
          if (flutter_foundation.kDebugMode) {
            debugPrint("⚠️ [ViewModel] ViewModel이 dispose됨, 콜백 무시: $pageId");
          }
          return; // dispose 체크
        }
        
        if (flutter_foundation.kDebugMode) {
          debugPrint("📞 [ViewModel] UI 콜백 받음: $pageId");
          debugPrint("   processedText: ${processedText != null ? "있음" : "없음"}");
          if (processedText != null) {
            debugPrint("   유닛 개수: ${processedText.units.length}");
            debugPrint("   번역 텍스트 길이: ${processedText.fullTranslatedText?.length ?? 0}");
          }
        }
        
        if (processedText != null) {
          final previousStatus = _pageStatuses[pageId];
          final previousProcessedText = _processedTexts[pageId];
          final previousUnits = previousProcessedText?.units.length ?? 0;
          
          // 실제로 변경된 경우에만 상태 업데이트
          bool hasActualChange = false;
          
          // ProcessedText 변경 여부 확인
          if (previousProcessedText == null) {
            hasActualChange = true;
          } else {
            // 유닛 수나 번역 내용 변경 확인
            if (previousProcessedText.units.length != processedText.units.length ||
                previousProcessedText.fullTranslatedText != processedText.fullTranslatedText) {
              hasActualChange = true;
            }
          }
          
          // 변경된 경우에만 상태 업데이트
          if (hasActualChange) {
            _processedTexts[pageId] = processedText;
            _pageStatuses[pageId] = ProcessingStatus.completed;
            
            if (flutter_foundation.kDebugMode) {
              debugPrint("📊 [ViewModel] 실제 변경 감지로 상태 업데이트: $pageId");
              debugPrint("   이전 상태: ${previousStatus?.displayName ?? '없음'}");
              debugPrint("   현재 상태: ${ProcessingStatus.completed.displayName}");
              debugPrint("   이전 유닛: $previousUnits개");
              debugPrint("   현재 유닛: ${processedText.units.length}개");
              debugPrint("   번역 텍스트 변경: ${previousProcessedText?.fullTranslatedText != processedText.fullTranslatedText}");
            }
          } else {
            if (flutter_foundation.kDebugMode) {
              debugPrint("✅ [ViewModel] 동일한 데이터로 UI 업데이트 스킵: $pageId");
              debugPrint("   유닛 수: ${processedText.units.length}개 (변경 없음)");
              debugPrint("   번역 텍스트: ${processedText.fullTranslatedText.length}자 (변경 없음)");
            }
            return; // 변경이 없으면 notifyListeners() 호출하지 않음
          }
          
          // 페이지 처리 완료 콜백 호출
          if (_pageProcessedCallback != null && _pages != null) {
            final pageIndex = _pages!.indexWhere((page) => page.id == pageId);
            if (pageIndex >= 0) {
              if (flutter_foundation.kDebugMode) {
                debugPrint("📞 [ViewModel] 페이지 완료 콜백 호출: 페이지 인덱스 $pageIndex");
              }
              _pageProcessedCallback!(pageIndex);
            }
          }
          
          // notifyListeners 호출
          if (!_disposed) {
            if (flutter_foundation.kDebugMode) {
              debugPrint("🔄 [ViewModel] notifyListeners() 호출 시작: $pageId");
            }
            
            notifyListeners();
            
            if (flutter_foundation.kDebugMode) {
              debugPrint("✅ [ViewModel] notifyListeners() 호출 완료: $pageId");
              debugPrint("🔔 [ViewModel] 페이지 상태 변경 처리 완료: $pageId");
              debugPrint("   이전 상태: ${previousStatus?.displayName ?? '없음'}");
              debugPrint("   현재 상태: ${ProcessingStatus.completed.displayName}");
              debugPrint("   UI 업데이트 완료");
            }
          } else {
            if (flutter_foundation.kDebugMode) {
              debugPrint("⚠️ [ViewModel] notifyListeners() 스킵 (dispose됨): $pageId");
            }
          }
        } else {
          if (flutter_foundation.kDebugMode) {
            debugPrint("⚠️ [ViewModel] processedText가 null임: $pageId");
          }
        }
      },
    );
    
    if (listener != null) {
      _pageListeners[pageId] = listener;
      if (flutter_foundation.kDebugMode) {
        debugPrint("✅ [ViewModel] 페이지 리스너 설정 완료: $pageId");
      }
    } else {
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ [ViewModel] 페이지 리스너 설정 실패: $pageId");
      }
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

  /// 페이지 처리 중 상태 확인
  List<bool> getProcessingPagesStatus() {
    if (_pages == null || _pages!.isEmpty) {
      return [];
    }
    
    List<bool> processingStatus = List.filled(_pages!.length, false);
    
    for (int i = 0; i < _pages!.length; i++) {
      final page = _pages![i];
      if (page.id != null) {
        final status = _pageStatuses[page.id] ?? ProcessingStatus.created;
        processingStatus[i] = status.isProcessing;
      }
    }
    
    return processingStatus;
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
    _disposed = true; // dispose 상태 설정
    
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
