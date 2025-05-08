import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../content/note_service.dart';
import '../media/image_service.dart';
import '../content/page_service.dart';
import '../storage/unified_cache_service.dart';
import '../../../core/widgets/loading_dialog_experience.dart';
import '../../../core/models/note.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../features/note_detail/note_detail_screen_mvvm.dart';
import '../../../core/utils/note_tutorial.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

/// 노트 생성 워크플로우 클래스
/// 이미지 선택부터 노트 생성, 화면 이동까지의 전체 프로세스를 관리합니다.
class NoteCreationWorkflow {
  final NoteService _noteService = NoteService();
  final ImageService _imageService = ImageService();
  final PageService _pageService = PageService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 싱글톤 패턴
  static final NoteCreationWorkflow _instance = NoteCreationWorkflow._internal();
  factory NoteCreationWorkflow() => _instance;
  NoteCreationWorkflow._internal();
  
  /// 이미지 파일로 노트 생성 프로세스 실행
  Future<void> createNoteWithImages(
    BuildContext context,
    List<File> imageFiles, {
    bool closeBottomSheet = true,
    bool showLoadingDialog = true  // 로딩 다이얼로그 표시 여부 (기본값: true)
  }) async {
    if (imageFiles.isEmpty) {
      if (kDebugMode) {
      debugPrint('이미지가 없어 노트 생성 취소');
      }
      return;
    }
    
    // 컨텍스트 확인 (rootContext가 필요한 경우에만 가져옴)
    final BuildContext rootContext = context;
    if (!rootContext.mounted) {
      if (kDebugMode) {
      debugPrint('컨텍스트가 더 이상 유효하지 않습니다');
      }
      return;
    }
    
    // 로딩 다이얼로그 표시 (옵션에 따라)
    bool loadingDialogShown = false;
    
    if (showLoadingDialog) {
      if (kDebugMode) {
    debugPrint('로딩 다이얼로그 표시 시작');
      }
    await NoteCreationLoader.show(
      rootContext, 
        message: '스마트 노트를 만들고 있어요.\n잠시만 기다려 주세요!'
    );
      loadingDialogShown = true;
    } else {
      if (kDebugMode) {
        debugPrint('로딩 다이얼로그 표시 건너뜀 (이미 표시됨)');
      }
    }
    
    // 바텀 시트가 있으면 닫기 (로딩 화면 표시 후)
    if (closeBottomSheet && Navigator.canPop(context)) {
      try {
        // 더 안정적인 바텀 시트 닫기
        Navigator.of(context).pop();
        
        // 안정성을 위해 약간의 딜레이 추가
        await Future.delayed(const Duration(milliseconds: 50));
        
        if (kDebugMode) {
          debugPrint('바텀 시트 닫기 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('바텀 시트 닫기 중 오류: $e');
        }
      }
    }
    
    String? createdNoteId;
    bool isSuccess = false;
    int totalImageCount = imageFiles.length;
    
    try {
      if (kDebugMode) {
      debugPrint('노트 생성 시작: ${imageFiles.length}개 이미지');
      }
      
      // 이미지 파일 유효성 검증
      final List<File> validImageFiles = [];
      for (final file in imageFiles) {
        if (await file.exists() && await file.length() > 0) {
          validImageFiles.add(file);
        } else {
          if (kDebugMode) {
            debugPrint('유효하지 않은 이미지 파일 무시: ${file.path}');
          }
        }
      }
      
      if (validImageFiles.isEmpty) {
        throw Exception('유효한 이미지가 없습니다');
      }
      
      // 노트 생성 (백그라운드 처리 위임)
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: validImageFiles,
        waitForFirstPageProcessing: true, // 첫 페이지 처리 기다리기 (변경됨)
      );
      
      if (kDebugMode) {
      debugPrint('노트 생성 완료: $result');
      }
      
      // 성공 여부 체크
      isSuccess = result['success'] == true;
      createdNoteId = result['noteId'] as String?;
      
      // 첫 페이지 처리 확인
      if (isSuccess && createdNoteId != null) {
        await _ensureFirstPageProcessed(createdNoteId);
      }
      
    } catch (e) {
      if (kDebugMode) {
      debugPrint('노트 생성 중 예외 발생: $e');
      }
      // 에러 처리는 아래 finally 블록에서 수행
      isSuccess = false;
    } finally {
      // 노트 생성 결과에 따른 처리
      if (isSuccess && createdNoteId != null && rootContext.mounted) {
        if (kDebugMode) {
        debugPrint('노트 생성 성공: $createdNoteId - 상세 화면으로 이동');
        }
        
        // 노트 정보 로드
        final Note? completedNote = await _loadCompleteNote(createdNoteId);
        
        // 임시 Note 객체 생성
        final tempNote = completedNote ?? Note(
          id: createdNoteId,
          originalText: '새 노트',
          translatedText: '',
          extractedText: '',
          imageCount: totalImageCount,
        );
        
        // 로딩 화면 숨기기 (표시된 경우에만)
        if (loadingDialogShown && rootContext.mounted) {
          if (kDebugMode) {
            debugPrint('로딩 다이얼로그 숨김 - 노트 상세 화면 이동 전');
          }
          NoteCreationLoader.hide(rootContext);
          
          // 안정적인 화면 전환을 위한 약간의 딜레이
          await Future.delayed(const Duration(milliseconds: 300));
        }
        
        // 노트 상세 화면으로 이동
        if (rootContext.mounted) {
        _navigateToNoteDetail(rootContext, tempNote, totalImageCount);
        }
      } else if (rootContext.mounted) {
        // 로딩 화면 숨기기 (표시된 경우에만) - 실패 시
        if (loadingDialogShown && rootContext.mounted) {
          if (kDebugMode) {
            debugPrint('로딩 다이얼로그 숨김 - 실패 처리');
          }
          NoteCreationLoader.hide(rootContext);
          
          // 약간의 딜레이 추가 (안정성 개선)
          await Future.delayed(const Duration(milliseconds: 300));
        }
        
        // 실패 시 메시지 표시
        if (rootContext.mounted) {
        ScaffoldMessenger.of(rootContext).showSnackBar(
          const SnackBar(content: Text('노트 생성에 실패했습니다. 다시 시도해주세요.')),
        );
          if (kDebugMode) {
        debugPrint('노트 생성 실패 또는 ID가 없음');
          }
        }
      }
    }
  }
  
