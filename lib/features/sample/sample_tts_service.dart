import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/theme/tokens/color_tokens.dart';

/// 샘플 TTS 예외 클래스
class SampleTtsException implements Exception {
  final String message;
  SampleTtsException(this.message);
  
  @override
  String toString() => 'SampleTtsException: $message';
}

/// 샘플 모드용 TTS 서비스
/// 로컬 assets만 사용합니다.
class SampleTtsService {
  static final SampleTtsService _instance = SampleTtsService._internal();
  factory SampleTtsService() => _instance;
  SampleTtsService._internal();

  AudioPlayer? _samplePlayer; // 샘플 전용 플레이어
  
  // 샘플 모드에서 지원하는 오디오 파일들 (하드코딩)
  static const Map<String, String> _sampleAudioAssets = {
    // 플래시카드 단어들
    '老师': 'assets/audio/sample/laoshi.mp3',
    '黑板': 'assets/audio/sample/heiban.mp3',
    
    // 문장 세그먼트들 (샘플 데이터 순서대로)
    '我们早上八点去学校。': 'assets/audio/sample/sentence_1.mp3',
    '教室里有很多桌子和椅子。': 'assets/audio/sample/sentence_2.mp3',
    
    // 나머지 문장들은 오디오 파일이 없으므로 스낵바 표시
    // '下课后，我们去操场玩。' - 오디오 없음
    // '我喜欢我的学校。' - 오디오 없음
  };

  /// 텍스트 음성 재생
  Future<void> speak(String text, {BuildContext? context}) async {
    try {
      if (kDebugMode) {
        debugPrint('🔊 [SampleTTS] 음성 재생 요청: "$text"');
      }

      // 1. 샘플 오디오 assets 확인
      if (_sampleAudioAssets.containsKey(text)) {
        if (kDebugMode) {
          debugPrint('✅ [SampleTTS] 매핑된 오디오 파일 발견: ${_sampleAudioAssets[text]}');
        }
        await _playFromAssets(_sampleAudioAssets[text]!);
        return;
      }

      // 2. 샘플 모드에서 지원하지 않는 오디오 파일인 경우 스낵바 표시
      if (kDebugMode) {
        debugPrint('⚠️ [SampleTTS] 지원하지 않는 텍스트: "$text"');
      }
      if (context != null) {
        _showSampleLimitationSnackBar(context);
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SampleTTS] 음성 재생 실패: $e');
        debugPrint('   실패한 텍스트: "$text"');
        debugPrint('   매핑 상태: ${_sampleAudioAssets.containsKey(text) ? "매핑됨" : "매핑 안됨"}');
      }
      
      // 실제 오디오 재생 실패인 경우에만 스낵바 표시
      if (context != null) {
        _showSampleLimitationSnackBar(context);
      }
    }
  }

  /// assets에서 음성 재생 (샘플 전용 플레이어 사용)
  Future<void> _playFromAssets(String assetPath) async {
    try {
      if (kDebugMode) {
        debugPrint('🎵 [SampleTTS] assets 오디오 재생: $assetPath');
      }
      
      // 기존 재생 완전 정리
      await _cleanupPlayer();
      
      // 새 플레이어 생성 및 초기화
      _samplePlayer = AudioPlayer();
      
      // assets 파일 설정 (assets/ 접두사 제거)
      final cleanPath = assetPath.replaceFirst('assets/', '');
      if (kDebugMode) {
        debugPrint('🎵 [SampleTTS] cleanPath: $cleanPath');
      }
      
      // 올바른 경로로 assets 파일 설정
      await _samplePlayer!.setAsset(cleanPath);
      
      if (kDebugMode) {
        debugPrint('🎧 [SampleTTS] assets 파일 설정 완료: $cleanPath');
      }
      
      // 재생 시작 (지연 제거)
      await _samplePlayer!.play();
      
      if (kDebugMode) {
        debugPrint('✅ [SampleTTS] 오디오 재생 시작됨: $cleanPath');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SampleTTS] assets 오디오 재생 실패: $e');
      }
      rethrow;
    }
  }

  /// 플레이어 완전 정리
  Future<void> _cleanupPlayer() async {
    if (_samplePlayer != null) {
      try {
        if (_samplePlayer!.playing) {
          await _samplePlayer!.stop();
        }
        await _samplePlayer!.dispose();
        if (kDebugMode) {
          debugPrint('🧹 [SampleTTS] 이전 플레이어 정리 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [SampleTTS] 플레이어 정리 중 오류 (무시): $e');
        }
      }
      _samplePlayer = null;
    }
  }
  


  /// 샘플 모드 제한 안내 스낵바 표시
  void _showSampleLimitationSnackBar(BuildContext context) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("샘플 모드에서는 일부 오디오파일만 지원됩니다. 로그인해서 듣기 기능을 사용해보세요."),
        backgroundColor: ColorTokens.snackbarBg, // dark green 색상으로 변경
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }



  /// 음성 재생 중지
  Future<void> stop() async {
    try {
      if (_samplePlayer != null && _samplePlayer!.playing) {
        await _samplePlayer!.stop();
        if (kDebugMode) {
          debugPrint('⏹️ [SampleTTS] 음성 재생 중지');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SampleTTS] 음성 중지 실패: $e');
      }
    }
  }

  /// 현재 재생 상태 확인
  bool get isPlaying => _samplePlayer?.playing ?? false;

  /// 리소스 정리
  Future<void> dispose() async {
    await _cleanupPlayer();
    if (kDebugMode) {
      debugPrint('🧹 [SampleTTS] dispose 완료');
    }
  }



  /// 샘플 오디오가 있는 텍스트인지 확인
  bool hasSampleAudio(String text) {
    return _sampleAudioAssets.containsKey(text);
  }

  /// 사용 가능한 샘플 텍스트 목록
  List<String> getSampleTexts() {
    return _sampleAudioAssets.keys.toList();
  }
  
 
} 