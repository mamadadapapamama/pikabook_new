import 'package:shared_preferences/shared_preferences.dart';
import '../models/text_processing_mode.dart';

/// 사용자 기본 설정을 관리하는 서비스
class UserPreferencesService {
  // 싱글톤 패턴 구현
  static final UserPreferencesService _instance =
      UserPreferencesService._internal();
  factory UserPreferencesService() => _instance;
  UserPreferencesService._internal();

  // SharedPreferences 키
  static const String _textProcessingModeKey = 'text_processing_mode';
  static const String _onboardingCompletedKey = 'onboarding_completed';

  // 기본 텍스트 처리 모드 (온보딩에서 설정)
  Future<void> setDefaultTextProcessingMode(TextProcessingMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_textProcessingModeKey, mode.index);
  }

  // 현재 텍스트 처리 모드 가져오기
  Future<TextProcessingMode> getTextProcessingMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_textProcessingModeKey);

    // 저장된 값이 없으면 기본값 반환
    if (modeIndex == null) {
      return TextProcessingMode.languageLearning; // 기본값
    }

    // 저장된 인덱스가 유효한지 확인
    if (modeIndex >= 0 && modeIndex < TextProcessingMode.values.length) {
      return TextProcessingMode.values[modeIndex];
    }

    return TextProcessingMode.languageLearning; // 기본값
  }

  // 온보딩 완료 여부 설정
  Future<void> setOnboardingCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, completed);
  }

  // 온보딩 완료 여부 확인
  Future<bool> isOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompletedKey) ?? false;
  }
}
