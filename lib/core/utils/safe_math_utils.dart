/// 안전한 수학 계산 유틸리티
/// NaN, 무한대 값을 방지하고 기본값을 제공합니다
class SafeMathUtils {
  /// 안전한 곱셈 (NaN 방지)
  static double safeMul(double a, double b, {double defaultValue = 0.0}) {
    if (a.isNaN || a.isInfinite || b.isNaN || b.isInfinite) {
      return defaultValue;
    }
    final result = a * b;
    return result.isNaN || result.isInfinite ? defaultValue : result;
  }
  
  /// 안전한 나눗셈 (NaN, 0으로 나누기 방지)
  static double safeDiv(double a, double b, {double defaultValue = 0.0}) {
    if (a.isNaN || a.isInfinite || b.isNaN || b.isInfinite || b == 0) {
      return defaultValue;
    }
    final result = a / b;
    return result.isNaN || result.isInfinite ? defaultValue : result;
  }
  
  /// 안전한 크기 값 (UI 레이아웃용)
  static double safeSize(double size, {double defaultValue = 24.0}) {
    if (size.isNaN || size.isInfinite || size <= 0) {
      return defaultValue;
    }
    return size;
  }
  
  /// 안전한 비율 계산 (0~1 범위)
  static double safeRatio(double value, double total, {double defaultValue = 0.0}) {
    if (value.isNaN || value.isInfinite || total.isNaN || total.isInfinite || total <= 0) {
      return defaultValue;
    }
    final ratio = value / total;
    if (ratio.isNaN || ratio.isInfinite) {
      return defaultValue;
    }
    return ratio.clamp(0.0, 1.0);
  }
  
  /// 안전한 화면 크기 계산
  static double safeScreenDimension(double dimension, {double defaultValue = 400.0}) {
    if (dimension.isNaN || dimension.isInfinite || dimension <= 0) {
      return defaultValue;
    }
    return dimension;
  }
} 