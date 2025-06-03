import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/note.dart';
import '../../../core/utils/date_formatter.dart';
import '../flashcard/flashcard_counter_badge.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 홈페이지 노트리스트 화면에서 사용되는 카드 위젯
class NoteListItem extends StatefulWidget {
  final Note note;
  final Function() onDismissed;
  final Function(Note note) onNoteTapped;
  final bool isFilteredList;

  const NoteListItem({
    super.key,
    required this.note,
    required this.onDismissed,
    required this.onNoteTapped,
    this.isFilteredList = false,
  });

  @override
  State<NoteListItem> createState() => _NoteListItemState();
}

class _NoteListItemState extends State<NoteListItem> with AutomaticKeepAliveClientMixin {
  Note? _previousNote;
  Widget? _cachedWidget;
  bool _isVisible = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _previousNote = widget.note;
    
    // 초기에는 간단한 placeholder만 생성
    _cachedWidget = _buildPlaceholder();
    
    // 다음 프레임에서 실제 위젯 빌드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isVisible = true;
          _cachedWidget = _buildNoteCard();
        });
      }
    });
  }

  @override
  void didUpdateWidget(NoteListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Note 객체가 실제로 변경되었는지 확인
    if (_hasNoteChanged(oldWidget.note, widget.note)) {
      if (kDebugMode) {
        debugPrint('노트 리스트 아이템 업데이트: ${widget.note.id} - 실제 변경 감지됨');
      }
      _previousNote = widget.note;
      if (_isVisible) {
        _cachedWidget = _buildNoteCard();
      }
    }
  }

  /// Note 객체가 변경되었는지 확인 (최적화된 버전)
  bool _hasNoteChanged(Note oldNote, Note newNote) {
    // 자주 변경되는 UI 중요 필드만 체크
    return oldNote.id != newNote.id ||
           oldNote.title != newNote.title ||
           oldNote.flashcardCount != newNote.flashcardCount ||
           oldNote.pageCount != newNote.pageCount;
  }

  String _getFormattedDate() {
    final noteDate = widget.note.createdAt;
    if (noteDate == null) {
      return '날짜 없음';
    }
    
    final dateStr = DateFormatter.formatDateWithMonthAbbr(noteDate);
    final pageCount = widget.note.pageCount;
    final pageText = pageCount == 1 ? 'page' : 'pages';
    
    return '$dateStr | $pageCount $pageText';
  }

  Widget _buildNoteCard() {
    
    return Container(
      height: 116, // 노트리스트 아이템 높이 116
      child: Dismissible(
        key: Key(widget.note.id ?? ''),
        background: Container(
          decoration: BoxDecoration(
            color: ColorTokens.errorBackground,
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: const Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Icon(
                Icons.delete,
                color: Colors.white,
              ),
            ),
          ),
        ),
        direction: DismissDirection.endToStart,
        confirmDismiss: (direction) async {
          return await showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                backgroundColor: ColorTokens.surface,
                title: const Text('노트 삭제'),
                content: const Text('정말로 이 노트를 삭제하시겠습니까?'),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('취소'),
                    style: TextButton.styleFrom(foregroundColor: ColorTokens.textPrimary),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('삭제'),
                    style: TextButton.styleFrom(foregroundColor: ColorTokens.error),
                  ),
                ],
              );
            },
          );
        },
        onDismissed: (direction) {
          widget.onDismissed();
        },
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: const BorderSide(color: ColorTokens.primaryverylight, width: 1.0),
          ),
          color: Colors.white,
          elevation: 0,
          child: InkWell(
            onTap: () {
              try {
                if (kDebugMode) {
                  debugPrint('노트 아이템 탭됨: id=${widget.note.id ?? "없음"}, 제목=${widget.note.title}');
                }
                
                // 노트 ID가 null이거나 비어있는 경우 처리
                if (widget.note.id == null || widget.note.id!.isEmpty) {
                  if (kDebugMode) {
                    debugPrint('⚠️ 경고: 유효하지 않은 노트 ID');
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('유효하지 않은 노트 ID입니다.')),
                  );
                  return;
                }
                
                // 정상적인 경우 노트 객체 전체를 전달
                widget.onNoteTapped(widget.note);
              } catch (e, stackTrace) {
                if (kDebugMode) {
                  debugPrint('❌ 노트 탭 처리 중 오류 발생: $e');
                  debugPrint('스택 트레이스: $stackTrace');
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('노트를 열 수 없습니다: $e')),
                );
              }
            },
            borderRadius: BorderRadius.circular(8.0),
            child: Padding(
              padding: const EdgeInsets.all(16.0), // 내부 패딩 16
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 썸네일 이미지 (80x80)
                  _buildThumbnail(),
                  const SizedBox(width: 16.0), // 썸네일과 텍스트 사이 간격
                  // 노트 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.note.title.isEmpty ? '제목 없음' : widget.note.title,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20.0,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0E2823),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          _getFormattedDate(),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12.0,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF969696),
                          ),
                        ),
                        if (widget.note.flashcardCount > 0) ...[
                          const SizedBox(height: 6.0),
                          FlashcardCounterBadge(
                            count: widget.note.flashcardCount,
                            noteId: widget.note.id,
                            flashcards: null,
                            sampleNoteTitle: null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4.0),
      child: widget.note.firstImageUrl != null && widget.note.firstImageUrl!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: widget.note.firstImageUrl!,
              fit: BoxFit.cover,
              width: 80, // 썸네일 크기 80x80
              height: 80,
              placeholder: (context, url) => Container(
                width: 80,
                height: 80,
                color: Colors.grey[200],
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ColorTokens.primary,
                    ),
                  ),
                ),
              ),
              errorWidget: (context, url, error) {
                if (kDebugMode) {
                  debugPrint('이미지 로드 오류 ($url): $error');
                }
                return Image.asset(
                  'assets/images/thumbnail_empty.png',
                  fit: BoxFit.cover,
                  width: 80,
                  height: 80,
                );
              },
            )
          : Image.asset(
              'assets/images/thumbnail_empty.png',
              fit: BoxFit.cover,
              width: 80, // 썸네일 크기 80x80
              height: 80,
            ),
    );
  }

  /// 간단한 placeholder 위젯 (빠른 초기 렌더링용)
  Widget _buildPlaceholder() {
    return Container(
      height: 120.0, // placeholder도 120 높이로 통일
      margin: const EdgeInsets.fromLTRB(24, 0, 16, 0),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: ColorTokens.primaryverylight, width: 1.0),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: ColorTokens.primary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 필수
    
    // 가시성에 따라 적절한 위젯 반환
    if (!_isVisible) {
      return _buildPlaceholder();
    }
    
    // 캐시된 위젯 반환
    return _cachedWidget ?? _buildNoteCard();
  }
}