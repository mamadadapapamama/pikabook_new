import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 네트워크 연결 상태 관리 서비스
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  List<ConnectivityResult> _connectionStatus = [ConnectivityResult.none];

  /// 현재 연결 상태 확인
  Future<bool> get isConnected async {
    try {
      final result = await _connectivity.checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('연결 상태 확인 실패: $e');
      }
      return false;
    }
  }

  /// 연결 상태 스트림
  Stream<bool> get connectionStream {
    return _connectivity.onConnectivityChanged
        .map((result) => !result.contains(ConnectivityResult.none));
  }

  /// 연결 상태 모니터링 시작
  void startMonitoring() {
    if (_subscription != null) return;

    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> result) {
        _connectionStatus = result;
        if (kDebugMode) {
          debugPrint('연결 상태 변경: $result');
        }
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('연결 상태 모니터링 오류: $error');
        }
      },
    );
  }

  /// 연결 상태 모니터링 중지
  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// 리소스 정리
  void dispose() {
    stopMonitoring();
  }
} 