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
  
  /// 버튼 크기 사전 정의값
  static const double sizeSmall = 24.0;
  static const double sizeMedium = 32.0;
  static const double sizeLarge = 40.0;

  const TtsButton({
    Key? key,
    required this.text,
    this.segmentIndex,
    this.size = sizeMedium, // 기본 크기를 medium으로 변경
    this.tooltip,
    this.iconColor,
    this.activeBackgroundColor,
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
    } else {
      // 재생 시작
      setState(() {
        _isPlaying = true;
      });
      
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
        }
      }
      
      // 사용량 확인 후 상태 업데이트
      _checkTtsAvailability();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 기본 색상 설정
    final Color defaultIconColor = widget.iconColor ?? ColorTokens.textSecondary;
    final Color defaultActiveBackground = widget.activeBackgroundColor ?? ColorTokens.primary.withOpacity(0.1);
    
    // 버튼 사이즈에 맞게 아이콘 사이즈 계산
    final double iconSize = widget.size * 0.6;
    
    // 버튼 배경색 - 재생 중일 때와 비활성화 상태에 따라 다르게 설정
    final Color backgroundColor = _isPlaying 
        ? defaultActiveBackground 
        : _isEnabled 
            ? ColorTokens.segmentButtonBackground
            : ColorTokens.textGrey.withOpacity(0.1); // 비활성화 시 회색 배경
    
    // 아이콘 색상 - 활성화 상태에 따라 다르게 설정
    final Color iconColor = _isEnabled 
        ? defaultIconColor 
        : ColorTokens.textGrey.withOpacity(0.5); // 비활성화 시 연한 회색
    
    final Widget buttonContent = AnimatedContainer(
      duration: const Duration(milliseconds: 200), // 상태 변화 시 애니메이션 효과
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(widget.size / 2), // 완전한 원형 버튼
      ),
      child: Icon(
        _isPlaying ? Icons.stop : Icons.volume_up,
        color: iconColor,
        size: iconSize,
      ),
    );
    
    // 비활성화 상태이고 툴팁이 있는 경우 툴팁으로 감싸기
    if (!_isEnabled && widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: buttonContent,
      );
    }
    
    return GestureDetector(
      onTap: _isEnabled ? _togglePlayback : null,
      child: buttonContent,
    );
  }
  
  @override
  void dispose() {
    // TTS 서비스에서 리스너 등록 해제는 필요없음 (싱글톤)
    super.dispose();
  }
} 