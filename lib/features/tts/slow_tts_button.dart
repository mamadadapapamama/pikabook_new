import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/services/authentication/auth_service.dart';
import '../../../core/widgets/upgrade_modal.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../sample/sample_tts_service.dart';
import '../../core/services/tts/slow_tts_service.dart';
import '../../core/services/common/plan_service.dart';
import '../../core/services/common/usage_limit_service.dart';

/// 느린 TTS 버튼을 위한 위젯 (거북이 아이콘 사용)
/// 50% 느린 속도로 재생하며 일시정지 기능을 제공합니다.
class SlowTtsButton extends StatefulWidget {
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
  
  /// 버튼 크기 사전 정의값
  static const double sizeSmall = 20.0;
  static const double sizeMedium = 24.0;
  static const double sizeLarge = 32.0;

  const SlowTtsButton({
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
    this.isEnabled = true,
  }) : super(key: key);

  @override
  State<SlowTtsButton> createState() => _SlowTtsButtonState();
}

class _SlowTtsButtonState extends State<SlowTtsButton> {
  final SlowTtsService _slowTtsService = SlowTtsService();
  final SampleTtsService _sampleTtsService = SampleTtsService();
  final AuthService _authService = AuthService();
  bool _isPlaying = false;
  
  @override
  void initState() {
    super.initState();
    _setupListeners();
  }
  
  // 느린 TTS 상태 변경 리스너 설정
  void _setupListeners() {
    // 재생 상태 변경 리스너
    _slowTtsService.setOnPlayingStateChanged((segmentIndex) {
      if (mounted) {
        // 현재 재생 중인 세그먼트인지 확인
        final bool isThisSegmentPlaying = widget.segmentIndex != null && 
                                         widget.segmentIndex == segmentIndex;
        
        // 상태가 변경된 경우에만 setState 호출
        if (_isPlaying != isThisSegmentPlaying) {
          setState(() {
            _isPlaying = isThisSegmentPlaying;
          });
          
          debugPrint('🐢 느린 TTS 버튼 상태 변경: _isPlaying=$_isPlaying, segmentIndex=$segmentIndex, widget.segmentIndex=${widget.segmentIndex}');
        }
      }
    });
    
    // 재생 완료 리스너
    _slowTtsService.setOnPlayingCompleted(() {
      if (mounted) {
        // 현재 재생 중이거나 이 버튼의 세그먼트가 재생 중이었던 경우 상태 리셋
        if (_isPlaying || _slowTtsService.currentSegmentIndex == widget.segmentIndex) {
          setState(() {
            _isPlaying = false;
          });
          
          debugPrint('🐢 느린 TTS 재생 완료: 버튼 상태 리셋 (segmentIndex=${widget.segmentIndex})');
          
          // 재생 종료 콜백 호출
          if (widget.onPlayEnd != null) {
            widget.onPlayEnd!();
          }
        }
      }
    });
  }
  
  @override
  void didUpdateWidget(SlowTtsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 세그먼트 인덱스가 변경된 경우
    if (oldWidget.segmentIndex != widget.segmentIndex) {
      // 느린 TTS 서비스의 현재 재생 중인 세그먼트와 비교
      final currentPlayingSegment = _slowTtsService.currentSegmentIndex;
      final bool shouldBePlaying = widget.segmentIndex != null && 
                                  widget.segmentIndex == currentPlayingSegment;
      
      // 상태 업데이트
      if (_isPlaying != shouldBePlaying) {
        setState(() {
          _isPlaying = shouldBePlaying;
        });
        
        debugPrint('🐢 세그먼트 인덱스 변경으로 인한 상태 업데이트: _isPlaying=$_isPlaying');
      }
    }
  }
  
