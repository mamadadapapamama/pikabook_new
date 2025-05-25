import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../core/models/dictionary.dart';

/// CC-CEDICT 사전 서비스
/// CC-CEDICT 사전 데이터를 사용하여 중국어 단어를 검색합니다.
class CcCedictService {
  // 싱글톤 패턴 구현
  static final CcCedictService _instance = CcCedictService._internal();
  factory CcCedictService() => _instance;
  CcCedictService._internal();

  // 사전 데이터 캐시
  final Map<String, DictionaryEntry> _cache = {};
  
  // 초기화 완료 여부
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // CC-CEDICT 데이터 로드
      final String jsonString = await rootBundle.loadString('assets/dictionary/cc_cedict.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      
      // 캐시에 데이터 추가
      jsonData.forEach((word, data) {
        _cache[word] = DictionaryEntry(
          word: word,
          pinyin: data['pinyin'] ?? '',
          meaning: data['meaning'] ?? '',
          source: 'cc_cedict',
        );
      });
      
      _isInitialized = true;
      debugPrint('CC-CEDICT 서비스 초기화 완료');
    } catch (e) {
      debugPrint('CC-CEDICT 서비스 초기화 중 오류 발생: $e');
      rethrow;
    }
  }

  // 초기화 검증
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  // 단어 검색
  Future<DictionaryEntry?> lookup(String word) async {
    try {
      await _ensureInitialized();
      
      // 캐시에서 검색
      return _cache[word];
    } catch (e) {
      debugPrint('CC-CEDICT 단어 검색 중 오류 발생: $e');
      return null;
    }
  }

  // 캐시 정리
  void clearCache() {
    _cache.clear();
    _isInitialized = false;
    debugPrint('CC-CEDICT 캐시 정리 완료');
  }
} 