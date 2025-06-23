// 이 서비스는 향후 다국어 지원을 위해 확장될 예정입니다.
// 현재는 중국어->한국어 (CC Cedict 은 영어 결과) 지원합니다.

import 'package:flutter/foundation.dart';
import 'package:pinyin/pinyin.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/models/dictionary.dart';
import 'internal_cn_dictionary_service.dart';
import 'cc_cedict_service.dart';
import '../../core/services/authentication/auth_service.dart';
import '../sample/sample_data_service.dart';

/// 간단한 번역 결과 클래스
class SimpleTranslation {
  final String text;
  final String sourceLanguage;
  final String targetLanguage;
  
  SimpleTranslation({
    required this.text,
    required this.sourceLanguage,
    required this.targetLanguage,
  });
}

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
  final AuthService _authService = AuthService();
  
  // 샘플 데이터 서비스 (샘플 모드에서만 사용)
  SampleDataService? _sampleDataService;
  
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

  // 현재는 중국어만 지원
  static const String currentLanguage = 'zh-cn';

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
        // 샘플 모드에서는 샘플 데이터 서비스 초기화
        await _initializeSampleMode();
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

  /// 샘플 모드 초기화
  Future<void> _initializeSampleMode() async {
    try {
      _sampleDataService = SampleDataService();
      await _sampleDataService!.loadSampleData();
      if (kDebugMode) {
        debugPrint('✅ [DictionaryService] 샘플 데이터 로드 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [DictionaryService] 샘플 데이터 로드 실패: $e');
      }
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

  /// Google Translate API 직접 호출 (간단한 텍스트 번역)
  Future<SimpleTranslation?> _translateWithFallback(String text, {
    required String to,
    String from = 'zh-cn',
    String? context,
  }) async {
    // Google Translate API가 비활성화된 경우 null 반환
    if (!_googleTranslateEnabled) {
      return null;
    }
    
    try {
      // 간단한 로컬 번역 로직 (제한적)
      // 실제 프로덕션에서는 Google Translate API 키가 필요합니다
      final translatedText = await _performSimpleTranslation(text, from: from, to: to);
      
      if (translatedText != null && translatedText.isNotEmpty) {
        return SimpleTranslation(
          text: translatedText,
          sourceLanguage: from,
          targetLanguage: to,
        );
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [번역${context != null ? '-$context' : ''}] 실패: $e');
      }
      return null;
    }
  }
  
  /// 간단한 번역 수행 (실제로는 Google Translate API 호출)
  Future<String?> _performSimpleTranslation(String text, {
    required String from,
    required String to,
  }) async {
    // 현재는 번역 기능을 비활성화하고 null 반환
    // 실제 구현시에는 Google Translate API를 호출해야 합니다
    if (kDebugMode) {
      debugPrint('⚠️ [번역] Google Translate API 키가 필요합니다. 번역 기능이 비활성화됩니다.');
    }
    return null;
  }

  /// 병음 생성 공통 메서드
  String _generatePinyin(String word) {
    try {
      // 성조 표시가 있는 병음 생성 (nǐ hǎo 형태)
      String pinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITH_TONE_MARK);
      
      // 빈 결과인 경우 성조 번호 형태로 재시도 (ni3 hao3 형태)
      if (pinyinText.isEmpty) {
        pinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITH_TONE_NUMBER);
      }
      
      // 여전히 빈 결과인 경우 성조 없는 형태로 재시도 (ni hao 형태)
      if (pinyinText.isEmpty) {
        pinyinText = PinyinHelper.getPinyinE(word, defPinyin: '', format: PinyinFormat.WITHOUT_TONE);
      }
      
      if (kDebugMode && pinyinText.isNotEmpty) {
        debugPrint('🎵 [Pinyin] 생성 완료: "$word" → "$pinyinText"');
      }
      
      return pinyinText;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Pinyin] 생성 실패: $e');
      }
      return '';
    }
  }

  /// 번역 결과가 유효한지 확인
  bool _isValidTranslation(String original, String translated) {
    return translated.isNotEmpty && translated != original;
  }

  // Google Cloud Translate를 사용한 다국어 번역 (한국어 + 영어)
  Future<DictionaryEntry?> _translateWithGoogleMultiLanguage(String word) async {
    try {
      if (kDebugMode) {
        debugPrint('🌐 [Google Translate-Multi] 다국어 번역 시작: "$word"');
        debugPrint('   설정: zh-cn → ko, en');
      }
      
      // 한국어와 영어 번역을 동시에 요청
      final futures = await Future.wait([
        _translateWithFallback(word, to: 'ko', context: 'Multi'),
        _translateWithFallback(word, to: 'en', context: 'Multi'),
      ]);
      
      final koTranslation = futures[0];
      final enTranslation = futures[1];
      
      if (kDebugMode) {
        debugPrint('🌐 [Google Translate-Multi] 원본: "$word"');
        debugPrint('🌐 [Google Translate-Multi] 한국어: "${koTranslation?.text ?? 'null'}"');
        debugPrint('🌐 [Google Translate-Multi] 영어: "${enTranslation?.text ?? 'null'}"');
      }
      
      // 적어도 하나의 번역이 유효해야 함
      final hasValidKo = koTranslation != null && _isValidTranslation(word, koTranslation.text);
      final hasValidEn = enTranslation != null && _isValidTranslation(word, enTranslation.text);
      
      if (hasValidKo || hasValidEn) {
        final pinyinText = _generatePinyin(word);

        final entry = DictionaryEntry.multiLanguage(
          word: word,
          pinyin: pinyinText,
          meaningKo: hasValidKo ? koTranslation!.text : null,
          meaningEn: hasValidEn ? enTranslation!.text : null,
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

  /// 한국어 번역 수행 헬퍼 메서드
  Future<String?> _translateToKorean(String word, {String context = '보완'}) async {
    if (!_googleTranslateEnabled) return null;
    
    try {
      final translation = await _translateWithFallback(word, to: 'ko', context: context);
      
      if (translation != null && _isValidTranslation(word, translation.text)) {
        if (kDebugMode) {
          debugPrint('✅ [Google Translate-$context] 한국어 번역 찾음: ${translation.text}');
        }
        return translation.text;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Google Translate-$context] 한국어 번역 실패: $e');
      }
      return null;
    }
  }

  // 단어 검색 (단순 인터페이스 - flashcard에서 사용)
  Future<DictionaryEntry?> lookup(String word) async {
    try {
      await _ensureInitialized();
      
      // 샘플 모드에서는 내부 사전 검색 불가
      if (_isSampleMode) {
        return null;
      }
      
      // 중국어만 지원
      return _chineseDictionaryService.lookup(word);
    } catch (e) {
      debugPrint('단순 단어 검색 중 오류 발생: $e');
      return null;
    }
  }
  
  // 사전에 단어 추가 (내부사전에 추가)
  Future<void> addEntry(DictionaryEntry entry) async {
    try {
      await _ensureInitialized();
      
      // 중국어만 지원
      _chineseDictionaryService.addEntry(entry);
      
      _notifyDictionaryUpdated();
    } catch (e) {
      debugPrint('단어 추가 중 오류 발생: $e');
    }
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
