import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../models/text_processing_mode.dart';
import '../../models/text_segment.dart';
import '../../models/processed_text.dart';
import '../../services/note_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/dictionary_service.dart';
import '../../services/tts_service.dart';
import '../../services/enhanced_ocr_service.dart';
import '../../services/user_preferences_service.dart';
import '../../services/page_content_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/note_detail_app_bar.dart';
import '../../widgets/note_action_bottom_sheet.dart';
import '../../widgets/note_page_view.dart';
import '../../widgets/page_content_widget.dart';
import '../../widgets/edit_title_dialog.dart';
import '../../widgets/page_indicator_widget.dart';
import '../../widgets/text_display_toggle_widget.dart';
import '../../utils/text_display_mode.dart';
import 'flashcard_screen.dart';
import 'full_image_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // Timer 클래스를 사용하기 위한 import 추가
import '../../services/unified_cache_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/text_reader_service.dart';

/// 노트 상세 화면
/// 페이지 탐색, 노트 액션, 백그라운드 처리, 이미지 로딩 등의 기능

class NoteDetailScreen extends StatefulWidget {
  final String noteId;
  final bool isProcessingBackground;

  const NoteDetailScreen({
    Key? key,
    required this.noteId,
    this.isProcessingBackground = false,
  }) : super(key: key);

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final FlashCardService _flashCardService = FlashCardService();
  final TtsService _ttsService = TtsService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final PageContentService _pageContentService = PageContentService();
  final TextReaderService _textReaderService = TextReaderService();

  // 상태 변수
  Note? _note;
  List<page_model.Page> _pages = [];
  List<File?> _imageFiles = [];
  bool _isLoading = true;
  String? _error;
  bool _isFavorite = false;
  int _currentPageIndex = 0;
  bool _isCreatingFlashCard = false;
  TextProcessingMode _textProcessingMode = TextProcessingMode.languageLearning;
  Timer? _backgroundCheckTimer;

  @override
  void initState() {
    super.initState();
    _loadNote();
    _initTts();
    _loadUserPreferences();
    _setupBackgroundProcessingCheck();
  }

  @override
  void dispose() {
    _backgroundCheckTimer?.cancel();
    _ttsService.stop();
    super.dispose();
  }

  // ===== 데이터 로딩 관련 메서드 =====

  // 페이지 병합 로직을 별도의 메서드로 분리
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

  // 이미지 파일 배열 업데이트 로직을 별도의 메서드로 분리
  List<File?> _updateImageFilesForPages(List<page_model.Page> newPages,
      List<page_model.Page> oldPages, List<File?> oldImageFiles) {
    if (oldImageFiles.length == newPages.length) {
      return oldImageFiles;
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

  Future<void> _loadNote() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 백그라운드 처리 중인 경우 스낵바 표시
      if (widget.isProcessingBackground && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('추가 페이지를 백그라운드에서 처리 중입니다...'),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // 노트와 페이지를 함께 로드 (캐싱 활용)
      final result = await _noteService.getNoteWithPages(widget.noteId);
      final note = result['note'] as Note;
      final serverPages = result['pages'] as List<dynamic>;
      final isFromCache = result['isFromCache'] as bool;
      final isProcessingBackground =
          result['isProcessingBackground'] as bool? ?? false;
      final processingCompleted = note.processingCompleted ?? false;

      if (mounted) {
        setState(() {
          _note = note;
          _isFavorite = note.isFavorite;

          // 페이지 업데이트
          final typedServerPages = serverPages.cast<page_model.Page>();

          if (_pages.isEmpty) {
            // 첫 로드 시에는 모든 페이지 설정
            _pages = typedServerPages;
            debugPrint('첫 로드: ${_pages.length}개 페이지 설정');
          } else {
            // 기존 페이지와 서버 페이지 병합
            final oldPages = List<page_model.Page>.from(_pages);
            _pages = _mergePagesById(oldPages, typedServerPages);
          }

          // 이미지 파일 배열 업데이트
          final oldImageFiles = List<File?>.from(_imageFiles);
          final oldPages = List<page_model.Page>.from(_pages);
          _imageFiles =
              _updateImageFilesForPages(_pages, oldPages, oldImageFiles);

          // 현재 페이지 인덱스 확인
          _currentPageIndex =
              _currentPageIndex >= 0 && _currentPageIndex < _pages.length
                  ? _currentPageIndex
                  : (_pages.isNotEmpty ? 0 : -1);
          _isLoading = false;
        });

        // 페이지 수 로그 출력
        debugPrint('노트에 ${_pages.length}개의 페이지가 있습니다. (캐시에서 로드: $isFromCache)');
        for (int i = 0; i < _pages.length; i++) {
          final page = _pages[i];
          debugPrint(
              '페이지[$i]: id=${page.id}, pageNumber=${page.pageNumber}, 이미지=${page.imageUrl != null}');
        }

        // 각 페이지의 이미지 로드 (현재 페이지 우선)
        _loadPageImages();

        // 다음 조건에서 페이지 서비스에 다시 요청:
        // 1. 페이지가 없거나 1개만 있고 캐시에서 로드된 경우
        // 2. 백그라운드 처리가 완료된 경우 (processingCompleted가 true)
        if ((_pages.length <= 1 && isFromCache) || processingCompleted) {
          debugPrint(
              '페이지 다시 로드 조건 충족: 페이지 수=${_pages.length}, 캐시=$isFromCache, 처리완료=$processingCompleted');
          _reloadPages(forceReload: processingCompleted);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '노트를 불러오는 중 오류가 발생했습니다: $e';
          _isLoading = false;
        });
      }
    }
  }

