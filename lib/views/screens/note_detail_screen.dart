import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../models/text_processing_mode.dart';
import '../../services/note_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/dictionary_service.dart';
import '../../services/tts_service.dart';
import '../../services/enhanced_ocr_service.dart';
import '../../services/user_preferences_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/note_detail_app_bar.dart';
import '../../widgets/note_action_bottom_sheet.dart';
import '../../widgets/note_page_view.dart';
import '../../widgets/edit_title_dialog.dart';
import 'flashcard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // Timer 클래스를 사용하기 위한 import 추가
import '../../services/unified_cache_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
      final pages = result['pages'] as List<dynamic>;
      final isFromCache = result['isFromCache'] as bool;
      final isProcessingBackground =
          result['isProcessingBackground'] as bool? ?? false;

      if (mounted) {
        setState(() {
          _note = note;
          _isFavorite = note.isFavorite;

          // 페이지 업데이트 (기존 페이지 유지하면서 새 페이지 추가)
          if (_pages.isEmpty) {
            // 첫 로드 시에는 모든 페이지 설정
            _pages = pages.cast<page_model.Page>();
          } else if (pages.isNotEmpty && pages.length > _pages.length) {
            // 페이지가 추가된 경우 (백그라운드 처리 완료 등)
            _pages = pages.cast<page_model.Page>();
            debugPrint('페이지 수가 증가하여 전체 페이지 업데이트: ${_pages.length}개');
          }

          // 페이지 번호 순으로 정렬
          _pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

          // 이미지 파일 배열 초기화 (이미 로드된 이미지는 유지)
          if (_imageFiles.length != _pages.length) {
            final newImageFiles = List<File?>.filled(_pages.length, null);
            // 기존 이미지 파일 복사
            for (int i = 0; i < _imageFiles.length && i < _pages.length; i++) {
              newImageFiles[i] = _imageFiles[i];
            }
            _imageFiles = newImageFiles;
          }

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

        // 페이지가 없거나 1개만 있고 캐시에서 로드된 경우에만 페이지 서비스에 다시 요청
        if (_pages.length <= 1 && isFromCache) {
          debugPrint('페이지가 ${_pages.length}개만 로드되어 페이지 서비스에 다시 요청합니다.');
          _reloadPages();
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

      // 페이지 서비스에서 직접 페이지 목록 가져오기
      final pages = await _pageService.getPagesForNote(widget.noteId);

      if (mounted && pages.isNotEmpty) {
        setState(() {
          // 기존 페이지 수보다 많은 경우 또는 강제 로드 시 업데이트
          if (forceReload || pages.length > _pages.length) {
            _pages = pages;
            // 이미지 파일 배열 크기 조정 (기존 이미지 유지)
            if (_imageFiles.length != _pages.length) {
              final newImageFiles = List<File?>.filled(_pages.length, null);
              // 기존 이미지 파일 복사
              for (int i = 0;
                  i < _imageFiles.length && i < _pages.length;
                  i++) {
                newImageFiles[i] = _imageFiles[i];
              }
              _imageFiles = newImageFiles;
            }

            // 현재 페이지 인덱스 확인
            if (_currentPageIndex >= _pages.length) {
              _currentPageIndex = _pages.isNotEmpty ? 0 : -1;
            }

            debugPrint('페이지 다시 로드 완료: ${_pages.length}개');
          } else {
            debugPrint(
                '서버에서 가져온 페이지 수(${pages.length})가 현재 페이지 수(${_pages.length})보다 적거나 같아 업데이트하지 않음');
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

  void _changePage(int newIndex) {
    if (newIndex < 0 ||
        newIndex >= _pages.length ||
        newIndex == _currentPageIndex) {
      return;
    }

    debugPrint('페이지 전환: $_currentPageIndex -> $newIndex');

    // TTS 중지
    _ttsService.stop();

    setState(() {
      _currentPageIndex = newIndex;
    });

    // 새 페이지의 이미지 로드
    _loadPageImages();
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

  Future<void> _navigateToFlashCardScreen() async {
    if (_note == null) return;

    // 플래시카드 화면으로 이동하고 결과를 받음
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(noteId: _note!.id),
      ),
    );

    // 플래시카드가 변경되었으면 노트 정보 다시 로드
    if (result == true && mounted) {
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

  // ===== UI 빌드 메서드 =====

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NoteDetailAppBar(
        note: _note,
        isFavorite: _isFavorite,
        onEditTitle: _showEditTitleDialog,
        onToggleFavorite: _toggleFavorite,
        onShowMoreOptions: _showMoreOptions,
        onFlashCardPressed: _navigateToFlashCardScreen,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingIndicator(message: '노트 불러오는 중...');
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadNote,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_note == null) {
      return const Center(child: Text('노트를 찾을 수 없습니다.'));
    }

    return NotePageView(
      pages: _pages,
      imageFiles: _imageFiles,
      currentPageIndex: _currentPageIndex,
      onPageChanged: _changePage,
      noteId: widget.noteId,
      onCreateFlashCard: _createFlashCard,
      textProcessingMode: _textProcessingMode,
      flashCards: _note?.flashCards,
    );
  }
}
