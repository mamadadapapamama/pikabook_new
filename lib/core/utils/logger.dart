import 'package:flutter/foundation.dart';

/// 로그 레벨 정의
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// 중앙 집중식 로깅 시스템
/// 로그 레벨과 태그를 지원하여 문제를 한눈에 파악할 수 있도록 함
class Logger {
  /// 최소 로그 레벨 (이 레벨 이상만 출력)
  static LogLevel _minLevel = LogLevel.debug;
  
  /// 릴리즈 모드에서 로그 출력 여부
  static bool _enableLogInRelease = false;
  
  /// 로그 레벨별 색상 이모지
  static const Map<LogLevel, String> _levelEmojis = {
    LogLevel.debug: '🔍',
    LogLevel.info: 'ℹ️',
    LogLevel.warning: '⚠️',
    LogLevel.error: '❌',
  };
  
  /// 로그 레벨별 텍스트
  static const Map<LogLevel, String> _levelTexts = {
    LogLevel.debug: 'DEBUG',
    LogLevel.info: 'INFO',
    LogLevel.warning: 'WARN',
    LogLevel.error: 'ERROR',
  };

  /// 최소 로그 레벨 설정
  static void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  /// 릴리즈 모드에서 로그 출력 여부 설정
  static void setEnableLogInRelease(bool enable) {
    _enableLogInRelease = enable;
  }

  /// 로그 출력 (내부 메서드)
  static void _log(LogLevel level, String tag, String message, [Object? error]) {
    // 릴리즈 모드에서 로그 레벨 체크
    if (kReleaseMode && !_enableLogInRelease) {
      return;
    }
    
    // 최소 로그 레벨 체크
    if (level.index < _minLevel.index) {
      return;
    }
    
    final emoji = _levelEmojis[level] ?? '';
    final levelText = _levelTexts[level] ?? '';
    final timestamp = DateTime.now().toIso8601String().substring(11, 19); // HH:MM:SS
    
    String logMessage = '$emoji [$levelText] [$timestamp]';
    if (tag.isNotEmpty) {
      logMessage += ' [$tag]';
    }
    logMessage += ' $message';
    
    if (error != null) {
      logMessage += '\n$error';
    }
    
    if (kReleaseMode) {
      print(logMessage);
    } else {
      debugPrint(logMessage);
    }
  }

  /// 디버그 로그
  static void debug(String message, {String tag = ''}) {
    _log(LogLevel.debug, tag, message);
  }

  /// 정보 로그
  static void info(String message, {String tag = ''}) {
    _log(LogLevel.info, tag, message);
  }

  /// 경고 로그
  static void warning(String message, {String tag = '', Object? error}) {
    _log(LogLevel.warning, tag, message, error);
  }

  /// 오류 로그
  static void error(String message, {String tag = '', Object? error}) {
    _log(LogLevel.error, tag, message, error);
  }

  /// 성능 측정용 로그
  static void performance(String message, {String tag = ''}) {
    if (kDebugMode) {
      _log(LogLevel.info, tag, '⏱️ $message');
    }
  }

  /// API 호출 로그
  static void api(String message, {String tag = ''}) {
    if (kDebugMode) {
      _log(LogLevel.info, tag, '🌐 $message');
    }
  }

  /// 데이터베이스 로그
  static void database(String message, {String tag = ''}) {
    if (kDebugMode) {
      _log(LogLevel.info, tag, '🗄️ $message');
    }
  }

  /// 인증 로그
  static void auth(String message, {String tag = ''}) {
    if (kDebugMode) {
      _log(LogLevel.info, tag, '🔐 $message');
    }
  }

  /// 구독/결제 로그
  static void subscription(String message, {String tag = ''}) {
    if (kDebugMode) {
      _log(LogLevel.info, tag, '💳 $message');
    }
  }

  /// UI 로그
  static void ui(String message, {String tag = ''}) {
    if (kDebugMode) {
      _log(LogLevel.info, tag, '🎨 $message');
    }
  }
} 