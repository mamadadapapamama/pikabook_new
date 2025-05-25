import 'dart:async';
import 'package:flutter/material.dart';
import '../services/media/screenshot_service.dart';
import '../../core/theme/tokens/color_tokens.dart';

class ScreenshotServiceHelper {
  final ScreenshotService _screenshotService = ScreenshotService();
  bool _isShowingScreenshotWarning = false;
  Timer? _screenshotWarningTimer;
  
  Future<void> initialize(Function(DateTime) onScreenshotDetected) async {
    await _screenshotService.initialize((timestamp) {
      onScreenshotDetected(timestamp);
    });
  }
  
  Future<void> startDetection() async {
    await _screenshotService.startDetection();
  }
  
  Future<void> stopDetection() async {
    await _screenshotService.stopDetection();
  }
  
  void showWarning(BuildContext context) {
    if (_isShowingScreenshotWarning) return;
    
    _isShowingScreenshotWarning = true;
    
    // 스크린샷 경고 다이얼로그 표시
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('스크린샷 감지됨'),
        content: const Text(
          '저작권 보호를 위해 스크린샷이 제한됩니다. 콘텐츠 공유는 앱 내 공유 기능을 사용해주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _isShowingScreenshotWarning = false;
            },
            child: const Text('확인'),
          ),
        ],
      ),
    ).then((_) {
      _isShowingScreenshotWarning = false;
    });
    
    // 일정 시간 후 경고 상태 자동 초기화
    _screenshotWarningTimer?.cancel();
    _screenshotWarningTimer = Timer(const Duration(seconds: 5), () {
      _isShowingScreenshotWarning = false;
    });
  }
  
  void showSnackBarWarning(BuildContext context) {
    if (_isShowingScreenshotWarning) return;
    
    _isShowingScreenshotWarning = true;
    
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '원서 내용을 무단으로 공유, 배포할 경우 법적 제재를 받을 수 있습니다.',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: ColorTokens.black,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        onVisible: () {
          _screenshotWarningTimer?.cancel();
          _screenshotWarningTimer = Timer(const Duration(seconds: 5), () {
            _isShowingScreenshotWarning = false;
          });
        },
      ),
    );
  }
  
  void dispose() {
    _screenshotWarningTimer?.cancel();
    stopDetection();
  }
}
