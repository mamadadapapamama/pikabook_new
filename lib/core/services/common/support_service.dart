import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 고객 지원 관련 서비스
class SupportService {
  // 싱글톤 패턴
  static final SupportService _instance = SupportService._internal();
  factory SupportService() => _instance;
  SupportService._internal();
  
  /// 문의하기 기능
  Future<void> contactSupport({String? subject, String? body}) async {
    try {
      if (kDebugMode) {
        debugPrint('문의하기 기능 호출됨: subject=$subject, body=$body');
      }
      
      // Google Form 열기
      final formUrl = Uri.parse('https://docs.google.com/forms/d/e/1FAIpQLSfgVL4Bd5KcTh9nhfbVZ51yApPAmJAZJZgtM4V9hNhsBpKuaA/viewform?usp=dialog');
      
      if (await canLaunchUrl(formUrl)) {
        await launchUrl(formUrl, mode: LaunchMode.externalApplication);
      } else {
        if (kDebugMode) {
          debugPrint('Google Form을 열 수 없습니다: $formUrl');
        }
        throw Exception('문의 폼을 열 수 없습니다.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('문의하기 기능 오류: $e');
      }
      rethrow;
    }
  }
} 