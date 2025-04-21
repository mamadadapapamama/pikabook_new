import 'dart:io';
import 'package:flutter/material.dart';
import '../models/page.dart' as page_model;
import '../models/note.dart';
import '../services/content/page_service.dart';
import '../services/media/image_service.dart';
import '../services/storage/unified_cache_service.dart';
import '../services/text_processing/text_processing_service.dart';
import '../services/content/note_service.dart';
import '../services/content/flashcard_service.dart' hide debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';

/// 페이지 관리 클래스
/// 페이지 로드, 병합, 이미지 로드 등의 기능 제공
class PageManager {
  final String noteId;
  final Note? initialNote;
  final PageService _pageService = PageService();
  final NoteService _noteService = NoteService();
  final FlashCardService _flashCardService = FlashCardService();
  final ImageService _imageService = ImageService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<page_model.Page> _pages = [];
  List<File?> _imageFiles = [];
  // 페이지 ID별 이미지 파일 맵
  Map<String, File> _imageFileMap = {};
  int _currentPageIndex = 0;
  
  PageManager({
    required this.noteId,
    this.initialNote,
  });
  
  // 상태 접근자
  List<page_model.Page> get pages => _pages;
  List<File?> get imageFiles => _imageFiles;
  int get currentPageIndex => _currentPageIndex;
  page_model.Page? get currentPage => 
    _currentPageIndex >= 0 && _currentPageIndex < _pages.length 
    ? _pages[_currentPageIndex] 
    : null;
  File? get currentImageFile => 
    _currentPageIndex >= 0 && _currentPageIndex < _imageFiles.length 
    ? _imageFiles[_currentPageIndex] 
    : null;
    
  // 페이지 인덱스 변경
  void changePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _currentPageIndex = index;
    
