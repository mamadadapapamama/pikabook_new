import 'package:flutter/material.dart';
import '../../../core/services/authentication/auth_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../sample/sample_tts_service.dart';

/// slowTTSbutton 과 TTSbutton 공통 기능을 제공하는 베이스 클래스

abstract class BaseTtsButton extends StatefulWidget {
  /// 재생할 텍스트
  final String text;
  
  /// 세그먼트 인덱스 (세그먼트 재생시에만 사용)
  final int? segmentIndex;
  
  /// 버튼의 크기를 지정
  final double size;
  
  /// 툴팁 메시지 (비활성화 시에만 표시)
  final String? tooltip;
  
  /// 커스텀 아이콘 색상
  final Color? iconColor;
  
  /// 커스텀 활성화 배경색
  final Color? activeBackgroundColor;
  
  /// 커스텀 재생 시작/종료 콜백
  final VoidCallback? onPlayStart;
  final VoidCallback? onPlayEnd;
  
  /// 커스텀 모양 (원형 또는 표준)
  final bool useCircularShape;
  
  /// TTS 활성화 여부 (외부에서 제어)
  final bool isEnabled;

  const BaseTtsButton({
    Key? key,
    required this.text,
    this.segmentIndex,
    this.size = 32.0,
    this.tooltip,
    this.iconColor,
    this.activeBackgroundColor,
    this.onPlayStart,
    this.onPlayEnd,
    this.useCircularShape = true,
    this.isEnabled = true,
  }) : super(key: key);
}

/// TTS 버튼의 공통 상태 관리를 제공하는 베이스 State 클래스
abstract class BaseTtsButtonState<T extends BaseTtsButton> extends State<T> {
  final AuthService authService = AuthService();
  final SampleTtsService _sampleTtsService = SampleTtsService();
  bool isPlaying = false;
  
  /// 각 구현체에서 정의해야 할 메서드들 (최소한만)
  Widget buildIcon(bool isPlaying, Color iconColor, double iconSize);
  Future<void> playTtsInternal(String text, int? segmentIndex);
  Future<void> stopTtsInternal();
  Future<bool> checkUsageLimit() async => true; // 기본값: 제한 없음

  @override
  void initState() {
    super.initState();
    if (authService.currentUser != null) {
      setupListeners();
    }
  }
  
  /// TTS 상태 변경 리스너 설정 (각 구현체에서 오버라이드)
  void setupListeners();
  
  /// 공통 재생 토글 로직
  Future<void> togglePlayback() async {
    if (!widget.isEnabled) return;
    
    if (authService.currentUser == null) {
      await _handleSampleModeTts();
      return;
    }
    
    if (!await checkUsageLimit()) {
      return;
    }
    
    if (isPlaying) {
      await stopTtsInternal();
      setState(() {
        isPlaying = false;
      });
      
      if (widget.onPlayEnd != null) {
        widget.onPlayEnd!();
      }
      
      debugPrint('🛑 TTS 재생 중지 (사용자에 의해, segmentIndex: ${widget.segmentIndex})');
    } else {
      setState(() {
        isPlaying = true;
      });
      
      if (widget.onPlayStart != null) {
        widget.onPlayStart!();
      }
      
      debugPrint('🎯 TTS 재생 시작: "${widget.text}" (segmentIndex: ${widget.segmentIndex})');
      
      try {
        await playTtsInternal(widget.text, widget.segmentIndex);
      } catch (e) {
        debugPrint('TTS 재생 중 오류: $e');
        if (mounted) {
          setState(() {
            isPlaying = false;
          });
          
          if (widget.onPlayEnd != null) {
            widget.onPlayEnd!();
          }
        }
      }
    }
  }
  
  Future<void> _handleSampleModeTts() async {
    if (isPlaying) {
      await _sampleTtsService.stop();
      setState(() {
        isPlaying = false;
      });
      
      if (widget.onPlayEnd != null) {
        widget.onPlayEnd!();
      }
      
      debugPrint('🛑 [Sample] TTS 재생 중지');
    } else {
      setState(() {
        isPlaying = true;
      });
      
      if (widget.onPlayStart != null) {
        widget.onPlayStart!();
      }
      
      debugPrint('🎯 [Sample] TTS 재생 시작: "${widget.text}"');
      
      try {
        await _sampleTtsService.speak(widget.text, context: context);
        
        if (mounted) {
          setState(() {
            isPlaying = false;
          });
          
          if (widget.onPlayEnd != null) {
            widget.onPlayEnd!();
          }
        }
        
        debugPrint('✅ [Sample] TTS 재생 완료');
      } catch (e) {
        debugPrint('❌ [Sample] TTS 재생 실패: $e');
        if (mounted) {
          setState(() {
            isPlaying = false;
          });
          
          if (widget.onPlayEnd != null) {
            widget.onPlayEnd!();
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color iconColor = widget.isEnabled 
        ? widget.iconColor ?? ColorTokens.textSecondary 
        : ColorTokens.textGrey.withOpacity(0.5);
    
    final Color backgroundColor = isPlaying 
        ? widget.activeBackgroundColor ?? ColorTokens.secondaryLight
        : Colors.transparent;
    
    Widget buttonWidget;
    
    if (widget.useCircularShape) {
      buttonWidget = Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: null,
        ),
        child: IconButton(
          icon: buildIcon(isPlaying, iconColor, widget.size * 0.5),
          onPressed: widget.isEnabled ? togglePlayback : null,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: widget.size,
            minHeight: widget.size,
          ),
          splashRadius: widget.size / 2,
        ),
      );
    } else {
      buttonWidget = IconButton(
        icon: buildIcon(isPlaying, iconColor, widget.size * 0.6),
        iconSize: widget.size * 0.6,
        padding: EdgeInsets.all(widget.size * 0.2),
        constraints: BoxConstraints(
          minWidth: widget.size,
          minHeight: widget.size,
        ),
        onPressed: widget.isEnabled ? togglePlayback : null,
        splashRadius: widget.size / 2,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
        ),
      );
    }
    
    if (!widget.isEnabled && widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: buttonWidget,
      );
    }
    
    return buttonWidget;
  }
  
  @override
  void dispose() {
    if (isPlaying) {
      debugPrint('BaseTtsButton dispose: 재생 중인 TTS 정리');
      isPlaying = false;
      Future.microtask(() async {
        if (authService.currentUser == null) {
          await _sampleTtsService.stop();
        } else {
          await stopTtsInternal();
        }
      });
    }
    super.dispose();
  }
} 