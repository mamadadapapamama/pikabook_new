import 'package:flutter/material.dart';
import '../../core/models/processed_text.dart';
import '../../core/models/text_unit.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/services/tts/tts_service.dart';
import '../../core/services/authentication/auth_service.dart';
import '../sample/sample_tts_service.dart';
import '../../core/services/common/plan_service.dart';
import '../../core/services/common/usage_limit_service.dart';
import '../../core/widgets/upgrade_modal.dart';
import '../../core/models/processed_text.dart';

/// 전체 텍스트 TTS 재생 버튼 위젯 (Pill 모양 Outline 버튼)
class TtsPlayAllButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPlayStart;
  
  const TtsPlayAllButton({
    Key? key,
    required this.text,
    this.onPlayStart,
  }) : super(key: key);

  @override
  State<TtsPlayAllButton> createState() => _TtsPlayAllButtonState();
}

class _TtsPlayAllButtonState extends State<TtsPlayAllButton> {
  final TTSService _ttsService = TTSService();
  final SampleTtsService _sampleTtsService = SampleTtsService();
  final AuthService _authService = AuthService();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    // 전체듣기 TTS 재생 완료 리스너 추가
    _ttsService.setOnPlayingCompleted(() {
      if (mounted && _isPlaying) {
        setState(() {
          _isPlaying = false;
        });
        debugPrint('🎵 TtsPlayAllButton: 재생 완료 리스너로 상태 리셋');
      }
    });
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
    final limitStatus = await usageService.checkInitialLimitStatus();
    
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
      debugPrint('🎵 TtsPlayAllButton: 재생 시작 상태로 변경');
      
      if (widget.onPlayStart != null) {
        widget.onPlayStart!();
      }
      
      try {
        // String을 ProcessedText로 변환하여 speakAllSegments 호출
        final textUnit = TextUnit(
          originalText: widget.text,
          translatedText: '',
          pinyin: '',
          sourceLanguage: 'zh',
          targetLanguage: 'ko',
        );
        final processedText = ProcessedText(
          mode: TextProcessingMode.segment,
          displayMode: TextDisplayMode.full,
          fullOriginalText: widget.text,
          fullTranslatedText: '',
          units: [textUnit],
          sourceLanguage: 'zh',
          targetLanguage: 'ko',
        );
        await _ttsService.speakAllSegments(processedText);
        
        // 재생 완료는 리스너에서 처리하므로 여기서는 제거
        // (리스너가 더 안정적으로 상태를 관리함)
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
          backgroundColor:ColorTokens.snackbarBg, // dark green 색상으로 변경
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    
    debugPrint('📢 샘플 모드에서 전체 듣기 TTS 기능 제한됨');
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
    if (_isPlaying) {
      _ttsService.stop();
    }
    super.dispose();
  }
} 