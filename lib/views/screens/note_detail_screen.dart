import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../services/note_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/dictionary_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_content_widget.dart';
import '../../widgets/page_indicator_widget.dart';
import 'flashcard_screen.dart';

class NoteDetailScreen extends StatefulWidget {
  final String noteId;

  const NoteDetailScreen({Key? key, required this.noteId}) : super(key: key);

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  final NoteService _noteService = NoteService();
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final FlashCardService _flashCardService = FlashCardService();

  Note? _note;
  List<page_model.Page> _pages = [];
  List<File?> _imageFiles = [];
  bool _isLoading = true;
  String? _error;
  bool _isFavorite = false;
  int _currentPageIndex = 0;
  bool _isCreatingFlashCard = false;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final note = await _noteService.getNoteById(widget.noteId);

      if (mounted) {
        setState(() {
          _note = note;
          _isFavorite = note?.isFavorite ?? false;
        });

        // 페이지 로드
        await _loadPages();
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

  Future<void> _loadPages() async {
    if (_note == null) return;

    try {
      // 노트에 연결된 페이지 로드
      final pages = await _pageService.getPagesForNote(_note!.id!);

      debugPrint('노트 ${_note!.id}의 페이지 ${pages.length}개 로드됨');

      if (mounted) {
        setState(() {
          _pages = pages;
          _imageFiles = List.filled(pages.length, null);
          _isLoading = false;
        });

        // 각 페이지의 이미지 로드
        _loadPageImages();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '페이지를 불러오는 중 오류가 발생했습니다: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPageImages() async {
    for (int i = 0; i < _pages.length; i++) {
      final page = _pages[i];
      if (page.imageUrl == null || page.imageUrl!.isEmpty) continue;

      try {
        if (mounted) {
          setState(() {
            _imageFiles[i] = null;
          });
        }

        final imageFile = await _imageService.getImageFile(page.imageUrl);
        if (mounted) {
          setState(() {
            _imageFiles[i] = imageFile;
          });
        }
      } catch (e) {
        debugPrint('이미지 로드 중 오류 발생: $e');
      }
    }
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 제목 변경'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: '제목',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
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

    setState(() {
      _isLoading = true;
    });

    try {
      // 노트 객체 복사 및 제목 업데이트
      final updatedNote = _note!.copyWith(
        originalText: newTitle,
        updatedAt: DateTime.now(),
      );

      // Firestore 업데이트
      await _noteService.updateNote(_note!.id!, updatedNote);

      // 상태 업데이트
      if (mounted) {
        setState(() {
          _note = updatedNote;
          _isLoading = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('노트 제목이 변경되었습니다.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('노트 제목 변경 중 오류가 발생했습니다: $e')));
      }
    }
  }

  void _changePage(int index) {
    if (index >= 0 && index < _pages.length) {
      setState(() {
        _currentPageIndex = index;
      });
    }
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('제목 변경'),
            onTap: () {
              Navigator.pop(context);
              _showEditTitleDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('노트 삭제'),
            onTap: () {
              Navigator.pop(context);
              _confirmDelete();
            },
          ),
        ],
      ),
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
            ? Text(_note!.originalText, overflow: TextOverflow.ellipsis)
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
          child: _buildCurrentPageContent(),
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

    return PageContentWidget(
      page: currentPage,
      imageFile: imageFile,
      isLoadingImage: isLoadingImage,
      noteId: widget.noteId,
      onCreateFlashCard: _createFlashCard,
    );
  }
}
