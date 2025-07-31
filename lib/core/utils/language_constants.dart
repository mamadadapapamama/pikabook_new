/// 🌍 통합 언어 상수 클래스
/// 다국어 지원을 위한 모든 언어 관련 상수를 중앙 집중 관리합니다.
/// 중국어 학습 중점 앱으로 중국어 관련 상수가 중심입니다.

class LanguageConstants {
  // ────────────────────────────────────────────────────────────────────────
  // 🎯 언어 코드 상수
  // ────────────────────────────────────────────────────────────────────────
  
  /// 소스 언어 (학습 대상 언어)
  static const String SOURCE_CHINESE = 'zh-CN';
  static const String SOURCE_CHINESE_TRADITIONAL = 'zh-TW';
  
  /// 타겟 언어 (번역 결과 언어)
  static const String TARGET_KOREAN = 'ko';
  static const String TARGET_ENGLISH = 'en';
  static const String TARGET_CHINESE = 'zh-CN';
  
  /// TTS 언어 코드
  static const String TTS_CHINESE = 'zh-CN';
  static const String TTS_KOREAN = 'ko-KR';
  static const String TTS_ENGLISH = 'en-US';
  
  // ────────────────────────────────────────────────────────────────────────
  // 📋 기본값 및 지원 목록
  // ────────────────────────────────────────────────────────────────────────
  
  /// 기본 소스 언어 (MVP: 중국어 간체)
  static const String DEFAULT_SOURCE = SOURCE_CHINESE;
  
  /// 기본 타겟 언어 (MVP: 한국어)
  static const String DEFAULT_TARGET = TARGET_KOREAN;
  
  /// 현재 지원하는 소스 언어 목록 (MVP)
  static const List<String> SUPPORTED_SOURCE_LANGUAGES = [SOURCE_CHINESE];
  
  /// 현재 지원하는 타겟 언어 목록 (MVP)
  static const List<String> SUPPORTED_TARGET_LANGUAGES = [TARGET_KOREAN];
  
  /// 확장 예정 소스 언어
  static const List<String> FUTURE_SOURCE_LANGUAGES = [SOURCE_CHINESE_TRADITIONAL];
  
  /// 확장 예정 타겟 언어
  static const List<String> FUTURE_TARGET_LANGUAGES = [TARGET_ENGLISH];
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔧 헬퍼 함수들
  // ────────────────────────────────────────────────────────────────────────
  
  /// 소스 언어 코드에 해당하는 언어 이름 반환
  static String getSourceLanguageName(String code) {
    switch (code) {
      case SOURCE_CHINESE:
        return '중국어 (간체)';
      case SOURCE_CHINESE_TRADITIONAL:
        return '중국어 (번체)';
      default:
        return '알 수 없는 언어';
    }
  }
  
  /// 타겟 언어 코드에 해당하는 언어 이름 반환
  static String getTargetLanguageName(String code) {
    switch (code) {
      case TARGET_KOREAN:
        return '한국어';
      case TARGET_ENGLISH:
        return 'English (Coming Soon)';
      case TARGET_CHINESE:
        return '중국어';
      default:
        return '알 수 없는 언어';
    }
  }
  
  /// TTS 언어 코드에 해당하는 음성 이름 반환
  static String getTtsVoiceName(String languageCode) {
    switch (languageCode) {
      case TTS_CHINESE:
        return 'zh-CN-Standard-A';
      case TTS_KOREAN:
        return 'ko-KR-Standard-A';
      case TTS_ENGLISH:
        return 'en-US-Standard-C';
      default:
        return 'zh-CN-Standard-A'; // 기본값
    }
  }
  
  /// 소스 언어에 해당하는 TTS 언어 코드 반환
  static String getTtsLanguageCode(String sourceLanguage) {
    switch (sourceLanguage) {
      case SOURCE_CHINESE:
      case SOURCE_CHINESE_TRADITIONAL:
        return TTS_CHINESE;
      default:
        return TTS_CHINESE; // 기본값 (MVP)
    }
  }
  
  /// 소스 언어가 지원되는지 확인
  static bool isSourceLanguageSupported(String code) {
    return SUPPORTED_SOURCE_LANGUAGES.contains(code);
  }
  
  /// 타겟 언어가 지원되는지 확인
  static bool isTargetLanguageSupported(String code) {
    return SUPPORTED_TARGET_LANGUAGES.contains(code);
  }
}

// ────────────────────────────────────────────────────────────────────────
// 🔄 하위 호환성을 위한 레거시 클래스들 (단순 래퍼)
// ────────────────────────────────────────────────────────────────────────

/// @deprecated LanguageConstants.SOURCE_* 사용 권장
class SourceLanguage {
  static const String CHINESE = LanguageConstants.SOURCE_CHINESE;
  static const String CHINESE_TRADITIONAL = LanguageConstants.SOURCE_CHINESE_TRADITIONAL;
  static const String DEFAULT = LanguageConstants.DEFAULT_SOURCE;
  static const List<String> SUPPORTED = LanguageConstants.SUPPORTED_SOURCE_LANGUAGES;
  static const List<String> FUTURE_SUPPORTED = LanguageConstants.FUTURE_SOURCE_LANGUAGES;
  
  static String getName(String code) => LanguageConstants.getSourceLanguageName(code);
}

/// @deprecated LanguageConstants.TARGET_* 사용 권장
class TargetLanguage {
  static const String KOREAN = LanguageConstants.TARGET_KOREAN;
  static const String ENGLISH = LanguageConstants.TARGET_ENGLISH;
  static const String CHINESE = LanguageConstants.TARGET_CHINESE;
  static const String DEFAULT = LanguageConstants.DEFAULT_TARGET;
  static const List<String> SUPPORTED = LanguageConstants.SUPPORTED_TARGET_LANGUAGES;
  static const List<String> FUTURE_SUPPORTED = LanguageConstants.FUTURE_TARGET_LANGUAGES;
  
  static String getName(String code) => LanguageConstants.getTargetLanguageName(code);
}

/// @deprecated LanguageConstants.TTS_* 및 getTts* 메서드 사용 권장
class TtsLanguage {
  static const String CHINESE = LanguageConstants.TTS_CHINESE;
  static const String KOREAN = LanguageConstants.TTS_KOREAN;
  static const String ENGLISH = LanguageConstants.TTS_ENGLISH;
  
  static String getVoiceName(String languageCode) => LanguageConstants.getTtsVoiceName(languageCode);
  static String getTtsLanguageCode(String sourceLanguage) => LanguageConstants.getTtsLanguageCode(sourceLanguage);
}

/// 언어별 처리 방식 정의
enum LanguageProcessor {
  chinese,  // 중국어 처리기 (분절, 핀인 등)
  auto,     // 자동 감지
}

// 언어 코드로부터 처리기 타입 결정
LanguageProcessor getProcessorForLanguage(String languageCode) {
  switch (languageCode) {
    case SourceLanguage.CHINESE:
    case SourceLanguage.CHINESE_TRADITIONAL:
      return LanguageProcessor.chinese;
    default:
      return LanguageProcessor.auto;
  }
}

// 언어별 문장 분리 규칙
class SentenceSplitRules {
  // 중국어 문장 분리 패턴
  static final RegExp chineseSentencePattern = RegExp(r'([。！？；]+)');
  
  // 언어에 맞는 문장 분리 패턴 반환
  static RegExp getPatternForLanguage(String languageCode) {
    switch (languageCode) {
      case SourceLanguage.CHINESE:
      case SourceLanguage.CHINESE_TRADITIONAL:
        return chineseSentencePattern;
      default:
        return chineseSentencePattern; // 기본값
    }
  }
} 