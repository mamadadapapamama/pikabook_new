import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';

/// 로딩 상태를 표시하는 인디케이터 위젯
///
/// 로딩 중임을 사용자에게 시각적으로 알려주는 간단한 위젯입니다.
/// 주로 페이지나 화면 내부의 작은 영역에서 작업 진행 중임을 표시하는 데 사용됩니다.
/// 
/// 전체 화면 로딩이나 사용자 액션을 막는 로딩은 LoadingDialog나 PikabookLoader를 사용하세요.
/// 
/// 선택적으로 메시지를 표시할 수 있습니다.
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final double size;
  final Color? color;

  const LoadingIndicator({
    Key? key,
    this.message,
    this.size = 24.0,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 3.0,
              valueColor: AlwaysStoppedAnimation<Color>(
                color ?? ColorTokens.primary,
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
