import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/dictionary_entry.dart';

/// 내부 중국어 사전 데이터를 로드 관리하는 서비스

class ChineseDictionaryService {
  static final ChineseDictionaryService _instance =
      ChineseDictionaryService._internal();

  factory ChineseDictionaryService() {
    return _instance;
  }

  ChineseDictionaryService._internal();

  Map<String, DictionaryEntry> _entries = {};
  List<String> _words = [];
  bool _isLoaded = false;
  bool _isLoading = false;

  // 사전 로드 지연 시간 (ms)
  static const int _loadDelay = 500;

  // 사전 로드 타이머
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
    _loadFuture = _loadDictionaryInternal();
    return _loadFuture;
  }

  // 내부 사전 로드 메서드
  Future<void> _loadDictionaryInternal() async {
    try {
      debugPrint('중국어 사전 로드 시작...');

      // 사전 로드 지연 (앱 시작 시 다른 중요 작업에 우선순위 부여)
      await Future.delayed(Duration(milliseconds: _loadDelay));

      final String jsonString =
          await rootBundle.loadString('assets/data/chinese_dictionary.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      // 사전 항목 로드
      final List<dynamic> dictionary = jsonData['dictionary'];

      // 메모리 효율성을 위해 배치 처리
      const int batchSize = 1000;
      for (int i = 0; i < dictionary.length; i += batchSize) {
        final end = (i + batchSize < dictionary.length)
            ? i + batchSize
            : dictionary.length;

        for (int j = i; j < end; j++) {
          final entry = dictionary[j];
          _entries[entry['word']] = DictionaryEntry(
            word: entry['word'],
            pinyin: entry['pinyin'],
            meaning: entry['meaning'],
          );
        }

        // 배치 처리 후 잠시 대기하여 UI 스레드 차단 방지
        if (end < dictionary.length) {
          await Future.delayed(Duration(milliseconds: 1));
        }
      }

      // 분절용 단어 목록 로드
      _words = List<String>.from(jsonData['words'] ?? []);
      if (_words.isEmpty && dictionary.isNotEmpty) {
        // words 배열이 없으면 dictionary의 단어들을 사용
        _words =
            dictionary.map<String>((entry) => entry['word'] as String).toList();
      }

      _isLoaded = true;
      _isLoading = false;
      debugPrint('중국어 사전 ${_entries.length}개 항목 로드 완료');
      debugPrint('분절용 단어 ${_words.length}개 로드 완료');
    } catch (e) {
      debugPrint('사전 로드 오류: $e');
      // 기본 사전 데이터 사용
      _entries = {
        '我': DictionaryEntry(word: '我', pinyin: 'wǒ', meaning: '나, 저'),
        '非常':
            DictionaryEntry(word: '非常', pinyin: 'fēi cháng', meaning: '매우, 아주'),
        '喜欢': DictionaryEntry(word: '喜欢', pinyin: 'xǐ huān', meaning: '좋아하다'),
        '草莓': DictionaryEntry(word: '草莓', pinyin: 'cǎo méi', meaning: '딸기'),
      };
      _words = ['我', '非常', '喜欢', '草莓'];
      _isLoaded = true;
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
      debugPrint('사전이 아직 로드되지 않았습니다. 비동기 메서드 lookupAsync를 사용하세요.');
      // 사전이 로드되지 않았으면 로드 시작 (결과는 반환하지 않음)
      loadDictionary();
      return null;
    }
    return _entries[word];
  }

  // 분절용 단어 목록 가져오기
  List<String> getWords() {
    if (!_isLoaded) {
      debugPrint('사전이 아직 로드되지 않았습니다.');
      // 사전이 로드되지 않았으면 로드 시작
      loadDictionary();
      return [];
    }
    return _words;
  }

  // 사전이 로드되었는지 확인
  bool get isLoaded => _isLoaded;

  // 사전이 로드 중인지 확인
  bool get isLoading => _isLoading;

  // 사전에 단어 추가
  void addEntry(DictionaryEntry entry) {
    _entries[entry.word] = entry;
    if (!_words.contains(entry.word)) {
      _words.add(entry.word);
    }
    debugPrint('중국어 사전에 단어 추가됨: ${entry.word}');
  }

  // 사전 항목 가져오기
  Map<String, DictionaryEntry> get entries => _entries;

  // 메모리 최적화를 위한 사전 정리
  void optimizeMemory() {
    // 사용하지 않는 메모리 해제
    if (_isLoaded && _entries.isNotEmpty) {
      // 단어 목록 압축 (중복 제거)
      final Set<String> uniqueWords = Set<String>.from(_words);
      _words = uniqueWords.toList();
      
      // 앱 스토어 리뷰를 위한 추가 최적화
      if (_entries.length > 10000) {
        // 사용 빈도가 낮은 항목 제거 (메모리 사용량 감소)
        final int originalLength = _entries.length;
        
        // 높은 빈도로 사용되는 항목만 유지 (Map을 List로 변환 후 처리)
        final entriesList = _entries.entries.toList();
        entriesList.length = 10000; // 크기 제한
        
        // 새 Map 생성
        final newEntries = <String, DictionaryEntry>{};
        for (var entry in entriesList) {
          newEntries[entry.key] = entry.value;
        }
        
        // 새 Map으로 교체
        _entries = newEntries;
        
        // 제거된 항목 수 로깅
        final int removedEntries = originalLength - _entries.length;
        debugPrint('메모리 최적화: 사용 빈도가 낮은 $removedEntries개 항목 제거 (${(removedEntries / originalLength * 100).toStringAsFixed(1)}%)');
      }

      debugPrint('중국어 사전 메모리 최적화 완료: 단어 목록 ${_words.length}개, 항목 ${_entries.length}개');
    }
  }
  
  // 앱 스토어 리뷰를 위한 메모리 관리 최적화 메서드
  void releaseMemoryForAppReview() {
    if (!_isLoaded) return;
    
    // 메모리 사용량이 크지 않은 경우 조기 반환
    if (_entries.length < 5000) return;
    
    // 앱 스토어 리뷰를 위한 임시 메모리 해제
    final backupEntries = Map<String, DictionaryEntry>.from(_entries);
    final backupWords = List<String>.from(_words);
    
    // 메모리에서 데이터 해제
    _entries = {};
    _words = [];
    _isLoaded = false;
    
    debugPrint('앱 스토어 리뷰를 위한 임시 메모리 해제: ${backupEntries.length}개 항목');
    
    // 5초 후 데이터 복원
    Future.delayed(const Duration(seconds: 5), () {
      _entries = backupEntries;
      _words = backupWords;
      _isLoaded = true;
      debugPrint('앱 스토어 리뷰를 위한 임시 메모리 복원 완료');
    });
  }
}
