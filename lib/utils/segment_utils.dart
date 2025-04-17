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
    return PhysicalModel(
      color: Colors.transparent,
      borderRadius: borderRadius ?? BorderRadius.zero,
      clipBehavior: Clip.antiAlias,
      child: Dismissible(
        key: key,
        direction: direction,
        background: PhysicalModel(
          color: ColorTokens.deleteSwipeBackground,
          borderRadius: borderRadius ?? BorderRadius.zero,
          clipBehavior: Clip.antiAlias,
          child: Container(
            alignment: direction == DismissDirection.endToStart
                ? Alignment.centerRight
                : Alignment.centerLeft,
            padding: direction == DismissDirection.endToStart
                ? const EdgeInsets.only(right: 20.0)
                : const EdgeInsets.only(left: 20.0),
            color: ColorTokens.deleteSwipeBackground,
            child: const Icon(
              Icons.delete,
              color: Colors.white,
            ),
          ),
        ),
        behavior: HitTestBehavior.opaque,
        movementDuration: const Duration(milliseconds: 200),
        confirmDismiss: confirmDismiss ?? ((direction) async {
          // 기본 확인 다이얼로그
          try {
            return await showDialog<bool>(
              context: _getApplicationContext(),
              builder: (context) => AlertDialog(
                title: const Text('항목 삭제'),
                content: const Text('이 항목을 삭제하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('삭제'),
                    style: TextButton.styleFrom(foregroundColor: ColorTokens.primary),
                  ),
                ],
              ),
            ) ?? false;
          } catch (e) {
            debugPrint('다이얼로그 표시 중 오류 발생: $e');
            return false;
          }
        }),
        onDismissed: (_) => onDelete(),
        child: child,
      ),
    );
  }

  // 현재 앱의 BuildContext를 얻기 위한 헬퍼 메서드
  static BuildContext _getApplicationContext() {
    // 여기서는 간단히 Navigator.of(context) 호출 시점에 context가 제공된다고 가정합니다.
    // 실제 사용 시에는 호출자가 context를 전달해야 합니다.
    throw UnimplementedError('confirmDismiss 콜백을 직접 제공하세요.');
  }
} 