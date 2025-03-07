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
import '../../widgets/page_content_widget.dart';
import '../../widgets/page_indicator_widget.dart';
import 'flashcard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // Timer 클래스를 사용하기 위한 import 추가

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
  final NoteService _noteService = NoteService();
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final FlashCardService _flashCardService = FlashCardService();
  final TtsService _ttsService = TtsService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UserPreferencesService _preferencesService = UserPreferencesService();

  Note? _note;
  List<page_model.Page> _pages = [];
  List<File?> _imageFiles = [];
  bool _isLoading = true;
  String? _error;
  bool _isFavorite = false;
  int _currentPageIndex = 0;
  bool _isCreatingFlashCard = false;

  // 텍스트 처리 모드
  TextProcessingMode _textProcessingMode = TextProcessingMode.languageLearning;

  Timer? _backgroundCheckTimer; // 타이머 변수 추가

  @override
  void initState() {
    super.initState();
    _loadNote();
    _initTts();
    _loadUserPreferences();

    // 백그라운드 처리 완료 확인을 위한 타이머 설정
    _setupBackgroundProcessingCheck();
  }

  @override
  void dispose() {
    // 타이머 정리
    _backgroundCheckTimer?.cancel();
    // 화면을 나갈 때 TTS 중지
    _ttsService.stop();
    super.dispose();
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

  // TTS 초기화
  void _initTts() {
    _ttsService.init();
  }

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
    final titleController = TextEditingController(text: _note!.originalText);
    final isDefaultTitle = _note!.originalText.startsWith('#') &&
        _note!.originalText.contains('Note');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 제목 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDefaultTitle)
              const Padding(
                padding: EdgeInsets.only(bottom: 8.0),
                child: Text(
                  '자동 생성된 제목을 더 의미 있는 제목으로 변경해보세요.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: '제목',
                hintText: '노트 내용을 잘 나타내는 제목을 입력하세요',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => titleController.clear(),
                ),
              ),
              autofocus: true,
              maxLength: 50, // 제목 길이 제한
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  _updateNoteTitle(value.trim());
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final newTitle = titleController.text.trim();
              if (newTitle.isNotEmpty) {
                _updateNoteTitle(newTitle);
              }
              Navigator.of(context).pop();
            },
            child: const Text('저장'),
          ),
        ],
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

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('노트 제목 변경'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditTitleDialog();
                },
              ),
              // 텍스트 처리 모드 선택 옵션 추가
              ListTile(
                leading: Icon(
                  _textProcessingMode == TextProcessingMode.professionalReading
                      ? Icons.menu_book
                      : Icons.school,
                ),
                title: const Text('텍스트 처리 모드'),
                subtitle: Text(
                  _textProcessingMode == TextProcessingMode.professionalReading
                      ? '전문 서적 모드 (전체 텍스트 번역)'
                      : '언어 학습 모드 (문장별 번역 및 핀인)',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showTextProcessingModeDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('노트 삭제'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // 사용자 기본 설정 로드
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

  // 텍스트 처리 모드 변경 및 저장
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

  // 텍스트 처리 모드 선택 다이얼로그
  void _showTextProcessingModeDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('텍스트 처리 모드 선택'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<TextProcessingMode>(
                title: const Text('전문 서적 모드'),
                subtitle: const Text('전체 텍스트 번역 제공'),
                value: TextProcessingMode.professionalReading,
                groupValue: _textProcessingMode,
                onChanged: (value) {
                  Navigator.pop(context);
                  if (value != null) {
                    _changeTextProcessingMode(value);
                  }
                },
              ),
              RadioListTile<TextProcessingMode>(
                title: const Text('언어 학습 모드'),
                subtitle: const Text('문장별 번역 및 핀인 제공'),
                value: TextProcessingMode.languageLearning,
                groupValue: _textProcessingMode,
                onChanged: (value) {
                  Navigator.pop(context);
                  if (value != null) {
                    _changeTextProcessingMode(value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  // 플래시카드 생성
  Future<void> _createFlashCard(String front, String back,
      {String? pinyin}) async {
    if (_isCreatingFlashCard) return;

    setState(() {
      _isCreatingFlashCard = true;
    });

    try {
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

      await _flashCardService.createFlashCard(
        front: front,
        back: finalBack,
        pinyin: finalPinyin,
        noteId: widget.noteId,
      );

      // 노트 다시 로드하여 카운터 업데이트
      await _loadNote();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('플래시카드가 추가되었습니다')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('플래시카드 추가 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingFlashCard = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _note != null
            ? GestureDetector(
                onTap: _showEditTitleDialog,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        _note!.originalText,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit, size: 16),
                  ],
                ),
              )
            : const Text('노트 상세'),
        actions: [
          if (_note != null) ...[
            // 플래시카드 카운터 및 버튼
            if (_note!.flashcardCount > 0 || (_note!.flashCards.isNotEmpty))
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => FlashCardScreen(noteId: _note!.id),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.school, size: 16, color: Colors.blue),
                      const SizedBox(width: 4),
                      Text(
                        '${_note!.flashcardCount > 0 ? _note!.flashcardCount : _note!.flashCards.length}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            IconButton(
              icon: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? Colors.red : null,
              ),
              onPressed: _toggleFavorite,
              tooltip: '즐겨찾기',
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _showMoreOptions,
              tooltip: '더 보기',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const LoadingIndicator(message: '노트 불러오는 중...')
          : _error != null
              ? Center(
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
                )
              : _note == null
                  ? const Center(child: Text('노트를 찾을 수 없습니다.'))
                  : _buildNoteContent(),
    );
  }

  Widget _buildNoteContent() {
    if (_pages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_alt_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('페이지가 없습니다.', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('이 노트에는 페이지가 없습니다.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 페이지 인디케이터 (여러 페이지가 있는 경우)
        if (_pages.length > 1)
          PageIndicatorWidget(
            currentPageIndex: _currentPageIndex,
            totalPages: _pages.length,
            onPageChanged: _changePage,
          ),

        // 현재 페이지 내용
        Expanded(
          child: GestureDetector(
            // 좌우 스와이프로 페이지 전환
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;

              // 오른쪽에서 왼쪽으로 스와이프 (다음 페이지)
              if (details.primaryVelocity! < 0 &&
                  _currentPageIndex < _pages.length - 1) {
                _changePage(_currentPageIndex + 1);
              }
              // 왼쪽에서 오른쪽으로 스와이프 (이전 페이지)
              else if (details.primaryVelocity! > 0 && _currentPageIndex > 0) {
                _changePage(_currentPageIndex - 1);
              }
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: _buildCurrentPageContent(),
            ),
          ),
        ),
      ],
    );
  }

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
      return Center(
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
    );
  }
}
