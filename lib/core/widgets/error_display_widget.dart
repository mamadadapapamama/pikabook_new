import 'package:flutter/material.dart';
import '../utils/error_handler.dart';
import '../theme/tokens/typography_tokens.dart';
import 'pika_button.dart';
import 'dot_loading_indicator.dart';

/// ErrorHandler와 연동되는 에러 표시 위젯
/// 
/// 로딩 상태와 에러 상태를 자동으로 전환하여 표시합니다.
class ErrorDisplayWidget extends StatelessWidget {
  final String errorId;
  final Widget? loadingWidget;
  final String? loadingMessage;
  final Widget? child;
  final bool showLoadingByDefault;

  const ErrorDisplayWidget({
    Key? key,
    required this.errorId,
    this.loadingWidget,
    this.loadingMessage,
    this.child,
    this.showLoadingByDefault = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final errorState = ErrorHandler.getError(errorId);
    
    // 에러가 있는 경우 에러 위젯 표시
    if (errorState != null) {
      return _buildErrorWidget(context, errorState);
    }
    
    // 자식 위젯이 있으면 표시
    if (child != null) {
      return child!;
    }
    
    // 기본 로딩 위젯 표시
    if (showLoadingByDefault) {
      return loadingWidget ?? _buildDefaultLoadingWidget();
    }
    
    // 아무것도 표시하지 않음
    return const SizedBox.shrink();
  }

  /// 에러 위젯 빌드
  Widget _buildErrorWidget(BuildContext context, ErrorState errorState) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            if (errorState.icon != null) ...[
              Icon(
                errorState.icon!,
                color: errorState.iconColor ?? Colors.grey,
                size: 48,
              ),
              const SizedBox(height: 16),
            ],
            
            // 에러 메시지
            Text(
              errorState.message,
              style: TypographyTokens.body2.copyWith(
                color: errorState.messageColor ?? Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            
            // 재시도 버튼
            if (ErrorHandler.hasRetryCallback(errorId)) ...[
              const SizedBox(height: 24),
              PikaButton(
                text: errorState.retryButtonText ?? '다시 시도',
                variant: PikaButtonVariant.text,
                onPressed: () => ErrorHandler.retry(errorId),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 기본 로딩 위젯
  Widget _buildDefaultLoadingWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: DotLoadingIndicator(
          message: loadingMessage ?? '처리 중입니다...',
        ),
      ),
    );
  }
}

/// 간단한 에러 표시 위젯 (직접 사용)
class SimpleErrorWidget extends StatelessWidget {
  final String message;
  final Color? messageColor;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onRetry;
  final String? retryButtonText;

  const SimpleErrorWidget({
    Key? key,
    required this.message,
    this.messageColor,
    this.icon,
    this.iconColor,
    this.onRetry,
    this.retryButtonText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            if (icon != null) ...[
              Icon(
                icon!,
                color: iconColor ?? Colors.grey,
                size: 48,
              ),
              const SizedBox(height: 16),
            ],
            
            // 에러 메시지
            Text(
              message,
              style: TypographyTokens.body2.copyWith(
                color: messageColor ?? Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            
            // 재시도 버튼
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              PikaButton(
                text: retryButtonText ?? '다시 시도',
                variant: PikaButtonVariant.text,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
} 