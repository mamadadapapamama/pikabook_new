import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../common/usage_limit_service.dart';
import '../common/plan_service.dart';
import '../../utils/language_constants.dart';

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
      _apiKey = jsonData['elevenlabs_key'] as String?;
      debugPrint('ElevenLabs API 키 로드 성공');
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
  Future<Uint8List?> synthesizeSpeech(String text) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      if (_apiKey == null) {
        await _loadApiKey();
      }

      final response = await http.post(
        Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM'),
        headers: {
          'Accept': 'audio/mpeg',
          'Content-Type': 'application/json',
          'xi-api-key': _apiKey!,
        },
        body: json.encode({
          'text': text,
          'model_id': 'eleven_monolingual_v1',
          'voice_settings': {
            'stability': 0.5,
            'similarity_boost': 0.5,
          },
        }),
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('음성 합성 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('음성 합성 중 오류: $e');
      }
      rethrow;
    }
  }

  /// 사용량 제한 확인 및 증가
  Future<bool> checkAndIncrementUsage() async {
    return await _usageLimitService.incrementTtsCharCount(1);
  }

  /// 현재 TTS 사용 횟수 가져오기
  Future<int> getCurrentTtsUsageCount() async {
    try {
      // 항상 최신 데이터 가져오기
      _usageLimitService.invalidateCache();
      final usage = await _usageLimitService.getUserUsage(forceRefresh: true);
      final int currentUsage = usage['ttsRequests'] is int 
          ? usage['ttsRequests'] as int 
          : 0;
      return currentUsage;
    } catch (e) {
      debugPrint('TTS 현재 사용량 확인 중 오류: $e');
      return 0;
    }
  }

  /// 남은 TTS 사용량 확인
  Future<int> getRemainingTtsCount() async {
    try {
      final plan = await PlanService().getCurrentPlan();
      final usage = await _usageLimitService.getTtsUsage();
      return (plan['maxTtsCount'] as int) - usage;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTS 사용량 확인 중 오류: $e');
      }
      rethrow;
    }
  }

  /// 전체 TTS 사용 한도 가져오기
  Future<int> getTtsUsageLimit() async {
    final limits = await _usageLimitService.getUserLimits();
    return limits['ttsRequests'] ?? 0;
  }

  /// TTS 사용량 안내 메시지 가져오기 (현재 사용량 포함)
  Future<String> getTtsUsageMessage() async {
    final currentCount = await getCurrentTtsUsageCount();
    final limit = await getTtsUsageLimit();
    return '현재 TTS 사용량: $currentCount/$limit회';
  }

  /// TTS 제한 안내 메시지 가져오기
  String getTtsLimitMessage() {
    return '무료 사용량을 모두 사용했습니다. 추가 사용을 원하시면 관리자에게 문의주세요.';
  }

  /// TTS 사용 가능 여부 확인
  Future<bool> isTtsAvailable() async {
    try {
      final remainingCount = await getRemainingTtsCount();
      return remainingCount > 0;
    } catch (e) {
      debugPrint('TTS 사용 가능 여부 확인 중 오류: $e');
      return false;
    }
  }
}
