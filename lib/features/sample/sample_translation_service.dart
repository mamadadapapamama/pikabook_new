import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/models/dictionary.dart';

/// 샘플 모드에서 사용할 로컬 번역 데이터 서비스
class SampleTranslationService {
  // 싱글톤 패턴
  static final SampleTranslationService _instance = SampleTranslationService._internal();
  factory SampleTranslationService() => _instance;
  SampleTranslationService._internal();

  // 번역 데이터 캐시
  final Map<String, DictionaryEntry> _translations = {};
  bool _isLoaded = false;

  /// 초기화 (샘플 번역 데이터 로드)
  Future<void> initialize() async {
    if (_isLoaded) return;

    try {
      if (kDebugMode) {
        debugPrint('🏠 [샘플 번역] 로컬 데이터 로드 시작');
      }

      final String jsonString = await rootBundle.loadString('assets/data/sample_translations.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      // 번역 데이터를 DictionaryEntry로 변환
      jsonData.forEach((word, data) {
        final Map<String, dynamic> wordData = data as Map<String, dynamic>;
        _translations[word] = DictionaryEntry.multiLanguage(
          word: word,
          pinyin: wordData['pinyin'] ?? '',
          meaningKo: wordData['ko'],
          meaningEn: wordData['en'],
          source: 'sample_local',
        );
      });

      _isLoaded = true;

      if (kDebugMode) {
        debugPrint('✅ [샘플 번역] 로컬 데이터 로드 완료: ${_translations.length}개 단어');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [샘플 번역] 로컬 데이터 로드 실패: $e');
      }
      _isLoaded = true; // 오류가 있어도 초기화 완료로 처리
    }
  }

  /// 단어 검색 (샘플 모드용)
  Future<DictionaryEntry?> lookup(String word) async {
    await initialize();

    if (kDebugMode) {
      debugPrint('🔍 [샘플 번역] 단어 검색: "$word"');
    }

    final entry = _translations[word];
    
    if (entry != null) {
      if (kDebugMode) {
        debugPrint('✅ [샘플 번역] 단어 찾음: $word');
        debugPrint('   병음: ${entry.pinyin}');
        debugPrint('   한국어: ${entry.meaningKo}');
        debugPrint('   영어: ${entry.meaningEn}');
      }
    } else {
      if (kDebugMode) {
        debugPrint('❌ [샘플 번역] 단어 없음: $word');
      }
    }

    return entry;
  }

  /// 사전 검색 결과 반환 (DictionaryService 호환)
  Future<Map<String, dynamic>> lookupWord(String word) async {
    final entry = await lookup(word);
    
    if (entry != null) {
      return {
        'entry': entry,
        'success': true,
        'source': 'sample_local',
      };
    } else {
      return {
        'success': false,
        'message': '샘플 데이터에서 "$word"를 찾을 수 없습니다.',
      };
    }
  }

  /// 샘플 데이터에 포함된 모든 단어 목록
  List<String> get availableWords {
    return _translations.keys.toList();
  }

  /// 캐시 정리
  void clearCache() {
    _translations.clear();
    _isLoaded = false;
    if (kDebugMode) {
      debugPrint('🧹 [샘플 번역] 캐시 정리 완료');
    }
  }
} 