  // 느린 TTS 재생 토글
  void _togglePlayback() async {
    if (!widget.isEnabled) return;
    
    // 샘플 모드(로그아웃 상태)에서는 SampleTtsService 사용
    if (_authService.currentUser == null) {
      await _handleSampleModeSlowTts();
      return;
    }
    
    // TTS 사용량 제한 체크
    final usageService = UsageLimitService();
    final limitStatus = await usageService.checkInitialLimitStatus();
    
    if (limitStatus['ttsLimitReached'] == true) {
      if (mounted) {
        await UpgradePromptHelper.showTtsUpgradePrompt(context);
      }
      return;
    }
    
    if (_isPlaying) {
      // 이미 재생 중이면 중지
      _slowTtsService.stop();
      setState(() {
        _isPlaying = false;
      });
      
      // 재생 종료 콜백 호출
      if (widget.onPlayEnd != null) {
        widget.onPlayEnd!();
      }
      
      debugPrint('🐢 느린 TTS 재생 중지 (사용자에 의해)');
    } else {
      // 재생 시작
      setState(() {
        _isPlaying = true;
      });
      
      // 재생 시작 콜백 호출
      if (widget.onPlayStart != null) {
        widget.onPlayStart!();
      }
      
      debugPrint('🐢 🔊 느린 TTS 재생 시작: "${widget.text}"');
      
      try {
        if (widget.segmentIndex != null) {
          // 세그먼트 재생
          await _slowTtsService.speakSegment(widget.text, widget.segmentIndex!);
        } else {
          // 일반 재생
          await _slowTtsService.speak(widget.text);
        }
        
        // 재생 완료 후 상태 업데이트
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
          
          if (widget.onPlayEnd != null) {
            widget.onPlayEnd!();
          }
        }
      } catch (e) {
        debugPrint('🐢 느린 TTS 재생 중 오류: $e');
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
          
          if (widget.onPlayEnd != null) {
            widget.onPlayEnd!();
          }
        }
      }
    }
  }

  /// 샘플 모드에서 느린 TTS 처리 - 스낵바 메시지만 표시
  Future<void> _handleSampleModeSlowTts() async {
    // 샘플 모드에서는 느린 TTS 기능을 지원하지 않음
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("샘플 모드에서는 일부 오디오파일만 지원됩니다. 로그인해서 듣기 기능을 사용해보세요."),
          backgroundColor: ColorTokens.snackbarBg, // dark green 색상으로 변경
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    
  }
  
  
  @override
  Widget build(BuildContext context) {
    // 아이콘 색상 - 활성화 상태에 따라 다르게 설정
    final Color iconColor = widget.isEnabled 
        ? widget.iconColor ?? ColorTokens.snackbarBg 
        : ColorTokens.textGrey.withOpacity(0.5); // 비활성화 시 연한 회색
    
    // 배경색 설정
    final Color backgroundColor = _isPlaying 
        ? widget.activeBackgroundColor ?? ColorTokens.secondaryLight
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
          border: null,
        ),
        child: IconButton(
          icon: _isPlaying 
              ? Icon(
                  Icons.stop,
                  color: iconColor,
                  size: widget.size * 0.5,
                )
              : SvgPicture.asset(
                  'assets/images/icon_turtle.svg',
                  width: widget.size * 0.5,
                  height: widget.size * 0.5,
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                ),
          onPressed: widget.isEnabled ? _togglePlayback : null,
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
        icon: _isPlaying 
            ? Icon(
                Icons.stop,
                color: iconColor,
              )
            : SvgPicture.asset(
                'assets/images/icon_turtle.svg',
                width: widget.size * 0.6,
                height: widget.size * 0.6,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
        iconSize: widget.size * 0.6,
        padding: EdgeInsets.all(widget.size * 0.2),
        constraints: BoxConstraints(
          minWidth: widget.size,
          minHeight: widget.size,
        ),
        onPressed: widget.isEnabled ? _togglePlayback : null,
        splashRadius: widget.size / 2,
        // 재생 중일 때 배경색 적용
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
        ),
      );
    }
    
    // 비활성화된 경우 툴팁 표시
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
    // 상태 정리를 위해 현재 재생 중인 경우 중지
    if (_isPlaying) {
      debugPrint('🐢 SlowTtsButton dispose: 재생 중인 느린 TTS 정리');
      // 동기 작업이 UI를 차단하지 않도록 별도 작업으로 분리
      _isPlaying = false; // 먼저 상태 업데이트
      Future.microtask(() {
        _slowTtsService.stop();
      });
    }
    super.dispose();
  }
} 