  // 백그라운드 처리 완료 확인을 위한 타이머 설정
  void _setupBackgroundProcessingCheck() {
    // 기존 타이머가 있으면 취소
    _backgroundCheckTimer?.cancel();

    // 타이머 생성 전 로그 출력
    debugPrint('백그라운드 처리 확인 타이머 설정: ${widget.noteId}');

    // 5초마다 백그라운드 처리 상태 확인하는 주기적 타이머 설정
    _backgroundCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      if (!mounted) {
        debugPrint('화면이 더 이상 마운트되지 않음 - 타이머 취소');
        timer.cancel();
        return;
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        final pagesUpdated =
            prefs.getBool('pages_updated_${widget.noteId}') ?? false;

        if (pagesUpdated) {
          // 페이지 업데이트가 완료된 경우
          final updatedPageCount =
              prefs.getInt('updated_page_count_${widget.noteId}') ?? 0;
          debugPrint('백그라운드 처리 완료 감지: $updatedPageCount 페이지 업데이트됨');

          // 플래그 초기화
          await prefs.remove('pages_updated_${widget.noteId}');
          await prefs.remove('updated_page_count_${widget.noteId}');

          // 페이지 다시 로드
          _reloadPages(forceReload: true);

          // 완료 메시지 표시
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$updatedPageCount개의 추가 페이지 처리가 완료되었습니다.'),
                duration: Duration(seconds: 3),
              ),
            );
          }

