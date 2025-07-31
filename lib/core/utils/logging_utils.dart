/// 📝 로깅 유틸리티 클래스
/// 기존 Logger 클래스를 확장하여 더 편리한 로깅 기능을 제공합니다.

import 'package:flutter/foundation.dart';
import 'logger.dart';

/// 🎯 통합 로깅 유틸리티
class LoggingUtils {
  // ────────────────────────────────────────────────────────────────────────
  // 🔧 기본 로깅 메서드들 (기존 Logger를 래핑)
  // ────────────────────────────────────────────────────────────────────────
  
  /// 디버그 로그 (개발 모드에서만 출력)
  static void debug(String message, {String? tag}) {
    if (kDebugMode) {
      Logger.debug(message, tag: tag ?? '');
    }
  }
  
  /// 정보 로그
  static void info(String message, {String? tag}) {
    Logger.info(message, tag: tag ?? '');
  }
  
  /// 경고 로그
  static void warning(String message, {String? tag, Object? error}) {
    Logger.warning(message, tag: tag ?? '', error: error);
  }
  
  /// 오류 로그
  static void error(String message, {String? tag, Object? error}) {
    Logger.error(message, tag: tag ?? '', error: error);
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🎯 특화된 로깅 메서드들
  // ────────────────────────────────────────────────────────────────────────
  
  /// 성능 측정 로그
  static void performance(String message, {String? tag}) {
    Logger.performance(message, tag: tag ?? '');
  }
  
  /// API 호출 로그
  static void api(String message, {String? tag}) {
    Logger.api(message, tag: tag ?? '');
  }
  
  /// 데이터베이스 로그
  static void database(String message, {String? tag}) {
    Logger.database(message, tag: tag ?? '');
  }
  
  /// 인증 로그
  static void auth(String message, {String? tag}) {
    Logger.auth(message, tag: tag ?? '');
  }
  
  /// 구독/결제 로그
  static void subscription(String message, {String? tag}) {
    Logger.subscription(message, tag: tag ?? '');
  }
  
  /// UI 로그
  static void ui(String message, {String? tag}) {
    Logger.ui(message, tag: tag ?? '');
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🚀 편의 메서드들 (자주 사용되는 패턴들)
  // ────────────────────────────────────────────────────────────────────────
  
  /// 메서드 진입 로그
  static void methodEnter(String className, String methodName, {Map<String, dynamic>? params}) {
    final paramsStr = params != null ? ' params: $params' : '';
    debug('🔄 [$className] $methodName 시작$paramsStr', tag: className);
  }
  
  /// 메서드 종료 로그
  static void methodExit(String className, String methodName, {dynamic result}) {
    final resultStr = result != null ? ' result: $result' : '';
    debug('✅ [$className] $methodName 완료$resultStr', tag: className);
  }
  
  /// 상태 변경 로그
  static void stateChange(String className, String from, String to, {String? context}) {
    final contextStr = context != null ? ' ($context)' : '';
    debug('🔄 [$className] 상태 변경: $from → $to$contextStr', tag: className);
  }
  
  /// 데이터 로드 시작 로그
  static void dataLoadStart(String dataType, {String? source, String? tag}) {
    debug('📥 $dataType 로드 시작${source != null ? ' from $source' : ''}', tag: tag);
  }
  
  /// 데이터 로드 완료 로그
  static void dataLoadComplete(String dataType, {int? count, String? tag}) {
    final countStr = count != null ? ' ($count개)' : '';
    debug('✅ $dataType 로드 완료$countStr', tag: tag);
  }
  
  /// 데이터 로드 실패 로그
  static void dataLoadFailed(String dataType, Object errorObj, {String? tag}) {
    LoggingUtils.error('❌ $dataType 로드 실패: $errorObj', tag: tag, error: errorObj);
  }
  
  /// 네트워크 요청 시작 로그
  static void networkStart(String method, String url, {String? tag}) {
    api('🌐 $method $url 요청 시작', tag: tag);
  }
  
  /// 네트워크 응답 성공 로그
  static void networkSuccess(String method, String url, int statusCode, {String? tag}) {
    api('✅ $method $url → $statusCode', tag: tag);
  }
  
  /// 네트워크 요청 실패 로그
  static void networkError(String method, String url, Object error, {String? tag}) {
    LoggingUtils.error('❌ $method $url 요청 실패: $error', tag: tag, error: error);
  }
  
  /// 사용자 액션 로그
  static void userAction(String action, {Map<String, dynamic>? context, String? tag}) {
    final contextStr = context != null ? ' context: $context' : '';
    ui('👤 사용자 액션: $action$contextStr', tag: tag ?? 'UserAction');
  }
  
  /// 업그레이드/구독 관련 로그
  static void subscriptionEvent(String event, {Map<String, dynamic>? details, String? tag}) {
    final detailsStr = details != null ? ' details: $details' : '';
    subscription('💳 구독 이벤트: $event$detailsStr', tag: tag ?? 'Subscription');
  }
  
  /// 사용량 관련 로그
  static void usageEvent(String event, {Map<String, dynamic>? usage, String? tag}) {
    final usageStr = usage != null ? ' usage: $usage' : '';
    debug('📊 사용량 이벤트: $event$usageStr', tag: tag ?? 'Usage');
  }
  
  /// 캐시 관련 로그
  static void cacheEvent(String event, String cacheType, {String? key, String? tag}) {
    final keyStr = key != null ? ' key: $key' : '';
    debug('💾 캐시 이벤트: $event ($cacheType)$keyStr', tag: tag ?? 'Cache');
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔧 개발 편의 메서드들
  // ────────────────────────────────────────────────────────────────────────
  
  /// 조건부 로깅 (디버그 모드에서만)
  static void debugIf(bool condition, String message, {String? tag}) {
    if (kDebugMode && condition) {
      debug(message, tag: tag);
    }
  }
  
  /// TODO 표시 로그 (개발 중 임시 로그)
  static void todo(String message, {String? tag}) {
    if (kDebugMode) {
      LoggingUtils.warning('🚧 TODO: $message', tag: tag ?? 'TODO');
    }
  }
  
  /// FIXME 표시 로그 (수정이 필요한 부분)
  static void fixme(String message, {String? tag}) {
    if (kDebugMode) {
      LoggingUtils.warning('🔧 FIXME: $message', tag: tag ?? 'FIXME');
    }
  }
  
  /// 시간 측정 시작
  static Stopwatch startTimer(String operation, {String? tag}) {
    if (kDebugMode) {
      debug('⏱️ 타이머 시작: $operation', tag: tag ?? 'Timer');
    }
    return Stopwatch()..start();
  }
  
  /// 시간 측정 종료
  static void stopTimer(Stopwatch stopwatch, String operation, {String? tag}) {
    stopwatch.stop();
    if (kDebugMode) {
      final elapsed = stopwatch.elapsedMilliseconds;
      performance('⏱️ $operation 완료: ${elapsed}ms', tag: tag ?? 'Timer');
    }
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🎨 포맷팅 헬퍼들
  // ────────────────────────────────────────────────────────────────────────
  
  /// Map을 읽기 쉬운 문자열로 변환
  static String formatMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return '{}';
    
    final entries = map.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
    return '{$entries}';
  }
  
  /// List를 읽기 쉬운 문자열로 변환
  static String formatList(List<dynamic>? list) {
    if (list == null || list.isEmpty) return '[]';
    return '[${list.join(', ')}]';
  }
  
  /// 큰 숫자를 읽기 쉽게 포맷
  static String formatNumber(num? number) {
    if (number == null) return '0';
    if (number < 1000) return number.toString();
    if (number < 1000000) return '${(number / 1000).toStringAsFixed(1)}K';
    return '${(number / 1000000).toStringAsFixed(1)}M';
  }
}

/// 🎯 로깅 관련 확장 메서드들
extension LoggingExtensions on Object? {
  /// 객체를 로그 친화적 문자열로 변환
  String get logString {
    if (this == null) return 'null';
    if (this is Map) return LoggingUtils.formatMap(this as Map<String, dynamic>);
    if (this is List) return LoggingUtils.formatList(this as List<dynamic>);
    if (this is num) return LoggingUtils.formatNumber(this as num);
    return toString();
  }
}