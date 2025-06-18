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

/// 노트 생성 UI 매니저
/// UI 관련 로직만 담당: 로딩, 화면 이동, 에러 처리, 튜토리얼 등
class NoteCreationUIManager {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PreLLMWorkflow _preLLMWorkflow = PreLLMWorkflow();
  
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
      // 1. 로딩 다이얼로그 표시 (즉시 표시)
      if (showLoadingDialog) {
        NoteCreationLoader.show(
          rootContext,
          message: '스마트 노트를 만들고 있어요.\n잠시만 기다려 주세요!',
          timeoutSeconds: 45,
          onTimeout: () {
            if (rootContext.mounted) {
              if (kDebugMode) {
                debugPrint('⏰ 노트 생성 타임아웃 발생');
              }
              ErrorHandler.showErrorSnackBar(
                rootContext, 
                '문제가 지속되고 있어요. 잠시 뒤에 다시 시도해 주세요.'
              );
            }
          },
        );
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

        // 첫 페이지 대기 없이 즉시 결과 처리로 이동
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 생성 실패: $e');
      }
      isSuccess = false;
      
      // 중국어 감지 실패의 경우 특별 처리
      if (e.toString().contains('중국어가 없습니다')) {
        // 로딩 다이얼로그가 표시되지 않은 경우에도 처리
        if (rootContext.mounted) {
          // 로딩 다이얼로그가 표시된 경우 닫기
          if (loadingDialogShown || NoteCreationLoader.isVisible) {
            NoteCreationLoader.hide(rootContext);
            await Future.delayed(const Duration(milliseconds: 300));
          }
          
          // 중국어 감지 실패 전용 에러 메시지
          ErrorHandler.showErrorSnackBar(
            rootContext,
            '공유해주신 이미지에 중국어가 없습니다.\n다른 이미지를 업로드해 주세요.',
          );
        }
        return; // 중국어 감지 실패 시 바로 종료
      }
      
      // 기타 에러 처리
      if (loadingDialogShown && rootContext.mounted) {
        NoteCreationLoader.hideWithError(rootContext, e);
        loadingDialogShown = false;
      }
    }

    // 5. 결과 처리 (성공한 경우만)
    if (isSuccess) {
      await _handleCreationResult(
        context: rootContext,
        isSuccess: isSuccess,
        noteId: createdNoteId,
        loadingDialogShown: loadingDialogShown,
      );
    }
  }

  /// 바텀 시트 닫기
  Future<void> _closeBottomSheet(BuildContext context) async {
    if (Navigator.canPop(context)) {
      Navigator.of(context).pop();
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// 노트 생성 결과 처리
  Future<void> _handleCreationResult({
    required BuildContext context,
    required bool isSuccess,
    required String? noteId,
    required bool loadingDialogShown,
  }) async {
    if (isSuccess && noteId != null && context.mounted) {
      // 성공 시 처리
      await _handleSuccess(
        context: context,
        noteId: noteId,
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

  /// 성공 시 처리 (타임아웃 처리)
  Future<void> _handleSuccess({
    required BuildContext context,
    required String noteId,
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
      await _navigateToNoteDetailWithTimeout(context, tempNote);
    }
  }

  /// 향상된 노트 상세 화면 이동 (타임아웃 처리)
  Future<void> _navigateToNoteDetailWithTimeout(
    BuildContext context,
    Note note,
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
        identifier: 'Navigation',
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

      // 화면 이동
      Navigator.of(context).push(
        NoteDetailScreenMVVM.route(
          note: note,
          isProcessingBackground: true,
        ),
             ).then((result) async {
         // 화면에서 돌아왔을 때의 처리
         if (kDebugMode) {
           debugPrint('✅ 노트 상세 화면에서 돌아옴');
         }
         // 홈 화면은 자동으로 새로고침되므로 별도 처리 불필요
       });
      
      // 화면 이동이 시작되면 즉시 네비게이션 완료 처리
      navigationCompleted = true;
      _navigationTimeoutManager?.complete();
      
      if (kDebugMode) {
        debugPrint('✅ 노트 상세 화면 네비게이션 시작 완료');
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