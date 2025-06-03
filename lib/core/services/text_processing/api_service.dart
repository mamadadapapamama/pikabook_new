import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  /// 텍스트 세그먼트들을 서버에서 번역
  Future<Map<String, dynamic>> translateSegments({
    required List<String> textSegments,
    String sourceLanguage = 'zh-CN',
    String targetLanguage = 'ko',
    bool needPinyin = true,
    String? pageId,
    String? noteId,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🌐 API 호출: ${textSegments.length}개 세그먼트 번역');
      }

      final callable = _functions.httpsCallable(
        'translateSegments',
        options: HttpsCallableOptions(
          timeout: const Duration(minutes: 8), // 8분으로 증가
        ),
      );
      
      final result = await callable.call({
        'textSegments': textSegments,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'needPinyin': needPinyin,
        'pageId': pageId,
        'noteId': noteId,
      });

      if (kDebugMode) {
        debugPrint('✅ API 응답 성공');
      }

      return result.data as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ API 호출 실패: $e');
      }
      rethrow;
    }
  }
}