import 'dart:io';
import '../utils/language_constants.dart';

/// 다국어 지원을 위한 언어 서비스 인터페이스
/// 이 인터페이스는 언어 처리 관련 서비스의 기본 구조를 정의합니다.
/// 향후 다양한 언어 지원을 위해 이 인터페이스를 구현하는 구체 클래스를 만들 수 있습니다.

abstract class LanguageServiceInterface {
  /// 텍스트 추출 (OCR)
  /// - imageFile: 이미지 파일
  /// - sourceLanguage: 추출할 언어 코드
  Future<String> extractText(File imageFile, {String? sourceLanguage});
  
  /// 텍스트 번역
  /// - text: 번역할 텍스트
  /// - sourceLanguage: 원본 언어 코드 
  /// - targetLanguage: 번역 대상 언어 코드
  Future<String> translateText(String text, {
    String? sourceLanguage,
    String? targetLanguage,
  });
  
  /// 텍스트를 문장으로 분리
  /// - text: 분리할 텍스트
  /// - languageCode: 언어 코드
  List<String> splitTextIntoSentences(String text, {String? languageCode});
  
  /// 발음 생성 (e.g. 핀인, 후리가나 등)
  /// - text: 원문 텍스트
  /// - languageCode: 언어 코드
  Future<String> generatePronunciation(String text, {String? languageCode});
  
  /// 지원되는 번역 언어 목록 조회
  Future<List<Map<String, String>>> getSupportedLanguages();
  
  /// 언어 감지
  /// - text: 감지할 텍스트
  Future<String> detectLanguage(String text);
  
  /// 언어 프로세서 타입 가져오기
  /// - languageCode: 언어 코드
  LanguageProcessor getLanguageProcessor(String languageCode);
}

/// 중국어 처리 서비스를 위한 확장 인터페이스
abstract class ChineseLanguageServiceInterface extends LanguageServiceInterface {
  /// 중국어 텍스트 분절
  /// - text: 분절할 중국어 텍스트
  Future<List<String>> segmentChineseText(String text);
  
  /// 핀인 생성
  /// - text: 핀인을 생성할 중국어 텍스트
  Future<String> generatePinyin(String text);
  
  /// 중국어 단어 사전 검색
  /// - word: 검색할 중국어 단어
  Future<Map<String, dynamic>?> lookupChineseWord(String word);
}

/// 일본어 처리 서비스를 위한 확장 인터페이스 (미래 확장용)
abstract class JapaneseLanguageServiceInterface extends LanguageServiceInterface {
  /// 일본어 후리가나 생성
  /// - text: 후리가나를 생성할 일본어 텍스트
  Future<String> generateFurigana(String text);
  
  /// 일본어 단어 사전 검색
  /// - word: 검색할 일본어 단어
  Future<Map<String, dynamic>?> lookupJapaneseWord(String word);
}

/// 서비스 팩토리 - 언어에 맞는 서비스 인스턴스 생성
class LanguageServiceFactory {
  // 언어 코드에 따른 서비스 인스턴스 반환
  static LanguageServiceInterface getServiceForLanguage(String languageCode) {
    // MVP에서는 중국어 서비스만 구현
    return GoogleCloudLanguageService();
  }
  
  // 확장: 중국어 서비스 인스턴스 반환
  static ChineseLanguageServiceInterface getChineseService() {
    // 실제 구현체 반환 (MVP에서는 가상 클래스)
    return GoogleCloudLanguageService() as ChineseLanguageServiceInterface;
  }
}

/// 구글 클라우드 기반 언어 서비스 (실제 구현은 별도의 파일에서 수행)
class GoogleCloudLanguageService implements LanguageServiceInterface {
  // 임시 구현 (실제 GoogleCloudService의 메서드를 호출해야 함)
  @override
  Future<String> extractText(File imageFile, {String? sourceLanguage}) async {
    throw UnimplementedError('이 메서드는 실제 구현 클래스에서 구현해야 합니다.');
  }
  
  @override
  Future<String> translateText(String text, {String? sourceLanguage, String? targetLanguage}) async {
    throw UnimplementedError('이 메서드는 실제 구현 클래스에서 구현해야 합니다.');
  }
  
  @override
  List<String> splitTextIntoSentences(String text, {String? languageCode}) {
    throw UnimplementedError('이 메서드는 실제 구현 클래스에서 구현해야 합니다.');
  }
  
  @override
  Future<String> generatePronunciation(String text, {String? languageCode}) async {
    throw UnimplementedError('이 메서드는 실제 구현 클래스에서 구현해야 합니다.');
  }
  
  @override
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    throw UnimplementedError('이 메서드는 실제 구현 클래스에서 구현해야 합니다.');
  }
  
  @override
  Future<String> detectLanguage(String text) async {
    throw UnimplementedError('이 메서드는 실제 구현 클래스에서 구현해야 합니다.');
  }
  
  @override
  LanguageProcessor getLanguageProcessor(String languageCode) {
    return getProcessorForLanguage(languageCode);
  }
}

// MARK: 다국어 지원을 위한 확장 포인트
// 이 주석 아래에 각 언어별 구체 클래스를 구현해야 합니다.
// e.g. ChineseLanguageService, JapaneseLanguageService 등 