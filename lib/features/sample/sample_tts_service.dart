import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/services/authentication/auth_service.dart';

/// 샘플 TTS 예외 클래스
class SampleTtsException implements Exception {
  final String message;
  SampleTtsException(this.message);
  
  @override
  String toString() => 'SampleTtsException: $message';
}

/// 샘플 모드용 하이브리드 TTS 서비스
/// 로컬 assets와 Firebase Storage를 조합하여 사용합니다.
class SampleTtsService {
  static final SampleTtsService _instance = SampleTtsService._internal();
  factory SampleTtsService() => _instance;
  SampleTtsService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final AuthService _authService = AuthService();
  
  // 로컬 assets에 있는 샘플 음성 파일들
  static const Map<String, String> _localAssets = {
    // 플래시카드 단어들 (실제 파일과 매칭)
    '老师': 'assets/audio/sample/laoshi.mp3',
    '黑板': 'assets/audio/sample/heiban.mp3',
    
    // 샘플 문장들 (첫 두 문장)
    '我们早上八点去学校。': 'assets/audio/sample/sentence_1.mp3',
    '教室里有很多桌子和椅子。': 'assets/audio/sample/sentence_2.mp3',
  };

  /// 텍스트 음성 재생
  Future<void> speak(String text) async {
    try {
      if (kDebugMode) {
        debugPrint('🔊 [SampleTTS] 음성 재생 요청: "$text"');
      }

      // 1. 로컬 assets 확인
      if (_localAssets.containsKey(text)) {
        await _playFromAssets(_localAssets[text]!);
        return;
      }

      // 2. Firebase Storage에서 다운로드 후 재생
      await _playFromFirebase(text);
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SampleTTS] 음성 재생 실패: $e');
      }
    }
  }

  /// 로컬 assets에서 음성 재생
  Future<void> _playFromAssets(String assetPath) async {
    try {
      if (kDebugMode) {
        debugPrint('🎵 [SampleTTS] 로컬 assets 재생: $assetPath');
      }
      
      await _audioPlayer.setAsset(assetPath.replaceFirst('assets/', ''));
      await _audioPlayer.play();
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SampleTTS] 로컬 assets 재생 실패: $e');
      }
      rethrow;
    }
  }

  /// Firebase Storage에서 다운로드 후 재생 (샘플 모드에서는 프리미엄 모달 표시)
  Future<void> _playFromFirebase(String text) async {
    // 샘플 모드에서는 로컬 assets에 없는 텍스트는 프리미엄 모달 표시
    if (kDebugMode) {
      debugPrint('🚫 [SampleTTS] 로컬 assets에 없는 텍스트: "$text" - 프리미엄 모달 표시 필요');
    }
    
    // 프리미엄 모달 표시 로직은 UI 레벨에서 처리
    // 여기서는 예외를 던져서 상위에서 처리하도록 함
    throw SampleTtsException('프리미엄 구독이 필요한 콘텐츠입니다.');
  }

  /// 중국어 텍스트를 안전한 파일명으로 변환
  String _generateFileName(String text) {
    // 간단한 해시 기반 파일명 생성
    // 실제로는 더 정교한 방식 사용 (예: 텍스트의 MD5 해시)
    return text.hashCode.abs().toString();
  }

  /// 음성 재생 중지
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
      if (kDebugMode) {
        debugPrint('⏹️ [SampleTTS] 음성 재생 중지');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SampleTTS] 음성 중지 실패: $e');
      }
    }
  }

  /// 현재 재생 상태 확인
  bool get isPlaying => _audioPlayer.playing;

  /// 리소스 정리
  void dispose() {
    _audioPlayer.dispose();
  }

  /// 캐시 정리
  Future<void> clearCache() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${appDir.path}/audio_cache');
      
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        if (kDebugMode) {
          debugPrint('🧹 [SampleTTS] 오디오 캐시 정리 완료');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SampleTTS] 캐시 정리 실패: $e');
      }
    }
  }

  /// 로컬 assets에 있는 텍스트인지 확인
  bool hasLocalAsset(String text) {
    return _localAssets.containsKey(text);
  }

  /// 사용 가능한 로컬 텍스트 목록
  List<String> getLocalTexts() {
    return _localAssets.keys.toList();
  }
} 