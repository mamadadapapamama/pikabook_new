import 'package:flutter/services.dart';

/// 스크린샷 감지 서비스
/// 
/// 플랫폼별 네이티브 구현을 통해 스크린샷을 감지하고 콜백을 제공합니다.
class ScreenshotService {
  static final ScreenshotService _instance = ScreenshotService._internal();
  factory ScreenshotService() => _instance;
  ScreenshotService._internal();

  final MethodChannel _channel = const MethodChannel('com.example.pikabook/screenshot');
  Function? _onScreenshotTaken;
  bool _isDetectionActive = false;

  /// 스크린샷 감지 초기화
  /// 
  /// [callback] 스크린샷이 감지되었을 때 호출될 함수
  Future<void> initialize(Function callback) async {
    _onScreenshotTaken = callback;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onScreenshotTaken' && _onScreenshotTaken != null) {
        _onScreenshotTaken!();
      }
    });
  }

  /// 스크린샷 감지 시작
  Future<bool> startDetection() async {
    if (_isDetectionActive) return true;
    
    try {
      final result = await _channel.invokeMethod('startScreenshotDetection');
      _isDetectionActive = result == true;
      return _isDetectionActive;
    } catch (e) {
      print('스크린샷 감지 시작 중 오류 발생: $e');
      return false;
    }
  }

  /// 스크린샷 감지 중지
  Future<bool> stopDetection() async {
    if (!_isDetectionActive) return true;
    
    try {
      final result = await _channel.invokeMethod('stopScreenshotDetection');
      _isDetectionActive = !(result == true);
      return !_isDetectionActive;
    } catch (e) {
      print('스크린샷 감지 중지 중 오류 발생: $e');
      return false;
    }
  }

  /// 스크린샷 감지 활성화 여부
  bool get isActive => _isDetectionActive;
} 