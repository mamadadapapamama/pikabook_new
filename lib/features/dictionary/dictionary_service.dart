// 이 서비스는 향후 다국어 지원을 위해 확장될 예정입니다.
// 현재는 중국어만 지원합니다.

import 'package:flutter/foundation.dart';
import '../../core/models/dictionary.dart';
import 'internal_cn_dictionary_service.dart';
import '../../core/services/text_processing/llm_text_processing.dart';
import 'cc_cedict_service.dart';

/// 범용 사전 서비스
/// 여러 언어의 사전 기능을 통합 관리합니다.

/// 외부 사전 유형 (CC-CEDICT)
enum ExternalDictType {
  ccCedict,
}

class DictionaryService {
  // 싱글톤 패턴 구현
  static final DictionaryService _instance = DictionaryService._internal();
  factory DictionaryService() => _instance;
  
  // 서비스 인스턴스
  final InternalCnDictionaryService _chineseDictionaryService = InternalCnDictionaryService();
  final LLMTextProcessing _llmService = LLMTextProcessing();
  final CcCedictService _ccCedictService = CcCedictService();
  
  // 사전 업데이트 리스너 목록
  late final List<Function()> _dictionaryUpdateListeners;
  
  // 초기화 완료 여부
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  DictionaryService._internal() {
    _dictionaryUpdateListeners = [];
  }

  // 현재 지원하는 언어 목록
  static const List<String> supportedLanguages = ['zh-CN'];
  
  // 현재 활성화된 언어
  String _currentLanguage = 'zh-CN';

  // 현재 언어 설정
  String get currentLanguage => _currentLanguage;
  set currentLanguage(String language) {
    if (supportedLanguages.contains(language)) {
      _currentLanguage = language;
    } else {
      debugPrint('지원하지 않는 언어: $language, 기본 언어(zh-CN)로 설정됩니다.');
      _currentLanguage = 'zh-CN';
    }
  }

