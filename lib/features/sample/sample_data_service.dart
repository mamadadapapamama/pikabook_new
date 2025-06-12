import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/models/note.dart';
import '../../core/models/page.dart' as page_model;
import '../../core/models/flash_card.dart';
import '../../core/models/processed_text.dart';

/// 샘플 데이터를 JSON 파일에서 로드하는 서비스
class SampleDataService {
  static final SampleDataService _instance = SampleDataService._internal();
  
  Note? _sampleNote;
  List<page_model.Page> _samplePages = [];
  List<FlashCard> _sampleFlashCards = [];
  Map<String, ProcessedText> _sampleProcessedTexts = {};
  
  bool _isLoaded = false;
  
  factory SampleDataService() {
    return _instance;
  }
  
  SampleDataService._internal();
  
  /// 샘플 데이터 로드
  Future<void> loadSampleData() async {
    if (_isLoaded) return;
    
    try {
      if (kDebugMode) {
        debugPrint('📦 샘플 데이터 로드 시작');
      }
      
      // JSON 파일 로드
      final String jsonString = await rootBundle.loadString('assets/data/sample_note_data.json');
      final Map<String, dynamic> data = json.decode(jsonString);
      
      // 노트 데이터 파싱
      if (data['note'] != null) {
        _sampleNote = Note.fromJson(data['note']);
      }
      
      // 페이지 데이터 파싱
      if (data['pages'] != null) {
        _samplePages = (data['pages'] as List)
            .map((pageData) => page_model.Page.fromJson(pageData))
            .toList();
      }
      
      // 플래시카드 데이터 파싱
      if (data['flashcards'] != null) {
        _sampleFlashCards = (data['flashcards'] as List)
            .map((cardData) => FlashCard.fromJson(cardData))
            .toList();
      }
      
      // 처리된 텍스트 데이터 파싱
      if (data['processedTexts'] != null) {
        final processedTextsData = data['processedTexts'] as Map<String, dynamic>;
        _sampleProcessedTexts = processedTextsData.map(
          (pageId, textData) => MapEntry(pageId, ProcessedText.fromJson(textData))
        );
      }
      
      _isLoaded = true;
      
      if (kDebugMode) {
        debugPrint('✅ 샘플 데이터 로드 완료');
        debugPrint('   노트: ${_sampleNote?.title}');
        debugPrint('   페이지: ${_samplePages.length}개');
        debugPrint('   플래시카드: ${_sampleFlashCards.length}개');
        debugPrint('   처리된 텍스트: ${_sampleProcessedTexts.length}개');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 샘플 데이터 로드 실패: $e');
      }
      rethrow;
    }
  }
  
  /// 샘플 노트 가져오기
  Note? getSampleNote() {
    return _sampleNote;
  }
  
  /// 샘플 노트 목록 가져오기 (단일 노트를 리스트로)
  List<Note> getSampleNotes() {
    return _sampleNote != null ? [_sampleNote!] : [];
  }
  
  /// 샘플 페이지 가져오기
  List<page_model.Page> getSamplePages(String? noteId) {
    if (noteId == null) return _samplePages;
    return _samplePages.where((page) => page.noteId == noteId).toList();
  }
  
  /// 특정 페이지 가져오기
  page_model.Page? getPageById(String pageId) {
    try {
      return _samplePages.firstWhere((page) => page.id == pageId);
    } catch (e) {
      return null;
    }
  }
  
  /// 샘플 플래시카드 가져오기
  List<FlashCard> getSampleFlashCards(String? noteId) {
    if (noteId == null) return _sampleFlashCards;
    return _sampleFlashCards.where((card) => card.noteId == noteId).toList();
  }
  
  /// 샘플 처리된 텍스트 가져오기
  ProcessedText? getProcessedText(String pageId) {
    return _sampleProcessedTexts[pageId];
  }
  
  /// 특정 단어가 샘플 데이터에 있는지 확인
  bool hasWord(String word) {
    return _sampleFlashCards.any((card) => card.front == word);
  }
  
  /// 사용 가능한 단어 목록 반환
  List<String> getAvailableWords() {
    return _sampleFlashCards.map((card) => card.front).toList();
  }
  
  /// 데이터 로드 상태 확인
  bool get isLoaded => _isLoaded;
} 