import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/note.dart' as note_model;
import '../../../core/services/content/page_service.dart';
import '../../../core/services/media/image_service.dart';
import '../../../core/services/media/image_cache_service.dart';
import '../../../core/services/storage/unified_cache_service.dart';
import '../../../core/services/text_processing/llm_text_processing.dart';
import '../../../core/services/content/note_service.dart';
import '../../../core/services/content/flashcard_service.dart' hide debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'segment_manager.dart';
import 'package:path_provider/path_provider.dart';

/// 페이지 관리 클래스
/// 페이지 로드, 병합, 이미지 로드 등의 기능 제공
/// 
class PageManager {
  final String noteId;
  final note_model.Note? initialNote;
  final PageService _pageService = PageService();
  final NoteService _noteService = NoteService();
  final FlashCardService _flashCardService = FlashCardService();
  final ImageService _imageService = ImageService();
  final ImageCacheService _imageCacheService = ImageCacheService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SegmentManager _segmentManager = SegmentManager();
  final UnifiedTextProcessingService _textProcessingService = UnifiedTextProcessingService();
  
  note_model.Note? _note;
  
  List<page_model.Page> _pages = [];
  List<File?> _imageFiles = [];
  // 페이지 ID별 이미지 파일 맵
  Map<String, File> _imageFileMap = {};
  int _currentPageIndex = 0;
  bool _loadingPages = false;
  
  ValueNotifier<int> currentPageNotifier = ValueNotifier<int>(0);
  bool _useCacheFirst = true;
  int _pageLoadCounter = 0;
  int _loadErrorCount = 0;
  bool _isSyncing = false;
  
  PageManager({
    required this.noteId,
    this.initialNote,
    bool useCacheFirst = true,
  }) : _useCacheFirst = useCacheFirst,
       _note = initialNote,
       _loadingPages = false,
       _pageLoadCounter = 0 {
    debugPrint('🔄 PageManager 초기화: noteId=$noteId, initialNote=${initialNote != null ? "있음" : "없음"}, useCacheFirst=$useCacheFirst');
    
    // 초기 노트가 있는 경우, 페이지가 있으면 사용하고 없으면 나중에 로드
    if (initialNote != null) {
      if (initialNote!.pages != null && initialNote!.pages!.isNotEmpty) {
        debugPrint('✅ 초기 노트에서 ${initialNote!.pages!.length}개 페이지를 즉시 설정합니다.');
        setPages(initialNote!.pages!);
      } else {
        debugPrint('⚠️ 초기 노트에 페이지가 없습니다. 필요 시 로드해야 합니다.');
        _pages = [];
      }
    }
  }
  
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
  
