import 'package:flutter/material.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../utils/error_handler.dart';
import 'pika_button.dart';

/// 인라인 에러 위젯
/// 특정 영역에 임베드되어 표시되는 에러 위젯
/// 
/// 사용 위치:
/// - 노트 생성 이전: 스낵바 대신 사용
/// - OCR 처리 중: '텍스트를 번역하고 있습니다' 메시지를 replace
/// - LLM 처리 중: '텍스트를 분석하고 있습니다' 메시지를 replace
/// - 기존 노트 로드 중: 홈 스낵바 대신 사용
class InlineErrorWidget extends StatelessWidget {
  /// 에러 메시지
  final String message;
  
  /// 에러 아이콘 (기본: Icons.error_outline)
  final IconData? icon;
  
  /// 에러 아이콘 색상
  final Color? iconColor;
  
  /// 메시지 텍스트 색상
  final Color? messageColor;
  
  /// 다시 시도 콜백 (null이면 다시 시도 버튼 숨김)
  final VoidCallback? onRetry;
  
  /// 나가기 콜백 (null이면 나가기 버튼 숨김)
  final VoidCallback? onExit;
  
  /// 다시 시도 버튼 텍스트 (기본: '다시 시도')
  final String? retryButtonText;
  
  /// 나가기 버튼 텍스트 (기본: '나가기')
  final String? exitButtonText;
  
  /// 컴팩트 모드 (작은 영역에 표시할 때)
  final bool isCompact;
  
  /// 배경색 (기본: 투명)
  final Color? backgroundColor;
  
  /// 패딩 (기본: 16.0)
  final EdgeInsets? padding;

  const InlineErrorWidget({
    Key? key,
    required this.message,
    this.icon,
    this.iconColor,
    this.messageColor,
    this.onRetry,
    this.onExit,
    this.retryButtonText,
    this.exitButtonText,
    this.isCompact = false,
    this.backgroundColor,
    this.padding,
  }) : super(key: key);

  /// 중국어 감지 실패 전용 생성자
  /// 다시 시도가 불가능하므로 나가기 버튼만 표시
  factory InlineErrorWidget.chineseDetectionFailed({
    required VoidCallback onExit,
    bool isCompact = false,
  }) {
    return InlineErrorWidget(
      message: ErrorHandler.getErrorMessage(ErrorType.chineseDetectionFailed),
      icon: Icons.translate_outlined,
      iconColor: Colors.orange,
      messageColor: Colors.orange[800],
      onExit: onExit,
      exitButtonText: '나가기',
      isCompact: isCompact,
    );
  }

  /// 타임아웃 에러 전용 생성자
  /// 다시 시도 가능
  factory InlineErrorWidget.timeout({
    required VoidCallback onRetry,
    bool isCompact = false,
  }) {
    return InlineErrorWidget(
      message: ErrorHandler.getErrorMessage(ErrorType.timeout, ErrorContext.ocr),
      icon: Icons.access_time,
      iconColor: Colors.red,
      messageColor: Colors.red[800],
      onRetry: onRetry,
      retryButtonText: '다시 시도',
      isCompact: isCompact,
    );
  }

  /// 네트워크 에러 전용 생성자
  /// 다시 시도 가능
  factory InlineErrorWidget.network({
    required VoidCallback onRetry,
    bool isCompact = false,
  }) {
    return InlineErrorWidget(
      message: ErrorHandler.getErrorMessage(ErrorType.network),
      icon: Icons.wifi_off,
      iconColor: Colors.red,
      messageColor: Colors.red[800],
      onRetry: onRetry,
      retryButtonText: '다시 시도',
      isCompact: isCompact,
    );
  }

  /// 텍스트 없음 에러 전용 생성자
  /// 다른 이미지 선택이 필요하므로 나가기 버튼만 표시
  factory InlineErrorWidget.noText({
    required VoidCallback onExit,
    bool isCompact = false,
  }) {
    return InlineErrorWidget(
      message: ErrorHandler.getErrorMessage(ErrorType.noText),
      icon: Icons.text_fields_outlined,
      iconColor: Colors.orange,
      messageColor: Colors.orange[800],
      onExit: onExit,
      exitButtonText: '나가기',
      isCompact: isCompact,
    );
  }

  /// 일반 에러 전용 생성자
  /// 상황에 따라 다시 시도 또는 나가기 버튼 표시
  factory InlineErrorWidget.general({
    String? message,
    VoidCallback? onRetry,
    VoidCallback? onExit,
    bool isCompact = false,
  }) {
    return InlineErrorWidget(
      message: message ?? ErrorHandler.getErrorMessage(ErrorType.general),
      icon: Icons.error_outline,
      iconColor: Colors.red,
      messageColor: Colors.red[800],
      onRetry: onRetry,
      onExit: onExit,
      isCompact: isCompact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ?? EdgeInsets.all(isCompact ? 12.0 : 16.0);
    final iconSize = isCompact ? 32.0 : 48.0;
    final messageStyle = isCompact 
        ? TypographyTokens.body2 
        : TypographyTokens.body1;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 아이콘
        if (icon != null) ...[
          Icon(
            icon!,
            color: iconColor ?? Colors.red,
            size: iconSize,
          ),
          SizedBox(height: isCompact ? 8 : 16),
        ],
        
        // 에러 메시지
        Text(
          message,
          style: messageStyle.copyWith(
            color: messageColor ?? Colors.red[800],
          ),
          textAlign: TextAlign.center,
        ),
        
        // 버튼들
        if (onRetry != null || onExit != null) ...[
          SizedBox(height: isCompact ? 16 : 24),
          _buildButtons(),
        ],
      ],
    );

