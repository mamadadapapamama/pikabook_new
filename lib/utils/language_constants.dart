/// 다국어 지원을 위한 언어 관련 상수 정의
/// 향후 확장성을 고려하여 모든 언어 관련 상수를 이 파일에 중앙화합니다.

// 지원하는 소스 언어 (학습 대상 언어)
class SourceLanguage {
  static const String CHINESE = 'zh-CN';
  static const String CHINESE_TRADITIONAL = 'zh-TW';
  static const String JAPANESE = 'ja';
  static const String ENGLISH = 'en';
  static const String KOREAN = 'ko';
  
  // MVP에서는 중국어만 지원
  static const String DEFAULT = CHINESE;
  
  // 향후 지원 예정인 언어들
  static const List<String> SUPPORTED = [CHINESE, CHINESE_TRADITIONAL];
  
  // 확장 단계에서 지원 예정인 언어들
  static const List<String> FUTURE_SUPPORTED = [JAPANESE, ENGLISH, KOREAN];
  
  // 언어 코드에 해당하는 언어 이름을 반환
  static String getName(String code) {
    switch (code) {
      case CHINESE:
        return '중국어 (간체)';
      case CHINESE_TRADITIONAL:
        return '중국어 (번체)';
      case JAPANESE:
        return '일본어';
      case ENGLISH:
        return '영어';
      case KOREAN:
        return '한국어';
      default:
        return '알 수 없는 언어';
    }
  }
}

// 지원하는 타겟 언어 (번역 결과 언어)
class TargetLanguage {
  static const String KOREAN = 'ko';
  static const String ENGLISH = 'en';
  static const String CHINESE = 'zh-CN';
  static const String JAPANESE = 'ja';
  
  // MVP에서는 한국어와 영어만 지원
  static const String DEFAULT = KOREAN;
  
  // 현재 지원 언어
  static const List<String> SUPPORTED = [KOREAN, ENGLISH];
  
  // 확장 단계에서 지원 예정인 언어들
  static const List<String> FUTURE_SUPPORTED = [CHINESE, JAPANESE];
  
  // 언어 코드에 해당하는 언어 이름을 반환
  static String getName(String code) {
    switch (code) {
      case KOREAN:
        return '한국어';
      case ENGLISH:
        return 'English';
      case CHINESE:
        return '중국어';
      case JAPANESE:
        return '일본어';
      default:
        return '알 수 없는 언어';
    }
  }
}

// TTS 언어 설정
class TtsLanguage {
  static const String CHINESE = 'zh-CN';
  static const String KOREAN = 'ko-KR';
  static const String ENGLISH = 'en-US';
  static const String JAPANESE = 'ja-JP';
  
  // TTS 음성 매핑
  static String getVoiceName(String languageCode) {
    switch (languageCode) {
      case CHINESE:
        return 'zh-CN-Standard-A';
      case KOREAN:
        return 'ko-KR-Standard-A';
      case ENGLISH:
        return 'en-US-Standard-C';
      case JAPANESE:
        return 'ja-JP-Standard-A';
      default:
        return 'zh-CN-Standard-A'; // 기본값
    }
  }
  
  // 언어에 해당하는 TTS 언어 코드 반환
  static String getTtsLanguageCode(String sourceLanguage) {
    switch (sourceLanguage) {
      case SourceLanguage.CHINESE:
      case SourceLanguage.CHINESE_TRADITIONAL:
        return CHINESE;
      case SourceLanguage.KOREAN:
        return KOREAN;
      case SourceLanguage.ENGLISH:
        return ENGLISH;
      case SourceLanguage.JAPANESE:
        return JAPANESE;
      default:
        return CHINESE; // 기본값 (MVPㄴ)
    }
  }
}

/// 언어별 처리 방식 정의
enum LanguageProcessor {
  chinese,  // 중국어 처리기 (분절, 핀인 등)
  japanese, // 일본어 처리기 (후리가나 등) - 향후 확장
  english,  // 영어 처리기 - 향후 확장
  korean,   // 한국어 처리기 - 향후 확장
  auto,     // 자동 감지
}

// 언어 코드로부터 처리기 타입 결정
LanguageProcessor getProcessorForLanguage(String languageCode) {
  switch (languageCode) {
    case SourceLanguage.CHINESE:
    case SourceLanguage.CHINESE_TRADITIONAL:
      return LanguageProcessor.chinese;
    case SourceLanguage.JAPANESE:
      return LanguageProcessor.japanese;
    case SourceLanguage.ENGLISH:
      return LanguageProcessor.english;
    case SourceLanguage.KOREAN:
      return LanguageProcessor.korean;
    default:
      return LanguageProcessor.auto;
  }
}

// 언어별 문장 분리 규칙
class SentenceSplitRules {
  // 중국어 문장 분리 패턴
  static final RegExp chineseSentencePattern = RegExp(r'([。！？；]+)');
  
  // 일본어 문장 분리 패턴 (향후 구현)
  static final RegExp japaneseSentencePattern = RegExp(r'([。！？；]+)');
  
  // 영어 문장 분리 패턴 (향후 구현)
  static final RegExp englishSentencePattern = RegExp(r'(?<=[.!?])\s+');
  
  // 한국어 문장 분리 패턴 (향후 구현)
  static final RegExp koreanSentencePattern = RegExp(r'(?<=[.!?])\s+');
  
  // 언어에 맞는 문장 분리 패턴 반환
  static RegExp getPatternForLanguage(String languageCode) {
    switch (languageCode) {
      case SourceLanguage.CHINESE:
      case SourceLanguage.CHINESE_TRADITIONAL:
        return chineseSentencePattern;
      case SourceLanguage.JAPANESE:
        return japaneseSentencePattern;
      case SourceLanguage.ENGLISH:
        return englishSentencePattern;
      case SourceLanguage.KOREAN:
        return koreanSentencePattern;
      default:
        return chineseSentencePattern; // 기본값
    }
  }
} 