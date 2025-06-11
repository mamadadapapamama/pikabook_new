import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../core/models/dictionary.dart';

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
      if (kDebugMode) {
        debugPrint('📖 [CC-CEDICT] 초기화 시작');
      }
      
      // CC-CEDICT 데이터 로드
      final String jsonString = await rootBundle.loadString('assets/data/CC-Cedict.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      
      if (kDebugMode) {
        debugPrint('📖 [CC-CEDICT] JSON 데이터 로드 완료: ${jsonData.length}개 항목');
      }
      
      // 캐시에 데이터 추가
      jsonData.forEach((word, data) {
        _cache[word] = DictionaryEntry.multiLanguage(
          word: word,
          pinyin: data['pinyin'] ?? '',
          meaningEn: data['meaning'] ?? '',
          source: 'cc_cedict',
        );
      });
      
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('✅ [CC-CEDICT] 초기화 완료: ${_cache.length}개 항목 캐시됨');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [CC-CEDICT] 파일을 찾을 수 없습니다. 내부 사전만 사용합니다: $e');
      }
      _isInitialized = true; // 오류가 있어도 초기화 완료로 처리
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
      
      if (kDebugMode) {
        debugPrint('📖 [CC-CEDICT] 단어 검색: "$word"');
        debugPrint('📖 [CC-CEDICT] 캐시 크기: ${_cache.length}개');
      }
      
      // 캐시에서 검색
      final result = _cache[word];
      
      if (kDebugMode) {
        if (result != null) {
          debugPrint('✅ [CC-CEDICT] 단어 찾음: "$word"');
          debugPrint('   병음: ${result.pinyin}');
          debugPrint('   의미: ${result.meaning}');
        } else {
          debugPrint('❌ [CC-CEDICT] 단어 찾지 못함: "$word"');
        }
      }
      
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('💥 [CC-CEDICT] 단어 검색 중 오류 발생: $e');
      }
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