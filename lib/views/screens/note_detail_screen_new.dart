import 'package:flutter/material.dart';
import '../../models/note.dart';
import '../../models/page.dart' as pika_page;
import '../../managers/page_manager.dart';
import '../../widgets/dot_loading_indicator.dart';
import '../../widgets/page_content_widget.dart';
import '../../managers/content_manager.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../widgets/common/pika_app_bar.dart';
import '../../models/flash_card.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../managers/note_options_manager.dart';
import '../../widgets/note_action_bottom_sheet.dart';
import '../../widgets/edit_title_dialog.dart';
import '../../services/content/note_service.dart';
import '../../views/screens/flashcard_screen.dart';

/// 노트 상세 화면 (개선된 버전)
class NoteDetailScreenNew extends StatefulWidget {
  final String noteId;
  final Note? initialNote;

  const NoteDetailScreenNew({
    Key? key,
    required this.noteId,
    this.initialNote,
  }) : super(key: key);

  // 라우트 생성 메서드
  static Route<dynamic> route({required Note note}) {
     print("🚀 Navigating to NoteDetailScreenNew for note: ${note.id}");
    return MaterialPageRoute(
      builder: (context) => NoteDetailScreenNew(
        noteId: note.id!,
        initialNote: note, // 초기 노트 전달 (pages는 null일 수 있음)
      ),
    );
  }

  @override
  _NoteDetailScreenNewState createState() => _NoteDetailScreenNewState();
}

class _NoteDetailScreenNewState extends State<NoteDetailScreenNew> with AutomaticKeepAliveClientMixin {
  late PageManager _pageManager;
  late PageController _pageController;
  final ContentManager _contentManager = ContentManager();
  final NoteOptionsManager _noteOptionsManager = NoteOptionsManager();
  final NoteService _noteService = NoteService();
  Note? _currentNote;
  List<pika_page.Page>? _pages;
  bool _isLoading = true;
  String? _error;
  int _currentPageIndex = 0;
  bool _isProcessingSegments = false;
  Timer? _processingTimer;
  List<FlashCard> _flashCards = [];
  // 페이지 컨텐츠 위젯 관련 상태
  Map<String, bool> _processedPageStatus = {};
  bool _shouldUpdateUI = true; // 화면 업데이트 제어 플래그
  bool _isFullTextMode = false; // 전체 텍스트 모드 상태

