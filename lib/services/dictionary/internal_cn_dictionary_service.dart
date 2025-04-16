import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/dictionary_entry.dart';

/// 내부 중국어 사전 데이터를 로드 관리하는 서비스

class InternalCnDictionaryService {
  static final InternalCnDictionaryService _instance =
      InternalCnDictionaryService._internal();

  factory InternalCnDictionaryService() {
    return _instance;
  }

  InternalCnDictionaryService._internal();

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

  // 단어 검색 (지연 로드 지원)
  Future<DictionaryEntry?> lookupAsync(String word) async {
    if (!_isLoaded) {
      await loadDictionary();
    }
    return _entries[word];
  }

  // 단어 검색 (동기식)
  DictionaryEntry? lookup(String word) {
    if (!_isLoaded) {
      // 사전이 로드되지 않았으면 로드 시작 (결과는 반환하지 않음)
      loadDictionary();
      return null;
    }
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
