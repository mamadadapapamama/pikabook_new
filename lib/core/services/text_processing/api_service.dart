import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  // 성능 통계 저장
  final Map<String, int> _performanceStats = {
    'totalCalls': 0,
    'totalTime': 0,
    'averageTime': 0,
    'fastestCall': 999999,
    'slowestCall': 0,
  };

  Map<String, int> get performanceStats => Map.from(_performanceStats);

  /// 텍스트 세그먼트들을 서버에서 번역
  Future<Map<String, dynamic>> translateSegments({
    required List<String> textSegments,
    String sourceLanguage = 'zh-CN',
    String targetLanguage = 'ko',
    bool needPinyin = true,
    String? pageId,
    String? noteId,
  }) async {
    final apiStartTime = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint('🌐 [API] 번역 시작: ${textSegments.length}개 세그먼트');
        debugPrint('📊 [API] 시작 시간: ${apiStartTime.millisecondsSinceEpoch}ms');
      }

      final callable = _functions.httpsCallable(
        'translateSegments',
        options: HttpsCallableOptions(
          timeout: const Duration(minutes: 8), // 8분으로 증가
        ),
      );
      
      final callStartTime = DateTime.now();
      final result = await callable.call({
        'textSegments': textSegments,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'needPinyin': needPinyin,
        'pageId': pageId,
        'noteId': noteId,
      });
      final callEndTime = DateTime.now();

      final apiTotalTime = callEndTime.difference(apiStartTime).inMilliseconds;
      final networkTime = callEndTime.difference(callStartTime).inMilliseconds;

      // 성능 통계 업데이트
      _updatePerformanceStats(apiTotalTime);

      if (kDebugMode) {
        debugPrint('✅ [API] 번역 완료');
        debugPrint('⏱️ [API] 총 소요시간: ${apiTotalTime}ms');
        debugPrint('🌐 [API] 네트워크 시간: ${networkTime}ms');
        debugPrint('🔧 [API] 오버헤드: ${apiTotalTime - networkTime}ms');
        debugPrint('📈 [API] 평균 응답시간: ${_performanceStats['averageTime']}ms');
        
        // 서버에서 반환한 통계 정보도 출력
        final data = result.data as Map<String, dynamic>;
        if (data['statistics'] != null) {
          final stats = data['statistics'] as Map<String, dynamic>;
          debugPrint('🤖 [서버] 처리시간: ${stats['processingTime']}ms');
          debugPrint('📝 [서버] 세그먼트: ${stats['segmentCount']}개');
          debugPrint('📄 [서버] 문자수: ${stats['totalCharacters']}자');
        }
      }

      return result.data as Map<String, dynamic>;
    } catch (e) {
      final apiErrorTime = DateTime.now().difference(apiStartTime).inMilliseconds;
      
      if (kDebugMode) {
        debugPrint('❌ [API] 호출 실패: $e');
        debugPrint('⏱️ [API] 실패까지 소요시간: ${apiErrorTime}ms');
      }
      rethrow;
    }
  }

  void _updatePerformanceStats(int responseTime) {
    _performanceStats['totalCalls'] = _performanceStats['totalCalls']! + 1;
    _performanceStats['totalTime'] = _performanceStats['totalTime']! + responseTime;
    _performanceStats['averageTime'] = _performanceStats['totalTime']! ~/ _performanceStats['totalCalls']!;
    
    if (responseTime < _performanceStats['fastestCall']!) {
      _performanceStats['fastestCall'] = responseTime;
    }
    if (responseTime > _performanceStats['slowestCall']!) {
      _performanceStats['slowestCall'] = responseTime;
    }
  }

  void resetPerformanceStats() {
    _performanceStats['totalCalls'] = 0;
    _performanceStats['totalTime'] = 0;
    _performanceStats['averageTime'] = 0;
    _performanceStats['fastestCall'] = 999999;
    _performanceStats['slowestCall'] = 0;
  }
}