/// 🔤 문자열 유틸리티 클래스
/// 문자열 검증, 변환, 포맷팅 등의 공통 기능을 제공합니다.

class StringUtils {
  // ────────────────────────────────────────────────────────────────────────
  // 🔍 문자열 검증 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// null 또는 빈 문자열인지 확인
  static bool isNullOrEmpty(String? value) {
    return value == null || value.isEmpty;
  }
  
  /// null이 아니고 비어있지 않은지 확인
  static bool isNotNullOrEmpty(String? value) {
    return value != null && value.isNotEmpty;
  }
  
  /// null 또는 공백만 있는 문자열인지 확인
  static bool isNullOrWhitespace(String? value) {
    return value == null || value.trim().isEmpty;
  }
  
  /// null이 아니고 공백이 아닌 실제 내용이 있는지 확인
  static bool hasContent(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
  
  /// 최소 길이 검증
  static bool hasMinLength(String? value, int minLength) {
    return value != null && value.length >= minLength;
  }
  
  /// 최대 길이 검증
  static bool hasMaxLength(String? value, int maxLength) {
    return value != null && value.length <= maxLength;
  }
  
  /// 길이 범위 검증
  static bool isLengthInRange(String? value, int minLength, int maxLength) {
    return value != null && 
           value.length >= minLength && 
           value.length <= maxLength;
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔄 안전한 문자열 변환
  // ────────────────────────────────────────────────────────────────────────
  
  /// null-safe 문자열 변환
  static String safeString(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    if (value is String) return value;
    return value.toString();
  }
  
  /// null-safe trim
  static String safeTrim(String? value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    return value.trim();
  }
  
  /// null-safe toLowerCase
  static String safeToLowerCase(String? value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    return value.toLowerCase();
  }
  
  /// null-safe toUpperCase
  static String safeToUpperCase(String? value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    return value.toUpperCase();
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 📝 문자열 포맷팅 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// 첫 글자를 대문자로 변환
  static String capitalize(String? value) {
    if (isNullOrEmpty(value)) return '';
    final trimmed = value!.trim();
    if (trimmed.isEmpty) return '';
    return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
  }
  
  /// 각 단어의 첫 글자를 대문자로 변환 (Title Case)
  static String toTitleCase(String? value) {
    if (isNullOrEmpty(value)) return '';
    return value!
        .trim()
        .split(' ')
        .map((word) => capitalize(word))
        .join(' ');
  }
  
  /// 카멜케이스를 읽기 쉬운 텍스트로 변환
  static String camelCaseToWords(String camelCase) {
    if (isNullOrEmpty(camelCase)) return '';
    
    return camelCase
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
        .trim()
        .toLowerCase();
  }
  
  /// 스네이크 케이스를 읽기 쉬운 텍스트로 변환
  static String snakeCaseToWords(String snakeCase) {
    if (isNullOrEmpty(snakeCase)) return '';
    
    return snakeCase
        .replaceAll('_', ' ')
        .trim();
  }
  
  /// 문자열을 지정된 길이로 잘라내기 (말줄임표 포함)
  static String truncate(String? value, int maxLength, {String ellipsis = '...'}) {
    if (isNullOrEmpty(value)) return '';
    if (value!.length <= maxLength) return value;
    
    final truncateLength = maxLength - ellipsis.length;
    if (truncateLength <= 0) return ellipsis;
    
    return '${value.substring(0, truncateLength)}$ellipsis';
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔍 문자열 검색 및 매칭
  // ────────────────────────────────────────────────────────────────────────
  
  /// 대소문자 무관 포함 여부 확인
  static bool containsIgnoreCase(String? text, String? search) {
    if (isNullOrEmpty(text) || isNullOrEmpty(search)) return false;
    return text!.toLowerCase().contains(search!.toLowerCase());
  }
  
  /// 대소문자 무관 시작 여부 확인
  static bool startsWithIgnoreCase(String? text, String? prefix) {
    if (isNullOrEmpty(text) || isNullOrEmpty(prefix)) return false;
    return text!.toLowerCase().startsWith(prefix!.toLowerCase());
  }
  
  /// 대소문자 무관 끝남 여부 확인
  static bool endsWithIgnoreCase(String? text, String? suffix) {
    if (isNullOrEmpty(text) || isNullOrEmpty(suffix)) return false;
    return text!.toLowerCase().endsWith(suffix!.toLowerCase());
  }
  
  /// 대소문자 무관 동일성 확인
  static bool equalsIgnoreCase(String? text1, String? text2) {
    if (text1 == null && text2 == null) return true;
    if (text1 == null || text2 == null) return false;
    return text1.toLowerCase() == text2.toLowerCase();
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🎯 특화된 검증 함수들
  // ────────────────────────────────────────────────────────────────────────
  
  /// 이메일 형식 검증 (간단한 패턴)
  static bool isValidEmail(String? email) {
    if (isNullOrEmpty(email)) return false;
    
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email!);
  }
  
  /// 숫자로만 구성되었는지 확인
  static bool isNumeric(String? value) {
    if (isNullOrEmpty(value)) return false;
    return double.tryParse(value!) != null;
  }
  
  /// 영문자로만 구성되었는지 확인
  static bool isAlphabetic(String? value) {
    if (isNullOrEmpty(value)) return false;
    final alphaRegex = RegExp(r'^[a-zA-Z]+$');
    return alphaRegex.hasMatch(value!);
  }
  
  /// 영문자와 숫자로만 구성되었는지 확인
  static bool isAlphanumeric(String? value) {
    if (isNullOrEmpty(value)) return false;
    final alphanumericRegex = RegExp(r'^[a-zA-Z0-9]+$');
    return alphanumericRegex.hasMatch(value!);
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🌏 다국어/중국어 특화 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// 중국어 문자가 포함되어 있는지 확인
  static bool containsChinese(String? text) {
    if (isNullOrEmpty(text)) return false;
    
    // 중국어 유니코드 범위: \u4e00-\u9fff (CJK Unified Ideographs)
    final chineseRegex = RegExp(r'[\u4e00-\u9fff]');
    return chineseRegex.hasMatch(text!);
  }
  
  /// 한글이 포함되어 있는지 확인
  static bool containsKorean(String? text) {
    if (isNullOrEmpty(text)) return false;
    
    // 한글 유니코드 범위: \uac00-\ud7af (한글 완성형), \u1100-\u11ff (한글 자모)
    final koreanRegex = RegExp(r'[\uac00-\ud7af\u1100-\u11ff]');
    return koreanRegex.hasMatch(text!);
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔗 문자열 조작 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// 문자열 목록을 구분자로 결합 (null/empty 값 필터링)
  static String joinNonEmpty(List<String?> values, String separator) {
    return values
        .where((value) => isNotNullOrEmpty(value))
        .map((value) => value!)
        .join(separator);
  }
  
  /// 문자열에서 특정 문자들 제거
  static String removeCharacters(String? text, String charactersToRemove) {
    if (isNullOrEmpty(text)) return '';
    
    String result = text!;
    for (int i = 0; i < charactersToRemove.length; i++) {
      result = result.replaceAll(charactersToRemove[i], '');
    }
    return result;
  }
  
  /// 연속된 공백을 하나로 압축
  static String compressWhitespace(String? text) {
    if (isNullOrEmpty(text)) return '';
    
    return text!.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// 🎯 String 확장 메서드들
extension StringExtensions on String? {
  /// null-safe isEmpty 확인
  bool get isNullOrEmpty => StringUtils.isNullOrEmpty(this);
  
  /// null-safe isNotEmpty 확인
  bool get isNotNullOrEmpty => StringUtils.isNotNullOrEmpty(this);
  
  /// 실제 내용이 있는지 확인
  bool get hasContent => StringUtils.hasContent(this);
  
  /// 안전한 trim
  String safeTrim([String defaultValue = '']) => StringUtils.safeTrim(this, defaultValue: defaultValue);
  
  /// 첫 글자 대문자화
  String get capitalized => StringUtils.capitalize(this);
  
  /// 중국어 포함 여부
  bool get containsChinese => StringUtils.containsChinese(this);
  
  /// 한글 포함 여부
  bool get containsKorean => StringUtils.containsKorean(this);
}