// MARK: 다국어 지원을 위한 확장 포인트
// 이 서비스는 향후 다국어 지원을 위해 리팩토링될 예정입니다.
// 현재는 중국어 핀인 생성만 지원합니다.
// 향후 언어별 발음 표기 서비스로 확장될 예정입니다 (예: 일본어 후리가나).

import 'package:flutter/foundation.dart';
import 'package:lpinyin/lpinyin.dart';

/// 중국어 텍스트에 대한 핀인 생성 서비스
class PinyinCreationService {
  // 싱글톤 패턴
  static final PinyinCreationService _instance =
      PinyinCreationService._internal();
  factory PinyinCreationService() => _instance;
  PinyinCreationService._internal();

  /// 중국어 텍스트에 대한 핀인 생성
  Future<String> generatePinyin(String chineseText) async {
    if (chineseText.isEmpty) return '';

    try {
      // lpinyin 라이브러리 사용
      final pinyinResult = PinyinHelper.getPinyinE(
        chineseText,
        separator: ' ',
        format: PinyinFormat.WITH_TONE_MARK,
        defPinyin: '', // 변환할 수 없는 문자는 빈 문자열로
      );

      return pinyinResult;
    } catch (e) {
      debugPrint('핀인 생성 중 오류 발생: $e');
      return '';
    }
  }

  /// 병렬 처리를 위한 격리 함수
  Future<String> generatePinyinIsolate(String chineseText) async {
    try {
      return await compute(_generatePinyinInIsolate, chineseText);
    } catch (e) {
      debugPrint('핀인 생성 격리 함수 실행 중 오류 발생: $e');
      return '';
    }
  }

  /// 격리 환경에서 실행되는 핀인 생성 함수
  static String _generatePinyinInIsolate(String chineseText) {
    if (chineseText.isEmpty) return '';

    try {
      return PinyinHelper.getPinyinE(
        chineseText,
        separator: ' ',
        format: PinyinFormat.WITH_TONE_MARK,
        defPinyin: '',
      );
    } catch (e) {
      return '';
    }
  }

  /// 핀인 포맷팅 (필요시 사용)
  String formatPinyin(String pinyin) {
    if (pinyin.isEmpty) return '';

    // 기본적인 포맷팅 (공백 정리 등)
    return pinyin.trim();
  }
}
