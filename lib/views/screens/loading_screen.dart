import 'package:flutter/material.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/widgets/dot_loading_indicator.dart';

/// 앱 초기화 중 표시되는 로딩 화면
/// 
/// Primary color 배경에 피카북 로고와 흰색 dot loading indicator를 표시합니다.
class LoadingScreen extends StatelessWidget {
  /// 로딩 상태 메시지 (디버그 모드에서만 표시)
  final String? message;

  const LoadingScreen({
    Key? key,
    this.message,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorTokens.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 피카북 로고
            Image.asset(
              'assets/images/pikabook_textlogo.png',
              width: 120,
              color: Colors.white,
            ),
            const SizedBox(height: 48),
            
            // 흰색 dot loading indicator
            const DotLoadingIndicator(
              dotColor: Colors.white,
              message: null,
            ),
          ],
        ),
      ),
    );
  }
} 