import 'package:flutter/foundation.dart';
import '../../core/models/dictionary.dart';

/// 샘플 모드에서 사용할 로컬 번역 데이터 서비스
class SampleTranslationService {
  // 싱글톤 패턴
  static final SampleTranslationService _instance = SampleTranslationService._internal();
  factory SampleTranslationService() => _instance;
  SampleTranslationService._internal();

  // 하드코딩된 번역 데이터 (JSON 파일 대신)
  final Map<String, DictionaryEntry> _translations = {
    '学校': DictionaryEntry.multiLanguage(
      word: '学校',
      pinyin: 'xuéxiào',
      meaningKo: '학교',
      meaningEn: 'school',
      source: 'sample_local',
    ),
    '教室': DictionaryEntry.multiLanguage(
      word: '教室',
      pinyin: 'jiàoshì',
      meaningKo: '교실',
      meaningEn: 'classroom',
      source: 'sample_local',
    ),
    '老师': DictionaryEntry.multiLanguage(
      word: '老师',
      pinyin: 'lǎoshī',
      meaningKo: '선생님',
      meaningEn: 'teacher',
      source: 'sample_local',
    ),
    '黑板': DictionaryEntry.multiLanguage(
      word: '黑板',
      pinyin: 'hēibǎn',
      meaningKo: '칠판',
      meaningEn: 'blackboard',
      source: 'sample_local',
    ),
    '操场': DictionaryEntry.multiLanguage(
      word: '操场',
      pinyin: 'cāochǎng',
      meaningKo: '운동장',
      meaningEn: 'playground',
      source: 'sample_local',
    ),
    '我们': DictionaryEntry.multiLanguage(
      word: '我们',
      pinyin: 'wǒmen',
      meaningKo: '우리',
      meaningEn: 'we',
      source: 'sample_local',
    ),
    '早上': DictionaryEntry.multiLanguage(
      word: '早上',
      pinyin: 'zǎoshang',
      meaningKo: '아침',
      meaningEn: 'morning',
      source: 'sample_local',
    ),
    '八点': DictionaryEntry.multiLanguage(
      word: '八点',
      pinyin: 'bādiǎn',
      meaningKo: '8시',
      meaningEn: '8 o\'clock',
      source: 'sample_local',
    ),
    '桌子': DictionaryEntry.multiLanguage(
      word: '桌子',
      pinyin: 'zhuōzi',
      meaningKo: '책상',
      meaningEn: 'desk',
      source: 'sample_local',
    ),
    '椅子': DictionaryEntry.multiLanguage(
      word: '椅子',
      pinyin: 'yǐzi',
      meaningKo: '의자',
      meaningEn: 'chair',
      source: 'sample_local',
    ),
  };

  bool _isLoaded = false;

  /// 초기화 (샘플 번역 데이터 로드)
  Future<void> initialize() async {
    if (_isLoaded) return;

    if (kDebugMode) {
      debugPrint('✅ [샘플 번역] 로컬 데이터 로드 완료: ${_translations.length}개 단어');
    }
    
    _isLoaded = true;
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
    _isLoaded = false;
    if (kDebugMode) {
      debugPrint('🧹 [샘플 번역] 캐시 정리 완료');
    }
  }
} 