  /// 서버에서 페이지를 로드합니다.
  Future<List<page_model.Page>> loadPagesFromServer({String? noteId, bool forceRefresh = false}) async {
    final String targetNoteId = noteId ?? this.noteId;
    
    debugPrint('🚀 loadPagesFromServer 호출됨: noteId=$targetNoteId, forceRefresh=$forceRefresh, _loadingPages=$_loadingPages');
    
    if (targetNoteId.isEmpty) {
      debugPrint('⚠️ loadPagesFromServer: noteId가 비어 있습니다');
      return [];
    }
    
    // 중요: 중복 요청 확인 로직
    // forceRefresh가 true면 무조건 로드, 아니면 이미 로딩 중인지 확인
    if (_loadingPages && !forceRefresh) {
      debugPrint('⚠️ 이미 페이지 로드 중입니다. 중복 요청 무시. (_loadingPages=true)');
      return _pages;
    }
    
    bool wasLoading = _loadingPages;
    _loadingPages = true;
    _pageLoadCounter++;
    final int currentLoadAttempt = _pageLoadCounter;
    
    debugPrint('📢 페이지 로드 시작: noteId=$targetNoteId, 시도 번호=$currentLoadAttempt, 이전 로딩 상태=$wasLoading');
    
    try {
      List<page_model.Page> pages = [];
      
      // 0. 이미 메모리에 페이지가 있고 강제 새로고침이 아니면 그대로 사용
      if (!forceRefresh && _pages.isNotEmpty) {
        debugPrint('✅ 메모리에 이미 ${_pages.length}개 페이지가 있어 그대로 사용합니다.');
        _loadingPages = false;
        return _pages;
      }
      
      // 1. Firestore에서 직접 페이지 로드 (가장 신뢰할 수 있는 소스)
      try {
        debugPrint('📄 Firestore에서 페이지 직접 로드 시작: noteId=$targetNoteId');
        final snapshot = await _firestore
          .collection('pages')
          .where('noteId', isEqualTo: targetNoteId)
          .orderBy('pageNumber')
          .get()
          .timeout(const Duration(seconds: 5));
        
        debugPrint('📊 Firestore 쿼리 결과: ${snapshot.docs.length}개 문서');
        
        if (snapshot.docs.isNotEmpty) {
          pages = snapshot.docs
            .map((doc) => page_model.Page.fromFirestore(doc))
            .toList();
          
          // 페이지를 번호순으로 정렬
          pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
          
          debugPrint('✅ Firestore에서 직접 ${pages.length}개 페이지 로드 완료');
          
          // 백그라운드에서 캐시 업데이트
          Future.microtask(() async {
            try {
              await _cacheService.cachePages(targetNoteId, pages);
              debugPrint('✅ 백그라운드에서 페이지 캐시 업데이트 완료');
            } catch (e) {
              debugPrint('⚠️ 페이지 캐시 업데이트 중 오류: $e');
            }
          });
          
          // 현재 로드 시도가 최신 시도와 동일한 경우에만 상태 업데이트
          if (currentLoadAttempt == _pageLoadCounter) {
            if (pages.isNotEmpty) {
              debugPrint('📝 페이지 목록 설정: ${pages.length}개 페이지');
              setPages(pages);
            }
            _loadingPages = false;
          } else {
            debugPrint('⚠️ 현재 로드 시도($currentLoadAttempt)가 최신 시도($_pageLoadCounter)와 다릅니다');
            _loadingPages = false;
          }
          
          return pages;
        } else {
          debugPrint('⚠️ Firestore에 페이지가 없습니다: noteId=$targetNoteId');
        }
      } catch (e) {
        debugPrint('❌ Firestore에서 페이지 로드 중 오류: $e');
        // Firestore 로드 실패 시 캐시 시도
      }
      
      // 2. Firestore 로드 실패 시 캐시에서 페이지 로드 시도
      if (_useCacheFirst || forceRefresh == false) {
        try {
          debugPrint('🔍 캐시에서 페이지 로드 시도: noteId=$targetNoteId');
          final cachedPages = await _pageService.getPagesForNote(targetNoteId);
          
          if (cachedPages.isNotEmpty) {
            debugPrint('✅ 캐시에서 ${cachedPages.length}개 페이지 로드 성공');
            pages = cachedPages;
            
            // 현재 로드 시도가 최신 시도와 동일한 경우에만 상태 업데이트
            if (currentLoadAttempt == _pageLoadCounter) {
              setPages(pages);
              _loadingPages = false;
            } else {
              _loadingPages = false;
            }
            
            return pages;
          } else {
            debugPrint('⚠️ 캐시에 페이지가 없습니다.');
          }
        } catch (e) {
          debugPrint('❌ 캐시에서 페이지 로드 중 오류: $e');
        }
      }
      
      // 로드 실패 시 빈 목록 반환
      debugPrint('⚠️ 페이지 로드 실패: Firestore와 캐시 모두에서 페이지를 찾지 못했습니다.');
      
      // 현재 로드 시도가 최신 시도와 동일한 경우에만 상태 업데이트
      if (currentLoadAttempt == _pageLoadCounter) {
        _loadingPages = false;
      } else {
        _loadingPages = false;
      }
      
      return pages;
    } catch (e, stack) {
      debugPrint('❌ 페이지 로드 중 예외 발생: $e');
      debugPrint('스택 트레이스: $stack');
      
      // 오류 발생 시 로딩 상태 해제
      _loadingPages = false;
      
      return [];
    } finally {
      // 여기서 확실하게 로딩 상태 해제
      if (_loadingPages && currentLoadAttempt == _pageLoadCounter) {
        debugPrint('🔄 finally 블록에서 로딩 상태 해제');
        _loadingPages = false;
      }
    }
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
      final imageUrl = page.imageUrl!;
      
      // 1. 먼저 메모리 캐시에서 이미지 확인
      final cachedBytes = _imageCacheService.getFromCache(imageUrl);
      if (cachedBytes != null) {
        // 캐시된 이미지가 있으면 임시 파일로 저장
        try {
          final tempDir = await getTemporaryDirectory();
          final cacheFile = File('${tempDir.path}/cache_${imageUrl.hashCode}.jpg');
          await cacheFile.writeAsBytes(cachedBytes);
          
          // 인덱스 범위 확인
          if (index < _imageFiles.length) {
            _imageFiles[index] = cacheFile;
            
            // 이미지 맵에도 추가
            if (page.id != null) {
              _imageFileMap[page.id!] = cacheFile;
            }
          }
          
          debugPrint('캐시에서 이미지 로드됨: $imageUrl');
          return;
        } catch (e) {
          debugPrint('캐시된 이미지 처리 중 오류: $e');
          // 오류 발생 시 일반 로드 로직으로 진행
        }
      }
      
      // 2. 캐시에 없으면 이미지 서비스로 로드
      final imageFile = await _imageService.getImageFile(imageUrl);
      
      // 이미지 파일이 로드되었는지 확인
      if (imageFile != null) {
        // 메모리 캐시에 추가
        try {
          final imageBytes = await imageFile.readAsBytes();
          _imageCacheService.addToCache(imageUrl, imageBytes);
        } catch (e) {
          debugPrint('이미지 캐싱 중 오류: $e');
          // 캐싱 실패는 무시하고 진행
        }
      
      // 인덱스 범위 확인
      if (index < _imageFiles.length) {
        _imageFiles[index] = imageFile;
        
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
  
  /// 특정 인덱스의 페이지 이미지를 로드합니다.
  Future<File?> loadPageImage(int index) async {
    if (index < 0 || index >= _pages.length) return null;
    
    final page = _pages[index];
    if (page.imageUrl == null || page.imageUrl!.isEmpty) return null;
    
    // 이미지 파일이 이미 로드되어 있으면 반환
    if (index < _imageFiles.length && _imageFiles[index] != null) {
      debugPrint('이미지 파일이 이미 로드되어 있음: ${page.id}');
      return _imageFiles[index];
    }
    
    // 페이지 ID로 이미지 맵에서 찾기
    if (page.id != null && _imageFileMap.containsKey(page.id!)) {
      final cachedFile = _imageFileMap[page.id!];
      // 이미지 파일 배열 업데이트
      if (index < _imageFiles.length) {
        _imageFiles[index] = cachedFile;
      }
      debugPrint('이미지 맵에서 파일 찾음: ${page.id}');
      return cachedFile;
    }
    
    try {
      final imageUrl = page.imageUrl!;
      
      // 1. 먼저 메모리 캐시에서 이미지 확인
      final cachedBytes = _imageCacheService.getFromCache(imageUrl);
      if (cachedBytes != null) {
        // 캐시된 이미지가 있으면 임시 파일로 저장
        try {
          final tempDir = await getTemporaryDirectory();
          final cacheFile = File('${tempDir.path}/cache_${imageUrl.hashCode}.jpg');
          await cacheFile.writeAsBytes(cachedBytes);
          
          // 이미지 파일 배열 업데이트
          if (index < _imageFiles.length) {
            _imageFiles[index] = cacheFile;
          }
          
          // 이미지 맵에 추가
          if (page.id != null) {
            _imageFileMap[page.id!] = cacheFile;
          }
          
          debugPrint('캐시에서 이미지 로드됨: $imageUrl');
          return cacheFile;
        } catch (e) {
          debugPrint('캐시된 이미지 처리 중 오류: $e');
          // 오류 발생 시 일반 로드 로직으로 진행
        }
      }
      
      // 2. 캐시에 없으면 이미지 서비스로 로드
      debugPrint('이미지 로드 시작: ${imageUrl}');
      final imageFile = await _imageService.getImageFile(imageUrl);
      
      if (imageFile != null) {
        // 메모리 캐시에 추가
        try {
          final imageBytes = await imageFile.readAsBytes();
          _imageCacheService.addToCache(imageUrl, imageBytes);
        } catch (e) {
          debugPrint('이미지 캐싱 중 오류: $e');
          // 캐싱 실패는 무시하고 진행
        }
        
        // 이미지 파일 배열 업데이트
        if (index < _imageFiles.length) {
          _imageFiles[index] = imageFile;
        }
        
        // 이미지 맵에 추가
        if (page.id != null) {
          _imageFileMap[page.id!] = imageFile;
        }
        
        debugPrint('이미지 로드 성공: ${page.id}');
        return imageFile;
      } else {
        debugPrint('이미지 로드 실패: 파일이 null임');
        return null;
      }
    } catch (e) {
      debugPrint('이미지 로드 중 오류: $e');
      return null;
    }
  }
  
  /// 페이지 내용을 로드하는 통합 메서드
  Future<Map<String, dynamic>> loadPageContent(
    page_model.Page page, 
    {
      UnifiedTextProcessingService? textProcessingService,
      ImageService? imageService,
      dynamic note,
  }) async {
    try {
      // 1. 이미지 로드
      File? imageFile;
      if (page.imageUrl != null && page.imageUrl!.isNotEmpty) {
        imageFile = await (imageService ?? _imageService).loadPageImage(page.imageUrl);
      } else {
        // 이미지 URL이 없는 경우 현재 페이지의 이미지를 사용
        imageFile = getImageFileForPage(page);
      }
      
      // 2. 텍스트 처리 (SegmentManager 사용)
      var processedText;
      if (page.originalText.isNotEmpty) {
        try {
          processedText = await _segmentManager.processPageText(page: page);
        } catch (e) {
          debugPrint('텍스트 처리 중 오류: $e');
        }
      }
      
      // 3. 현재 페이지의 이미지 파일 업데이트 (이미지가 있는 경우)
      if (imageFile != null && page.id == currentPage?.id) {
        for (int i = 0; i < _pages.length; i++) {
          if (_pages[i].id == page.id && i < _imageFiles.length) {
            _imageFiles[i] = imageFile;
            break;
          }
        }
      }
      
      return {
        'imageFile': imageFile,
        'processedText': processedText,
        'isSuccess': imageFile != null || processedText != null,
        'error': (imageFile == null && processedText == null) ? '콘텐츠 로드 실패' : null,
      };
    } catch (e) {
      debugPrint('페이지 내용 로드 중 오류: $e');
      return {
        'imageFile': null,
        'processedText': null,
        'isSuccess': false,
        'error': e.toString(),
      };
    }
  }
}
