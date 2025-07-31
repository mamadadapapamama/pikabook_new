/// 🔧 공통 Enum 유틸리티 클래스
/// 다양한 enum들에서 사용되는 공통 기능들을 중앙 집중 관리합니다.

class EnumUtils {
  // ────────────────────────────────────────────────────────────────────────
  // 🔄 문자열 <-> Enum 변환 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// Enum 값을 문자열로 변환 (name 속성 사용)
  static String enumToString<T extends Enum>(T enumValue) {
    return enumValue.name;
  }
  
  /// 문자열을 Enum으로 변환 (안전한 변환, 기본값 지원)
  static T? stringToEnum<T extends Enum>(
    List<T> enumValues,
    String? value, {
    T? defaultValue,
    bool ignoreCase = true,
  }) {
    if (value == null || value.isEmpty) return defaultValue;
    
    final searchValue = ignoreCase ? value.toLowerCase() : value;
    
    for (final enumValue in enumValues) {
      final enumName = ignoreCase ? enumValue.name.toLowerCase() : enumValue.name;
      if (enumName == searchValue) {
        return enumValue;
      }
    }
    
    return defaultValue;
  }
  
  /// 문자열을 Enum으로 변환 (예외 발생 버전)
  static T stringToEnumStrict<T extends Enum>(
    List<T> enumValues,
    String value, {
    bool ignoreCase = true,
  }) {
    final result = stringToEnum<T>(
      enumValues,
      value,
      ignoreCase: ignoreCase,
    );
    
    if (result == null) {
      throw ArgumentError('Invalid enum value: $value for ${T.toString()}');
    }
    
    return result;
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 📋 Enum 리스트 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// 모든 Enum 값들을 문자열 목록으로 변환
  static List<String> enumValuesToStringList<T extends Enum>(List<T> enumValues) {
    return enumValues.map((e) => e.name).toList();
  }
  
  /// Enum 값들을 표시 이름과 함께 Map으로 변환
  static Map<T, String> enumValuesToDisplayMap<T extends Enum>(
    List<T> enumValues,
    String Function(T) getDisplayName,
  ) {
    final Map<T, String> result = {};
    for (final enumValue in enumValues) {
      result[enumValue] = getDisplayName(enumValue);
    }
    return result;
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔍 Enum 검색 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// Enum 값이 주어진 목록에 포함되는지 확인
  static bool isEnumValueIn<T extends Enum>(T enumValue, List<T> allowedValues) {
    return allowedValues.contains(enumValue);
  }
  
  /// 문자열이 유효한 Enum 값인지 확인
  static bool isValidEnumString<T extends Enum>(
    List<T> enumValues,
    String? value, {
    bool ignoreCase = true,
  }) {
    return stringToEnum<T>(enumValues, value, ignoreCase: ignoreCase) != null;
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 💡 특화된 변환 함수들
  // ────────────────────────────────────────────────────────────────────────
  
  /// Enum을 JSON 직렬화용 문자열로 변환
  static String enumToJsonString<T extends Enum>(T enumValue) {
    return enumValue.name;
  }
  
  /// JSON 문자열을 Enum으로 역직렬화
  static T? enumFromJsonString<T extends Enum>(
    List<T> enumValues,
    dynamic jsonValue, {
    T? defaultValue,
  }) {
    if (jsonValue is! String) return defaultValue;
    return stringToEnum<T>(enumValues, jsonValue, defaultValue: defaultValue);
  }
  
  /// Enum을 사용자 친화적 문자열로 변환 (스네이크 케이스 -> 일반 텍스트)
  static String enumToDisplayString<T extends Enum>(T enumValue) {
    return enumValue.name
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty 
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }
}

// ────────────────────────────────────────────────────────────────────────
// 🎯 특정 프로젝트용 Enum 확장들
// ────────────────────────────────────────────────────────────────────────

/// ErrorType enum 확장 (error_handler.dart와 함께 사용)
extension ErrorTypeExtension on Enum {
  /// 에러 타입을 사용자 친화적 문자열로 변환
  String get displayName {
    return EnumUtils.enumToDisplayString(this);
  }
  
  /// JSON 직렬화
  String toJson() {
    return EnumUtils.enumToJsonString(this);
  }
}

/// 플랜 상태 관련 Enum들을 위한 확장
extension PlanStatusExtension on Enum {
  /// 상태를 한국어로 변환
  String get koreanName {
    switch (name) {
      case 'active':
        return '활성';
      case 'inactive':
        return '비활성';
      case 'cancelled':
        return '취소됨';
      case 'expired':
        return '만료됨';
      case 'pending':
        return '대기중';
      default:
        return EnumUtils.enumToDisplayString(this);
    }
  }
}