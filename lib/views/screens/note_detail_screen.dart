import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../services/note_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
import '../../services/tts_service.dart';
import '../../utils/date_formatter.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_widget.dart';

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
  final TtsService _ttsService = TtsService();

  Note? _note;
  List<page_model.Page> _pages = [];
  List<File?> _imageFiles = [];
  bool _isLoading = true;
  String? _error;
  bool _isFavorite = false;
  bool _isSpeaking = false;
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadNote();
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }

  Future<void> _initTts() async {
    try {
      await _ttsService.init();
    } catch (e) {
      debugPrint('TTS 초기화 중 오류 발생: $e');
    }
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
        // 이미지 로딩 상태 표시
        if (mounted) {
          setState(() {
            // 이미지 로딩 중임을 표시하는 플래그 추가
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

  Future<void> _speakCurrentPage() async {
    if (_pages.isEmpty || _currentPageIndex >= _pages.length) return;

    final currentPage = _pages[_currentPageIndex];
    final textToSpeak = currentPage.translatedText.isNotEmpty
        ? currentPage.translatedText
        : currentPage.originalText;

    if (textToSpeak.isEmpty) return;

    setState(() {
      _isSpeaking = true;
    });

    try {
      await _ttsService.speak(textToSpeak);
    } catch (e) {
      debugPrint('TTS 실행 중 오류 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성 재생 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _stopSpeaking() async {
    if (!_isSpeaking) return;

    try {
      await _ttsService.stop();
      setState(() {
        _isSpeaking = false;
      });
    } catch (e) {
      debugPrint('TTS 중지 중 오류 발생: $e');
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('즐겨찾기 설정 중 오류가 발생했습니다: $e')),
        );
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 삭제 중 오류가 발생했습니다: $e')),
        );
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

  void _changePage(int index) {
    if (index >= 0 && index < _pages.length) {
      setState(() {
        _currentPageIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('노트 상세'),
        actions: [
          if (_note != null) ...[
            IconButton(
              icon: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? Colors.red : null,
              ),
              onPressed: _toggleFavorite,
              tooltip: '즐겨찾기',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
              tooltip: '삭제',
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
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
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
    return Column(
      children: [
        // 노트 헤더
        _buildNoteHeader(),

        // 페이지 인디케이터 (여러 페이지가 있는 경우)
        if (_pages.length > 1) _buildPageIndicator(),

        // 현재 페이지 내용
        Expanded(
          child: _pages.isEmpty
              ? _buildLegacyNoteContent() // 기존 노트 형식 지원
              : _buildPageContent(),
        ),

        // 하단 액션 버튼
        if (_note!.flashCards.isNotEmpty) _buildActionButtons(),
      ],
    );
  }

  Widget _buildNoteHeader() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _showEditTitleDialog,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _note!.originalText,
                            style: Theme.of(context).textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit, size: 16),
                      ],
                    ),
                  ),
                ),
                Text(
                  DateFormatter.formatDateTime(_note!.updatedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_note!.tags.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _note!.tags
                    .map((tag) => Chip(
                          label: Text(tag),
                          backgroundColor: Colors.blue[50],
                          labelStyle: const TextStyle(fontSize: 12),
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
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

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노트 제목이 변경되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 제목 변경 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Widget _buildPageIndicator() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          // 페이지 번호 표시
          Text(
            '${_currentPageIndex + 1}/${_pages.length} 페이지',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          // 페이지 인디케이터
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                final isSelected = index == _currentPageIndex;
                return GestureDetector(
                  onTap: () => _changePage(index),
                  child: Container(
                    width: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(color: Colors.blue.shade700, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent() {
    if (_pages.isEmpty || _currentPageIndex >= _pages.length) {
      return const Center(
        child: Text('페이지 내용이 없습니다.'),
      );
    }

    final currentPage = _pages[_currentPageIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (currentPage.imageUrl != null && currentPage.imageUrl!.isNotEmpty)
          Center(
            child:
                _imageFiles.isNotEmpty && _imageFiles[_currentPageIndex] != null
                    ? Image.file(
                        _imageFiles[_currentPageIndex]!,
                        fit: BoxFit.contain,
                        height: 200,
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 200,
                            width: double.infinity,
                            color: Colors.grey[200],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('이미지 로딩 중...'),
                            ],
                          ),
                        ],
                      ),
          ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '원본 텍스트',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: Icon(
                        _isSpeaking ? Icons.stop : Icons.volume_up,
                        color: Theme.of(context).primaryColor,
                      ),
                      onPressed:
                          _isSpeaking ? _stopSpeaking : _speakCurrentPage,
                      tooltip: _isSpeaking ? '음성 중지' : '음성으로 듣기',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  currentPage.originalText,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (currentPage.translatedText.isNotEmpty)
          Card(
            elevation: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '번역 텍스트',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentPage.translatedText,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLegacyNoteContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_note!.imageUrl != null && _note!.imageUrl!.isNotEmpty) ...[
            FutureBuilder<File?>(
              future: _imageService.getImageFile(_note!.imageUrl),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    snapshot.data == null) {
                  return Container(
                    height: 150,
                    width: double.infinity,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Text('이미지를 불러올 수 없습니다.'),
                    ),
                  );
                }

                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    snapshot.data!,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          _buildTextSection('원문 (중국어)', _note!.originalText, 'zh-CN'),
          const SizedBox(height: 16),
          _buildTextSection('번역 (한국어)', _note!.translatedText, 'ko-KR'),
        ],
      ),
    );
  }

  Widget _buildTextSection(String title, String content, String language) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: Icon(
                    _isSpeaking ? Icons.stop : Icons.volume_up,
                    size: 24,
                    color: _isSpeaking ? Colors.red : Colors.blue,
                  ),
                  onPressed: () => _speakCurrentPage(),
                  tooltip: _isSpeaking ? '중지' : '소리 듣기',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                content,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              // TODO: 플래시카드 학습 화면으로 이동
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('플래시카드 기능은 추후 업데이트 예정입니다.')),
              );
            },
            icon: const Icon(Icons.school),
            label: const Text('플래시카드 학습'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
