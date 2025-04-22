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

class _NoteDetailScreenNewState extends State<NoteDetailScreenNew> {
  late PageManager _pageManager;
  late PageController _pageController;
  final ContentManager _contentManager = ContentManager();
  Note? _currentNote;
  List<pika_page.Page>? _pages;
  bool _isLoading = true;
  String? _error;
  int _currentPageIndex = 0;
  bool _isProcessingSegments = false;
  Timer? _processingTimer;
  List<FlashCard> _flashCards = [];

  @override
  void initState() {
    super.initState();
    debugPrint("🏁 NoteDetailScreenNew initState: noteId=${widget.noteId}");
    _currentNote = widget.initialNote;
    _pageController = PageController(initialPage: _currentPageIndex);

    _pageManager = PageManager(
      noteId: widget.noteId,
      initialNote: widget.initialNote,
       useCacheFirst: false,
    );

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
    }
    super.dispose();
  }

  Future<void> _loadInitialPages() async {
    debugPrint("🔄 NoteDetailScreenNew: _loadInitialPages 시작");
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // forceRefresh: true로 항상 서버/캐시에서 로드 시도
      final pages = await _pageManager.loadPagesFromServer(forceRefresh: true);
      if (mounted) {
        setState(() {
          _pages = pages;
          _isLoading = false;
          debugPrint("✅ NoteDetailScreenNew: 페이지 로드 완료 (${pages.length}개)");
        });
        // 페이지 로드 후 세그먼트 처리 시작
        _startSegmentProcessing();
      }
    } catch (e, stackTrace) {
      debugPrint("❌ NoteDetailScreenNew: 페이지 로드 중 오류: $e");
      debugPrint("Stack Trace: $stackTrace");
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
    
    setState(() {
      _isProcessingSegments = true;
    });
    
    // 첫 번째 페이지부터 순차적으로 세그먼트 처리
    _processPageSegments(_currentPageIndex);
    
    // 3초마다 세그먼트 처리 상태 확인
    _processingTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      if (!_isProcessingSegments) {
        timer.cancel();
        _processingTimer = null;
      }
    });
  }
  
  Future<void> _processPageSegments(int pageIndex) async {
    if (_pages == null || pageIndex >= _pages!.length) {
      setState(() {
        _isProcessingSegments = false;
      });
      return;
    }
    
    try {
      final page = _pages![pageIndex];
      debugPrint("🔄 페이지 ${pageIndex + 1} 세그먼트 처리 시작: ${page.id}");
      
      // ContentManager를 통해 페이지 텍스트 처리
      final processedText = await _contentManager.processPageText(
        page: page,
        imageFile: null, // 명시적으로 null을 전달하여 이미지 파일이 없음을 표시
      );
      
      // 세그먼트 처리 결과 확인
      if (processedText != null) {
        debugPrint("✅ 페이지 ${pageIndex + 1} 세그먼트 처리 완료 - 결과: ${processedText.segments?.length ?? 0}개 세그먼트");
      } else {
        debugPrint("⚠️ 페이지 ${pageIndex + 1} 세그먼트 처리 결과가 null입니다");
      }
      
      if (mounted) {
        debugPrint("✅ 페이지 ${pageIndex + 1} 세그먼트 처리 완료");
        
        // 다음 페이지 처리 (필요한 경우)
        if (pageIndex < _pages!.length - 1) {
          _processPageSegments(pageIndex + 1);
        } else {
          setState(() {
            _isProcessingSegments = false;
            // 모든 페이지 처리 완료 후 화면 새로고침
            if (mounted) {
              Future.delayed(Duration(milliseconds: 500), () {
                if (mounted) setState(() {});
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint("❌ 페이지 세그먼트 처리 중 오류: $e");
      if (mounted) {
        setState(() {
          _isProcessingSegments = false;
        });
      }
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPageIndex = index;
    });
    print("페이지 변경됨: $_currentPageIndex");
    
    // 페이지가 변경될 때 해당 페이지의 세그먼트가 처리되지 않았다면 처리 시작
    if (_pages != null && index < _pages!.length) {
      final page = _pages![index];
      _checkAndProcessPageIfNeeded(page);
    }
  }
  
  void _checkAndProcessPageIfNeeded(pika_page.Page page) async {
    try {
      // 이미 처리된 세그먼트가 있는지 확인
      final processedText = await _contentManager.getProcessedText(page.id!);
      if (processedText == null) {
        // 처리된 세그먼트가 없으면 처리 시작
        debugPrint("🔄 현재 페이지 세그먼트 처리 시작: ${page.id}");
        _contentManager.processPageText(
          page: page,
          imageFile: null, // 명시적으로 null을 전달하여 이미지 파일이 없음을 표시
        );
      }
    } catch (e) {
      debugPrint("❌ 세그먼트 처리 확인 중 오류: $e");
    }
  }
  
  // 플래시카드 생성 핸들러
  void _handleCreateFlashCard(String originalText, String translatedText, {String? pinyin}) {
    // 플래시카드 추가 로직 구현 (실제 구현은 추후 필요)
    debugPrint("플래시카드 생성: $originalText - $translatedText");
  }

  @override
  Widget build(BuildContext context) {
     debugPrint("🧱 NoteDetailScreenNew build: isLoading=$_isLoading, pages=${_pages?.length ?? 0}, error=$_error");
    return Scaffold(
      appBar: PikaAppBar(
        title: widget.initialNote?.originalText ?? _currentNote?.originalText ?? '노트 로딩 중...',
        actions: [
          // 수동 새로고침 버튼 추가 (디버깅용)
          IconButton(
            icon: const Icon(Icons.refresh, color: ColorTokens.textSecondary),
            onPressed: () {
              debugPrint("수동 새로고침 버튼 클릭");
              if (_pages != null && _currentPageIndex < _pages!.length) {
                _checkAndProcessPageIfNeeded(_pages![_currentPageIndex]);
                setState(() {}); // 화면 강제 새로고침
              }
            },
          ),
        ],
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

    return PageView.builder(
      controller: _pageController,
      itemCount: _pages!.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final page = _pages![index];
       
        // 특수 처리 마커("___PROCESSING___")가 있는지 확인
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
        
        // 처리된 텍스트가 있는지 확인하기 위한 로그 추가
        _checkProcessedTextStatus(page);

        // PageContentWidget 사용하여 페이지 콘텐츠 표시
        return PageContentWidget(
          key: ValueKey('page_content_${page.id}_${DateTime.now().millisecondsSinceEpoch}'), // 키 추가하여 재생성 강제
          page: page,
          imageFile: null, // 이미지는 이미 처리 완료된 상태
          isLoadingImage: false,
          noteId: widget.noteId,
          onCreateFlashCard: _handleCreateFlashCard,
          flashCards: _flashCards,
          useSegmentMode: true, // 세그먼트 모드 활성화
        );
      },
    );
  }

  // 처리된 텍스트 상태 확인 함수
  void _checkProcessedTextStatus(pika_page.Page page) async {
    if (page.id == null) {
      debugPrint("⚠️ 페이지 ID가 null입니다");
      return;
    }
    
    // 특수 처리 마커("___PROCESSING___")가 있는지 확인하고 건너뛰기
    if (page.originalText == "___PROCESSING___") {
      debugPrint("⚠️ 페이지 ${page.id}에 특수 처리 마커가 있습니다");
      return;
    }
    
    try {
      final processedText = await _contentManager.getProcessedText(page.id!);
      if (processedText != null) {
        debugPrint("✅ 페이지 ${page.id}의 처리된 텍스트가 있습니다: ${processedText.segments?.length ?? 0}개 세그먼트");
        
        // 세그먼트가 비어있는지 확인
        if (processedText.segments == null || processedText.segments!.isEmpty) {
          debugPrint("⚠️ 페이지 ${page.id}의 세그먼트가 비어 있습니다. 처리 다시 시도");
          // 페이지 처리 다시 시도 (자동 처리 대기)
          debugPrint("⌛ 페이지 자동 처리 대기 중");
        }
      } else {
        debugPrint("❌ 페이지 ${page.id}의 처리된 텍스트가 없습니다 - 세그먼트 처리 필요");
        // 처리된 텍스트가 없으면 처리 시작
        _contentManager.processPageText(
          page: page,
          imageFile: null,
        ).then((result) {
          if (result != null) {
            debugPrint("✅ 처리 완료: ${result.segments?.length ?? 0}개 세그먼트");
            // 화면 갱신
            if (mounted) setState(() {});
          } else {
            debugPrint("❌ 처리 결과가 null입니다");
          }
        }).catchError((e) {
          debugPrint("❌ 처리 중 오류 발생: $e");
        });
      }
    } catch (e) {
      debugPrint("❌ 처리된 텍스트 확인 중 오류 발생: $e");
    }
  }
} 