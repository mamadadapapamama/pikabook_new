import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../models/dictionary.dart';
import '../text_processing/llm_text_processing.dart';
import '../../models/chinese_text.dart';

/// 내부 중국어 사전 데이터를 로드 관리하는 서비스
/// LLM 캐시를 먼저 확인하고, 내부 사전 DB에서 검색하는 기능 제공

class InternalCnDictionaryService {
  static final InternalCnDictionaryService _instance =
      InternalCnDictionaryService._internal();

  factory InternalCnDictionaryService() {
    return _instance;
  }

  InternalCnDictionaryService._internal() {
    // LLM 텍스트 처리 서비스 초기화
    _textProcessingService = UnifiedTextProcessingService();
  }

  // LLM 텍스트 처리 서비스 (캐시 연동용)
  late final UnifiedTextProcessingService _textProcessingService;

  Map<String, DictionaryEntry> _entries = {};
  bool _isLoaded = false;
  bool _isLoading = false;

  // 사전 로드 지연 시간 (ms)
  static const int _loadDelay = 500;

  // 사전 로드 Future
  Future<void>? _loadFuture;

  // 사전 데이터 로드
  Future<void> loadDictionary() async {
    // 이미 로드되었거나 로드 중이면 반환
    if (_isLoaded) return;
    if (_isLoading) {
      // 로드 중인 경우 완료될 때까지 대기
      if (_loadFuture != null) {
        return _loadFuture;
      }
      return;
    }

    _isLoading = true;
    
    // 비동기 로드 방식 사용
    try {
      _loadFuture = _loadDictionaryInternal();
      return _loadFuture;
    } catch (e) {
      debugPrint('사전 로드 오류: $e');
      _isLoading = false;
      rethrow;
    }
  }

  // 내부 사전 로드 메서드
  Future<void> _loadDictionaryInternal() async {
    try {
      // 지연 추가 (타이머 대신 Future.delayed 사용)
      await Future.delayed(Duration(milliseconds: _loadDelay));
      
      final String jsonString =
          await rootBundle.loadString('assets/data/chinese_dictionary.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      // 사전 항목 로드
      final List<dynamic> dictionary = jsonData['dictionary'];
      
      // 사전 크기 제한 (메모리 최적화)
      final int maxDictionaryEntries = 10000;
      final int effectiveSize = dictionary.length > maxDictionaryEntries 
          ? maxDictionaryEntries 
          : dictionary.length;

      // 메모리 효율성을 위해 배치 처리
      const int batchSize = 1000;
      for (int i = 0; i < effectiveSize; i += batchSize) {
        final end = (i + batchSize < effectiveSize)
            ? i + batchSize
            : effectiveSize;

        for (int j = i; j < end; j++) {
          final entry = dictionary[j];
          _entries[entry['word']] = DictionaryEntry(
            word: entry['word'],
            pinyin: entry['pinyin'],
            meaning: entry['meaning'],
          );
        }

        // 배치 처리 후 UI 스레드 차단 방지
        if (end < effectiveSize) {
          await Future.delayed(Duration(milliseconds: 5));
        }
      }

      _isLoaded = true;
      _isLoading = false;
    } catch (e) {
      debugPrint('사전 로드 오류: $e');
      _isLoaded = false;
      _isLoading = false;
    }
  }

  // LLM 캐시에서 단어 정보 찾기
  Future<DictionaryEntry?> _lookupFromLLMCache(String word) async {
    try {
      // LLM 서비스가 캐시하고 있는지 확인
      final cacheData = _textProcessingService.getWordCacheData(word);
      
      if (cacheData != null) {
        if (kDebugMode) {
          debugPrint('LLM 캐시에서 단어 정보 찾음: $word');
        }
        
        return DictionaryEntry(
          word: cacheData['chinese'] ?? word,
          pinyin: cacheData['pinyin'] ?? '',
          meaning: cacheData['korean'] ?? '',
          source: 'llm_cache'
        );
      }
      
      return null;
    } catch (e) {
      debugPrint('LLM 캐시 조회 중 오류: $e');
      return null;
    }
  }

  // 단어 검색 (지연 로드 지원) - LLM 캐시 먼저 확인
  Future<DictionaryEntry?> lookupAsync(String word) async {
    // 1. LLM 캐시에서 먼저 확인
    final llmCacheResult = await _lookupFromLLMCache(word);
    if (llmCacheResult != null) {
      return llmCacheResult;
    }
    
    // 2. 내부 사전에서 확인
    if (!_isLoaded) {
      await loadDictionary();
    }
    return _entries[word];
  }

  // 단어 검색 (동기식) - LLM 캐시 먼저 확인
  DictionaryEntry? lookup(String word) {
    // 내부 사전이 로드되지 않았으면 로드 시작
    if (!_isLoaded) {
      loadDictionary();
      
      // LLM 캐시에서 확인 - 비동기지만 async 메서드 내부에서 처리
      _lookupFromLLMCache(word).then((llmResult) {
        if (llmResult != null) {
          // 여기서는 결과를 반환할 수 없고, UI가 새로고침되어야 함
          if (kDebugMode) {
            debugPrint('LLM 캐시에서 단어 정보 찾음 (비동기): $word');
          }
        }
      });
      
      // 초기 요청에서는 null 반환 (UI가 나중에 새로고침해야 함)
      return null;
    }
    
    // LLM 캐시에서 즉시 확인 시도 (이미 캐시되어 있는지 확인)
    if (_textProcessingService.hasWordInCache(word)) {
      // 비동기 작업 시작 (결과는 UI 갱신에 사용)
      _lookupFromLLMCache(word).then((llmResult) {
        if (kDebugMode && llmResult != null) {
          debugPrint('LLM 캐시에서 단어 정보 찾음 (사전 로드 완료 후): $word');
        }
      });
    }
    
    // 내부 사전에서 확인
    return _entries[word];
  }

  // 사전이 로드되었는지 확인
  bool get isLoaded => _isLoaded;

  // 사전이 로드 중인지 확인
  bool get isLoading => _isLoading;

  // 단어 목록 가져오기 (분절 서비스용)
  List<String> getWords() {
    if (!_isLoaded) {
      // 사전이 로드되지 않았으면 로드 시작
      loadDictionary();
      return [];
    }
    // 단어 목록 생성 (키 목록)
    return _entries.keys.toList();
  }
  
  // 사전에 단어 추가 (다른 서비스에서 호출됨)
  void addEntry(DictionaryEntry entry) {
    if (!_isLoaded) {
      // 사전이 로드되지 않았으면 먼저 로드
      loadDictionary();
    }
    
    // 사전에 단어 추가
    _entries[entry.word] = entry;
  }

  // 메모리 최적화
  void optimizeMemory() {
    if (_isLoaded && _entries.length > 10000) {
      final entriesList = _entries.entries.toList();
      final optimizedEntries = <String, DictionaryEntry>{};
      
      // 상위 1만 개만 유지
      for (int i = 0; i < 10000 && i < entriesList.length; i++) {
        optimizedEntries[entriesList[i].key] = entriesList[i].value;
      }
      
      _entries = optimizedEntries;
    }
  }
}