    // 이미지 로드
    _loadPageImage(_currentPageIndex);
  }
  
  // 페이지 설정
  void setPages(List<page_model.Page> pages) {
    final oldPages = List<page_model.Page>.from(_pages);
    _pages = pages;
    
    // 이미지 파일 배열 업데이트
    final oldImageFiles = List<File?>.from(_imageFiles);
    _imageFiles = _updateImageFilesForPages(_pages, oldPages, oldImageFiles);
    
    // 현재 페이지 인덱스 확인
    _currentPageIndex = _currentPageIndex >= 0 && _currentPageIndex < _pages.length
        ? _currentPageIndex
        : (_pages.isNotEmpty ? 0 : -1);
  }
  
  // 페이지 병합
  void mergePages(List<page_model.Page> serverPages) {
    final oldPages = List<page_model.Page>.from(_pages);
    _pages = _mergePagesById(oldPages, serverPages);
    
    // 이미지 파일 배열 업데이트
    final oldImageFiles = List<File?>.from(_imageFiles);
    _imageFiles = _updateImageFilesForPages(_pages, oldPages, oldImageFiles);
    
    // 현재 페이지 인덱스 확인
    _currentPageIndex = _currentPageIndex >= 0 && _currentPageIndex < _pages.length
        ? _currentPageIndex
        : (_pages.isNotEmpty ? 0 : -1);
  }
  
  // 페이지 병합 로직
  List<page_model.Page> _mergePagesById(
      List<page_model.Page> localPages, List<page_model.Page> serverPages) {
    // 페이지 ID를 기준으로 병합
    final Map<String, page_model.Page> pageMap = {};

    // 기존 페이지를 맵에 추가
    for (final page in localPages) {
      if (page.id != null) {
        pageMap[page.id!] = page;
      }
    }

    // 새 페이지로 맵 업데이트 (기존 페이지 덮어쓰기)
    for (final page in serverPages) {
      if (page.id != null) {
        pageMap[page.id!] = page;
      }
    }

    // 맵에서 페이지 목록 생성
    final mergedPages = pageMap.values.toList();

    // 페이지 번호 순으로 정렬
    mergedPages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

    debugPrint(
        '페이지 병합 결과: 로컬=${localPages.length}개, 서버=${serverPages.length}개, 병합 후=${mergedPages.length}개');

    return mergedPages;
  }

  // 이미지 파일 배열 업데이트 로직
  List<File?> _updateImageFilesForPages(List<page_model.Page> newPages,
      List<page_model.Page> oldPages, List<File?> oldImageFiles) {
    if (oldPages.isEmpty) {
      return List<File?>.filled(newPages.length, null);
    }
    
    final newImageFiles = List<File?>.filled(newPages.length, null);

    // 페이지 ID를 기준으로 이미지 파일 매핑
    for (int i = 0; i < newPages.length; i++) {
      final pageId = newPages[i].id;
      if (pageId != null) {
        // 기존 페이지 목록에서 같은 ID를 가진 페이지의 인덱스 찾기
        for (int j = 0; j < oldPages.length; j++) {
          if (j < oldPages.length &&
              oldPages[j].id == pageId &&
              j < oldImageFiles.length) {
            newImageFiles[i] = oldImageFiles[j];
            break;
          }
        }
      }
    }

    return newImageFiles;
  }
  
  // 서버에서 페이지 로드 - 캐시 확인과 서버 요청을 명확히 분리
  Future<List<page_model.Page>> loadPagesFromServer({bool forceReload = false}) async {
    if (noteId.isEmpty) {
      debugPrint('❌ PageManager.loadPagesFromServer: 노트 ID가 비어있음');
      return _pages;
    }
    
    try {
      // 로딩 시작 로그
      debugPrint('🔄 PageManager.loadPagesFromServer 시작: noteId=$noteId, forceReload=$forceReload');
      final startTime = DateTime.now();
      
      List<page_model.Page> loadedPages = [];
      
      // 1. 강제 리로드가 아니고 이미 페이지가 로드된 경우 현재 페이지 반환
      if (!forceReload && _pages.isNotEmpty) {
        debugPrint('✅ 이미 메모리에 ${_pages.length}개 페이지가 로드되어 있어 재사용합니다.');
        return _pages;
      }
      
      // 2. 강제 리로드인 경우 서버에서만 로드
      if (forceReload) {
        debugPrint('🔄 강제 로드 모드: 서버에서 직접 페이지를 로드합니다.');
        loadedPages = await _directlyLoadFromServer();
        
        // 로드된 페이지로 현재 페이지 목록 업데이트
        setPages(loadedPages);
        
        // 백그라운드에서 캐시 업데이트
        _updateCacheInBackground(loadedPages);
        
        return _pages;
      }
      
      // 3. 일반 모드: 초기 노트가 전달되었으면 초기 노트의 페이지 정보 확인
      if (initialNote != null) {
        debugPrint('🔄 초기 노트가 전달됨, 페이지 수: ${initialNote!.pages.length}');
        
        // 초기 노트에 페이지가 있으면 그대로 사용
        if (initialNote!.pages.isNotEmpty) {
          debugPrint('✅ 초기 노트의 페이지를 사용합니다: ${initialNote!.pages.length}개');
          setPages(initialNote!.pages);
          
          // 백그라운드에서 서버와 동기화
          _syncWithServerInBackground();
          
          return _pages;
        }
        
        // 초기 노트에 페이지가 없으면 서버에서 로드
        debugPrint('⚠️ 초기 노트에 페이지가 없어 서버에서 로드합니다.');
        loadedPages = await _directlyLoadFromServer();
        
        // 로드된 페이지로 현재 페이지 목록 업데이트
        setPages(loadedPages);
        
        // 백그라운드에서 캐시 업데이트
        _updateCacheInBackground(loadedPages);
        
        return _pages;
      }
      
      // 4. 캐시 확인
      try {
        // 캐시에서 페이지 확인 (타임아웃 적용)
        loadedPages = await Future.any([
          _cacheService.getPagesForNote(noteId),
          Future.delayed(const Duration(seconds: 1), () => <page_model.Page>[])
        ]);
      } catch (e) {
        debugPrint('⚠️ 캐시 확인 중 오류: $e');
        loadedPages = [];
      }
      
      // 캐시에서 페이지를 찾은 경우
      if (loadedPages.isNotEmpty) {
        debugPrint('✅ 캐시에서 ${loadedPages.length}개 페이지를 로드했습니다.');
        
        // 페이지 설정
        setPages(loadedPages);
        
        // 백그라운드에서 서버와 동기화
        _syncWithServerInBackground();
        
        return _pages;
      }
      
      // 5. 캐시에 없는 경우 서버에서 로드
      debugPrint('⚠️ 캐시에 페이지가 없어 서버에서 직접 로드합니다.');
      loadedPages = await _directlyLoadFromServer();
      
      // 로드된 페이지로 현재 페이지 목록 업데이트
      setPages(loadedPages);
      
      // 백그라운드에서 캐시 업데이트
      _updateCacheInBackground(loadedPages);
      
      // 실행 시간 로깅
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      debugPrint('⏱️ 페이지 로드 총 소요 시간: ${duration.inMilliseconds}ms');
      
      return _pages;
    } catch (e, stackTrace) {
      debugPrint('❌ PageManager.loadPagesFromServer 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      return _pages; // 오류 발생 시 현재 페이지 목록 반환
    }
  }
  
  // 서버에서 직접 페이지 로드 (별도 메서드로 분리하여 재사용)
  Future<List<page_model.Page>> _directlyLoadFromServer() async {
    try {
      final snapshot = await _firestore.collection('pages')
        .where('noteId', isEqualTo: noteId)
        .orderBy('pageNumber')
        .get()
        .timeout(const Duration(seconds: 5), onTimeout: () {
          debugPrint('⚠️ 서버에서 페이지 가져오기 타임아웃');
          throw Exception('서버에서 페이지 가져오기 타임아웃');
        });
      
      final loadedPages = snapshot.docs
        .map((doc) => page_model.Page.fromFirestore(doc))
        .toList();
      
      debugPrint('✅ 서버에서 ${loadedPages.length}개 페이지를 직접 로드했습니다.');
      return loadedPages;
    } catch (e) {
      debugPrint('❌ 서버에서 페이지 로드 중 오류: $e');
      return [];
    }
  }
  
  // 백그라운드에서 캐시 업데이트 (UI 차단 방지)
  void _updateCacheInBackground(List<page_model.Page> pages) {
    if (pages.isEmpty) return;
    
    Future.microtask(() async {
      try {
        await _cacheService.cachePages(noteId, pages);
        debugPrint('✅ 백그라운드에서 ${pages.length}개 페이지를 캐시에 저장했습니다.');
      } catch (e) {
        debugPrint('⚠️ 백그라운드 캐시 업데이트 중 오류 (무시됨): $e');
      }
    });
  }
  
  // 백그라운드에서 서버와 동기화 (UI 차단 방지)
  void _syncWithServerInBackground() {
    Future.microtask(() async {
      try {
        debugPrint('🔄 백그라운드에서 서버와 페이지 동기화 시작');
        final serverPages = await _directlyLoadFromServer();
        
        if (serverPages.isEmpty) {
          debugPrint('⚠️ 서버에서 페이지를 가져오지 못해 동기화를 건너뜁니다.');
          return;
        }
        
        // 서버 페이지와 현재 페이지 병합
        final oldPageCount = _pages.length;
        mergePages(serverPages);
        
        // 페이지 수가 변경된 경우 캐시 업데이트
        if (_pages.length != oldPageCount) {
          await _cacheService.cachePages(noteId, _pages);
          debugPrint('✅ 서버 동기화 후 캐시 업데이트 (페이지 수: $oldPageCount → ${_pages.length})');
        } else {
          debugPrint('✅ 서버 동기화 완료 (변경사항 없음)');
        }
      } catch (e) {
        debugPrint('⚠️ 백그라운드 서버 동기화 중 오류 (무시됨): $e');
      }
    });
  }
  
  // 모든 페이지 이미지 로드
  Future<void> loadAllPageImages() async {
    if (_pages.isEmpty) return;

    // 현재 페이지 이미지 우선 로드 (동기적으로 처리)
    if (_currentPageIndex >= 0 && _currentPageIndex < _pages.length) {
      await _loadPageImage(_currentPageIndex);
    }

    // 다음 페이지와 이전 페이지 이미지 미리 로드 (비동기적으로 처리)
    Future.microtask(() async {
      // 다음 페이지 로드
      if (_currentPageIndex + 1 < _pages.length) {
        await _loadPageImage(_currentPageIndex + 1);
      }

      // 이전 페이지 로드
      if (_currentPageIndex - 1 >= 0) {
        await _loadPageImage(_currentPageIndex - 1);
      }

      // 나머지 페이지 이미지는 백그라운드에서 로드
      for (int i = 0; i < _pages.length; i++) {
        if (i != _currentPageIndex &&
            i != _currentPageIndex + 1 &&
            i != _currentPageIndex - 1) {
          await _loadPageImage(i);
        }
      }
    });
  }
  
  // 단일 페이지 이미지 로드
  Future<void> _loadPageImage(int index) async {
    if (index < 0 || index >= _pages.length) return;
    if (_imageFiles.length <= index) return;

    final page = _pages[index];
    if (page.imageUrl == null || page.imageUrl!.isEmpty) return;
    if (_imageFiles[index] != null) return; // 이미 로드된 경우 스킵

    try {
      // 이미지 로드 시도
      final imageFile = await _imageService.getImageFile(page.imageUrl);
      
      // 인덱스 범위 확인
      if (index < _imageFiles.length) {
        _imageFiles[index] = imageFile;
        
        // 이미지가 로드되었는지 추가 확인
        if (imageFile != null) {
          // 이미지 맵에도 추가
          if (page.id != null) {
            _imageFileMap[page.id!] = imageFile;
          }
        }
      }
    } catch (e) {
      debugPrint('이미지 로드 중 오류: $e');
    }
  }
  
  // 페이지 캐시 업데이트
  Future<void> updatePageCache(page_model.Page page) async {
    await _cacheService.cachePage(noteId, page);
  }
  
  // 현재 페이지 업데이트
  void updateCurrentPage(page_model.Page updatedPage) {
    if (_currentPageIndex < 0 || _currentPageIndex >= _pages.length) return;
    
    // 페이지 ID가 일치하는지 확인
    if (_pages[_currentPageIndex].id == updatedPage.id) {
      _pages[_currentPageIndex] = updatedPage;
    }
  }
  
  // 특정 인덱스의 페이지 가져오기
  page_model.Page? getPageAtIndex(int index) {
    if (index >= 0 && index < _pages.length) {
      return _pages[index];
    }
    return null;
  }
  
  // 특정 페이지의 이미지 파일 가져오기
  File? getImageFileForPage(page_model.Page? page) {
    if (page == null || page.id == null) return null;
    
    // 페이지 ID로 인덱스 찾기
    for (int i = 0; i < _pages.length; i++) {
      if (_pages[i].id == page.id && i < _imageFiles.length) {
        return _imageFiles[i];
      }
    }
    return null;
  }
  
  /// 현재 페이지의 이미지를 업데이트합니다.
  /// 이미지 파일과 URL을 모두 업데이트하여 UI에 즉시 반영되도록 합니다.
  void updateCurrentPageImage(File imageFile, String imageUrl) {
    if (currentPage == null) return;
    
    // 현재 페이지의 이미지 URL 업데이트
    final updatedPage = currentPage!.copyWith(imageUrl: imageUrl);
    
    // 현재 인덱스에 업데이트된 페이지 저장
    if (currentPageIndex >= 0 && currentPageIndex < pages.length) {
      _pages[currentPageIndex] = updatedPage;
      
      // 현재 인덱스의 이미지 파일 업데이트
      _imageFiles[currentPageIndex] = imageFile;
    }
    
    // 이미지 파일 캐싱 (맵에 저장)
    if (updatedPage.id != null) {
      _imageFileMap[updatedPage.id!] = imageFile;
    }
  }
  
  /// 페이지 내용을 로드하는 통합 메서드
  /// 이미지와 텍스트 처리를 모두 처리합니다.
  Future<Map<String, dynamic>> loadPageContent(
    page_model.Page page, 
    {required TextProcessingService textProcessingService,
    required ImageService imageService,
    required dynamic note}) async {
    
    // 결과를 담을 맵
    final Map<String, dynamic> result = {
      'imageFile': null,
      'processedText': null,
      'isSuccess': false,
    };
    
    try {
      // 1. 이미지 로드 (있는 경우)
      File? imageFile;
      if (page.imageUrl != null && page.imageUrl!.isNotEmpty) {
        imageFile = await imageService.loadPageImage(page.imageUrl);
        result['imageFile'] = imageFile;
      }
      
      // 2. 텍스트 처리
      if (page.id != null) {
        final processedText = await textProcessingService.processAndPreparePageContent(
          page: page,
          imageFile: imageFile ?? imageService.getCurrentImageFile(),
          note: note,
        );
        
        result['processedText'] = processedText;
        result['isSuccess'] = processedText != null;
      }
      
      // 현재 페이지의 이미지 파일 업데이트
      if (page.id == currentPage?.id && imageFile != null) {
        for (int i = 0; i < _pages.length; i++) {
          if (_pages[i].id == page.id && i < _imageFiles.length) {
            _imageFiles[i] = imageFile;
            break;
          }
        }
      }
      
      return result;
    } catch (e) {
      debugPrint('페이지 내용 로드 중 오류: $e');
      result['error'] = e.toString();
      return result;
    }
  }
}
