import 'dart:io';
import 'package:flutter/material.dart';
import '../content/note_service.dart';
import '../media/image_service.dart';
import '../content/page_service.dart';
import '../storage/unified_cache_service.dart';
import '../../../core/widgets/loading_dialog_experience.dart';
import '../../../core/models/note.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../features/note_detail/note_detail_screen_mvvm.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

/// 노트 생성 워크플로우 클래스
/// 이미지 선택부터 노트 생성, 화면 이동까지의 전체 프로세스를 관리합니다.
class NoteCreationWorkflow {
  final NoteService _noteService = NoteService();
  final ImageService _imageService = ImageService();
  final PageService _pageService = PageService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // 싱글톤 패턴
  static final NoteCreationWorkflow _instance = NoteCreationWorkflow._internal();
  factory NoteCreationWorkflow() => _instance;
  NoteCreationWorkflow._internal();
  
  /// 이미지 파일로 노트 생성 프로세스 실행
  Future<void> createNoteWithImages(
    BuildContext context,
    List<File> imageFiles,
    {bool closeBottomSheet = true}
  ) async {
    if (imageFiles.isEmpty) {
      debugPrint('이미지가 없어 노트 생성 취소');
      return;
    }
    
    // 바텀 시트가 있으면 먼저 닫기
    if (closeBottomSheet && Navigator.canPop(context)) {
      Navigator.pop(context);
      // 약간의 지연 추가
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    // 로딩 화면 표시 (글로벌 context 사용)
    final BuildContext rootContext = Navigator.of(context, rootNavigator: true).context;
    if (!rootContext.mounted) {
      debugPrint('컨텍스트가 더 이상 유효하지 않습니다');
      return;
    }
    
    debugPrint('로딩 다이얼로그 표시 시작');
    await NoteCreationLoader.show(
      rootContext, 
      message: '스마트 노트를 만들고 있어요\n잠시만 기다려 주세요!'
    );
    
    String? createdNoteId;
    bool isSuccess = false;
    int totalImageCount = imageFiles.length;
    
    try {
      debugPrint('노트 생성 시작: ${imageFiles.length}개 이미지');
      
      // 노트 생성 (백그라운드 처리 위임)
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: imageFiles,
        waitForFirstPageProcessing: true, // 첫 페이지 처리 기다리기 (변경됨)
      );
      
      debugPrint('노트 생성 완료: $result');
      
      // 성공 여부 체크
      isSuccess = result['success'] == true;
      createdNoteId = result['noteId'] as String?;
      
      // 첫 페이지 처리 확인
      if (isSuccess && createdNoteId != null) {
        await _ensureFirstPageProcessed(createdNoteId);
      }
      
    } catch (e) {
      debugPrint('노트 생성 중 예외 발생: $e');
      // 에러 처리는 아래 finally 블록에서 수행
      isSuccess = false;
    } finally {
      // 로딩 화면 숨기기 (먼저 실행)
      if (rootContext.mounted) {
        debugPrint('로딩 다이얼로그 숨김');
        NoteCreationLoader.hide(rootContext);
        
        // 약간의 딜레이 추가 (화면 전환 안정성 개선)
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      // 노트 생성 결과에 따른 처리
      if (isSuccess && createdNoteId != null && rootContext.mounted) {
        debugPrint('노트 생성 성공: $createdNoteId - 상세 화면으로 이동');
        
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
        
        _navigateToNoteDetail(rootContext, tempNote, totalImageCount);
      } else if (rootContext.mounted) {
        // 실패 시 메시지 표시
        ScaffoldMessenger.of(rootContext).showSnackBar(
          const SnackBar(content: Text('노트 생성에 실패했습니다. 다시 시도해주세요.')),
        );
        debugPrint('노트 생성 실패 또는 ID가 없음');
      }
    }
  }
  
  /// 첫 번째 페이지의 처리 완료를 확인
  Future<void> _ensureFirstPageProcessed(String noteId) async {
    debugPrint('첫 번째 페이지 처리 상태 확인 시작: noteId=$noteId');
    
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
            debugPrint('첫 번째 페이지 처리 완료 확인됨: ${page.id}');
            
            // 캐시 업데이트
            await _cacheService.cachePage(noteId, page);
            return;
          }
        }
        
        // 0.5초 대기 후 다시 시도
        await Future.delayed(const Duration(milliseconds: 500));
        attempts++;
        debugPrint('첫 번째 페이지 처리 대기 중... ($attempts/$maxAttempts)');
      } catch (e) {
        debugPrint('페이지 처리 상태 확인 중 오류: $e');
        break;
      }
    }
    
    debugPrint('첫 번째 페이지 처리 완료 확인 시간 초과');
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
      debugPrint('완전한 노트 정보 로드 중 오류: $e');
      return null;
    }
  }
  
  /// 노트 상세 화면으로 안전하게 이동
  void _navigateToNoteDetail(BuildContext context, Note note, int totalImageCount) {
    if (!context.mounted) return;
    
    try {
      debugPrint('노트 상세 화면으로 이동 시작');
      
      Navigator.of(context).push(
        NoteDetailScreenMVVM.route(
          note: note,
          isProcessingBackground: true,
          totalImageCount: totalImageCount,
        ),
      );
      
      debugPrint('노트 상세 화면으로 이동 완료');
    } catch (e) {
      debugPrint('노트 상세 화면 이동 중 오류: $e');
      
      // 오류 발생 시 스낵바 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('화면 이동에 실패했습니다.'),
            action: SnackBarAction(
              label: '다시 시도',
              onPressed: () {
                if (context.mounted) {
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
} 