    // 컴팩트 모드가 아닌 경우 Center로 감싸기
    if (!isCompact) {
      content = Center(child: content);
    }

    return Container(
      padding: effectivePadding,
      decoration: backgroundColor != null
          ? BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8.0),
            )
          : null,
      child: content,
    );
  }

  /// 버튼들 빌드
  Widget _buildButtons() {
    final buttons = <Widget>[];

    // 다시 시도 버튼
    if (onRetry != null) {
      buttons.add(
        PikaButton(
          text: retryButtonText ?? '다시 시도',
          variant: PikaButtonVariant.primary,
          onPressed: onRetry!,
          size: isCompact ? PikaButtonSize.small : PikaButtonSize.medium,
        ),
      );
    }

    // 나가기 버튼
    if (onExit != null) {
      buttons.add(
        PikaButton(
          text: exitButtonText ?? '나가기',
          variant: PikaButtonVariant.text,
          onPressed: onExit!,
          size: isCompact ? PikaButtonSize.small : PikaButtonSize.medium,
        ),
      );
    }

    // 버튼이 하나만 있으면 그대로 반환
    if (buttons.length == 1) {
      return buttons.first;
    }

    // 버튼이 두 개 있으면 Row로 배치
    if (buttons.length == 2) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          buttons[0],
          SizedBox(width: isCompact ? 8 : 12),
          buttons[1],
        ],
      );
    }

    // 버튼이 없으면 빈 위젯
    return const SizedBox.shrink();
  }
}

/// 로딩 상태와 에러 상태를 자동으로 전환하는 인라인 위젯
/// 기존 ErrorDisplayWidget의 인라인 버전
class InlineLoadingErrorWidget extends StatelessWidget {
  /// 로딩 메시지
  final String? loadingMessage;
  
  /// 로딩 위젯 (기본: DotLoadingIndicator)
  final Widget? loadingWidget;
  
  /// 에러 위젯 빌더
  final Widget Function(String error)? errorWidgetBuilder;
  
  /// 현재 에러 메시지 (null이면 로딩 상태)
  final String? error;
  
  /// 컴팩트 모드
  final bool isCompact;
  
  /// 다시 시도 콜백
  final VoidCallback? onRetry;
  
  /// 나가기 콜백
  final VoidCallback? onExit;

  const InlineLoadingErrorWidget({
    Key? key,
    this.loadingMessage,
    this.loadingWidget,
    this.errorWidgetBuilder,
    this.error,
    this.isCompact = false,
    this.onRetry,
    this.onExit,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 에러가 있는 경우 에러 위젯 표시
    if (error != null) {
      if (errorWidgetBuilder != null) {
        return errorWidgetBuilder!(error!);
      }
      
      // 중국어 감지 실패 체크 - 나가기만 가능
      if (error!.contains('중국어가 없습니다')) {
        return InlineErrorWidget.chineseDetectionFailed(
          onExit: onExit ?? () {},
          isCompact: isCompact,
        );
      }
      
      // 타임아웃 에러 체크 - 다시 시도 가능
      if (error!.contains('타임아웃') || error!.contains('timeout')) {
        return InlineErrorWidget.timeout(
          onRetry: onRetry ?? () {},
          isCompact: isCompact,
        );
      }
      
      // 네트워크 에러 체크 - 다시 시도 가능
      if (error!.contains('네트워크') || error!.contains('인터넷') || error!.contains('연결')) {
        return InlineErrorWidget.network(
          onRetry: onRetry ?? () {},
          isCompact: isCompact,
        );
      }
      
      // 텍스트 없음 에러 체크 - 다른 이미지로 다시 시도 가능
      if (error!.contains('번역할 텍스트가 없습니다')) {
        return InlineErrorWidget.noText(
          onExit: onExit ?? () {},
          isCompact: isCompact,
        );
      }
      
      // 일반 에러 - 상황에 따라 버튼 표시
      return InlineErrorWidget.general(
        message: error,
        onRetry: onRetry,
        onExit: onExit,
        isCompact: isCompact,
      );
    }
    
    // 로딩 상태 표시
    if (loadingWidget != null) {
      return loadingWidget!;
    }
    
    // 기본 로딩 위젯
    return Container(
      padding: EdgeInsets.all(isCompact ? 12.0 : 16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: isCompact ? 20 : 24,
            height: isCompact ? 20 : 24,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          if (loadingMessage != null) ...[
            SizedBox(height: isCompact ? 8 : 12),
            Text(
              loadingMessage!,
              style: (isCompact ? TypographyTokens.body2 : TypographyTokens.body1).copyWith(
                color: ColorTokens.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
} 