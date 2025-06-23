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
import 'base_tts_button.dart';

/// 느린 TTS 버튼을 위한 위젯 (거북이 아이콘 사용)
/// 50% 느린 속도로 재생하며 일시정지 기능을 제공합니다.
class SlowTtsButton extends BaseTtsButton {
  /// 버튼 크기 사전 정의값
  static const double sizeSmall = 20.0;
  static const double sizeMedium = 24.0;
  static const double sizeLarge = 32.0;

  const SlowTtsButton({
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
    iconColor: iconColor ?? ColorTokens.snackbarBg, // 기본 색상 다름
    activeBackgroundColor: activeBackgroundColor,
    onPlayStart: onPlayStart,
    onPlayEnd: onPlayEnd,
    useCircularShape: useCircularShape,
    isEnabled: isEnabled,
  );

  @override
  State<SlowTtsButton> createState() => _SlowTtsButtonState();
}

class _SlowTtsButtonState extends BaseTtsButtonState<SlowTtsButton> {
  final SlowTtsService _slowTtsService = SlowTtsService();
  final SampleTtsService _sampleTtsService = SampleTtsService();
  final AuthService _authService = AuthService();

  @override
  Widget buildIcon(bool isPlaying, Color iconColor, double iconSize) {
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
  }

  @override
  Future<void> playTtsInternal(String text, int? segmentIndex) async {
    if (segmentIndex != null) {
      await _slowTtsService.speakSegment(text, segmentIndex);
    } else {
      await _slowTtsService.speak(text);
    }
  }

  @override
  Future<void> stopTtsInternal() async {
    await _slowTtsService.stop();
  }

  @override
  Future<bool> checkUsageLimit() async {
    // 느린 TTS 사용량 제한 체크
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
    _slowTtsService.setOnPlayingStateChanged((segmentIndex) {
      if (mounted) {
        // 현재 재생 중인 세그먼트인지 확인
        final bool isThisSegmentPlaying = segmentIndex != null && 
                                         widget.segmentIndex == segmentIndex;
        
        // 상태가 변경된 경우에만 setState 호출
        if (isPlaying != isThisSegmentPlaying) {
          setState(() {
            isPlaying = isThisSegmentPlaying;
          });
          
          debugPrint('🐢 느린 TTS 버튼 상태 변경: isPlaying=$isPlaying, segmentIndex=$segmentIndex, widget.segmentIndex=${widget.segmentIndex}');
        }
      }
    });
    
    // 재생 완료 리스너
    _slowTtsService.setOnPlayingCompleted(() {
      if (mounted && isPlaying) {
        setState(() {
          isPlaying = false;
        });
        
        debugPrint('🐢 느린 TTS 재생 완료: 버튼 상태 리셋 (segmentIndex=${widget.segmentIndex})');
        
        // 재생 종료 콜백 호출
        if (widget.onPlayEnd != null) {
          widget.onPlayEnd!();
        }
      }
    });
  }


} 