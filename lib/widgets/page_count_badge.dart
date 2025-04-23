import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/theme/tokens/color_tokens.dart';
import '../core/theme/tokens/typography_tokens.dart';
import '../core/theme/tokens/spacing_tokens.dart';
import '../core/theme/tokens/ui_tokens.dart';

/// 노트의 페이지 개수를 보여주는 배지 위젯
/// 
/// FlashcardCounterBadge와 유사하지만 페이지 수를 표시합니다.
/// 서버에서 실시간으로 페이지 수를 가져와 표시합니다.
class PageCountBadge extends StatefulWidget {
  final String? noteId;
  final int initialCount;
  
  const PageCountBadge({
    Key? key,
    required this.noteId,
    required this.initialCount,
  }) : super(key: key);

  @override
  State<PageCountBadge> createState() => _PageCountBadgeState();
}

class _PageCountBadgeState extends State<PageCountBadge> {
  int _pageCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    // 초기값 설정 (1 이상)
    _pageCount = widget.initialCount > 0 ? widget.initialCount : 1;
    
    // 백그라운드에서 페이지 수 업데이트
    _loadPageCount();
  }
  
  @override
  void didUpdateWidget(PageCountBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // noteId나 initialCount가 변경되면 다시 로드
    if (oldWidget.noteId != widget.noteId || 
        oldWidget.initialCount != widget.initialCount) {
      // 새 initialCount가 더 크면 즉시 업데이트
      if (widget.initialCount > _pageCount) {
        _pageCount = widget.initialCount;
      }
      
      // 데이터 재로드
      _loadPageCount();
    }
  }
  
  /// 페이지 수를 Firestore에서 로드
  Future<void> _loadPageCount() async {
    if (widget.noteId == null || widget.noteId!.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    
    try {
      // 노트 문서 가져오기
      final noteDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId)
          .get();
          
      if (!mounted) return;
      
      if (noteDoc.exists) {
        final data = noteDoc.data();
        if (data != null) {
          int? serverCount;
          
          // 페이지 카운트 필드들을 우선순위에 따라 확인
          if (data['totalPageCount'] is int && data['totalPageCount'] > 0) {
            serverCount = data['totalPageCount'];
          } else if (data['pages'] is List && (data['pages'] as List).isNotEmpty) {
            serverCount = (data['pages'] as List).length;
          } else if (data['imageCount'] is int && data['imageCount'] > 0) {
            serverCount = data['imageCount'];
          }
          
          // 서버에서 가져온 값이 있고 현재 값보다 크면 업데이트
          if (serverCount != null && serverCount > _pageCount) {
            setState(() {
              _pageCount = serverCount!;
              _isLoading = false;
            });
          } else {
            setState(() => _isLoading = false);
          }
          return;
        }
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('페이지 수 로드 중 오류 발생: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: SpacingTokens.xs,
        vertical: SpacingTokens.xs / 4,
      ),
      decoration: BoxDecoration(
        color: ColorTokens.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(SpacingTokens.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_stories,
            size: 10,
            color: ColorTokens.primary,
          ),
          SizedBox(width: 2),
          Text(
            _isLoading 
                ? '로딩 중...' 
                : '$_pageCount 페이지',
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: ColorTokens.primary,
            ),
          ),
        ],
      ),
    );
  }
} 