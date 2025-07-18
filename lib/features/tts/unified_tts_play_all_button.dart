import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/services/tts/unified_tts_service.dart';
import '../../core/services/authentication/auth_service.dart';
import '../sample/sample_tts_service.dart';
import '../../core/services/common/usage_limit_service.dart';
import '../../core/widgets/upgrade_modal.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';

/// 통합 TTS 전체 재생 버튼
class UnifiedTtsPlayAllButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPlayStart;
  
  const UnifiedTtsPlayAllButton({
    Key? key,
    required this.text,
    this.onPlayStart,
  }) : super(key: key);

  @override
  State<UnifiedTtsPlayAllButton> createState() => _UnifiedTtsPlayAllButtonState();
}

class _UnifiedTtsPlayAllButtonState extends State<UnifiedTtsPlayAllButton> {
  final UnifiedTtsService _ttsService = UnifiedTtsService();
  final SampleTtsService _sampleTtsService = SampleTtsService();
  final AuthService _authService = AuthService();
  final UnifiedSubscriptionManager _subscriptionManager = UnifiedSubscriptionManager();
  bool _isPlaying = false;

  // 콜백 참조 저장
  Function()? _completedCallback;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    // 전체듣기 TTS 재생 완료 리스너 추가
    _completedCallback = () {
      if (mounted && _isPlaying) {
        setState(() {
          _isPlaying = false;
        });
        if (kDebugMode) {
          debugPrint('🎵 통합 TTS 전체 재생 완료');
        }
      }
    };
    
    _ttsService.setOnPlayingCompleted(_completedCallback!, mode: TtsMode.normal);
  }

  void _togglePlayback() async {
    if (widget.text.isEmpty) return;

    // 샘플 모드(로그아웃 상태)에서는 SampleTtsService 사용
    if (_authService.currentUser == null) {
      await _handleSampleModeTts();  
      return;
    }

    // TTS 사용량 제한 체크
    final usageService = UsageLimitService();
    final subscriptionState = await _subscriptionManager.getSubscriptionState();
    final limitStatus = await usageService.checkInitialLimitStatus(subscriptionState: subscriptionState);
    
    if (limitStatus['ttsLimitReached'] == true) {
      if (mounted) {
        await UpgradePromptHelper.showTtsUpgradePrompt(context);
      }
      return;
    }

    if (_isPlaying) {
      // 재생 중이면 중지
      _ttsService.stop();
      setState(() {
        _isPlaying = false;
      });
    } else {
      // 재생 시작
      setState(() {
        _isPlaying = true;
      });
      
      if (widget.onPlayStart != null) {
        widget.onPlayStart!();
      }
      
      try {
        // 통합 서비스 사용하여 전체 텍스트 재생
        await _ttsService.speak(widget.text, mode: TtsMode.normal);
      } catch (e) {
        debugPrint('전체 TTS 재생 중 오류: $e');
        if (mounted) {
          setState(() {
            _isPlaying = false;
          });
        }
      }
    }
  }

  /// 샘플 모드에서 전체 듣기 TTS 처리 - 스낵바 메시지만 표시
  Future<void> _handleSampleModeTts() async {
    // 샘플 모드에서는 전체 듣기 기능을 지원하지 않음
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("샘플 모드에서는 일부 오디오파일만 지원됩니다. 로그인해서 듣기 기능을 사용해보세요."),
          backgroundColor: ColorTokens.snackbarBg,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    
    if (kDebugMode) {
      debugPrint('📢 샘플 모드에서 전체 듣기 TTS 기능 제한됨');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _togglePlayback,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isPlaying ? ColorTokens.primary : ColorTokens.secondary,
              width: 1,
            ),
            color: _isPlaying ? ColorTokens.primary.withOpacity(0.1) : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isPlaying ? Icons.stop : Icons.volume_up,
                color: _isPlaying ? ColorTokens.primary : ColorTokens.secondary,
                size: 12,
              ),
              const SizedBox(width: 6),
              Text(
                '본문 전체 듣기',
                style: TypographyTokens.caption.copyWith(
                  color: _isPlaying ? ColorTokens.primary : ColorTokens.secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // 리스너 제거
    final callback = _completedCallback;
    if (callback != null) {
      _ttsService.removeOnPlayingCompleted(callback, mode: TtsMode.normal);
    }
    
    if (_isPlaying) {
      _ttsService.stop();
    }
    super.dispose();
  }
} 