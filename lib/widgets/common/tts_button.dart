import 'package:flutter/material.dart';
import '../../services/tts_service.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';

/// TTS 버튼을 위한 공용 위젯
/// 상태에 따라 적절한 스타일과 피드백을 제공합니다.
class TtsButton extends StatefulWidget {
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
  
  /// 버튼 크기 사전 정의값
  static const double sizeSmall = 24.0;
  static const double sizeMedium = 32.0;
  static const double sizeLarge = 40.0;

  const TtsButton({
    Key? key,
    required this.text,
    this.segmentIndex,
    this.size = sizeMedium,
    this.tooltip,
    this.iconColor,
    this.activeBackgroundColor,
    this.onPlayStart,
    this.onPlayEnd,
    this.useCircularShape = true,
  }) : super(key: key);

  @override
  State<TtsButton> createState() => _TtsButtonState();
}

class _TtsButtonState extends State<TtsButton> {
  final TtsService _ttsService = TtsService();
  bool _isPlaying = false;
  bool _isEnabled = true;
  
  @override
  void initState() {
    super.initState();
    _checkTtsAvailability();
    
    // TTS 상태 변경 리스너 등록
    _ttsService.setOnPlayingStateChanged((segmentIndex) {
      if (mounted) {
        setState(() {
          _isPlaying = widget.segmentIndex == segmentIndex;
        });
      }
    });
    
    // TTS 재생 완료 리스너 등록
    _ttsService.setOnPlayingCompleted(() {
      if (mounted) {
        setState(() {
          _isPlaying = false;
        });
        
        // 재생 완료 콜백 호출
        if (widget.onPlayEnd != null) {
          widget.onPlayEnd!();
        }
      }
    });
  }
  
  // TTS 사용 가능 여부 확인
  Future<void> _checkTtsAvailability() async {
    try {
      final isAvailable = await _ttsService.isTtsAvailable();
      if (mounted && _isEnabled != isAvailable) {
        setState(() {
          _isEnabled = isAvailable;
        });
      }
    } catch (e) {
      debugPrint('TTS 버튼 사용 가능 여부 확인 중 오류: $e');
      // 오류 발생 시 기본적으로 활성화 상태 유지
      if (mounted) {
        setState(() {
          _isEnabled = true;
        });
      }
    }
  }
  
  // TTS 재생 토글
  void _togglePlayback() async {
    if (!_isEnabled) return;
    
    if (_isPlaying) {
      // 이미 재생 중이면 중지
      _ttsService.stop();
      setState(() {
        _isPlaying = false;
      });
      
      // 재생 종료 콜백 호출
      if (widget.onPlayEnd != null) {
        widget.onPlayEnd!();
      }
    } else {
      // 재생 시작
      setState(() {
        _isPlaying = true;
      });
      
      // 재생 시작 콜백 호출
      if (widget.onPlayStart != null) {
        widget.onPlayStart!();
      }
      
      try {
        if (widget.segmentIndex != null) {
          await _ttsService.speakSegment(widget.text, widget.segmentIndex!);
        } else {
          await _ttsService.speak(widget.text);
        }
      } catch (e) {
        debugPrint('TTS 재생 중 오류 발생: $e');
        // 오류 발생 시 재생 상태 업데이트
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
          
          // 재생 종료 콜백 호출
          if (widget.onPlayEnd != null) {
            widget.onPlayEnd!();
          }
        }
      }
      
      // 사용량 확인 후 상태 업데이트
      _checkTtsAvailability();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 아이콘 색상 - 활성화 상태에 따라 다르게 설정
    final Color iconColor = _isEnabled 
        ? widget.iconColor ?? ColorTokens.textSecondary 
        : ColorTokens.textGrey.withOpacity(0.5); // 비활성화 시 연한 회색
    
    // 배경색 설정
    final Color backgroundColor = _isPlaying 
        ? widget.activeBackgroundColor ?? ColorTokens.primary.withOpacity(0.1)
        : Colors.transparent;
    
    Widget buttonWidget;
    
    if (widget.useCircularShape) {
      // 원형 버튼 스타일
      buttonWidget = Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: _isEnabled ? ColorTokens.primary.withOpacity(0.2) : Colors.transparent,
            width: 1,
          ),
        ),
        child: IconButton(
          icon: Icon(
            _isPlaying ? Icons.stop : Icons.volume_up,
            color: iconColor,
            size: widget.size * 0.5,
          ),
          onPressed: _isEnabled ? _togglePlayback : null,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(
            minWidth: widget.size,
            minHeight: widget.size,
          ),
          splashRadius: widget.size / 2,
        ),
      );
    } else {
      // 기본 IconButton 스타일
      buttonWidget = IconButton(
        icon: Icon(
          _isPlaying ? Icons.stop : Icons.volume_up,
          color: iconColor,
        ),
        iconSize: widget.size * 0.6,
        padding: EdgeInsets.all(widget.size * 0.2),
        constraints: BoxConstraints(
          minWidth: widget.size,
          minHeight: widget.size,
        ),
        onPressed: _isEnabled ? _togglePlayback : null,
        splashRadius: widget.size / 2,
      );
    }
    
    // 비활성화된 경우 툴팁 표시
    if (!_isEnabled && widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: buttonWidget,
      );
    }
    
    return buttonWidget;
  }
  
  @override
  void dispose() {
    // TTS 서비스에서 리스너 등록 해제는 필요없음 (싱글톤)
    super.dispose();
  }
} 