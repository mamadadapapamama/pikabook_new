// 이 서비스는 향후 다국어 지원을 위해 확장될 예정입니다.
// 현재는 중국어->한국어 (CC Cedict 은 영어 결과) 지원합니다.

import 'package:flutter/foundation.dart';
import 'package:translator/translator.dart';
import '../../core/models/dictionary.dart';
import 'internal_cn_dictionary_service.dart';
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
  final CcCedictService _ccCedictService = CcCedictService();
  final GoogleTranslator _translator = GoogleTranslator();
  
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

  // Google Cloud Translate를 사용한 단어 번역
  Future<DictionaryEntry?> _translateWithGoogle(String word) async {
    try {
      if (kDebugMode) {
        debugPrint('🌐 [Google Translate] 번역 시작: "$word"');
        debugPrint('   설정: zh (중국어) → ko (한국어)');
      }
      
      // 중국어 → 한국어 번역
      final translation = await _translator.translate(word, from: 'zh', to: 'ko');
      
      if (kDebugMode) {
        debugPrint('🌐 [Google Translate] 원본: "$word"');
        debugPrint('🌐 [Google Translate] 번역 결과: "${translation.text}"');
        debugPrint('🌐 [Google Translate] 번역 결과 길이: ${translation.text.length}');
        debugPrint('🌐 [Google Translate] 원본과 같은지: ${translation.text == word}');
      }
      
      if (translation.text.isNotEmpty && translation.text != word) {
        final entry = DictionaryEntry(
          word: word,
          pinyin: '', // Google Cloud Translate는 병음을 제공하지 않음
          meaning: translation.text,
          source: 'google_translate'
        );
        
        if (kDebugMode) {
          debugPrint('✅ [Google Translate] 사전 항목 생성 완료');
          debugPrint('   단어: ${entry.word}');
          debugPrint('   의미: ${entry.meaning}');
          debugPrint('   소스: ${entry.source}');
        }
        
        // 내부 사전에 추가
        _chineseDictionaryService.addEntry(entry);
        _notifyDictionaryUpdated();
        
        if (kDebugMode) {
          debugPrint('✅ [Google Translate] 내부 사전에 추가 완료');
        }
        
        return entry;
      } else {
        if (kDebugMode) {
          debugPrint('❌ [Google Translate] 유효한 번역 결과 없음');
          debugPrint('   이유: ${translation.text.isEmpty ? "빈 결과" : "원본과 동일"}');
        }
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('💥 [Google Translate] 번역 실패: $e');
        debugPrint('   오류 타입: ${e.runtimeType}');
      }
      return null;
    }
  }

  // 단어 검색 : 내부 사전 → CC-CEDICT → Google Cloud Translate 순서
  Future<Map<String, dynamic>> lookupWord(String word) async {
    try {
      await _ensureInitialized();
      
      if (kDebugMode) {
        debugPrint('🔍 [사전검색] 시작: "$word" (언어: $_currentLanguage)');
      }
      
      switch (_currentLanguage) {
        case 'zh-CN':
          // 1. 내부 사전에서 검색
          if (kDebugMode) {
            debugPrint('🔍 [1단계] 내부 사전 검색 중...');
          }
          final internalEntry = await _chineseDictionaryService.lookupAsync(word);
          if (internalEntry != null) {
            if (kDebugMode) {
              debugPrint('✅ [1단계] 내부 사전에서 단어 찾음: $word');
            }
            return {
              'entry': internalEntry,
              'success': true,
              'source': 'internal',
            };
          }
          if (kDebugMode) {
            debugPrint('❌ [1단계] 내부 사전에서 찾지 못함');
          }
          
          // 2. CC-CEDICT에서 검색
          if (kDebugMode) {
            debugPrint('🔍 [2단계] CC-CEDICT 검색 중...');
          }
          try {
            final ccCedictEntry = await _ccCedictService.lookup(word);
            if (ccCedictEntry != null) {
              if (kDebugMode) {
                debugPrint('✅ [2단계] CC-CEDICT에서 단어 찾음: $word');
                debugPrint('   병음: ${ccCedictEntry.pinyin}');
                debugPrint('   의미: ${ccCedictEntry.meaning}');
              }
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
            if (kDebugMode) {
              debugPrint('❌ [2단계] CC-CEDICT에서 찾지 못함');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ [2단계] CC-CEDICT 검색 실패: $e');
            }
          }
          
          // 3. Google Translate로 번역 시도
          if (kDebugMode) {
            debugPrint('🔍 [3단계] Google Translate 시도 중...');
          }
          try {
            final googleEntry = await _translateWithGoogle(word);
            if (googleEntry != null) {
              if (kDebugMode) {
                debugPrint('✅ [3단계] Google Translate 성공');
              }
              return {
                'entry': googleEntry,
                'success': true,
                'source': 'google_translate',
              };
            }
            if (kDebugMode) {
              debugPrint('❌ [3단계] Google Translate에서 결과 없음');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ [3단계] Google Translate 검색 실패: $e');
            }
          }
          
          // 모든 방법 실패
          if (kDebugMode) {
            debugPrint('💥 [사전검색] 모든 방법 실패: $word');
          }
          return {
            'success': false,
            'message': '사전 검색 결과가 없습니다. 모든 소스(내부 사전, CC-CEDICT, Google Translate)에서 "$word"를 찾을 수 없습니다.',
          };
        
        default:
          return {
            'success': false,
            'message': '지원하지 않는 언어: $_currentLanguage',
          };
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('💥 [사전검색] 전체 오류 발생: $e');
      }
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
