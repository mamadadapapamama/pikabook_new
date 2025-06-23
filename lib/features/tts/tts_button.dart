import 'package:flutter/material.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/services/common/usage_limit_service.dart';
import 'base_tts_button.dart';

/// TTS 버튼을 위한 공용 위젯
/// 상태에 따라 적절한 스타일과 피드백을 제공합니다.
class TtsButton extends BaseTtsButton {
  /// 버튼 크기 사전 정의값
  static const double sizeSmall = 24.0;
  static const double sizeMedium = 32.0;
  static const double sizeLarge = 40.0;

  const TtsButton({
    Key? key,
    required String text,
    int? segmentIndex,
    double size = sizeMedium,
    String? tooltip,
    Color? iconColor,
    Color? activeBackgroundColor,
    VoidCallback? onPlayStart,
    VoidCallback? onPlayEnd,
    bool useCircularShape = true,
    bool isEnabled = true,
  }) : super(
    key: key,
    text: text,
    segmentIndex: segmentIndex,
    size: size,
    tooltip: tooltip,
    iconColor: iconColor,
    activeBackgroundColor: activeBackgroundColor,
    onPlayStart: onPlayStart,
    onPlayEnd: onPlayEnd,
    useCircularShape: useCircularShape,
    isEnabled: isEnabled,
  );

  @override
  State<TtsButton> createState() => _TtsButtonState();
}

class _TtsButtonState extends BaseTtsButtonState<TtsButton> {
  final TTSService _ttsService = TTSService();

  @override
  Widget buildIcon(bool isPlaying, Color iconColor, double iconSize) {
    return Icon(
      isPlaying ? Icons.stop : Icons.volume_up,
      color: iconColor,
      size: iconSize,
    );
  }

  @override
  Future<void> playTtsInternal(String text, int? segmentIndex) async {
    if (segmentIndex != null) {
      await _ttsService.speakSegment(text, segmentIndex);
    } else {
      await _ttsService.speak(text);
    }
  }

  @override
  Future<void> stopTtsInternal() async {
    await _ttsService.stop();
  }

  @override
  Future<bool> checkUsageLimit() async {
    // 일반 TTS 사용량 제한 체크 (느린 TTS와 동일)
    final usageService = UsageLimitService();
    final limitStatus = await usageService.checkInitialLimitStatus();
    
    if (limitStatus['ttsLimitReached'] == true) {
      if (mounted) {
        // 사용량 제한 도달 시 업그레이드 프롬프트 표시
        // await UpgradePromptHelper.showTtsUpgradePrompt(context);
      }
      return false;
    }
    return true;
  }
  
  @override
  void setupListeners() {
    // 재생 상태 변경 리스너
    _ttsService.setOnPlayingStateChanged((segmentIndex) {
      if (mounted) {
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
        if (isPlaying != isThisSegmentPlaying) {
          setState(() {
            isPlaying = isThisSegmentPlaying;
          });
          
          debugPrint('TTS 버튼 상태 변경: isPlaying=$isPlaying, segmentIndex=$segmentIndex, widget.segmentIndex=${widget.segmentIndex}');
        }
      }
    });
    
    // 재생 완료 리스너
    _ttsService.setOnPlayingCompleted(() {
      if (mounted && isPlaying) {
        setState(() {
          isPlaying = false;
        });
        
        debugPrint('TTS 재생 완료: 버튼 상태 리셋 (segmentIndex=${widget.segmentIndex})');
        
        // 재생 종료 콜백 호출
        if (widget.onPlayEnd != null) {
          widget.onPlayEnd!();
        }
      }
    });
  }
} 