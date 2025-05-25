import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/note.dart';
import '../../../core/utils/date_formatter.dart';
import '../flashcard/flashcard_counter_badge.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 홈페이지 노트리스트 화면에서 사용되는 카드 위젯
class NoteListItem extends StatelessWidget {
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

  String _getFormattedDate() {
    final noteDate = note.createdAt;
    if (noteDate == null) {
      return '날짜 없음';
    }
    return DateFormatter.formatDate(noteDate);
  }

  @override
  Widget build(BuildContext context) {
    // 디버깅: 첫 번째 이미지 URL 확인
    if (kDebugMode) {
      print('노트 리스트 아이템 빌드: ${note.id} - firstImageUrl: ${note.firstImageUrl}');
    }
    
    return Dismissible(
      key: Key(note.id ?? ''),
      background: Container(
        decoration: BoxDecoration(
          color: ColorTokens.errorBackground,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.all(24),
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
        onDismissed();
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
                debugPrint('노트 아이템 탭됨: id=${note.id ?? "없음"}, 제목=${note.title}');
              }
              
              // 노트 ID가 null이거나 비어있는 경우 처리
              if (note.id == null || note.id!.isEmpty) {
                if (kDebugMode) {
                  debugPrint('⚠️ 경고: 유효하지 않은 노트 ID');
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('유효하지 않은 노트 ID입니다.')),
                );
                return;
              }
              
              // 정상적인 경우 노트 객체 전체를 전달
              onNoteTapped(note);
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
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 썸네일 이미지 (기본 이미지 표시)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: note.firstImageUrl != null && note.firstImageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: note.firstImageUrl!,
                          fit: BoxFit.cover,
                          width: 80,
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
                              print('이미지 로드 오류 ($url): $error');
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
                          width: 80,
                          height: 80,
                        ),
                ),
                const SizedBox(width: 16.0),
                // 노트 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title.isEmpty ? '제목 없음' : note.title,
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
                      Row(
                        children: [
                          Text(
                            _getFormattedDate(),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.0,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF969696),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      if (note.flashcardCount > 0)
                        FlashcardCounterBadge(
                          count: note.flashcardCount,
                          noteId: note.id,
                          flashcards: null,
                          sampleNoteTitle: null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}