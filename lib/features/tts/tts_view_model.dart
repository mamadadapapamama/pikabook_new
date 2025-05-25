import 'package:flutter/foundation.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../core/models/processed_text.dart';
import '../../core/models/text_unit.dart';

class TtsViewModel extends ChangeNotifier {
  final TTSService _ttsService;
  
  // 상태 변수
  int? _currentUnitIndex;
  bool _isPlaying = false;
  
  // Getters
  int? get currentUnitIndex => _currentUnitIndex;
  bool get isPlaying => _isPlaying;
  
  TtsViewModel({TTSService? ttsService}) 
      : _ttsService = ttsService ?? TTSService() {
    _init();
  }
  
  Future<void> _init() async {
    await _ttsService.init();
    // TTSService의 상태 변화 감지를 위한 주기적인 체크
    Future.delayed(Duration(milliseconds: 500), () {
      if (!disposed) updateState();
    });
  }
  
  bool disposed = false;
  
  // 텍스트 유닛 재생
  Future<bool> playUnit(String text, {int? unitIndex}) async {
    if (text.isEmpty) return false;
    
    // 현재 재생 중인 유닛을 다시 클릭한 경우 중지
    if (_currentUnitIndex == unitIndex && _isPlaying) {
      await stop();
      return true;
    }
    
    try {
      await _ttsService.speak(text);
      _currentUnitIndex = unitIndex;
      _isPlaying = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('TTS 재생 중 오류: $e');
      return false;
    }
  }
  
  // 모든 유닛 재생
  Future<bool> playAllUnits(ProcessedText processedText) async {
    if (processedText.units.isEmpty) {
      return false;
    }
    
    // 현재 재생 중인 경우 중지
    if (_isPlaying) {
      await stop();
      return true;
    }
    
    try {
      await _ttsService.speakAllSegments(processedText);
      _isPlaying = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('모든 유닛 재생 중 오류: $e');
      return false;
    }
  }
  
  // 재생 중지
  Future<void> stop() async {
    await _ttsService.stop();
    _isPlaying = false;
    _currentUnitIndex = null;
    notifyListeners();
  }
  
  // 상태 업데이트 - TTSService의 상태 변화 감지용
  void updateState() {
    _isPlaying = _ttsService.state.toString().contains('playing');
    _currentUnitIndex = _ttsService.currentSegmentIndex;
    notifyListeners();
    
    // 주기적으로 상태 체크 (재생 중일 때만)
    if (!disposed) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (!disposed) updateState();
      });
    }
  }
  
  @override
  void dispose() {
    disposed = true;
    _ttsService.dispose();
    super.dispose();
  }
} 