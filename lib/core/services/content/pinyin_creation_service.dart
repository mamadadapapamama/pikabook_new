import 'package:flutter/foundation.dart';
import 'package:lpinyin/lpinyin.dart' as lpinyin;
import 'package:flutter/material.dart';
import 'package:pinyin/pinyin.dart' as pinyin;
import 'dart:async';
import 'dart:convert';
import '../../../LLM test/llm_text_processing.dart';

/// 중국어 텍스트에 대한 핀인 생성 서비스
/// LLM 기반 핀인 생성을 우선 시도하고, 실패 시 로컬 라이브러리로 폴백
class PinyinCreationService {
  // 싱글톤 패턴
  static final PinyinCreationService _instance = PinyinCreationService._internal();
  factory PinyinCreationService() => _instance;
  
  // LLM 서비스 참조
  final UnifiedTextProcessingService _llmService = UnifiedTextProcessingService();
  
  // 핀인 변환 캐시
  final Map<String, String> _cache = {};
  
  // 다음자(多音字) 목록 - 가장 흔한 다음자들
  final Set<String> _polyphones = {
    '了', '还', '长', '地', '得', '和', '为', '中', '着', '间',
    '重', '朝', '行', '解', '好', '教', '过', '假', '角', '觉',
    '少', '空', '量', '乐', '落', '沉', '藏', '兴', '数', '血',
    '一', '不', '与', '且', '丽', '乘', '乱', '亏', '亚', '什',
    '仇', '会', '传', '似', '佛', '作', '供', '便', '俗', '倒'
  };
  
  PinyinCreationService._internal();
  
  /// 중국어 텍스트에 대한 핀인 생성 (LLM 우선, 실패 시 로컬 라이브러리 사용)
  Future<String> generatePinyin(String chineseText) async {
    if (chineseText.isEmpty) return '';
    
    // 캐시 확인
    if (_cache.containsKey(chineseText)) {
      if (kDebugMode) debugPrint('캐시에서 핀인 반환: "${_truncateForLog(chineseText)}"');
      return _cache[chineseText]!;
    }
    
    try {
      // 다음자 포함 여부 확인
      bool containsPolyphoneChar = _containsPolyphoneChar(chineseText);
      
      // 다음자 포함 또는 긴 텍스트인 경우 LLM 시도
      if ((containsPolyphoneChar || chineseText.length > 10) && chineseText.length <= 500) {
        try {
          if (kDebugMode) debugPrint('LLM으로 핀인 생성 시도: "${_truncateForLog(chineseText)}"');
          
          // LLM 핀인 생성 시도
          final List<String> pinyinResult = await _llmService.processPinyinWithLLM([chineseText]);
          
          if (pinyinResult.isNotEmpty && pinyinResult[0].isNotEmpty) {
            // 캐시에 저장
            _cache[chineseText] = pinyinResult[0];
            return pinyinResult[0];
          }
        } catch (llmError) {
          if (kDebugMode) debugPrint('LLM 핀인 생성 실패, 로컬 처리로 전환: $llmError');
          // LLM 실패 시 로컬 처리로 계속 진행
        }
      }
      
      // 로컬 라이브러리 처리
      if (kDebugMode) debugPrint('로컬 라이브러리로 핀인 생성: "${_truncateForLog(chineseText)}"');
      final pinyinResult = lpinyin.PinyinHelper.getPinyinE(
        chineseText,
        separator: ' ',
        format: lpinyin.PinyinFormat.WITH_TONE_MARK,
        defPinyin: '', // 변환할 수 없는 문자는 빈 문자열로
      );
      
      // 캐시에 저장
      _cache[chineseText] = pinyinResult;
      return pinyinResult;
    } catch (e) {
      if (kDebugMode) debugPrint('핀인 생성 중 오류 발생: $e');
      return '';
    }
  }
  
  /// 최적의 성능을 위한 격리 처리
  Future<String> generatePinyinIsolate(String chineseText) async {
    if (chineseText.isEmpty) return '';
    
    // 캐시 확인
    if (_cache.containsKey(chineseText)) {
      return _cache[chineseText]!;
    }
    
    try {
      // 긴 텍스트는 Isolate로 처리
      final result = await compute(_generatePinyinInIsolate, chineseText);
      
      // 캐시에 저장
      _cache[chineseText] = result;
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('핀인 생성 격리 함수 실행 중 오류 발생: $e');
      return await generatePinyin(chineseText); // 격리 처리 실패 시 기본 방식으로 폴백
    }
  }
  
  /// 격리 환경에서 실행되는 핀인 생성 함수
  static String _generatePinyinInIsolate(String chineseText) {
    if (chineseText.isEmpty) return '';

    try {
      return lpinyin.PinyinHelper.getPinyinE(
        chineseText,
        separator: ' ',
        format: lpinyin.PinyinFormat.WITH_TONE_MARK,
        defPinyin: '',
      );
    } catch (e) {
      return '';
    }
  }
  
  /// 단어별 핀인 생성
  Future<List<String>> generatePinyinForChars(String chineseText) async {
    if (chineseText.isEmpty) return [];
    
    try {
      final List<String> chars = chineseText.split('');
      final List<String> results = [];
      
      for (String char in chars) {
        if (char.trim().isEmpty) {
          results.add('');
          continue;
        }
        
        final pinyin = await generatePinyin(char);
        results.add(pinyin);
      }
      
      return results;
    } catch (e) {
      if (kDebugMode) debugPrint('단어별 핀인 생성 중 오류: $e');
      return [];
    }
  }
  
  /// 캐시 관리
  void clearCache() {
    _cache.clear();
    if (kDebugMode) debugPrint('핀인 캐시 초기화됨');
  }

  /// 핀인 포맷팅 (필요시 사용)
  String formatPinyin(String pinyin) {
    if (pinyin.isEmpty) return '';

    // 기본적인 포맷팅 (공백 정리 등)
    return pinyin.trim();
  }
  
  /// 텍스트에 다음자가 포함되어 있는지 확인
  bool _containsPolyphoneChar(String text) {
    for (final char in text.split('')) {
      if (_polyphones.contains(char)) {
        return true;
      }
    }
    return false;
  }
  
  /// 로깅용 텍스트 축약
  String _truncateForLog(String text) {
    if (text.length <= 20) return text;
    return '${text.substring(0, 20)}...';
  }
}