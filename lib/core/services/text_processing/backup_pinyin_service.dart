import 'package:flutter/foundation.dart';
import 'package:lpinyin/lpinyin.dart' as lpinyin;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../dictionary/internal_cn_dictionary_service.dart';

/// 중국어 텍스트에 대한 핀인 생성 서비스 (백업용)
/// 1. 내부 사전 검색
/// 2. 실패 시 Google Translation API 사용
/// 3. 마지막으로 로컬 라이브러리 사용
class BackupPinyinService {
  // 싱글톤 패턴
  static final BackupPinyinService _instance = BackupPinyinService._internal();
  factory BackupPinyinService() => _instance;
  
  // 내부 사전 서비스
  final InternalCnDictionaryService _dictionaryService = InternalCnDictionaryService();
  
  // 핀인 변환 캐시
  final Map<String, String> _cache = {};
  
  // Google Translation API 키
  String? _googleApiKey;
  
  BackupPinyinService._internal();
  
  /// 중국어 텍스트에 대한 핀인 생성 (백업용)
  Future<String> generatePinyin(String chineseText) async {
    if (chineseText.isEmpty) return '';
    
    // 캐시 확인
    if (_cache.containsKey(chineseText)) {
      if (kDebugMode) debugPrint('캐시에서 핀인 반환: "${_truncateForLog(chineseText)}"');
      return _cache[chineseText]!;
    }
    
    try {
      // 1. 내부 사전에서 검색
      final dictionaryEntry = await _dictionaryService.lookupAsync(chineseText);
      if (dictionaryEntry?.pinyin != null && dictionaryEntry!.pinyin!.isNotEmpty) {
        if (kDebugMode) debugPrint('내부 사전에서 핀인 찾음: "${_truncateForLog(chineseText)}"');
        _cache[chineseText] = dictionaryEntry.pinyin!;
        return dictionaryEntry.pinyin!;
      }
      
      // 2. Google Translation API 시도
      try {
        if (kDebugMode) debugPrint('Google Translation API로 핀인 생성 시도: "${_truncateForLog(chineseText)}"');
        final pinyinResult = await _generatePinyinWithGoogle(chineseText);
        if (pinyinResult.isNotEmpty) {
          _cache[chineseText] = pinyinResult;
          return pinyinResult;
        }
      } catch (googleError) {
        if (kDebugMode) debugPrint('Google Translation API 실패, 로컬 처리로 전환: $googleError');
      }
      
      // 3. 로컬 라이브러리 처리
      if (kDebugMode) debugPrint('로컬 라이브러리로 핀인 생성: "${_truncateForLog(chineseText)}"');
      final pinyinResult = lpinyin.PinyinHelper.getPinyinE(
        chineseText,
        separator: ' ',
        format: lpinyin.PinyinFormat.WITH_TONE_MARK,
        defPinyin: '', // 변환할 수 없는 문자는 빈 문자열로
      );
      
      _cache[chineseText] = pinyinResult;
      return pinyinResult;
    } catch (e) {
      if (kDebugMode) debugPrint('핀인 생성 중 오류 발생: $e');
      return '';
    }
  }
  
  /// Google Translation API로 핀인 생성
  Future<String> _generatePinyinWithGoogle(String text) async {
    if (_googleApiKey == null) {
      throw Exception('Google API 키가 설정되지 않았습니다.');
    }
    
    final response = await http.post(
      Uri.parse('https://translation.googleapis.com/language/translate/v2'),
      body: {
        'q': text,
        'source': 'zh-CN',
        'target': 'en',
        'format': 'text',
        'key': _googleApiKey,
      },
    );
    
    if (response.statusCode != 200) {
      throw Exception('Google Translation API 호출 실패: ${response.body}');
    }
    
    final result = jsonDecode(response.body);
    return result['data']['translations'][0]['translatedText'];
  }
  
  /// 캐시 관리
  void clearCache() {
    _cache.clear();
    if (kDebugMode) debugPrint('핀인 캐시 초기화됨');
  }
  
  /// 로깅용 텍스트 축약
  String _truncateForLog(String text) {
    if (text.length <= 20) return text;
    return '${text.substring(0, 20)}...';
  }
  
  /// Google Translation API로 핀인과 한글 번역 모두 반환
  Future<Map<String, String>> generatePinyinAndTranslation(String text) async {
    if (_googleApiKey == null) {
      throw Exception('Google API 키가 설정되지 않았습니다.');
    }

    // 1. 핀인(영어로 번역) 요청
    final pinyinResponse = await http.post(
      Uri.parse('https://translation.googleapis.com/language/translate/v2'),
      body: {
        'q': text,
        'source': 'zh-CN',
        'target': 'en',
        'format': 'text',
        'key': _googleApiKey,
      },
    );
    if (pinyinResponse.statusCode != 200) {
      throw Exception('Google Translation API(핀인) 호출 실패: ${pinyinResponse.body}');
    }
    final pinyinResult = jsonDecode(pinyinResponse.body);
    final pinyin = pinyinResult['data']['translations'][0]['translatedText'] ?? '';

    // 2. 한글 번역 요청
    final korResponse = await http.post(
      Uri.parse('https://translation.googleapis.com/language/translate/v2'),
      body: {
        'q': text,
        'source': 'zh-CN',
        'target': 'ko',
        'format': 'text',
        'key': _googleApiKey,
      },
    );
    if (korResponse.statusCode != 200) {
      throw Exception('Google Translation API(한글) 호출 실패: ${korResponse.body}');
    }
    final korResult = jsonDecode(korResponse.body);
    final korean = korResult['data']['translations'][0]['translatedText'] ?? '';

    return {
      'pinyin': pinyin,
      'korean': korean,
    };
  }
} 