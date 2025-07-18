import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/services/tts/unified_tts_service.dart';
import '../../core/services/authentication/auth_service.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/services/common/usage_limit_service.dart';
import '../sample/sample_tts_service.dart';
import '../../core/utils/safe_math_utils.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';

/// 통합 TTS 버튼
/// 일반 TTS와 느린 TTS를 하나의 버튼으로 처리
class UnifiedTtsButton extends StatefulWidget {
  /// 재생할 텍스트
  final String text;
  
  /// 세그먼트 인덱스 (세그먼트 재생시에만 사용)
  final int? segmentIndex;
  
  /// TTS 모드 (일반 vs 느린)
  final TtsMode mode;
  
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

  const UnifiedTtsButton({
    Key? key,
    required this.text,
    this.segmentIndex,
    this.mode = TtsMode.normal,
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
  State<UnifiedTtsButton> createState() => _UnifiedTtsButtonState();
}

class _UnifiedTtsButtonState extends State<UnifiedTtsButton> {
  final UnifiedTtsService _ttsService = UnifiedTtsService();
  final SampleTtsService _sampleTtsService = SampleTtsService();
  final AuthService _authService = AuthService();
  final UnifiedSubscriptionManager _subscriptionManager = UnifiedSubscriptionManager();
  
  bool _isPlaying = false;
  
  // 콜백 참조 저장 (dispose 시 제거용)
  Function(int?)? _stateChangedCallback;
  Function()? _completedCallback;

  @override
  void initState() {
    super.initState();
    if (_authService.currentUser != null) {
      _setupListeners();
    }
  }

  /// TTS 상태 변경 리스너 설정
  void _setupListeners() {
    // 콜백 함수 정의 (dispose 시 제거를 위해 참조 저장)
    _stateChangedCallback = (segmentIndex) {
      if (mounted && context.mounted) {
        // 현재 재생 중인 세그먼트인지 확인
        final bool isThisSegmentPlaying;
        
        if (widget.segmentIndex == null && segmentIndex == null) {
          // 둘 다 null이면 일반 텍스트 재생
          isThisSegmentPlaying = true;
        } else if (widget.segmentIndex != null && segmentIndex != null) {
          // 둘 다 값이 있으면 세그먼트 인덱스 비교
          isThisSegmentPlaying = widget.segmentIndex == segmentIndex;
        } else {
          // 하나는 null, 하나는 값이 있으면 다른 버튼
          isThisSegmentPlaying = false;
        }
        
        // 상태가 변경된 경우에만 setState 호출
        if (_isPlaying != isThisSegmentPlaying) {
          try {
            setState(() {
              _isPlaying = isThisSegmentPlaying;
            });
          } catch (e) {
            if (kDebugMode) {
              debugPrint('TTS 버튼 상태 변경 중 setState 오류: $e');
            }
          }
        }
      }
    };
    
    _completedCallback = () {
      if (mounted && context.mounted) {
        // 재생 완료 시에는 모든 버튼이 false로 변경되어야 함
        if (_isPlaying) {
          try {
            setState(() {
              _isPlaying = false;
            });
            
            // 재생 종료 콜백 호출
            if (widget.onPlayEnd != null) {
              Future.microtask(() {
                if (mounted && widget.onPlayEnd != null) {
                  widget.onPlayEnd!();
                }
              });
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('TTS 재생 완료 중 setState 오류: $e');
            }
          }
        }
      }
    };
    
    // 리스너 등록 (모드별)
    _ttsService.setOnPlayingStateChanged(_stateChangedCallback!, mode: widget.mode);
    _ttsService.setOnPlayingCompleted(_completedCallback!, mode: widget.mode);
  }

  /// 재생 토글
  Future<void> _togglePlayback() async {
    if (!widget.isEnabled) return;
    
    // 샘플 모드 처리
    if (_authService.currentUser == null) {
      await _handleSampleModeTts();
      return;
    }
    
    // 사용량 제한 체크
    if (!await _checkUsageLimit()) {
      return;
    }
    
    if (_isPlaying) {
      // 재생 중지
      await _ttsService.stop();
      setState(() {
        _isPlaying = false;
      });
      
      if (widget.onPlayEnd != null) {
        widget.onPlayEnd!();
      }
    } else {
      // 재생 시작
      setState(() {
        _isPlaying = true;
      });
      
      if (widget.onPlayStart != null) {
        widget.onPlayStart!();
      }
      
      try {
        if (widget.segmentIndex != null) {
          await _ttsService.speakSegment(
            widget.text, 
            widget.segmentIndex!, 
            mode: widget.mode
          );
        } else {
          await _ttsService.speak(widget.text, mode: widget.mode);
        }
      } catch (e) {
        debugPrint('TTS 재생 중 오류: $e');
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

  /// 사용량 제한 체크
  Future<bool> _checkUsageLimit() async {
    final usageService = UsageLimitService();
    final subscriptionState = await _subscriptionManager.getSubscriptionState();
    final limitStatus = await usageService.checkInitialLimitStatus(subscriptionState: subscriptionState);
    
    if (limitStatus['ttsLimitReached'] == true) {
      // 사용량 제한 도달 시 처리 (필요시 업그레이드 프롬프트)
      return false;
    }
    return true;
  }

  /// 샘플 모드 TTS 처리
  Future<void> _handleSampleModeTts() async {
    if (_isPlaying) {
      await _sampleTtsService.stop();
      setState(() {
        _isPlaying = false;
      });
      
      if (widget.onPlayEnd != null) {
        widget.onPlayEnd!();
      }
    } else {
      setState(() {
        _isPlaying = true;
      });
      
      if (widget.onPlayStart != null) {
        widget.onPlayStart!();
      }
      
      try {
        await _sampleTtsService.speak(widget.text, context: context, mode: widget.mode);
        
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
          
          if (widget.onPlayEnd != null) {
            widget.onPlayEnd!();
          }
        }
      } catch (e) {
        debugPrint('샘플 TTS 재생 실패: $e');
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

  /// 아이콘 빌드
  Widget _buildIcon(bool isPlaying, Color iconColor, double iconSize) {
    if (widget.mode == TtsMode.slow) {
      // 느린 TTS: 거북이 아이콘 또는 정지 아이콘
      return isPlaying 
          ? Icon(
              Icons.stop,
              color: iconColor,
              size: iconSize,
            )
          : SvgPicture.asset(
              'assets/images/icon_turtle.svg',
              width: iconSize,
              height: iconSize,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            );
    } else {
      // 일반 TTS: 볼륨 아이콘 또는 정지 아이콘
      return Icon(
        isPlaying ? Icons.stop : Icons.volume_up,
        color: iconColor,
        size: iconSize,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color iconColor = widget.isEnabled 
        ? widget.iconColor ?? ColorTokens.textSecondary 
        : ColorTokens.textGrey.withOpacity(0.5);
    
    final Color backgroundColor = _isPlaying 
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
        ),
        child: IconButton(
          icon: _buildIcon(_isPlaying, iconColor, SafeMathUtils.safeMul(widget.size, 0.5, defaultValue: 12.0)),
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
      buttonWidget = IconButton(
        icon: _buildIcon(_isPlaying, iconColor, SafeMathUtils.safeMul(widget.size, 0.6, defaultValue: 14.4)),
        iconSize: SafeMathUtils.safeMul(widget.size, 0.6, defaultValue: 14.4),
        padding: EdgeInsets.all(SafeMathUtils.safeMul(widget.size, 0.2, defaultValue: 4.8)),
        constraints: BoxConstraints(
          minWidth: widget.size,
          minHeight: widget.size,
        ),
        onPressed: widget.isEnabled ? _togglePlayback : null,
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
    // 로그인 상태일 때만 리스너 제거
    if (_authService.currentUser != null) {
      final stateCallback = _stateChangedCallback;
      if (stateCallback != null) {
        _ttsService.removeOnPlayingStateChanged(stateCallback, mode: widget.mode);
      }
      final completedCallback = _completedCallback;
      if (completedCallback != null) {
        _ttsService.removeOnPlayingCompleted(completedCallback, mode: widget.mode);
      }
    }
    
    // 재생 중이면 정리
    if (_isPlaying) {
      Future.microtask(() async {
        if (_authService.currentUser == null) {
          await _sampleTtsService.stop();
        } else {
          await _ttsService.stop();
        }
      });
    }
    
    super.dispose();
  }
} 