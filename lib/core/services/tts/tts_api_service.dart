import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../../../core/services/common/usage_limit_service.dart';
import '../../utils/language_constants.dart';
import '../../../core/services/subscription/unified_subscription_manager.dart';

/// TTS API 서비스
/// ElevenLabs API 호출 및 음성 합성, 사용량 관리를 담당합니다.
class TtsApiService {
  // 싱글톤 패턴
  static final TtsApiService _instance = TtsApiService._internal();
  factory TtsApiService() => _instance;
  TtsApiService._internal();

  // API 관련
  String? _apiKey;
  String _currentLanguage = SourceLanguage.DEFAULT;

  // 사용량 제한 서비스
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // 초기화 상태
  bool _isInitialized = false;

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _loadApiKey();
      _isInitialized = true;
      debugPrint('TTS API 서비스 초기화 완료');
    } catch (e) {
      debugPrint('TTS API 서비스 초기화 실패: $e');
      rethrow;
    }
  }

  /// API 키 로드
  Future<void> _loadApiKey() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/credentials/api_keys.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      _apiKey = jsonData['elevenlabs_api_key'] as String?;
      if (kDebugMode) {
        debugPrint('ElevenLabs API 키 로드 성공: ${_apiKey != null ? "키 존재함" : "키 없음"}');
        if (_apiKey != null) {
          debugPrint('API 키 길이: ${_apiKey!.length}자');
        }
      }
    } catch (e) {
      debugPrint('API 키 로드 중 오류: $e');
      rethrow;
    }
  }

  /// 언어 설정
  Future<void> setLanguage(String language) async {
    _currentLanguage = language;
    debugPrint('TTS 언어 설정: $_currentLanguage');
  }

  /// 현재 설정된 언어
  String get currentLanguage => _currentLanguage;

  /// ElevenLabs TTS API를 사용하여 음성 합성
  Future<Uint8List?> synthesizeSpeech(String text, {String? voiceId, double? speed}) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      if (_apiKey == null) {
        await _loadApiKey();
      }
      
      // API 키 검증
      if (_apiKey == null || _apiKey!.isEmpty) {
        throw Exception('ElevenLabs API 키가 설정되지 않았습니다');
      }

      // 언어 확인 - 중국어만 지원
      if (_currentLanguage != 'zh-CN') {
        if (kDebugMode) {
          debugPrint('TTS: 중국어만 지원합니다. 현재 설정된 언어: $_currentLanguage');
        }
        throw Exception('TTS는 중국어(zh-CN)만 지원합니다');
      }

      // 텍스트가 비어있는지 확인
      if (text.isEmpty) {
        if (kDebugMode) {
          debugPrint('TTS: 텍스트가 비어있어 합성을 건너뜁니다.');
        }
        throw Exception('텍스트가 비어있습니다');
      }

      // 텍스트 길이 제한 (ElevenLabs는 5000자 제한이 있음)
      final String truncatedText = text.length > 4000 
          ? text.substring(0, 4000) 
          : text;

      // Voice ID 설정 (기본값: James 음성, 느린 TTS용: 새로운 음성)
      final String selectedVoiceId = voiceId ?? '4VZIsMPtgggwNg7OXbPY'; // 기본 중국어 남성 음성
      final double selectedSpeed = speed ?? 0.9; // 기본 속도

      if (kDebugMode) {
        debugPrint('TTS 요청: ${truncatedText.length}자, Voice: $selectedVoiceId, Speed: $selectedSpeed');
        debugPrint('TTS 요청 텍스트(일부): ${truncatedText.substring(0, min(30, truncatedText.length))}...');
      }

      final response = await http.post(
        Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$selectedVoiceId'),
        headers: {
          'Accept': 'audio/mpeg',
          'Content-Type': 'application/json',
          'xi-api-key': _apiKey!,
        },
        body: json.encode({
          'text': truncatedText,
          'voice_settings': {
            'stability': 1.0,
            'similarity_boost': 1.0,
            'speed': selectedSpeed,
          },
        }),
      );

      if (response.statusCode == 200) {
        if (kDebugMode) {
          debugPrint('TTS API 응답 성공: ${response.bodyBytes.length} 바이트');
        }
        return response.bodyBytes;
      } else {
        if (kDebugMode) {
          debugPrint('TTS API 응답 실패: ${response.statusCode}');
          debugPrint('응답 내용: ${response.body}');
        }
        throw Exception('음성 합성 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('음성 합성 중 오류: $e');
      }
      rethrow;
    }
  }

  /// TTS 재생 완료 후 사용량 증가
  Future<bool> incrementTtsUsageAfterPlayback() async {
    try {
      // 🎯 구독 상태를 가져와서 UsageLimitService에 전달
      final subscriptionState = await UnifiedSubscriptionManager().getSubscriptionState();
      return await _usageLimitService.incrementTtsUsageAfterPlayback(
        subscriptionState: subscriptionState,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TTS 사용량 증가 실패: $e');
      }
      return false;
    }
  }
}