  /// 첫 번째 페이지의 처리 완료를 확인
  Future<void> _ensureFirstPageProcessed(String noteId) async {
    if (kDebugMode) {
    debugPrint('첫 번째 페이지 처리 상태 확인 시작: noteId=$noteId');
    }
    
    // 최대 10초 동안 첫 페이지 처리 상태 확인 (500ms 간격)
    final maxAttempts = 20; 
    int attempts = 0;
    
    while (attempts < maxAttempts) {
      try {
        // Firestore에서 페이지 문서 확인
        final snapshot = await _firestore
            .collection('pages')
            .where('noteId', isEqualTo: noteId)
            .orderBy('pageNumber')
            .limit(1)
            .get();
        
        if (snapshot.docs.isNotEmpty) {
          final pageDoc = snapshot.docs.first;
          final page = page_model.Page.fromFirestore(pageDoc);
          
          // 페이지 처리 상태 확인
          if (page.originalText != '___PROCESSING___' && 
              page.originalText.isNotEmpty) {
            if (kDebugMode) {
            debugPrint('첫 번째 페이지 처리 완료 확인됨: ${page.id}');
            }
            
            // 캐시 업데이트
            await _cacheService.cachePage(noteId, page);
            return;
          }
        }
        
        // 0.5초 대기 후 다시 시도
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
        if (kDebugMode) {
        debugPrint('첫 번째 페이지 처리 대기 중... ($attempts/$maxAttempts)');
        }
      } catch (e) {
        if (kDebugMode) {
        debugPrint('페이지 처리 상태 확인 중 오류: $e');
        }
        break;
      }
    }
    
    if (kDebugMode) {
    debugPrint('첫 번째 페이지 처리 완료 확인 시간 초과');
    }
  }
  
