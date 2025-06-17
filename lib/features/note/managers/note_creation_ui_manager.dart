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
      
      // 에러 발생 시 반드시 로딩 다이얼로그 닫기
      if (rootContext.mounted) {
        if (kDebugMode) {
          debugPrint('📱 에러 처리: 로딩 다이얼로그 강제 닫기 시작');
        }
        
        NoteCreationLoader.ensureHidden(rootContext);
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (kDebugMode) {
          debugPrint('📱 에러 처리: 로딩 다이얼로그 강제 닫기 완료');
        }
      }
      
      // 중국어 감지 실패의 경우 특별 처리
      if (e.toString().contains('중국어가 없습니다')) {
        if (rootContext.mounted) {
          // 중국어 감지 실패 전용 에러 메시지
          ErrorHandler.showErrorSnackBar(
            rootContext,
            '공유해주신 이미지에 중국어가 없습니다.\n다른 이미지를 업로드해 주세요.',
          );
        }
        return; // 중국어 감지 실패 시 바로 종료
      }
      
      // 기타 에러 처리
      if (rootContext.mounted) {
        ErrorHandler.showErrorSnackBar(rootContext, e);
      }
    }

    // 5. 결과 처리 (성공한 경우만 → 성공/실패 모두 처리)
    await _handleCreationResult(
      context: rootContext,
      isSuccess: isSuccess,
      noteId: createdNoteId,
      loadingDialogShown: loadingDialogShown,
    );
  }

  /// 강화된 로딩 다이얼로그 표시 (타임아웃 처리)
  Future<void> _showLoadingDialogWithTimeout(BuildContext context) async {
    if (kDebugMode) {
      debugPrint('📱 향상된 로딩 다이얼로그 표시');
    }

    await NoteCreationLoader.show(
      context,
      message: '스마트 노트를 만들고 있어요.\n잠시만 기다려 주세요!',
      timeoutSeconds: 45,
      onTimeout: () {
        // 타임아웃 시 강제 처리
        if (context.mounted) {
          if (kDebugMode) {
            debugPrint('⏰ 노트 생성 타임아웃 발생 - 강제 다이얼로그 닫기');
          }
          
          // 강제로 다이얼로그 닫기
          Future.delayed(const Duration(milliseconds: 100), () {
            if (context.mounted) {
              NoteCreationLoader.ensureHidden(context);
              
              // 에러 메시지 표시
              Future.delayed(const Duration(milliseconds: 500), () {
                if (context.mounted) {
                  ErrorHandler.showErrorSnackBar(
                    context, 
                    '처리 시간이 너무 오래 걸리고 있어요. 잠시 뒤에 다시 시도해 주세요.'
                  );
                }
              });
            }
          });
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
    String? noteId,
    required bool loadingDialogShown,
  }) async {
    if (kDebugMode) {
      debugPrint('📱 노트 생성 결과 처리 시작: isSuccess=$isSuccess, noteId=$noteId');
    }

    // 로딩 다이얼로그가 표시된 경우 닫기
    if (loadingDialogShown && context.mounted) {
      if (kDebugMode) {
        debugPrint('📱 결과 처리: 로딩 다이얼로그 닫기 시작');
      }
      
      NoteCreationLoader.ensureHidden(context);
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (kDebugMode) {
        debugPrint('📱 결과 처리: 로딩 다이얼로그 닫기 완료');
      }
    }

    // 성공한 경우에만 노트 상세 화면으로 이동
    if (isSuccess && noteId != null && context.mounted) {
      if (kDebugMode) {
        debugPrint('📱 노트 생성 성공 - 상세 화면으로 이동: $noteId');
      }
      
      await Navigator.pushNamed(
        context,
        '/note_detail',
        arguments: {'noteId': noteId},
      );
    } else if (!isSuccess) {
      // 실패한 경우 로그만 출력 (에러는 이미 catch 블록에서 처리됨)
      if (kDebugMode) {
        debugPrint('❌ 노트 생성 실패 - 상세 화면 이동하지 않음');
      }
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