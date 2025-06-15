import 'dart:async';
import 'package:flutter/foundation.dart' as flutter_foundation;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/note.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import '../../../core/models/processing_status.dart';
import '../post_llm_workflow.dart';
import '../services/page_service.dart';
import '../managers/note_options_manager.dart';
import '../services/note_service.dart';
import '../../../core/services/text_processing/text_processing_service.dart';
import '../services/pending_job_recovery_service.dart';
import '../../sample/sample_data_service.dart';
import '../../../core/services/authentication/auth_service.dart';

/// 단순화된 노트 상세 화면 ViewModel
/// UI 상태만 관리하고 비즈니스 로직은 Service Layer에 위임
class NoteDetailViewModel extends ChangeNotifier {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final TextProcessingService _textProcessingService = TextProcessingService();
  final PendingJobRecoveryService _pendingJobRecoveryService = PendingJobRecoveryService();
  final PostLLMWorkflow _postLLMWorkflow = PostLLMWorkflow();
  final SampleDataService _sampleDataService = SampleDataService();
  final AuthService _authService = AuthService();
  
  // 로그인 상태 (샘플 모드 여부 결정)
  bool _isLoggedIn = false;
  
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
  
  // LLM 재시도 관련 상태
  bool _llmTimeoutOccurred = false;
  bool _llmRetryAvailable = false;
  bool _isRetryingLlm = false;
  
  // 최종 실패 관련 상태
  bool _showFailureMessage = false;
  String? _userFriendlyError;
  
  // Getters
  String get noteId => _noteId;
  List<page_model.Page>? get pages => _pages;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Note? get note => _note;
  int get currentPageIndex => _currentPageIndex;
  int get flashcardCount => _note?.flashcardCount ?? 0;
  
  // LLM 재시도 관련 getters
  bool get llmTimeoutOccurred => _llmTimeoutOccurred;
  bool get llmRetryAvailable => _llmRetryAvailable;
  bool get isRetryingLlm => _isRetryingLlm;
  
  // 최종 실패 관련 getters
  bool get showFailureMessage => _showFailureMessage;
  String? get userFriendlyError => _userFriendlyError;
  
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
    
