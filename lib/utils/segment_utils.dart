import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';

/// 텍스트 세그먼트 관련 유틸리티를 제공하는 클래스
class SegmentUtils {
  /// 세그먼트 삭제를 위한 Dismissible 위젯을 생성합니다.
  /// 
  /// [key] - 위젯의 고유 키
  /// [child] - Dismissible로 감싸질 위젯
  /// [onDelete] - 삭제 콜백 함수
  /// [confirmDismiss] - 삭제 확인 여부를 반환하는 함수 (기본값 제공)
  static Widget buildDismissibleSegment({
    required Key key,
    required Widget child,
    required Function onDelete,
    DismissDirection direction = DismissDirection.endToStart,
    Future<bool?> Function(DismissDirection)? confirmDismiss,
    BorderRadius? borderRadius,
  }) {
    return Dismissible(
      key: key,
      direction: direction,
      background: Container(
        alignment: direction == DismissDirection.endToStart 
            ? Alignment.centerRight 
            : Alignment.centerLeft,
        padding: direction == DismissDirection.endToStart 
            ? const EdgeInsets.only(right: 20.0)
            : const EdgeInsets.only(left: 20.0),
        decoration: BoxDecoration(
          color: ColorTokens.deleteSwipeBackground,
          borderRadius: borderRadius,
        ),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      behavior: HitTestBehavior.opaque,
      movementDuration: const Duration(milliseconds: 200),
      confirmDismiss: confirmDismiss ?? ((direction) async {
        // 기본 확인 다이얼로그
        return await showDialog<bool>(
          context: _getApplicationContext(),
          builder: (context) => AlertDialog(
            title: const Text('세그먼트 삭제'),
            content: const Text('이 세그먼트를 삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('삭제'),
                style: TextButton.styleFrom(foregroundColor: ColorTokens.error),
              ),
            ],
          ),
        ) ?? false;
      }),
      onDismissed: (_) => onDelete(),
      child: child,
    );
  }

  // 현재 앱의 BuildContext를 얻기 위한 헬퍼 메서드
  static BuildContext _getApplicationContext() {
    // GlobalKey를 통해 context를 가져올 수도 있지만, 
    // 여기서는 간단히 Navigator.of(context) 호출 시점에 context가 제공된다고 가정합니다.
    // 실제 사용 시에는 호출자가 context를 전달해야 합니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('AlertDialog Builder에 context가 필요합니다. 이 함수는 context가 제공된 상태에서 호출해야 합니다.');
    });
    
    // 여기서 빈 BuildContext를 반환하면 오류가 발생할 수 있으므로,
    // confirmDismiss 콜백을 사용할 때는 context를 명시적으로 전달하는 것이 좋습니다.
    throw UnimplementedError('confirmDismiss 콜백을 직접 제공하세요.');
  }
} 