  /// 완전한 노트 정보 로드
  Future<Note?> _loadCompleteNote(String noteId) async {
    try {
      // Firestore에서 노트 문서 로드
      final docSnapshot = await _firestore
          .collection('notes')
          .doc(noteId)
          .get();
      
      if (!docSnapshot.exists) {
        return null;
      }
      
      // 노트 객체 생성
      final Note note = Note.fromFirestore(docSnapshot);
      
      // 노트의 페이지 목록 로드
      final pagesSnapshot = await _firestore
          .collection('pages')
          .where('noteId', isEqualTo: noteId)
          .orderBy('pageNumber')
          .get();
      
      if (pagesSnapshot.docs.isNotEmpty) {
        // Note 클래스의 pages가 final이므로 새 Note 객체 생성
        final pages = pagesSnapshot.docs
            .map((doc) => page_model.Page.fromFirestore(doc))
            .toList();
        
        return note.copyWith(pages: pages);
      }
      
      return note;
    } catch (e) {
      if (kDebugMode) {
      debugPrint('완전한 노트 정보 로드 중 오류: $e');
      }
      return null;
    }
  }
  
  /// 노트 상세 화면으로 안전하게 이동
  void _navigateToNoteDetail(BuildContext context, Note note, int totalImageCount) {
    if (!context.mounted) return;
    
    try {
      if (kDebugMode) {
      debugPrint('노트 상세 화면으로 이동 시작');
      }
      
      // 로딩 다이얼로그가 완전히 닫혔는지 한번 더 확인 (안전 장치)
      NoteCreationLoader.ensureHidden(context);
      
      // 노트 개수를 강제로 1로 설정 (첫 번째 노트 생성 시 확실하게 튜토리얼 표시)
      // 이후에 _forceUpdateNoteCount 메서드에서 실제 개수로 업데이트됨
      NoteTutorial.updateNoteCount(1);
      
      if (kDebugMode) {
        debugPrint('노트 상세 화면 이동 전: 노트 개수를 1로 강제 설정 (튜토리얼용)');
      }
      
      // 노트 상세 화면으로 이동
      Navigator.of(context).push(
        NoteDetailScreenMVVM.route(
          note: note,
          isProcessingBackground: true,
          totalImageCount: totalImageCount,
        ),
      );
      
      // 이동 후에 백그라운드로 실제 노트 개수 조회 및 업데이트
      Future.microtask(() async {
        await _forceUpdateNoteCount(context);
      });
      
      if (kDebugMode) {
      debugPrint('노트 상세 화면으로 이동 완료');
      }
    } catch (e) {
      if (kDebugMode) {
      debugPrint('노트 상세 화면 이동 중 오류: $e');
      }
      
      // 오류 발생 시 스낵바 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('화면 이동에 실패했습니다.'),
            action: SnackBarAction(
              label: '다시 시도',
              onPressed: () {
                if (context.mounted) {
                  // 로딩 다이얼로그 닫기 확인
                  NoteCreationLoader.ensureHidden(context);
                  
                  // 다시 한번 시도
                  Navigator.of(context).push(
                    NoteDetailScreenMVVM.route(
                      note: note,
                      isProcessingBackground: true,
                      totalImageCount: totalImageCount,
                    ),
                  );
                }
              },
            ),
          ),
        );
      }
    }
  }
  
  /// 노트 개수 업데이트 (튜토리얼 표시 여부 결정)
  Future<void> _forceUpdateNoteCount(BuildContext context) async {
    try {
      // Firestore에서 현재 노트 개수 가져오기
      final notesCollection = _firestore.collection('notes');
      final User? currentUser = _auth.currentUser;
      
      if (currentUser == null) {
      if (kDebugMode) {
          debugPrint('사용자가 로그인되지 않음, 노트 개수 업데이트 건너뜀');
        }
        return;
      }
      
      final querySnapshot = await notesCollection
          .where('userId', isEqualTo: currentUser.uid)
          .count()
          .get();
      
      final noteCount = querySnapshot.count ?? 0;
      
      // NoteTutorial에 실제 노트 개수 업데이트
      await NoteTutorial.updateNoteCount(noteCount);
      
      if (kDebugMode) {
        debugPrint('노트 튜토리얼: 실제 노트 개수 업데이트 = $noteCount');
      }
      
      // 디버그 모드에서 테스트를 위한 튜토리얼 상태 리셋
      if (kDebugMode && false) { // false로 설정하여 기본적으로 비활성화
        debugPrint('⚠️ 튜토리얼 상태 리셋 (테스트용)');
        await NoteTutorial.resetTutorialState();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('노트 개수 업데이트 중 오류: $e');
      }
    }
  }
} 