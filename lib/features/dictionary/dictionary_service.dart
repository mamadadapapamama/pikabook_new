// 이 서비스는 향후 다국어 지원을 위해 확장될 예정입니다.
// 현재는 중국어->한국어 (CC Cedict 은 영어 결과) 지원합니다.

import 'package:flutter/foundation.dart';
import 'package:translator/translator.dart';
import 'package:pinyin/pinyin.dart';
import '../../core/models/dictionary.dart';
import 'internal_cn_dictionary_service.dart';
import 'cc_cedict_service.dart';
import '../../core/services/authentication/auth_service.dart';
import '../sample/sample_data_service.dart';

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
  final AuthService _authService = AuthService();
  
  // 사전 업데이트 리스너 목록
  late final List<Function()> _dictionaryUpdateListeners;
  
  // 초기화 완료 여부
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  // Google Translate 사용 가능 여부 (오류 발생시 비활성화)
  bool _googleTranslateEnabled = true;
  
  // 샘플 모드 여부 (초기화 시 설정)
  bool _isSampleMode = false;
  
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
      // 로그인 상태 확인 (샘플 모드 여부 결정)
      _isSampleMode = _authService.currentUser == null;
      
      if (_isSampleMode) {
        if (kDebugMode) {
          debugPrint('🏠 [DictionaryService] 샘플 모드로 초기화 (사전 기능 제한)');
        }
        // 샘플 모드에서는 사전 기능을 제한적으로 사용
      } else {
        if (kDebugMode) {
          debugPrint('🌐 [DictionaryService] 일반 모드로 초기화');
        }
        await _chineseDictionaryService.loadDictionary();
        await _ccCedictService.initialize();
      }
      
      _isInitialized = true;
      debugPrint('DictionaryService 초기화 완료 (샘플모드: $_isSampleMode)');
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

  // Google Cloud Translate를 사용한 다국어 번역 (한국어 + 영어)
  Future<DictionaryEntry?> _translateWithGoogleMultiLanguage(String word) async {
    try {
      if (kDebugMode) {
        debugPrint('🌐 [Google Translate-Multi] 다국어 번역 시작: "$word"');
        debugPrint('   설정: auto → ko, en');
      }
      
      // 한국어와 영어 번역을 동시에 요청
      final futures = await Future.wait([
        _translator.translate(word, from: 'auto', to: 'ko'),
        _translator.translate(word, from: 'auto', to: 'en'),
      ]);
      
      final koTranslation = futures[0];
      final enTranslation = futures[1];
      
      if (kDebugMode) {
        debugPrint('🌐 [Google Translate-Multi] 원본: "$word"');
        debugPrint('🌐 [Google Translate-Multi] 한국어: "${koTranslation.text}"');
        debugPrint('🌐 [Google Translate-Multi] 영어: "${enTranslation.text}"');
      }
      
      // 적어도 하나의 번역이 유효해야 함
      final hasValidKo = koTranslation.text.isNotEmpty && koTranslation.text != word;
      final hasValidEn = enTranslation.text.isNotEmpty && enTranslation.text != word;
      
      if (hasValidKo || hasValidEn) {
        // 병음 생성
        String pinyinText = '';
        try {
          pinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITH_TONE_MARK);
          if (pinyinText.isEmpty) {
            pinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITH_TONE_NUMBER);
          }
          if (pinyinText.isEmpty) {
            pinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITHOUT_TONE);
          }
          if (kDebugMode) {
            debugPrint('🎵 [Pinyin-Multi] 생성 완료: "$word" → "$pinyinText"');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ [Pinyin-Multi] 생성 실패: $e');
          }
        }

        final entry = DictionaryEntry.multiLanguage(
          word: word,
          pinyin: pinyinText,
          meaningKo: hasValidKo ? koTranslation.text : null,
          meaningEn: hasValidEn ? enTranslation.text : null,
          source: 'google_translate_multi'
        );
        
        if (kDebugMode) {
          debugPrint('✅ [Google Translate-Multi] 다국어 사전 항목 생성 완료');
          debugPrint('   단어: ${entry.word}');
          debugPrint('   한국어: ${entry.meaningKo}');
          debugPrint('   영어: ${entry.meaningEn}');
          debugPrint('   소스: ${entry.source}');
        }
        
        _chineseDictionaryService.addEntry(entry);
        _notifyDictionaryUpdated();
        
        return entry;
      } else {
        if (kDebugMode) {
          debugPrint('❌ [Google Translate-Multi] 유효한 번역 결과 없음');
        }
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('💥 [Google Translate-Multi] 다국어 번역 실패: $e');
        debugPrint('   오류 타입: ${e.runtimeType}');
        debugPrint('   단어: "$word"');
      }
      return null;
    }
  }

  // Google Cloud Translate를 사용한 단어 번역 (기존 한국어만)
  Future<DictionaryEntry?> _translateWithGoogle(String word) async {
    try {
      if (kDebugMode) {
        debugPrint('🌐 [Google Translate] 번역 시작: "$word"');
        debugPrint('   설정: auto (자동 감지) → ko (한국어)');
      }
      
      // 자동 언어 감지 → 한국어 번역 (더 안정적)
      final translation = await _translator.translate(word, from: 'auto', to: 'ko');
      
      if (kDebugMode) {
        debugPrint('🌐 [Google Translate] 원본: "$word"');
        debugPrint('🌐 [Google Translate] 번역 결과: "${translation.text}"');
        debugPrint('🌐 [Google Translate] 번역 결과 길이: ${translation.text.length}');
        debugPrint('🌐 [Google Translate] 원본과 같은지: ${translation.text == word}');
      }
      
      if (translation.text.isNotEmpty && translation.text != word) {
        // 중국어 텍스트에서 병음 생성
        String pinyinText = '';
        try {
          // 성조 표시가 있는 병음 생성 (nǐ hǎo 형태)
          pinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITH_TONE_MARK);
          
          // 빈 결과인 경우 성조 번호 형태로 재시도 (ni3 hao3 형태)
          if (pinyinText.isEmpty) {
            pinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITH_TONE_NUMBER);
          }
          
          // 여전히 빈 결과인 경우 성조 없는 형태로 재시도 (ni hao 형태)
          if (pinyinText.isEmpty) {
            pinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITHOUT_TONE);
          }
          
          if (kDebugMode) {
            debugPrint('🎵 [Pinyin] 생성 완료: "$word" → "$pinyinText"');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ [Pinyin] 생성 실패: $e');
          }
          pinyinText = '';
        }

        final entry = DictionaryEntry.korean(
          word: word,
          pinyin: pinyinText, // 자동 생성된 병음
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
        debugPrint('   단어: "$word"');
        debugPrint('   언어 설정: auto → ko');
        
        // 언어 코드 지원 문제인 경우 대안 시도
        if (e.toString().contains('LanguageNotSupportedException') || 
            e.toString().contains('language') ||
            e.toString().contains('not supported')) {
          debugPrint('🔄 [Google Translate] 언어 코드 문제 감지, 대안 시도...');
          
          try {
            // 대안 1: zh 사용
            debugPrint('🔄 [Google Translate] 대안 1: zh → ko');
            final altTranslation = await _translator.translate(word, from: 'zh', to: 'ko');
            
            if (altTranslation.text.isNotEmpty && altTranslation.text != word) {
              // 대안 방법에서도 병음 생성
              String altPinyinText = '';
              try {
                // 성조 표시가 있는 병음 생성 (nǐ hǎo 형태)
                altPinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITH_TONE_MARK);
                
                // 빈 결과인 경우 성조 번호 형태로 재시도 (ni3 hao3 형태)
                if (altPinyinText.isEmpty) {
                  altPinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITH_TONE_NUMBER);
                }
                
                // 여전히 빈 결과인 경우 성조 없는 형태로 재시도 (ni hao 형태)
                if (altPinyinText.isEmpty) {
                  altPinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITHOUT_TONE);
                }
                
                if (kDebugMode) {
                  debugPrint('🎵 [Pinyin-대안] 생성 완료: "$word" → "$altPinyinText"');
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('❌ [Pinyin-대안] 생성 실패: $e');
                }
                altPinyinText = '';
              }

              final entry = DictionaryEntry.korean(
                word: word,
                pinyin: altPinyinText,
                meaning: altTranslation.text,
                source: 'google_translate'
              );
              
              if (kDebugMode) {
                debugPrint('✅ [Google Translate] 대안으로 성공: "${altTranslation.text}"');
              }
              
              _chineseDictionaryService.addEntry(entry);
              _notifyDictionaryUpdated();
              return entry;
            }
          } catch (altError) {
            if (kDebugMode) {
              debugPrint('❌ [Google Translate] 대안도 실패: $altError');
            }
          }
        }
      }
      return null;
    }
  }

  // 단어 검색 : 샘플 모드면 로컬 데이터 → 일반 모드면 내부 사전 → CC-CEDICT → Google Cloud Translate 순서
  Future<Map<String, dynamic>> lookupWord(String word) async {
    try {
      await _ensureInitialized();
      
      if (kDebugMode) {
        debugPrint('🔍 [사전검색] 시작: "$word" (샘플모드: $_isSampleMode)');
      }
      
      // 샘플 모드일 때는 샘플 데이터에 있는 단어만 검색 가능
      if (_isSampleMode) {
        if (kDebugMode) {
          debugPrint('🏠 [샘플모드] 샘플 데이터에서 단어 검색: "$word"');
        }
        return await _lookupInSampleMode(word);
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
              debugPrint('   현재 한국어: ${internalEntry.meaningKo}');
              debugPrint('   현재 영어: ${internalEntry.meaningEn}');
            }
            
            // 한국어는 있지만 영어가 없는 경우 CC-CEDICT에서 영어 번역 보완
            if (internalEntry.meaningKo != null && internalEntry.meaningEn == null) {
              if (kDebugMode) {
                debugPrint('🔍 [1단계-보완] CC-CEDICT에서 영어 번역 검색 중...');
              }
              try {
                final ccCedictEntry = await _ccCedictService.lookup(word);
                if (ccCedictEntry != null && ccCedictEntry.meaningEn != null) {
                  if (kDebugMode) {
                    debugPrint('✅ [1단계-보완] CC-CEDICT에서 영어 번역 찾음');
                  }
                  final completeEntry = internalEntry.copyWith(
                    meaningEn: ccCedictEntry.meaningEn,
                  );
                  // 보완된 항목을 내부 사전에 업데이트
                  _chineseDictionaryService.addEntry(completeEntry);
                  _notifyDictionaryUpdated();
                  return {
                    'entry': completeEntry,
                    'success': true,
                    'source': 'internal_with_cc',
                  };
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('❌ [1단계-보완] CC-CEDICT 보완 실패: $e');
                }
              }
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
                debugPrint('   영어: ${ccCedictEntry.meaningEn}');
              }
              
              // 영어 번역은 있지만 한국어가 없는 경우 Google Translate로 한국어 번역 보완
              String? koreanMeaning;
              if (_googleTranslateEnabled) {
                if (kDebugMode) {
                  debugPrint('🔍 [2단계-보완] Google Translate로 한국어 번역 검색 중...');
                }
                try {
                  final translation = await _translator.translate(word, from: 'auto', to: 'ko');
                  if (translation.text.isNotEmpty && translation.text != word) {
                    koreanMeaning = translation.text;
                    if (kDebugMode) {
                      debugPrint('✅ [2단계-보완] Google Translate로 한국어 번역 찾음: $koreanMeaning');
                    }
                  }
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('❌ [2단계-보완] Google Translate 한국어 번역 실패: $e');
                  }
                }
              }
              
              final newEntry = DictionaryEntry.multiLanguage(
                word: word,
                pinyin: ccCedictEntry.pinyin,
                meaningKo: koreanMeaning,
                meaningEn: ccCedictEntry.meaningEn,
                source: koreanMeaning != null ? 'cc_cedict_with_google' : 'cc_cedict'
              );
              
              // 내부 사전에 추가
              _chineseDictionaryService.addEntry(newEntry);
              _notifyDictionaryUpdated();
              return {
                'entry': newEntry,
                'success': true,
                'source': koreanMeaning != null ? 'cc_cedict_with_google' : 'cc_cedict',
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
          
          // 3. Google Translate로 다국어 번역 시도 (활성화된 경우에만)
          if (_googleTranslateEnabled) {
            if (kDebugMode) {
              debugPrint('🔍 [3단계] Google Translate 다국어 번역 시도 중...');
            }
            try {
              final googleMultiEntry = await _translateWithGoogleMultiLanguage(word);
              if (googleMultiEntry != null) {
                if (kDebugMode) {
                  debugPrint('✅ [3단계] Google Translate 다국어 번역 성공');
                  debugPrint('   한국어: ${googleMultiEntry.meaningKo}');
                  debugPrint('   영어: ${googleMultiEntry.meaningEn}');
                }
                return {
                  'entry': googleMultiEntry,
                  'success': true,
                  'source': 'google_translate_multi',
                };
              }
              if (kDebugMode) {
                debugPrint('❌ [3단계] Google Translate 다국어 번역에서 결과 없음');
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ [3단계] Google Translate 다국어 번역 실패: $e');
              }
              
              // 언어 지원 문제인 경우 Google Translate 비활성화
              if (e.toString().contains('LanguageNotSupportedException')) {
                _googleTranslateEnabled = false;
                if (kDebugMode) {
                  debugPrint('🚫 Google Translate 비활성화됨 (언어 지원 문제)');
                }
              }
            }
          } else {
            if (kDebugMode) {
              debugPrint('⏭️ [3단계] Google Translate 비활성화됨 (이전 오류로 인해)');
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

  /// 샘플 모드에서 단어 검색
  Future<Map<String, dynamic>> _lookupInSampleMode(String word) async {
    try {
      final sampleDataService = SampleDataService();
      await sampleDataService.loadSampleData();
      
      // 샘플 플래시카드에서 해당 단어 찾기
      final sampleFlashCards = sampleDataService.getSampleFlashCards(null);
      final matchingCard = sampleFlashCards.where((card) => card.front == word).firstOrNull;
      
      if (matchingCard != null) {
        if (kDebugMode) {
          debugPrint('✅ [샘플모드] 샘플 데이터에서 단어 찾음: $word');
          debugPrint('   번역: ${matchingCard.back}');
        }
        
        // 샘플 데이터의 플래시카드를 사전 항목으로 변환
        final entry = DictionaryEntry.multiLanguage(
          word: matchingCard.front,
          pinyin: '', // 샘플 데이터에는 병음이 없음
          meaningKo: matchingCard.back,
          meaningEn: null,
          source: 'sample_data'
        );
        
        return {
          'entry': entry,
          'success': true,
          'source': 'sample_data',
        };
      } else {
        if (kDebugMode) {
          debugPrint('❌ [샘플모드] 샘플 데이터에서 단어를 찾지 못함: $word');
          debugPrint('   사용 가능한 단어: ${sampleDataService.getAvailableWords().take(5).join(", ")}...');
        }
        
        return {
          'success': false,
          'message': '샘플 모드에서는 제한된 단어만 검색할 수 있습니다.\n로그인하시면 모든 단어를 검색할 수 있습니다.',
          'availableWords': sampleDataService.getAvailableWords(),
        };
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [샘플모드] 단어 검색 중 오류: $e');
      }
      return {
        'success': false,
        'message': '샘플 모드에서 단어 검색 중 오류가 발생했습니다.',
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