          // 초기 데이터 로드 (비동기)
      Future.microtask(() async {
        // 로그인 상태 확인
        await _checkLoginStatus();
        
        if (!_isLoggedIn) {
          // 로그아웃 상태 = 샘플 데이터 사용
          await _loadSampleData();
        } else {
          // 로그인 상태 = 실제 데이터 사용
          if (initialNote == null && noteId.isNotEmpty) {
            await _loadNoteInfo();
          }
          await loadInitialPages();
        }
      });
  }

  /// 로그인 상태 확인
  Future<void> _checkLoginStatus() async {
    try {
      final currentUser = _authService.currentUser;
      _isLoggedIn = currentUser != null;
      if (flutter_foundation.kDebugMode) {
        debugPrint("👤 [ViewModel] 로그인 상태 확인:");
        debugPrint("   currentUser: ${currentUser?.uid ?? 'null'}");
        debugPrint("   _isLoggedIn: $_isLoggedIn");
      }
    } catch (e) {
      _isLoggedIn = false;
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ [ViewModel] 로그인 상태 확인 중 오류: $e");
      }
    }
  }

  /// 샘플 데이터 로드
  Future<void> _loadSampleData() async {
    if (flutter_foundation.kDebugMode) {
      debugPrint("📦 샘플 데이터 로드 시작");
    }
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // 샘플 데이터 로드
      await _sampleDataService.loadSampleData();
      
      // 샘플 노트 설정
      _note = _sampleDataService.getSampleNote();
      
      // 샘플 페이지 설정
      _pages = _sampleDataService.getSamplePages(_noteId);
      
      // 샘플 처리된 텍스트 설정
      if (_pages != null && _pages!.isNotEmpty) {
        for (final page in _pages!) {
          final processedText = _sampleDataService.getProcessedText(page.id);
          if (processedText != null) {
            _processedTexts[page.id] = processedText;
          }
        }
      }
      
      _isLoading = false;
      notifyListeners();
      
      if (flutter_foundation.kDebugMode) {
        debugPrint("✅ 샘플 데이터 로드 완료");
        debugPrint("   노트: ${_note?.title}");
        debugPrint("   페이지: ${_pages?.length}개");
        debugPrint("   처리된 텍스트: ${_processedTexts.length}개");
      }
    } catch (e) {
      _isLoading = false;
      _error = "샘플 데이터 로드 중 오류가 발생했습니다: $e";
      notifyListeners();
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 샘플 데이터 로드 중 오류: $e");
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
      if (flutter_foundation.kDebugMode) {
        debugPrint("❌ 노트 로드 중 오류: $e");
      }
    }
  }

  /// 초기 페이지 로드
  Future<void> loadInitialPages() async {
    // 로그아웃 상태(샘플 모드)에서는 실행하지 않음
    if (!_isLoggedIn) return;
    
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
      
      // 3. LLM 타임아웃 상태 확인
      await checkLlmTimeoutStatus();
      
      // 4. 모든 페이지에 대한 실시간 리스너 설정
      _setupAllPageListeners();
      
      // 5. 현재 페이지 텍스트 로드
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
    if (flutter_foundation.kDebugMode) {
      debugPrint("🔔 [ViewModel] 페이지 리스너 설정 시도:");
      debugPrint("   _disposed: $_disposed");
      debugPrint("   _pages: ${_pages?.length ?? 'null'}");
      debugPrint("   _isLoggedIn: $_isLoggedIn");
    }
    
    if (_disposed || _pages == null || !_isLoggedIn) {
      if (flutter_foundation.kDebugMode) {
        debugPrint("⚠️ [ViewModel] 페이지 리스너 설정 건너뜀 (조건 불만족)");
      }
      return;
    }
    
    for (final page in _pages!) {
      if (page.id.isNotEmpty) {
        _setupPageListener(page.id);
        // 각 페이지의 초기 상태도 로드
        _loadPageInitialStatus(page.id);
      }
    }
    
    if (flutter_foundation.kDebugMode) {
      debugPrint("🔔 [ViewModel] 모든 페이지 리스너 설정 완료: ${_pages!.length}개");
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
    if (_disposed || currentPage == null || !_isLoggedIn) return;
    
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
      // 먼저 페이지 문서에서 에러 상태 확인
      final pageDoc = await FirebaseFirestore.instance
          .collection('pages')
          .doc(pageId)
          .get();
      
      if (pageDoc.exists) {
        final pageData = pageDoc.data() as Map<String, dynamic>;
        final status = pageData['status'] as String?;
        final errorMessage = pageData['errorMessage'] as String?;
        final errorType = pageData['errorType'] as String?;
        
        // 실패 상태이고 에러 메시지가 있는 경우
        if (status == ProcessingStatus.failed.toString() && errorMessage != null) {
          if (_disposed) return;
          
          _textLoadingStates[pageId] = false;
          _textErrors[pageId] = errorMessage;
          _pageStatuses[pageId] = ProcessingStatus.failed;
          if (!_disposed) notifyListeners();
          
          if (flutter_foundation.kDebugMode) {
            debugPrint("❌ 페이지 에러 상태 감지: $pageId");
            debugPrint("   에러 메시지: $errorMessage");
            debugPrint("   에러 타입: $errorType");
          }
          return;
        }
      }
      
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

  /// LLM 타임아웃 상태 업데이트
  void updateLlmTimeoutStatus(bool timeoutOccurred, bool retryAvailable) {
    if (_disposed) return;
    
    _llmTimeoutOccurred = timeoutOccurred;
    _llmRetryAvailable = retryAvailable;
    notifyListeners();
    
    if (flutter_foundation.kDebugMode) {
      debugPrint('🔄 [ViewModel] LLM 타임아웃 상태 업데이트: timeout=$timeoutOccurred, retry=$retryAvailable');
    }
  }

  /// LLM 처리 재시도
  Future<void> retryLlmProcessing() async {
    if (_disposed || _isRetryingLlm || !_llmRetryAvailable) return;
    
    try {
      _isRetryingLlm = true;
      _llmTimeoutOccurred = false;
      _llmRetryAvailable = false;
      notifyListeners();
      
      if (flutter_foundation.kDebugMode) {
        debugPrint('🔄 [ViewModel] LLM 재시도 시작: $_noteId');
      }
      
      // PostLLMWorkflow를 통해 재시도 실행
      await _postLLMWorkflow.retryLlmProcessing(_noteId);
      
      if (flutter_foundation.kDebugMode) {
        debugPrint('✅ [ViewModel] LLM 재시도 완료: $_noteId');
      }
      
    } catch (e) {
      if (flutter_foundation.kDebugMode) {
        debugPrint('❌ [ViewModel] LLM 재시도 실패: $_noteId, 오류: $e');
      }
      
      // 재시도 실패시 다시 재시도 가능 상태로 복원
      _llmTimeoutOccurred = true;
      _llmRetryAvailable = true;
      
    } finally {
      _isRetryingLlm = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  /// 노트의 LLM 타임아웃 및 실패 상태 확인 (Firestore에서)
  Future<void> checkLlmTimeoutStatus() async {
    if (_disposed) return;
    
    try {
      final noteDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(_noteId)
          .get();
      
      if (noteDoc.exists) {
        final data = noteDoc.data() as Map<String, dynamic>;
        
        // LLM 타임아웃 상태 확인
        final timeoutOccurred = data['llmTimeout'] as bool? ?? false;
        final retryAvailable = data['retryAvailable'] as bool? ?? false;
        updateLlmTimeoutStatus(timeoutOccurred, retryAvailable);
        
        // 최종 실패 상태 확인
        final showFailure = data['showFailureMessage'] as bool? ?? false;
        final userError = data['userFriendlyError'] as String?;
        updateFailureStatus(showFailure, userError);
      }
      
    } catch (e) {
      if (flutter_foundation.kDebugMode) {
        debugPrint('⚠️ [ViewModel] 노트 상태 확인 실패: $_noteId, 오류: $e');
      }
    }
  }

  /// 최종 실패 상태 업데이트
  void updateFailureStatus(bool showFailure, String? userError) {
    if (_disposed) return;
    
    _showFailureMessage = showFailure;
    _userFriendlyError = userError;
    notifyListeners();
    
    if (flutter_foundation.kDebugMode) {
      debugPrint('💀 [ViewModel] 실패 상태 업데이트: show=$showFailure, error=$userError');
    }
  }

  /// 실패 메시지 확인 완료 (사용자가 확인한 후 호출)
  Future<void> dismissFailureMessage() async {
    if (_disposed) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('notes')
          .doc(_noteId)
          .update({
        'showFailureMessage': false,
        'messageDismissedAt': FieldValue.serverTimestamp(),
      });
      
      _showFailureMessage = false;
      notifyListeners();
      
      if (flutter_foundation.kDebugMode) {
        debugPrint('✅ [ViewModel] 실패 메시지 확인 완료: $_noteId');
      }
      
    } catch (e) {
      if (flutter_foundation.kDebugMode) {
        debugPrint('⚠️ [ViewModel] 실패 메시지 확인 처리 실패: $_noteId, 오류: $e');
      }
    }
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
