import 'dart:async';
import 'package:flutter/foundation.dart';

/// 타임아웃 관리 클래스
class TimeoutManager {
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isActive = false;
  VoidCallback? _onTimeout;
  Function(int)? _onProgress;
  Function? _onComplete;

  /// 현재 경과 시간 (초)
  int get elapsedSeconds => _elapsedSeconds;
  
  /// 타임아웃 매니저가 활성 상태인지 확인
  bool get isActive => _isActive;

  /// 타임아웃 시작
  /// [timeoutSeconds]: 총 타임아웃 시간 (기본 30초)
  /// [onProgress]: 매초마다 호출되는 콜백 (경과 시간 전달)
  /// [onTimeout]: 타임아웃 발생시 호출되는 콜백
  /// [onComplete]: 정상 완료시 호출되는 콜백
  void start({
    int timeoutSeconds = 30,
    Function(int)? onProgress,
    VoidCallback? onTimeout,
    VoidCallback? onComplete,
  }) {
    if (_isActive) {
      if (kDebugMode) {
        debugPrint('⚠️ [TimeoutManager] 이미 실행 중입니다.');
      }
      return;
    }

    _elapsedSeconds = 0;
    _isActive = true;
    _onProgress = onProgress;
    _onTimeout = onTimeout;
    _onComplete = onComplete;

    if (kDebugMode) {
      debugPrint('⏱️ [TimeoutManager] 타임아웃 시작: ${timeoutSeconds}초');
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      
      if (kDebugMode) {
        debugPrint('⏱️ [TimeoutManager] 경과시간: ${_elapsedSeconds}초');
      }

      // 진행상황 콜백 호출
      _onProgress?.call(_elapsedSeconds);

      // 타임아웃 체크
      if (_elapsedSeconds >= timeoutSeconds) {
        if (kDebugMode) {
          debugPrint('⏰ [TimeoutManager] 타임아웃 발생: ${_elapsedSeconds}초');
        }
        
        _onTimeout?.call();
        stop();
      }
    });
  }

  /// 타임아웃 중지 (정상 완료)
  void complete() {
    if (!_isActive) return;

    if (kDebugMode) {
      debugPrint('✅ [TimeoutManager] 정상 완료: ${_elapsedSeconds}초 경과');
    }

    _onComplete?.call();
    stop();
  }

  /// 타임아웃 중지
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isActive = false;
    
    if (kDebugMode) {
      debugPrint('🛑 [TimeoutManager] 타임아웃 중지');
    }
  }

  /// 리소스 정리
  void dispose() {
    stop();
    _onProgress = null;
    _onTimeout = null;
    _onComplete = null;
  }

  /// 현재 단계에 맞는 메시지 반환
  String getCurrentMessage(String baseMessage) {
    // 테스트용: 2초/3초/5초로 단축 (원래는 10초/20초/30초)
    if (_elapsedSeconds >= 2 && _elapsedSeconds < 3) {
      return '처리 시간이 평소보다 오래 걸리고 있어요. (약 ${_elapsedSeconds}초 경과)';
    } else if (_elapsedSeconds >= 3 && _elapsedSeconds < 5) {
      return '다시 시도 중입니다…';
    } else if (_elapsedSeconds >= 5) {
      return '문제가 지속되고 있어요. 잠시 뒤에 다시 시도해 주세요.';
    }
    return baseMessage;
  }

  /// 단계별 메시지 업데이트가 필요한 시점인지 확인
  bool shouldUpdateMessage() {
    // 테스트용: 2초/3초/5초로 단축 (원래는 10초/20초/30초)
    return _elapsedSeconds == 2 || _elapsedSeconds == 3 || _elapsedSeconds == 5;
  }
} 