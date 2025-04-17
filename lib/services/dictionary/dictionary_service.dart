// 이 서비스는 향후 다국어 지원을 위해 확장될 예정입니다.
// 현재는 중국어만 지원합니다.

import 'package:flutter/foundation.dart';
import '../../models/dictionary_entry.dart';
import './internal_cn_dictionary_service.dart';
import './external_cn_dictionary_service.dart';

/// 범용 사전 서비스
/// 여러 언어의 사전 기능을 통합 관리합니다.

/// 외부 사전 유형 (구글, 네이버, 바이두)
enum ExternalDictType {
  google,
  naver,
  baidu,
}

class DictionaryService {
  // 싱글톤 패턴 구현
  static final DictionaryService _instance = DictionaryService._internal();
  factory DictionaryService() => _instance;
  
  // 언어별 사전 서비스 인스턴스 (즉시 초기화)
  final InternalCnDictionaryService _chineseDictionaryService = InternalCnDictionaryService();
  final ExternalCnDictionaryService _externalCnDictionaryService = ExternalCnDictionaryService();
  
  // 사전 업데이트 리스너 목록
  late final List<Function()> _dictionaryUpdateListeners;
  
  // 초기화 완료 여부
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  DictionaryService._internal() {
    // 사전 업데이트 리스너 목록 초기화
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

  // 초기화 메서드 - 필요한 서비스 인스턴스 생성
  Future<void> initialize() async {
    // 이미 초기화된 경우 빠르게 반환
    if (_isInitialized) return;
    
    try {
      // 중국어 사전 서비스 초기화
      await _chineseDictionaryService.loadDictionary();
      
      _isInitialized = true;
      debugPrint('DictionaryService 초기화 완료');
    } catch (e) {
      debugPrint('DictionaryService 초기화 중 오류 발생: $e');
      rethrow;
    }
  }

  // 사전 초기화 검증 및 필요시 초기화
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

  // 단어 검색 - 내부 사전, 외부 사전 순차적으로 검색
  Future<Map<String, dynamic>> lookupWord(String word) async {
    try {
      // 초기화 확인
      await _ensureInitialized();
      
      // 현재 설정된 언어에 따라 다른 사전 서비스 사용
      switch (_currentLanguage) {
        case 'zh-CN':
          // 1. 먼저 내부 중국어 사전에서 검색
          final internalEntry = _chineseDictionaryService.lookup(word);
          if (internalEntry != null) {
            debugPrint('내부 중국어 사전에서 단어 찾음: $word');
            return {
              'entry': internalEntry,
              'success': true,
              'source': 'internal',
            };
          }
          
          // 2. 내부 사전에 없으면 외부 사전 검색
          final externalResult = await _externalCnDictionaryService.lookupWord(word);
          
          // 외부 사전에서 찾은 경우, 내부 사전에도 추가
          if (externalResult['success'] == true && externalResult['entry'] != null) {
            final externalEntry = externalResult['entry'] as DictionaryEntry;
            
            // 내부 사전에 추가
            _chineseDictionaryService.addEntry(externalEntry);
            
            // 업데이트 알림
            _notifyDictionaryUpdated();
            
            return externalResult;
          }
          
          // 3. 내부와 외부 사전 모두 실패한 경우
          return externalResult; // 외부 사전 결과에는 실패 메시지가 포함되어 있음
        
        default:
          // 지원하지 않는 언어
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

  // 단어 검색 (단순 인터페이스, 내부 사전만 검색)
  Future<DictionaryEntry?> lookup(String word) async {
    try {
      // 초기화 확인
      await _ensureInitialized();
      
      // 현재 설정된 언어에 따라 다른 사전 서비스 사용
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
      // 초기화 확인
      await _ensureInitialized();
      
      // 현재 설정된 언어에 따라 다른 사전 서비스 사용
      switch (_currentLanguage) {
        case 'zh-CN':
          _chineseDictionaryService.addEntry(entry);
          break;
        default:
          // 지원하지 않는 언어
          break;
      }
      
      // 업데이트 알림
      _notifyDictionaryUpdated();
    } catch (e) {
      debugPrint('단어 추가 중 오류 발생: $e');
    }
  }
  
  // 사전 캐시 정리
  Future<void> clearCache() async {
    try {
      // 외부 사전 캐시 정리
      _externalCnDictionaryService.clearCache();
      
      debugPrint('사전 캐시 정리 완료');
    } catch (e) {
      debugPrint('사전 캐시 정리 중 오류 발생: $e');
    }
  }

  /// 외부 사전 열기
  /// [word] 검색할 단어
  /// [type] 사전 타입 (구글, 네이버, 바이두)
  String getExternalDictionaryUrl(String word, ExternalDictType type) {
    if (_currentLanguage == 'zh-CN') {
      final cnDictType = ExternalCnDictType.values[type.index];
      return _externalCnDictionaryService.getExternalDictionaryUrl(word, cnDictType);
    } else {
      throw UnsupportedError('지원되지 않는 언어입니다: $_currentLanguage');
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