          // 업데이트가 완료되었으므로 타이머 취소
          debugPrint('백그라운드 처리 완료 - 타이머 취소');
          timer.cancel();
        }
      } catch (e) {
        debugPrint('백그라운드 처리 상태 확인 중 오류 발생: $e');
      }
    });
  }

  // 페이지 다시 로드 (forceReload 매개변수 추가)
  Future<void> _reloadPages({bool forceReload = false}) async {
    try {
      // 이미 로드 중인지 확인
      if (_isLoading) return;

      setState(() {
        _isLoading = true;
      });

      // 노트 문서에서 처리 완료 상태 확인
      bool processingCompleted = false;
      if (_note != null && _note!.id != null) {
        try {
          final noteDoc = await FirebaseFirestore.instance
              .collection('notes')
              .doc(_note!.id)
              .get();
          if (noteDoc.exists) {
            final data = noteDoc.data();
            processingCompleted =
                data?['processingCompleted'] as bool? ?? false;
            if (processingCompleted) {
              debugPrint('노트 문서에서 백그라운드 처리 완료 상태 확인: $processingCompleted');
              forceReload = true; // 처리가 완료된 경우 강제 로드
            }
          }
        } catch (e) {
          debugPrint('노트 문서 확인 중 오류 발생: $e');
        }
      }

      // 페이지 서비스에서 직접 페이지 목록 가져오기
      final serverPages = await _pageService.getPagesForNote(widget.noteId);

      // 디버그 로그 추가 (간소화)
      debugPrint('서버에서 가져온 페이지 수: ${serverPages.length}');
      debugPrint('현재 로컬 페이지 수: ${_pages.length}');

      if (mounted) {
        setState(() {
          // 항상 페이지 병합 수행 (서버 페이지가 적더라도 기존 페이지 유지)
          final oldPages = List<page_model.Page>.from(_pages);
          _pages = _mergePagesById(oldPages, serverPages);

          // 이미지 파일 배열 업데이트
          final oldImageFiles = List<File?>.from(_imageFiles);
          _imageFiles =
              _updateImageFilesForPages(_pages, oldPages, oldImageFiles);

          // 현재 페이지 인덱스 확인
          if (_currentPageIndex >= _pages.length) {
            _currentPageIndex = _pages.isNotEmpty ? 0 : -1;
          }

          _isLoading = false;
        });

        // 이미지 로드
        _loadPageImages();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('페이지 다시 로드 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ===== 이미지 로딩 관련 메서드 =====

  Future<void> _loadPageImages() async {
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

  Future<void> _loadPageImage(int index) async {
    if (index < 0 || index >= _pages.length) return;
    if (_imageFiles.length <= index) return;

    final page = _pages[index];
    if (page.imageUrl == null || page.imageUrl!.isEmpty) return;
    if (_imageFiles[index] != null) return; // 이미 로드된 경우 스킵

    try {
      final imageFile = await _imageService.getImageFile(page.imageUrl);
      if (mounted && index < _imageFiles.length) {
        setState(() {
          _imageFiles[index] = imageFile;
        });
      }
    } catch (e) {
      debugPrint('이미지 로드 중 오류 발생: $e');
    }
  }

  // ===== TTS 관련 메서드 =====

  void _initTts() {
    _ttsService.init();
  }

  // ===== 노트 액션 관련 메서드 =====

  Future<void> _toggleFavorite() async {
    if (_note == null || _note?.id == null) return;

    final newValue = !_isFavorite;

    setState(() {
      _isFavorite = newValue;
    });

    try {
      await _noteService.toggleFavorite(_note!.id!, newValue);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFavorite = !newValue; // 실패 시 원래 값으로 되돌림
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('즐겨찾기 설정 중 오류가 발생했습니다: $e')));
      }
    }
  }

  Future<void> _deleteNote() async {
    if (_note == null || _note?.id == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 페이지 삭제
      await _pageService.deleteAllPagesForNote(_note!.id!);

      // 노트 삭제
      await _noteService.deleteNote(_note!.id!);

      if (mounted) {
        Navigator.of(context).pop(); // 삭제 후 이전 화면으로 돌아가기
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('노트 삭제 중 오류가 발생했습니다: $e')));
      }
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 삭제'),
        content: const Text('이 노트를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteNote();
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  void _showEditTitleDialog() {
    if (_note == null) return;

    showDialog(
      context: context,
      builder: (context) => EditTitleDialog(
        currentTitle: _note!.originalText,
        onTitleUpdated: _updateNoteTitle,
      ),
    );
  }

  Future<void> _updateNoteTitle(String newTitle) async {
    if (_note == null || _note?.id == null) return;

    // 즉시 UI 업데이트 (낙관적 업데이트)
    final previousTitle = _note!.originalText;
    setState(() {
      _note = _note!.copyWith(
        originalText: newTitle,
        updatedAt: DateTime.now(),
      );
      _isLoading = true;
    });

    try {
      // Firestore 업데이트
      await _noteService.updateNote(_note!.id!, _note!);

      // 업데이트 완료
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노트 제목이 변경되었습니다.')),
        );
      }
    } catch (e) {
      // 오류 발생 시 이전 제목으로 복원
      if (mounted) {
        setState(() {
          _note = _note!.copyWith(
            originalText: previousTitle,
          );
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 제목 변경 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  // ===== 페이지 탐색 관련 메서드 =====

  void _changePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    
    setState(() {
      _currentPageIndex = index;
    });
    
    // 현재 페이지 이미지 로드
    _loadPageImage(_currentPageIndex);
  }

  // ===== 메뉴 및 다이얼로그 관련 메서드 =====

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => NoteActionBottomSheet(
        onEditTitle: _showEditTitleDialog,
        onDeleteNote: _confirmDelete,
        onShowTextProcessingModeDialog: _showTextProcessingModeDialog,
        textProcessingMode: _textProcessingMode,
      ),
    );
  }

  // ===== 사용자 설정 관련 메서드 =====

  Future<void> _loadUserPreferences() async {
    try {
      final mode = await _preferencesService.getTextProcessingMode();
      if (mounted) {
        setState(() {
          _textProcessingMode = mode;
        });
      }
    } catch (e) {
      debugPrint('사용자 기본 설정 로드 중 오류 발생: $e');
    }
  }

  Future<void> _changeTextProcessingMode(TextProcessingMode mode) async {
    setState(() {
      _textProcessingMode = mode;
    });

    try {
      // 앱 전체 설정 업데이트
      await _preferencesService.setDefaultTextProcessingMode(mode);
    } catch (e) {
      debugPrint('텍스트 처리 모드 저장 중 오류 발생: $e');
    }
  }

  void _showTextProcessingModeDialog() {
    showDialog(
      context: context,
      builder: (context) => TextProcessingModeDialog(
        currentMode: _textProcessingMode,
        onModeChanged: _changeTextProcessingMode,
      ),
    );
  }

  // ===== 플래시카드 관련 메서드 =====

  Future<void> _createFlashCard(String front, String back,
      {String? pinyin}) async {
    if (_isCreatingFlashCard) return;

    setState(() {
      _isCreatingFlashCard = true;
    });

    try {
      // 빈 문자열이 전달된 경우 (SegmentedTextWidget에서 호출된 경우)
      // 플래시카드 생성을 건너뛰고 노트 상태만 업데이트
      if (front.isEmpty && back.isEmpty) {
        debugPrint('SegmentedTextWidget에서 호출: 노트 상태만 업데이트');
      } else {
        // 사전에서 단어 정보 찾기
        final dictionaryService = DictionaryService();
        final dictionaryEntry = dictionaryService.lookupWord(front);

        // 사전에 단어가 있으면 병음과 의미 사용
        final String finalBack;
        final String? finalPinyin;

        if (dictionaryEntry != null) {
          finalBack = dictionaryEntry.meaning;
          finalPinyin = dictionaryEntry.pinyin;
        } else {
          finalBack = back;
          finalPinyin = pinyin;
        }

        // 플래시카드 생성
        final newFlashCard = await _flashCardService.createFlashCard(
          front: front,
          back: finalBack,
          pinyin: finalPinyin,
          noteId: widget.noteId,
        );
      }

      // 캐시 무효화
      await _cacheService.removeCachedNote(widget.noteId);

      // Firestore에서 직접 노트 가져오기
      final noteDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId)
          .get();

      if (noteDoc.exists && mounted) {
        final updatedNote = Note.fromFirestore(noteDoc);
        setState(() {
          _note = updatedNote;
          debugPrint(
              '노트 ${widget.noteId}의 플래시카드 카운터 업데이트: ${_note!.flashcardCount}개');
        });
      }
    } catch (e) {
      debugPrint('플래시카드 생성 중 오류 발생: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingFlashCard = false;
        });
      }
    }
  }

  // ===== 플래시카드 화면 이동 관련 메서드 =====

  Future<void> _navigateToFlashcards() async {
    if (_note == null) return;
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(
          noteId: widget.noteId,
        ),
      ),
    );
    
    // 플래시카드가 변경되었으면 노트 정보 다시 로드
    if (result != null && mounted) {
      if (result is Note) {
        // 플래시카드 화면에서 직접 업데이트된 노트 객체를 받은 경우
        setState(() {
          _note = result;
          debugPrint(
              '노트 ${widget.noteId}의 플래시카드 카운터 업데이트: ${_note!.flashcardCount}개');
        });

        // 노트 정보가 변경되었으므로 캐시도 무효화
        await _cacheService.removeCachedNote(widget.noteId);
      } else if (result == true) {
        // 이전 방식과의 호환성을 위해 boolean 결과도 처리
        // 캐시 무효화
        await _cacheService.removeCachedNote(widget.noteId);

        // Firestore에서 직접 노트 가져오기
        final noteDoc = await FirebaseFirestore.instance
            .collection('notes')
            .doc(widget.noteId)
            .get();

        if (noteDoc.exists && mounted) {
          setState(() {
            _note = Note.fromFirestore(noteDoc);
            debugPrint(
                '노트 ${widget.noteId}의 플래시카드 카운터 업데이트: ${_note!.flashcardCount}개');
          });
        }
      }
    }
  }

  // 세그먼트 삭제 처리 메서드
  void _handleDeleteSegment(int segmentIndex) async {
    if (_currentPageIndex < 0 || _currentPageIndex >= _pages.length) return;
    
    final page = _pages[_currentPageIndex];
    if (page.id == null) return;
    
    // 현재 페이지의 processedText 객체 가져오기
    if (_pageContentService.hasProcessedText(page.id!)) {
      final processedText = _pageContentService.getProcessedText(page.id!);
      
      if (processedText != null && 
          processedText.segments != null && 
          segmentIndex < processedText.segments!.length) {
        
        // 세그먼트 목록에서 해당 인덱스의 세그먼트 제거
        final updatedSegments = List<TextSegment>.from(processedText.segments!);
        final removedSegment = updatedSegments.removeAt(segmentIndex);
        
        // 전체 원문에서도 해당 세그먼트 문장 제거
        String updatedFullOriginalText = processedText.fullOriginalText;
        String updatedFullTranslatedText = processedText.fullTranslatedText ?? '';
        
        // 원문에서 해당 세그먼트 문장 제거
        if (removedSegment.originalText.isNotEmpty) {
          updatedFullOriginalText = updatedFullOriginalText.replaceAll(removedSegment.originalText, '');
          // 연속된 공백 제거
          updatedFullOriginalText = updatedFullOriginalText.replaceAll(RegExp(r'\s+'), ' ').trim();
        }
        
        // 번역본에서 해당 세그먼트 문장 제거
        if (removedSegment.translatedText != null && removedSegment.translatedText!.isNotEmpty) {
          updatedFullTranslatedText = updatedFullTranslatedText.replaceAll(
              removedSegment.translatedText!, '');
          // 연속된 공백 제거
          updatedFullTranslatedText = updatedFullTranslatedText.replaceAll(RegExp(r'\s+'), ' ').trim();
        }
        
        // 업데이트된 세그먼트 목록으로 새 ProcessedText 생성
        final updatedProcessedText = processedText.copyWith(
          segments: updatedSegments,
          fullOriginalText: updatedFullOriginalText,
          fullTranslatedText: updatedFullTranslatedText,
        );
        
        // 업데이트된 ProcessedText 저장
        _pageContentService.setProcessedText(page.id!, updatedProcessedText);
        
        // Firestore 업데이트
        try {
          // 페이지 내용 업데이트
          await _pageService.updatePageContent(
            page.id!,
            updatedFullOriginalText,
            updatedFullTranslatedText,
          );
          
          // 캐시 업데이트
          final updatedPage = page.copyWith(
            originalText: updatedFullOriginalText,
            translatedText: updatedFullTranslatedText,
            updatedAt: DateTime.now(),
          );
          
          setState(() {
            // 페이지 목록 업데이트
            _pages[_currentPageIndex] = updatedPage;
          });
          
          // 캐시 업데이트
          await _cacheService.cachePage(widget.noteId, updatedPage);
          
          debugPrint('세그먼트 삭제 후 Firestore 및 캐시 업데이트 완료');
        } catch (e) {
          debugPrint('세그먼트 삭제 후 페이지 업데이트 중 오류 발생: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('세그먼트 삭제 후 저장 중 오류가 발생했습니다: $e')),
          );
        }
      }
    }
  }

  // ===== UI 빌드 메서드 =====

  @override
  Widget build(BuildContext context) {
    // 노트 또는 현재 페이지 인덱스가 유효하지 않은 경우 로딩 표시
    if (_note == null || _currentPageIndex < 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('로딩 중...')),
        body: _isLoading
            ? const Center(child: LoadingIndicator(message: '노트 로딩 중...'))
            : Center(child: Text(_error ?? '노트를 불러올 수 없습니다.')),
      );
    }

    final currentPage = _currentPageIndex < _pages.length ? _pages[_currentPageIndex] : null;
    final imageFile = _currentPageIndex < _imageFiles.length ? _imageFiles[_currentPageIndex] : null;

    return Scaffold(
      appBar: NoteDetailAppBar(
        note: _note!,
        isFavorite: _isFavorite,
        onEditTitle: _showEditTitleDialog,
        onToggleFavorite: _toggleFavorite,
        onShowMoreOptions: _showMoreOptions,
        onFlashCardPressed: _navigateToFlashcards,
      ),
      body: Column(
        children: [
          // 페이지 내용 (Expanded로 감싸 남은 공간 채우기)
          Expanded(
            child: _buildCurrentPageContent(),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(currentPage, imageFile),
    );
  }
  
  // 현재 페이지 내용 빌드
  Widget _buildCurrentPageContent() {
    if (_currentPageIndex >= _pages.length) {
      return const Center(child: Text('페이지를 찾을 수 없습니다.'));
    }

    final currentPage = _pages[_currentPageIndex];
    final imageFile = _imageFiles[_currentPageIndex];
    final bool isLoadingImage =
        imageFile == null && currentPage.imageUrl != null;

    // 이미지가 로딩 중이면 로딩 인디케이터 표시
    if (isLoadingImage) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('페이지 로딩 중...', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return PageContentWidget(
      key: ValueKey('page_content_${currentPage.id}_$_currentPageIndex'),
      page: currentPage,
      imageFile: imageFile,
      isLoadingImage: false,
      noteId: widget.noteId,
      onCreateFlashCard: _createFlashCard,
      textProcessingMode: _textProcessingMode,
      flashCards: _note?.flashCards,
      onDeleteSegment: _handleDeleteSegment,
    );
  }

  // 바텀 네비게이션 바 빌드
  Widget _buildBottomNavigationBar(page_model.Page? currentPage, File? imageFile) {
    if (currentPage == null) return const SizedBox.shrink();
    
    final processedText = _pageContentService.getProcessedText(currentPage.id ?? '');
    final bool hasSegments = processedText != null && 
                            processedText.segments != null && 
                            processedText.segments!.isNotEmpty;
    
    // TTS 재생 중인지 확인
    final bool isPlaying = _textReaderService.isPlaying;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 페이지 인디케이터 위젯 사용
        if (_pages.length > 1)
          PageIndicatorWidget(
            currentPageIndex: _currentPageIndex,
            totalPages: _pages.length,
            onPageChanged: _changePage,
          ),
          
        // 바텀 바 컨테이너  
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 상단 행: 텍스트 토글 위젯과 TTS 버튼
              if (hasSegments)
                Row(
                  children: [
                    // TextDisplayToggleWidget 추가
                    Expanded(
                      child: TextDisplayToggleWidget(
                        currentMode: TextDisplayMode.both, // 기본값 설정
                        onModeChanged: (mode) {
                          // 모드 변경 처리
                          setState(() {});
                        },
                        originalText: currentPage.originalText,
                      ),
                    ),
                    
                    // 전체 읽기/멈춤 버튼 (토글)
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.stop : Icons.play_arrow, 
                        size: 20
                      ),
                      tooltip: isPlaying ? '읽기 중지' : '전체 읽기',
                      onPressed: () {
                        if (isPlaying) {
                          _textReaderService.stop();
                        } else if (currentPage.originalText.isNotEmpty) {
                          _textReaderService.readTextBySentences(currentPage.originalText);
                        }
                        setState(() {});
                      },
                    ),
                  ],
                ),
              
              const SizedBox(height: 8),
              
              // 하단 행: 이미지 썸네일
              if (imageFile != null || currentPage.imageUrl != null)
                GestureDetector(
                  onTap: () {
                    // FullImageScreen으로 이동
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullImageScreen(
                          imageFile: imageFile,
                          imageUrl: currentPage.imageUrl,
                          title: '페이지 이미지',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        // 이미지 썸네일
                        if (imageFile != null)
                          SizedBox(
                            width: 80,
                            height: 60,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(4),
                                bottomLeft: Radius.circular(4),
                              ),
                              child: Image.file(
                                imageFile,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        
                        const SizedBox(width: 8),
                        
                        // 이미지 설명 텍스트
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '페이지 이미지',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '눌러서 원본 이미지 보기',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // 화살표 아이콘
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // 이미지 페이지 추가 메서드
  Future<void> _addImagePage() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 이미지 선택 및 처리
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      
      if (pickedFile == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      final imageFile = File(pickedFile.path);

      // 새 페이지 번호 계산
      final int newPageNumber = _pages.isEmpty ? 1 : _pages.last.pageNumber + 1;

      // 페이지 생성 및 이미지 업로드
      final newPage = await _pageService.createPageWithImage(
        noteId: widget.noteId,
        pageNumber: newPageNumber,
        imageFile: imageFile,
      );

      // 페이지 목록 업데이트
      setState(() {
        _pages.add(newPage);
        _imageFiles.add(imageFile); // 이미지 파일 배열에 추가
        _currentPageIndex = _pages.length - 1; // 새 페이지로 이동
        _isLoading = false;
      });

      // 성공 메시지
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('페이지가 추가되었습니다')),
        );
      }
    } catch (e) {
      debugPrint('이미지 페이지 추가 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('페이지 추가 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
}