  // 초기화 메서드
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _chineseDictionaryService.loadDictionary();
      await _ccCedictService.initialize();
      _isInitialized = true;
      debugPrint('DictionaryService 초기화 완료');
    } catch (e) {
      debugPrint('DictionaryService 초기화 중 오류 발생: $e');
      rethrow;
    }
  }

  // 사전 초기화 검증
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  // 사전 업데이트 리스너 추가
  void addDictionaryUpdateListener(Function() listener) {
    if (!_dictionaryUpdateListeners.contains(listener)) {
      _dictionaryUpdateListeners.add(listener);
    }
  }

  // 사전 업데이트 리스너 제거
  void removeDictionaryUpdateListener(Function() listener) {
    _dictionaryUpdateListeners.remove(listener);
  }

  // 사전 업데이트 알림
  void _notifyDictionaryUpdated() {
    for (final listener in _dictionaryUpdateListeners) {
      listener();
    }
  }

  // 외부 사전 검색 (추가 기능)
  Future<Map<String, dynamic>> lookupExternalDictionary(String word) async {
    try {
      await _ensureInitialized();
      
      // CC-CEDICT에서 검색
      try {
        final ccCedictEntry = await _ccCedictService.lookup(word);
        if (ccCedictEntry != null) {
          final newEntry = DictionaryEntry(
            word: word,
            pinyin: ccCedictEntry.pinyin,
            meaning: ccCedictEntry.meaning,
            source: 'cc_cedict'
          );
          // 내부 사전에 추가
          _chineseDictionaryService.addEntry(newEntry);
          _notifyDictionaryUpdated();
          return {
            'entry': newEntry,
            'success': true,
            'source': 'cc_cedict',
          };
        }
      } catch (e) {
        debugPrint('CC-CEDICT 검색 실패: $e');
      }
      
      return {
        'success': false,
        'message': '외부 사전에서 단어를 찾을 수 없습니다: $word'
      };
    } catch (e) {
      return {
        'success': false,
        'message': '외부 사전 검색 중 오류 발생: $e'
      };
    }
  }

  // 단어 검색 - LLM 캐시 -> 내부 사전 -> CC-CEDICT 순서
  Future<Map<String, dynamic>> lookupWord(String word) async {
    try {
      await _ensureInitialized();
      
      switch (_currentLanguage) {
        case 'zh-CN':
          // 1. LLM 캐시에서 검색 (현재 비활성화 - getWordCacheData 메서드 구현 필요)
          /*
          final llmCacheData = _llmService.getWordCacheData(word);
          if (llmCacheData != null) {
            debugPrint('LLM 캐시에서 단어 찾음: $word');
            return {
              'entry': DictionaryEntry(
                word: llmCacheData['chinese'] ?? word,
                pinyin: llmCacheData['pinyin'] ?? '',
                meaning: llmCacheData['korean'] ?? '',
                source: 'llm_cache'
              ),
              'success': true,
              'source': 'llm_cache',
            };
          }
          */
          
          // 2. 내부 사전에서 검색
          final internalEntry = await _chineseDictionaryService.lookupAsync(word);
          if (internalEntry != null) {
            debugPrint('내부 사전에서 단어 찾음: $word');
            return {
              'entry': internalEntry,
              'success': true,
              'source': 'internal',
            };
          }
          
          // 3. CC-CEDICT에서 검색
          try {
            final ccCedictEntry = await _ccCedictService.lookup(word);
            if (ccCedictEntry != null) {
              final newEntry = DictionaryEntry(
                word: word,
                pinyin: ccCedictEntry.pinyin,
                meaning: ccCedictEntry.meaning,
                source: 'cc_cedict'
              );
              // 내부 사전에 추가
              _chineseDictionaryService.addEntry(newEntry);
              _notifyDictionaryUpdated();
              return {
                'entry': newEntry,
                'success': true,
                'source': 'cc_cedict',
              };
            }
          } catch (e) {
            debugPrint('CC-CEDICT 검색 실패: $e');
          }
          
          // 모든 방법 실패
          return {
            'success': false,
            'message': '단어를 찾을 수 없습니다: $word',
          };
        
        default:
          return {
            'success': false,
            'message': '지원하지 않는 언어: $_currentLanguage',
          };
      }
    } catch (e) {
      debugPrint('단어 검색 중 오류 발생: $e');
      return {
        'success': false,
        'message': '단어 검색 중 오류가 발생했습니다: $e',
      };
    }
  }

  // 단어 검색 (단순 인터페이스)
  Future<DictionaryEntry?> lookup(String word) async {
    try {
      await _ensureInitialized();
      
      switch (_currentLanguage) {
        case 'zh-CN':
          return _chineseDictionaryService.lookup(word);
        default:
          return null;
      }
    } catch (e) {
      debugPrint('단순 단어 검색 중 오류 발생: $e');
      return null;
    }
  }
  
  // 사전에 단어 추가
  Future<void> addEntry(DictionaryEntry entry) async {
    try {
      await _ensureInitialized();
      
      switch (_currentLanguage) {
        case 'zh-CN':
          _chineseDictionaryService.addEntry(entry);
          break;
        default:
          break;
      }
      
      _notifyDictionaryUpdated();
    } catch (e) {
      debugPrint('단어 추가 중 오류 발생: $e');
    }
  }
  
  // 최근 검색어 목록 가져오기
  Future<List<String>> getRecentSearches() async {
    // 임시로 빈 목록 반환
    return [];
  }
  
  // 사전 캐시 정리
  Future<void> clearCache() async {
    try {
      _ccCedictService.clearCache();
      debugPrint('사전 캐시 정리 완료');
    } catch (e) {
      debugPrint('사전 캐시 정리 중 오류 발생: $e');
    }
  }
}

// 단어 분석 결과를 담는 클래스
class WordAnalysis {
  final String word;
  final String pinyin;
  final String meaning;
  final String partOfSpeech; // 품사 정보

  WordAnalysis({
    required this.word,
    required this.pinyin,
    required this.meaning,
    required this.partOfSpeech,
  });
}