  @override
  bool get wantKeepAlive => true; // AutomaticKeepAliveClientMixin 구현

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint("🏁 NoteDetailScreenNew initState: noteId=${widget.noteId}");
    }
    _currentNote = widget.initialNote;
    _pageController = PageController(initialPage: _currentPageIndex);

    _pageManager = PageManager(
      noteId: widget.noteId,
      initialNote: widget.initialNote,
      useCacheFirst: false,
    );

    // 플래시카드 데이터 로드
    _loadFlashcards();

    // 첫 프레임 빌드 후에 페이지 로드 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
       if (mounted) {
         _loadInitialPages();
       }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    if (_processingTimer != null) {
      _processingTimer!.cancel();
      _processingTimer = null;
      if (kDebugMode) {
        debugPrint("⏱️ 처리 타이머 취소됨");
      }
    }
    super.dispose();
  }

  // 사용량 데이터 처리 중 불필요한 UI 업데이트를 방지
  void _pauseUIUpdates() {
    _shouldUpdateUI = false;
  }

  void _resumeUIUpdates() {
    _shouldUpdateUI = true;
  }

  Future<void> _loadInitialPages() async {
    if (kDebugMode) {
      debugPrint("🔄 NoteDetailScreenNew: _loadInitialPages 시작");
    }
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // forceRefresh: true로 항상 서버/캐시에서 로드 시도
      final pages = await _pageManager.loadPagesFromServer(forceRefresh: true);
      
      // 마운트 확인 및 상태 업데이트
      if (!mounted) return;
      
      // 로드된 페이지가 없으면 빈 리스트로 설정하여 로딩 상태 해제
      if (pages.isEmpty) {
        if (kDebugMode) {
          debugPrint("⚠️ NoteDetailScreenNew: 로드된 페이지가 없습니다.");
        }
        setState(() {
          _pages = pages;
          _isLoading = false;
        });
        return;
      }
      
      // 페이지 처리 상태를 미리 확인하여 처리 필요 여부 결정
      bool needsProcessing = false;
      if (pages.isNotEmpty) {
        try {
          final firstPage = pages.first;
          final processedText = await _contentManager.getProcessedText(firstPage.id!);
          needsProcessing = processedText == null || 
                           (processedText.segments == null || processedText.segments!.isEmpty);
          if (kDebugMode) {
            debugPrint("🔍 첫 페이지 처리 필요 여부: $needsProcessing");
          }
          
          // 페이지 처리 상태 기록
          if (firstPage.id != null) {
            _processedPageStatus[firstPage.id!] = !needsProcessing;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint("⚠️ 페이지 처리 상태 확인 중 오류: $e");
          }
          needsProcessing = true;
        }
      }
      
      _pauseUIUpdates(); // 불필요한 UI 업데이트 방지 시작
      
      setState(() {
        _pages = pages;
        _isLoading = false;
        if (kDebugMode) {
          debugPrint("✅ NoteDetailScreenNew: 페이지 로드 완료 (${pages.length}개)");
        }
      });
      
      // UI 업데이트 재개를 지연시켜 불필요한 업데이트 방지
      Future.delayed(Duration(milliseconds: 500), () {
        _resumeUIUpdates();
      });
      
      // 페이지 로드 후 세그먼트 처리가 필요한 경우에만 시작
      if (needsProcessing) {
        _startSegmentProcessing();
      } else {
        if (kDebugMode) {
          debugPrint("✅ 모든 페이지가 이미 처리되어 있어 세그먼트 처리 건너뜀");
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint("❌ NoteDetailScreenNew: 페이지 로드 중 오류: $e");
        debugPrint("Stack Trace: $stackTrace");
      }
      if (mounted) {
        setState(() {
          _error = "페이지 로드 실패: $e";
          _isLoading = false;
        });
      }
    }
  }

  void _startSegmentProcessing() {
    if (_pages == null || _pages!.isEmpty) return;
    
    _isProcessingSegments = true; // setState 없이 상태만 설정
    
    // 첫 번째 페이지부터 순차적으로 세그먼트 처리
    _processPageSegments(_currentPageIndex);
    
    // 3초마다 세그먼트 처리 상태 확인
    _processingTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      if (!_isProcessingSegments) {
        timer.cancel();
        _processingTimer = null;
        if (kDebugMode) {
          debugPrint("⏱️ 처리 타이머 종료됨: 모든 세그먼트 처리 완료");
        }
      }
    });
    
    if (kDebugMode) {
      debugPrint("⏱️ 세그먼트 처리 타이머 시작됨 (3초 간격)");
    }
  }
  
  Future<void> _processPageSegments(int pageIndex) async {
    if (_pages == null || pageIndex >= _pages!.length) {
      _isProcessingSegments = false; // setState 없이 플래그만 업데이트
      return;
    }
    
    try {
      final page = _pages![pageIndex];
      if (kDebugMode) {
        debugPrint("🔄 페이지 ${pageIndex + 1} 세그먼트 처리 시작: ${page.id}");
      }
      
      // 이미 처리된 페이지인지 확인
      if (page.id != null && _processedPageStatus[page.id!] == true) {
        if (kDebugMode) {
          debugPrint("✅ 페이지 ${pageIndex + 1}는 이미 처리되어 있어 건너뜁니다.");
        }
        // 다음 페이지로 진행
        if (pageIndex < _pages!.length - 1) {
          _processPageSegments(pageIndex + 1);
        } else {
          _isProcessingSegments = false;
        }
        return;
      }
      
      // ContentManager를 통해 페이지 텍스트 처리
      final processedText = await _contentManager.processPageText(
        page: page,
        imageFile: null,
      );
      
      // 세그먼트 처리 결과 확인
      if (processedText != null) {
        if (kDebugMode) {
          debugPrint("✅ 페이지 ${pageIndex + 1} 세그먼트 처리 완료 - 결과: ${processedText.segments?.length ?? 0}개 세그먼트");
        }
        // 페이지 처리 상태 업데이트
        if (page.id != null) {
          _processedPageStatus[page.id!] = true;
        }
      } else {
        if (kDebugMode) {
          debugPrint("⚠️ 페이지 ${pageIndex + 1} 세그먼트 처리 결과가 null입니다");
        }
      }
      
      if (mounted) {
        if (kDebugMode) {
          debugPrint("✅ 페이지 ${pageIndex + 1} 세그먼트 처리 완료");
        }
        
        // 다음 페이지 처리 (필요한 경우)
        if (pageIndex < _pages!.length - 1) {
          _processPageSegments(pageIndex + 1);
        } else {
          _isProcessingSegments = false; // setState 없이 상태만 업데이트
          
          // 모든 페이지 처리 완료 후 화면 새로고침은 필요한 경우에만 실행
          if (mounted && _currentPageIndex == 0 && _shouldUpdateUI) { // 첫 페이지이고 UI 업데이트가 허용된 경우에만
            Future.delayed(Duration(milliseconds: 500), () {
              if (mounted) setState(() {});
            });
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 페이지 세그먼트 처리 중 오류: $e");
      }
      if (mounted) {
        _isProcessingSegments = false; // setState 없이 상태만 업데이트
      }
    }
  }

  void _onPageChanged(int index) {
    if (!mounted || _pages == null || index >= _pages!.length || _currentPageIndex == index) return;
    
    setState(() {
      _currentPageIndex = index;
    });
    if (kDebugMode) {
      debugPrint("📄 페이지 변경됨: $_currentPageIndex");
    }
    
    // 페이지가 변경될 때 해당 페이지의 세그먼트가 처리되지 않았다면 처리 시작
    if (_pages != null && index < _pages!.length) {
      final page = _pages![index];
      _checkAndProcessPageIfNeeded(page);
    }
  }
  
  void _checkAndProcessPageIfNeeded(pika_page.Page page) async {
    if (page.id == null) return;
    
    // 이미 처리 상태를 알고 있는 경우 체크 스킵
    if (_processedPageStatus.containsKey(page.id!) && _processedPageStatus[page.id!] == true) {
      if (kDebugMode) {
        debugPrint("✅ 페이지 ${page.id}는 이미 처리되어 있어 다시 처리하지 않습니다.");
      }
      return;
    }
    
    try {
      // 이미 처리된 세그먼트가 있는지 확인
      final processedText = await _contentManager.getProcessedText(page.id!);
      if (processedText != null && processedText.segments != null && processedText.segments!.isNotEmpty) {
        // 처리된 세그먼트가 있으면 상태 업데이트
        _processedPageStatus[page.id!] = true;
        if (kDebugMode) {
          debugPrint("✅ 페이지 ${page.id}는 이미 처리되어 있습니다: ${processedText.segments!.length}개 세그먼트");
        }
        return;
      }
      
      if (processedText == null) {
        // 처리된 세그먼트가 없으면 처리 시작
        if (kDebugMode) {
          debugPrint("🔄 현재 페이지 세그먼트 처리 시작: ${page.id}");
        }
        _pauseUIUpdates(); // UI 업데이트 일시 중지
        
        _contentManager.processPageText(
          page: page,
          imageFile: null,
        ).then((result) {
          if (result != null) {
            if (kDebugMode) {
              debugPrint("✅ 처리 완료: ${result.segments?.length ?? 0}개 세그먼트");
            }
            // 페이지 처리 상태 업데이트
            _processedPageStatus[page.id!] = true;
            
            // 딜레이 후 UI 업데이트 재개 및 화면 갱신
            Future.delayed(Duration(milliseconds: 300), () {
              _resumeUIUpdates();
              // 현재 페이지인 경우에만 화면 갱신
              if (mounted && _pages != null && _currentPageIndex < _pages!.length && 
                  _pages![_currentPageIndex].id == page.id && _shouldUpdateUI) {
                setState(() {});
              }
            });
          }
        }).catchError((e) {
          if (kDebugMode) {
            debugPrint("❌ 처리 중 오류 발생: $e");
          }
          _resumeUIUpdates();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 세그먼트 처리 확인 중 오류: $e");
      }
      _resumeUIUpdates();
    }
  }
  
  // 플래시카드 데이터 로드
  Future<void> _loadFlashcards() async {
    try {
      // 노트에 속한 플래시카드 로드
      if (kDebugMode) {
        debugPrint("📚 노트 ${widget.noteId}의 플래시카드 로드 시작");
      }
      
      // noteService를 통해 플래시카드 목록 가져오기
      final flashcards = await _noteService.getFlashcardsByNoteId(widget.noteId);
      
      if (mounted) {
        setState(() {
          _flashCards = flashcards;
        });
        
        if (kDebugMode) {
          debugPrint("📚 노트 ${widget.noteId}의 플래시카드 ${_flashCards.length}개 로드 완료");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 플래시카드 로드 중 오류: $e");
      }
    }
  }

  // 플래시카드 생성 핸들러
  void _handleCreateFlashCard(String originalText, String translatedText, {String? pinyin}) {
    // 플래시카드 생성 로직
    final newFlashCard = FlashCard(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      front: originalText,
      back: translatedText,
      pinyin: pinyin ?? '',
      noteId: widget.noteId,
      createdAt: DateTime.now(),
    );
    
    // 플래시카드 저장
    _saveFlashcard(newFlashCard);
    
    // 상태 업데이트
    setState(() {
      _flashCards.add(newFlashCard);
    });
    
    if (kDebugMode) {
      debugPrint("📝 플래시카드 생성: $originalText - $translatedText");
      debugPrint("📊 현재 플래시카드 수: ${_flashCards.length}");
    }
    
    // 노트의 플래시카드 카운터 업데이트
    _updateNoteFlashcardCount();
  }
  
  // 플래시카드 저장
  Future<void> _saveFlashcard(FlashCard flashcard) async {
    try {
      // 플래시카드 서비스를 통해 저장
      await _noteService.saveFlashcard(flashcard);
      
      if (kDebugMode) {
        debugPrint("✅ 플래시카드 저장 완료: ${flashcard.id}");
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 플래시카드 저장 중 오류: $e");
      }
    }
  }
  
  // 노트의 플래시카드 카운터 업데이트
  Future<void> _updateNoteFlashcardCount() async {
    if (_currentNote == null || _currentNote!.id == null) return;
    
    try {
      // 현재 노트 정보 가져오기
      final note = await _noteService.getNoteById(_currentNote!.id!);
      if (note == null) return;
      
      // 플래시카드 카운트 업데이트
      final updatedNote = note.copyWith(flashcardCount: _flashCards.length);
      await _noteService.updateNote(updatedNote.id!, updatedNote);
      
      // 현재 노트 정보 업데이트
      setState(() {
        _currentNote = updatedNote;
      });
      
      if (kDebugMode) {
        debugPrint("✅ 노트 플래시카드 카운트 업데이트: ${_flashCards.length}");
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 노트 플래시카드 카운트 업데이트 실패: $e");
      }
    }
  }
  
  // 더보기 메뉴 처리
  void _handleMoreButtonPressed() {
    if (_currentNote == null) return;
    
    // 바텀시트 표시
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NoteActionBottomSheet(
        isFullTextMode: _isFullTextMode,
        isFavorite: _currentNote?.isFavorite ?? false,
        onToggleFullTextMode: _toggleFullTextMode,
        onToggleFavorite: _toggleFavorite,
        onEditTitle: _showEditTitleDialog,
        onDeleteNote: _confirmDeleteNote,
      ),
    );
  }
  
  // 전체 텍스트 모드 토글
  void _toggleFullTextMode() {
    setState(() {
      _isFullTextMode = !_isFullTextMode;
    });
    
    if (kDebugMode) {
      debugPrint("🔤 전체 텍스트 모드 변경: $_isFullTextMode");
    }
  }
  
  // 즐겨찾기 토글
  void _toggleFavorite() async {
    if (_currentNote == null || _currentNote!.id == null) return;
    
    final newValue = !(_currentNote?.isFavorite ?? false);
    final success = await _noteOptionsManager.toggleFavorite(_currentNote!.id!, newValue);
    
    if (success) {
      setState(() {
        _currentNote = _currentNote!.copyWith(isFavorite: newValue);
      });
      
      if (kDebugMode) {
        debugPrint("⭐ 즐겨찾기 상태 변경: $newValue");
      }
    }
  }
  
  // 제목 편집 다이얼로그 표시
  void _showEditTitleDialog() {
    if (_currentNote == null) return;
    
    showDialog(
      context: context,
      builder: (context) => EditTitleDialog(
        currentTitle: _currentNote!.originalText,
        onTitleUpdated: (newTitle) async {
          final success = await _noteOptionsManager.updateNoteTitle(_currentNote!.id!, newTitle);
          if (success && mounted) {
            // 노트 정보 다시 로드
            final updatedNote = await _noteService.getNoteById(_currentNote!.id!);
            setState(() {
              _currentNote = updatedNote;
            });
            
            if (kDebugMode) {
              debugPrint("✏️ 노트 제목 변경: $newTitle");
            }
          }
        },
      ),
    );
  }
  
  // 노트 삭제 확인
  void _confirmDeleteNote() {
    if (_currentNote == null || _currentNote!.id == null) return;
    
    _noteOptionsManager.confirmDelete(
      context, 
      _currentNote!.id!, 
      onDeleted: () {
        // 화면 닫기
        Navigator.of(context).pop();
        
        if (kDebugMode) {
          debugPrint("🗑️ 노트 삭제 완료");
        }
      },
    );
  }
  
  // 플래시카드 화면으로 이동
  void _navigateToFlashcards() {
    if (_flashCards.isEmpty) {
      // 플래시카드가 없는 경우 안내 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장된 플래시카드가 없습니다. 먼저 플래시카드를 추가해주세요.')),
      );
      return;
    }
    
    if (kDebugMode) {
      debugPrint("📚 플래시카드 화면으로 이동");
    }
    
    // 플래시카드 화면으로 이동
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(
          noteId: widget.noteId,
          initialFlashcards: _flashCards, // 미리 로드된 플래시카드 목록 전달
        ),
      ),
    ).then((result) {
      // 플래시카드 화면에서 돌아왔을 때 데이터 갱신
      if (result != null && result is Map && result.containsKey('flashcardCount')) {
        final int count = result['flashcardCount'] as int;
        
        setState(() {
          if (result.containsKey('flashcards')) {
            _flashCards = List<FlashCard>.from(result['flashcards'] ?? []);
          }
        });
        
        // 노트 플래시카드 카운트 업데이트
        _updateNoteFlashcardCountWithValue(count);
        
        if (kDebugMode) {
          debugPrint("🔄 플래시카드 화면에서 돌아옴: 카운트=$count");
        }
      } else {
        // 결과가 없어도 최신 데이터로 갱신
        _loadFlashcards();
      }
    });
  }
  
  // 노트의 플래시카드 카운터 직접 값 지정 업데이트
  Future<void> _updateNoteFlashcardCountWithValue(int count) async {
    if (_currentNote == null || _currentNote!.id == null) return;
    
    try {
      // 현재 노트 정보 가져오기
      final note = await _noteService.getNoteById(_currentNote!.id!);
      if (note == null) return;
      
      // 플래시카드 카운트 업데이트
      final updatedNote = note.copyWith(flashcardCount: count);
      await _noteService.updateNote(updatedNote.id!, updatedNote);
      
      // 현재 노트 정보 업데이트
      setState(() {
        _currentNote = updatedNote;
      });
      
      if (kDebugMode) {
        debugPrint("✅ 노트 플래시카드 카운트 명시적 업데이트: $count");
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 노트 플래시카드 카운트 업데이트 실패: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 요구사항
    if (kDebugMode) {
      debugPrint("🧱 NoteDetailScreenNew build: isLoading=$_isLoading, pages=${_pages?.length ?? 0}, error=$_error");
    }
    
    return Scaffold(
      appBar: PikaAppBar.noteDetail(
        title: _currentNote?.originalText ?? widget.initialNote?.originalText ?? '노트 로딩 중...',
        currentPage: _pages != null && _pages!.isNotEmpty ? _currentPageIndex + 1 : 0,
        totalPages: _pages?.length ?? 0,
        flashcardCount: _flashCards.length,
        onMorePressed: _handleMoreButtonPressed,
        onFlashcardTap: _navigateToFlashcards,
        onBackPressed: () {
          Navigator.of(context).pop();
        },
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: DotLoadingIndicator(message: '페이지 로딩 중...'));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '오류 발생: $_error',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_pages == null || _pages!.isEmpty) {
      return Center(
        child: Text(
          '표시할 페이지가 없습니다.',
          style: TypographyTokens.body1,
        ),
      );
    }

    // 위젯 캐싱을 위한 변수
    final List<Widget> pageWidgets = List.generate(_pages!.length, (index) {
      final page = _pages![index];
      
      // 특수 처리 마커가 있는지 확인
      if (page.originalText == "___PROCESSING___") {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DotLoadingIndicator(message: '텍스트 처리를 기다리는 중...'),
              Text(
                '이 페이지는 아직 처리 중입니다.\n잠시 후 자동으로 업데이트됩니다.',
                textAlign: TextAlign.center,
                style: TypographyTokens.body2,
              ),
            ],
          ),
        );
      }
      
      // 비동기적으로 처리된 텍스트 확인 (백그라운드에서)
      if (page.id != null && !_processedPageStatus.containsKey(page.id!)) {
        Future.microtask(() => _checkProcessedTextStatus(page));
      }

      // 메모이제이션을 위해 ValueKey 사용 및 RepaintBoundary로 감싸기
      return RepaintBoundary(
        child: PageContentWidget(
          key: ValueKey('page_content_${page.id}'),
          page: page,
          imageFile: null,
          isLoadingImage: false,
          noteId: widget.noteId,
          onCreateFlashCard: _handleCreateFlashCard,
          flashCards: _flashCards,
          useSegmentMode: !_isFullTextMode, // 전체 텍스트 모드 여부에 따라 설정
        ),
      );
    });

    return PageView(
      controller: _pageController,
      onPageChanged: _onPageChanged,
      children: pageWidgets,
    );
  }

  // 처리된 텍스트 상태 확인 함수
  void _checkProcessedTextStatus(pika_page.Page page) async {
    if (page.id == null) {
      if (kDebugMode) {
        debugPrint("⚠️ 페이지 ID가 null입니다");
      }
      return;
    }
    
    // 이미 확인된 페이지는 건너뛰기
    if (_processedPageStatus.containsKey(page.id!) && _processedPageStatus[page.id!] == true) {
      return;
    }
    
    // 특수 처리 마커("___PROCESSING___")가 있는지 확인하고 건너뛰기
    if (page.originalText == "___PROCESSING___") {
      if (kDebugMode) {
        debugPrint("⚠️ 페이지 ${page.id}에 특수 처리 마커가 있습니다");
      }
      return;
    }
    
    try {
      final processedText = await _contentManager.getProcessedText(page.id!);
      if (processedText != null) {
        if (kDebugMode) {
          debugPrint("✅ 페이지 ${page.id}의 처리된 텍스트가 있습니다: ${processedText.segments?.length ?? 0}개 세그먼트");
        }
        
        // 세그먼트가 비어있는지 확인
        if (processedText.segments == null || processedText.segments!.isEmpty) {
          if (kDebugMode) {
            debugPrint("⚠️ 페이지 ${page.id}의 세그먼트가 비어 있습니다. 처리 다시 시도");
          }
          // 처리 상태 기록 안함 (빈 세그먼트는 제대로 처리되지 않은 것으로 간주)
        } else {
          // 정상적으로 처리된 페이지 기록
          _processedPageStatus[page.id!] = true;
        }
      } else {
        if (kDebugMode) {
          debugPrint("❌ 페이지 ${page.id}의 처리된 텍스트가 없습니다 - 세그먼트 처리 필요");
        }
        
        // 현재 UI 업데이트가 일시 중지된 상태인지 확인
        bool wasUpdatesPaused = !_shouldUpdateUI;
        
        if (!wasUpdatesPaused) {
          _pauseUIUpdates(); // UI 업데이트 일시 중지
        }
        
        // 처리된 텍스트가 없으면 처리 시작
        _contentManager.processPageText(
          page: page,
          imageFile: null,
        ).then((result) {
          if (result != null) {
            if (kDebugMode) {
              debugPrint("✅ 처리 완료: ${result.segments?.length ?? 0}개 세그먼트");
            }
            // 처리 상태 기록
            _processedPageStatus[page.id!] = true;
            
            // 업데이트를 일시 중지한 경우만 재개
            if (!wasUpdatesPaused) {
              Future.delayed(Duration(milliseconds: 300), () {
                _resumeUIUpdates();
                // 현재 페이지인 경우에만 화면 갱신
                if (mounted && _pages != null && _currentPageIndex < _pages!.length && 
                    _pages![_currentPageIndex].id == page.id && _shouldUpdateUI) {
                  setState(() {});
                }
              });
            }
          } else {
            if (kDebugMode) {
              debugPrint("❌ 처리 결과가 null입니다");
            }
            // 업데이트를 일시 중지한 경우만 재개
            if (!wasUpdatesPaused) {
              _resumeUIUpdates();
            }
          }
        }).catchError((e) {
          if (kDebugMode) {
            debugPrint("❌ 처리 중 오류 발생: $e");
          }
          // 업데이트를 일시 중지한 경우만 재개
          if (!wasUpdatesPaused) {
            _resumeUIUpdates();
          }
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ 처리된 텍스트 확인 중 오류 발생: $e");
      }
    }
  }
} 