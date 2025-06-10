import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/loading_dialog_experience.dart';
import '../../../core/models/note.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/utils/note_tutorial.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/timeout_manager.dart';
import '../view/note_detail_screen.dart';
import '../pre_llm_workflow.dart';
import '../post_llm_workflow.dart';
import '../services/note_service.dart';
import '../../home/home_viewmodel.dart';

/// 노트 생성 UI 매니저
/// UI 관련 로직만 담당: 로딩, 화면 이동, 에러 처리, 튜토리얼 등
class NoteCreationUIManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NoteService _noteService = NoteService();
  final PreLLMWorkflow _preLLMWorkflow = PreLLMWorkflow();
  final PostLLMWorkflow _postLLMWorkflow = PostLLMWorkflow();
  
  // 타임아웃 관리
  TimeoutManager? _navigationTimeoutManager;

  // 싱글톤 패턴
  static final NoteCreationUIManager _instance = NoteCreationUIManager._internal();
  factory NoteCreationUIManager() => _instance;
  NoteCreationUIManager._internal();

  /// 이미지 파일로 노트 생성 프로세스 실행 (UI 포함)
  Future<void> createNoteWithImages(
    BuildContext context,
    List<File> imageFiles, {
    bool closeBottomSheet = true,
    bool showLoadingDialog = true,
  }) async {
    if (imageFiles.isEmpty) {
      if (kDebugMode) {
        debugPrint('이미지가 없어 노트 생성 취소');
      }
      return;
    }

    // 컨텍스트 유효성 확인
    final BuildContext rootContext = context;
    if (!rootContext.mounted) {
      if (kDebugMode) {
        debugPrint('컨텍스트가 더 이상 유효하지 않습니다');
      }
      return;
    }

    bool loadingDialogShown = false;
    String? createdNoteId;
    bool isSuccess = false;

    try {
      // 1. 로딩 다이얼로그 표시 (향상된 타임아웃 처리)
      if (showLoadingDialog) {
        await _showLoadingDialogWithTimeout(rootContext);
        loadingDialogShown = true;
      }

      // 2. 바텀 시트 닫기
      if (closeBottomSheet) {
        await _closeBottomSheet(context);
      }

      // 3. 빠른 노트 생성 (비즈니스 로직)
      if (kDebugMode) {
        debugPrint('🚀 빠른 노트 생성 시작: ${imageFiles.length}개 이미지');
      }

      createdNoteId = await _preLLMWorkflow.createNoteQuickly(imageFiles);
      
      if (createdNoteId.isNotEmpty) {
        isSuccess = true;
        
        if (kDebugMode) {
          debugPrint('✅ 빠른 노트 생성 완료: $createdNoteId');
        }

        // 4. 첫 페이지 기본 정보 확인 (이미지만) - 타임아웃 처리 추가
        await _waitForFirstPageReadyWithTimeout(createdNoteId);
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 생성 실패: $e');
      }
      isSuccess = false;
      
      // 에러 처리
      if (loadingDialogShown && rootContext.mounted) {
        NoteCreationLoader.hideWithError(rootContext, e);
        loadingDialogShown = false;
      }
    }

    // 5. 결과 처리
    if (isSuccess) {
      await _handleCreationResult(
        context: rootContext,
        isSuccess: isSuccess,
        noteId: createdNoteId,
        totalImageCount: imageFiles.length,
        loadingDialogShown: loadingDialogShown,
      );
    }
  }

  /// 강화된 로딩 다이얼로그 표시 (타임아웃 처리)
  Future<void> _showLoadingDialogWithTimeout(BuildContext context) async {
    if (kDebugMode) {
      debugPrint('📱 향상된 로딩 다이얼로그 표시');
    }

    await NoteCreationLoader.show(
      context,
      message: '스마트 노트를 만들고 있어요.\n잠시만 기다려 주세요!',
      timeoutSeconds: 30,
      onTimeout: () {
        // 30초 타임아웃 시 에러 처리
        if (context.mounted) {
          if (kDebugMode) {
            debugPrint('⏰ 노트 생성 타임아웃 발생');
          }
          
          ErrorHandler.showErrorSnackBar(
            context, 
            '문제가 지속되고 있어요. 잠시 뒤에 다시 시도해 주세요.'
          );
        }
      },
    );
  }

  /// 바텀 시트 닫기
  Future<void> _closeBottomSheet(BuildContext context) async {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// 첫 페이지 준비 대기 (향상된 타임아웃 처리)
  Future<void> _waitForFirstPageReadyWithTimeout(String noteId) async {
    if (kDebugMode) {
      debugPrint('⏳ 첫 페이지 기본 정보 준비 대기: $noteId');
    }

    final completer = Completer<void>();
    StreamSubscription? subscription;
    Timer? timeoutTimer;

    // 10초 후 타임아웃
    timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        if (kDebugMode) {
          debugPrint('⚠️ 페이지 준비 대기 타임아웃 - 계속 진행');
        }
        subscription?.cancel();
        completer.complete();
      }
    });

    subscription = _firestore
        .collection('pages')
        .where('noteId', isEqualTo: noteId)
        .orderBy('pageNumber')
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) return;

      final pageDoc = snapshot.docs.first;
      final page = page_model.Page.fromFirestore(pageDoc);

      // 이미지가 준비되었는지 확인
      if (page.imageUrl != null && page.imageUrl!.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('✅ 첫 페이지 이미지 준비 완료: ${page.id}');
        }
        subscription?.cancel();
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }, onError: (error) {
      if (kDebugMode) {
        debugPrint('⚠️ 페이지 준비 확인 중 오류: $error');
      }
      subscription?.cancel();
      timeoutTimer?.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future;
  }

  /// 노트 생성 결과 처리
  Future<void> _handleCreationResult({
    required BuildContext context,
    required bool isSuccess,
    required String? noteId,
    required int totalImageCount,
    required bool loadingDialogShown,
  }) async {
    if (isSuccess && noteId != null && context.mounted) {
      // 성공 시 처리
      await _handleSuccess(
        context: context,
        noteId: noteId,
        totalImageCount: totalImageCount,
        loadingDialogShown: loadingDialogShown,
      );
    } else if (context.mounted) {
      // 실패 시 처리
      await _handleFailure(
        context: context,
        loadingDialogShown: loadingDialogShown,
      );
    }
  }

  /// 성공 시 처리 (향상된 네비게이션 타임아웃)
  Future<void> _handleSuccess({
    required BuildContext context,
    required String noteId,
    required int totalImageCount,
    required bool loadingDialogShown,
  }) async {
    if (kDebugMode) {
      debugPrint('🎉 노트 생성 성공: $noteId - 화면 이동 준비');
    }

    // 노트 정보 로드
    final Note? note = await _loadCompleteNote(noteId);
    final String userId = _auth.currentUser?.uid ?? '';

    // 임시 Note 객체 생성
    final tempNote = note ?? Note(
      id: noteId,
      userId: userId,
      title: '새 노트',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isFavorite: false,
      flashcardCount: 0,
    );

    // 로딩 다이얼로그 닫기
    if (loadingDialogShown && context.mounted) {
      NoteCreationLoader.hide(context);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // 노트 상세 화면으로 이동 (타임아웃 처리)
    if (context.mounted) {
      await _navigateToNoteDetailWithTimeout(context, tempNote, totalImageCount);
    }
  }

  /// 향상된 노트 상세 화면 이동 (타임아웃 처리)
  Future<void> _navigateToNoteDetailWithTimeout(
    BuildContext context,
    Note note,
    int totalImageCount,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('📱 노트 상세 화면으로 이동 시작 (타임아웃 30초)');
      }

      // 네비게이션 타임아웃 매니저 설정
      _navigationTimeoutManager?.dispose();
      _navigationTimeoutManager = TimeoutManager();
      
      bool navigationCompleted = false;
      
      _navigationTimeoutManager!.start(
        timeoutSeconds: 30,
        onProgress: (elapsedSeconds) {
          if (context.mounted && !navigationCompleted) {
            // 단계별 메시지 업데이트
            if (_navigationTimeoutManager!.shouldUpdateMessage()) {
              final message = _navigationTimeoutManager!.getCurrentMessage(
                '노트 페이지로 이동하고 있어요...'
              );
              NoteCreationLoader.updateMessage(message);
            }
          }
        },
        onTimeout: () {
          if (context.mounted && !navigationCompleted) {
            if (kDebugMode) {
              debugPrint('⏰ 노트 상세 화면 이동 타임아웃');
            }
            
            NoteCreationLoader.hide(context);
            ErrorHandler.showErrorSnackBar(
              context,
              '문제가 지속되고 있어요. 잠시 뒤에 다시 시도해 주세요.'
            );
          }
        },
      );

      // 안전 장치: 로딩 다이얼로그 완전히 닫기
      NoteCreationLoader.ensureHidden(context);

      // 튜토리얼 설정 - 첫 번째 노트 생성 시 튜토리얼 표시 준비
      NoteTutorial.markFirstNoteCreated();

      // 화면 이동 (결과를 받아서 홈 화면 새로고침)
      final result = await Navigator.of(context).push(
        NoteDetailScreenMVVM.route(
          note: note,
          isProcessingBackground: true,
          totalImageCount: totalImageCount,
        ),
      );
      
      navigationCompleted = true;
      _navigationTimeoutManager?.complete();
      
      // 노트 상세 화면에서 돌아왔을 때 홈 화면 새로고침
      if (context.mounted) {
        try {
          final homeViewModel = Provider.of<HomeViewModel>(context, listen: false);
          await homeViewModel.refreshNotes();
          await homeViewModel.refreshUsageLimits();
          
          if (kDebugMode) {
            debugPrint('✅ 노트 생성 후 홈 화면 새로고침 완료');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ 홈 화면 새로고침 실패 (무시됨): $e');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('✅ 노트 상세 화면 이동 완료');
      }
    } catch (e) {
      _navigationTimeoutManager?.dispose();
      
      if (kDebugMode) {
        debugPrint('❌ 노트 상세 화면 이동 실패: $e');
      }

      if (context.mounted) {
        ErrorHandler.showErrorSnackBar(context, e);
      }
    }
  }

  /// 실패 시 처리
  Future<void> _handleFailure({
    required BuildContext context,
    required bool loadingDialogShown,
  }) async {
    // 로딩 다이얼로그 닫기
    if (loadingDialogShown && context.mounted) {
      NoteCreationLoader.hide(context);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // 에러 메시지 표시
    if (context.mounted) {
      ErrorHandler.showErrorSnackBar(
        context,
        '노트 생성에 실패했습니다. 다시 시도해주세요.'
      );
    }

    if (kDebugMode) {
      debugPrint('💀 노트 생성 실패 처리 완료');
    }
  }

  /// 완전한 노트 정보 로드
  Future<Note?> _loadCompleteNote(String noteId) async {
    try {
      final docSnapshot = await _firestore
          .collection('notes')
          .doc(noteId)
          .get();

      if (!docSnapshot.exists) return null;

      return Note.fromFirestore(docSnapshot);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 노트 정보 로드 실패: $e');
      }
      return null;
    }
  }

  /// 화면 이동 재시도
  void _retryNavigation(BuildContext context, Note note, int totalImageCount) {
    if (!context.mounted) return;

    NoteCreationLoader.ensureHidden(context);
    Navigator.of(context).push(
      NoteDetailScreenMVVM.route(
        note: note,
        isProcessingBackground: true,
        totalImageCount: totalImageCount,
      ),
    );
  }

  /// 앱 시작시 미완료 작업 복구
  Future<void> initializeOnAppStart() async {
    try {
      // 후처리 워크플로우 미완료 작업 복구 - 비활성화됨
      // 이유: 새 노트 생성을 블로킹하는 문제 방지
      // 미완료 작업 복구는 노트 상세페이지 진입시에만 수행됨
      // await _postLLMWorkflow.recoverPendingJobs();
      
      if (kDebugMode) {
        debugPrint('✅ 앱 시작시 초기화 완료 (자동 복구 비활성화)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 앱 시작시 초기화 실패: $e');
      }
    }
  }

  /// 리소스 정리
  void dispose() {
    _navigationTimeoutManager?.dispose();
    _navigationTimeoutManager = null;
  }
} 