import 'package:flutter/material.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';

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
  final TTSService _ttsService = TTSService();
  bool _isPlaying = false;
  bool _isEnabled = true;
  
  @override
  void initState() {
    super.initState();
    _checkTtsAvailability();
    _setupListeners();
  }
  
  // TTS 상태 변경 리스너 설정
  void _setupListeners() {
    // 재생 상태 변경 리스너
    _ttsService.setOnPlayingStateChanged((segmentIndex) {
      if (mounted) {
        // 현재 재생 중인 세그먼트인지 확인
        final bool isThisSegmentPlaying = widget.segmentIndex != null && 
                                         widget.segmentIndex == segmentIndex;
        
        // 상태가 변경된 경우에만 setState 호출
        if (_isPlaying != isThisSegmentPlaying) {
          setState(() {
            _isPlaying = isThisSegmentPlaying;
          });
          
          debugPrint('TTS 버튼 상태 변경: _isPlaying=$_isPlaying, segmentIndex=$segmentIndex, widget.segmentIndex=${widget.segmentIndex}');
        }
      }
    });
    
    // 재생 완료 리스너
    _ttsService.setOnPlayingCompleted(() {
      if (mounted) {
        // 현재 재생 중이거나 이 버튼의 세그먼트가 재생 중이었던 경우 상태 리셋
        if (_isPlaying || _ttsService.currentSegmentIndex == widget.segmentIndex) {
          setState(() {
            _isPlaying = false;
          });
          
          debugPrint('TTS 재생 완료: 버튼 상태 리셋 (segmentIndex=${widget.segmentIndex})');
          
          // 재생 종료 콜백 호출
          if (widget.onPlayEnd != null) {
            widget.onPlayEnd!();
          }
        }
      }
    });
  }
  
  @override
  void didUpdateWidget(TtsButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 세그먼트 인덱스가 변경된 경우
    if (oldWidget.segmentIndex != widget.segmentIndex) {
      // TTS 서비스의 현재 재생 중인 세그먼트와 비교
      final currentPlayingSegment = _ttsService.currentSegmentIndex;
      final bool shouldBePlaying = widget.segmentIndex != null && 
                                  widget.segmentIndex == currentPlayingSegment;
      
      // 상태 업데이트
      if (_isPlaying != shouldBePlaying) {
        setState(() {
          _isPlaying = shouldBePlaying;
        });
        
        debugPrint('세그먼트 인덱스 변경으로 인한 상태 업데이트: _isPlaying=$_isPlaying');
      }
    }
  }
  
  // TTS 사용 가능 여부 확인
  Future<void> _checkTtsAvailability() async {
    try {
      // 항상 최신 데이터로 확인 (forceRefresh 사용)
      final isAvailable = await _ttsService.isTtsAvailable();
      
      if (mounted && _isEnabled != isAvailable) {
        setState(() {
          _isEnabled = isAvailable;
        });
        
        // 상태 변경 로그
        debugPrint('TTS 버튼 사용 가능 상태 변경: $_isEnabled');
        
        // 사용 불가로 변경된 경우 재생 중 상태도 리셋
        if (!_isEnabled && _isPlaying) {
          setState(() {
            _isPlaying = false;
          });
          debugPrint('TTS 제한으로 인해 재생 상태 리셋');
        }
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
    
    // 사용 가능 여부 다시 확인 (최신 데이터로)
    final isStillEnabled = await _ttsService.isTtsAvailable();
    if (!isStillEnabled) {
      if (mounted) {
        setState(() {
          _isEnabled = false;
        });
        debugPrint('TTS 재생 전 확인: 사용량 제한 도달');
      }
      return;
    }
    
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
      
      debugPrint('TTS 재생 중지 (사용자에 의해)');
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
        // 재생 메서드 호출 전에 디버그 로그
        debugPrint('TTS 재생 시작: "${widget.text}", 세그먼트=${widget.segmentIndex}');
        
        if (widget.segmentIndex != null) {
          await _ttsService.speakSegment(widget.text, widget.segmentIndex!);
        } else {
          await _ttsService.speak(widget.text);
        }
        
        // speakSegment이 비동기적으로 완료된 후에도 상태 확인
        // 2초 후에 TTS 서비스 상태를 확인하여 현재 재생 중인지 확인 (타임아웃 시간 단축)
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            final currentSegment = _ttsService.currentSegmentIndex;
            final bool shouldStillBePlaying = widget.segmentIndex != null && 
                                             widget.segmentIndex == currentSegment;
            
            // 상태가 불일치하는 경우 강제 업데이트
            if (_isPlaying && !shouldStillBePlaying) {
              setState(() {
                _isPlaying = false;
              });
              
              debugPrint('2초 타임아웃으로 TTS 버튼 상태 리셋');
              
              // 재생 종료 콜백 호출
              if (widget.onPlayEnd != null) {
                widget.onPlayEnd!();
              }
            }
          }
        });
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
          // 테두리 제거 (재생 상태에 관계없이 항상 테두리 없음)
          border: null,
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
        // 재생 중일 때 배경색 적용
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
        ),
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
    // 상태 정리를 위해 현재 재생 중인 경우 중지
    if (_isPlaying) {
      debugPrint('TtsButton dispose: 재생 중인 TTS 정리');
      // 동기 작업이 UI를 차단하지 않도록 별도 작업으로 분리
      _isPlaying = false; // 먼저 상태 업데이트
      Future.microtask(() {
        _ttsService.stop();
      });
    }
    super.dispose();
  }
} 