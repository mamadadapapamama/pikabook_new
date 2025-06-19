import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/note.dart';
import '../../core/models/page.dart' as page_model;
import '../../core/models/flash_card.dart';
import '../../core/models/processed_text.dart';
import 'sample_tts_service.dart';

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
      
      // 샘플 이미지 경로를 assets 경로로 하드코딩
      _updateImagePathsToAssets();
      
      // 오디오 파일 체크는 하드코딩으로 처리하므로 불필요
      // await SampleTtsService().checkAudioAssets();
      
      _isLoaded = true;
      
      if (kDebugMode) {
        debugPrint('✅ 샘플 데이터 로드 완료');
        debugPrint('   노트: ${_sampleNote?.title}');
        debugPrint('   노트 firstImageUrl: ${_sampleNote?.firstImageUrl}');
        debugPrint('   페이지: ${_samplePages.length}개');
        for (var page in _samplePages) {
          debugPrint('   페이지 ${page.pageNumber} imageUrl: ${page.imageUrl}');
        }
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
  
  /// 샘플 이미지를 로컬 디렉토리에 복사 (사용 안함 - 하드코딩 방식 사용)
  /*
  Future<void> _copySampleImages() async {
    // 복잡한 파일 복사 로직 대신 assets 경로 하드코딩 사용
    // _updateImagePathsToAssets() 메서드 사용
  }
  */
  
  /// 샘플 이미지 경로를 assets 경로로 하드코딩 (간단한 방법)
  void _updateImagePathsToAssets() {
    if (kDebugMode) {
      debugPrint('📷 샘플 이미지 경로를 assets으로 하드코딩');
    }
    
    const String assetsImagePath = 'assets/images/sample_page_1.png';
    
    // 페이지 데이터의 imageUrl을 assets 경로로 업데이트
    for (int i = 0; i < _samplePages.length; i++) {
      var page = _samplePages[i];
      if (page.imageUrl == 'images/sample_page_1.png') {
        if (kDebugMode) {
          debugPrint('📷 페이지 ${page.id} 이미지 경로 업데이트: ${page.imageUrl} → $assetsImagePath');
        }
        
        _samplePages[i] = page_model.Page(
          id: page.id,
          noteId: page.noteId,
          pageNumber: page.pageNumber,
          imageUrl: assetsImagePath, // assets 경로로 변경
          originalText: page.originalText,
          createdAt: page.createdAt,
          updatedAt: page.updatedAt,
          sourceLanguage: page.sourceLanguage,
          targetLanguage: page.targetLanguage,
          showTypewriterEffect: page.showTypewriterEffect,
        );
      }
    }
    
    // 노트의 firstImageUrl도 assets 경로로 업데이트
    if (_sampleNote != null && _sampleNote!.firstImageUrl == 'images/sample_page_1.png') {
      if (kDebugMode) {
        debugPrint('📷 노트 ${_sampleNote!.id} firstImageUrl 업데이트: ${_sampleNote!.firstImageUrl} → $assetsImagePath');
      }
      
      _sampleNote = Note(
        id: _sampleNote!.id,
        title: _sampleNote!.title,
        userId: _sampleNote!.userId,
        description: _sampleNote!.description,
        isFavorite: _sampleNote!.isFavorite,
        flashcardCount: _sampleNote!.flashcardCount,
        pageCount: _sampleNote!.pageCount,
        createdAt: _sampleNote!.createdAt,
        updatedAt: _sampleNote!.updatedAt,
        firstImageUrl: assetsImagePath, // assets 경로로 변경
      );
    }
    
    if (kDebugMode) {
      debugPrint('📷 샘플 이미지 경로 하드코딩 완료');
    }
  }

  /// 페이지 데이터의 이미지 경로를 절대 경로로 업데이트 (사용 안함)
  void _updateImagePaths(String absolutePath) {
    if (kDebugMode) {
      debugPrint('📷 이미지 경로 업데이트 시작: $absolutePath');
    }
    
    int updatedPageCount = 0;
    for (var page in _samplePages) {
      if (page.imageUrl == 'images/sample_page_1.png') {
        if (kDebugMode) {
          debugPrint('📷 페이지 ${page.id} 이미지 경로 업데이트: ${page.imageUrl} → $absolutePath');
        }
        
        // 새로운 Page 객체를 생성하여 imageUrl 업데이트
        final updatedPage = page_model.Page(
          id: page.id,
          noteId: page.noteId,
          pageNumber: page.pageNumber,
          imageUrl: absolutePath, // 절대 경로로 변경
          originalText: page.originalText,
          createdAt: page.createdAt,
          updatedAt: page.updatedAt,
          sourceLanguage: page.sourceLanguage,
          targetLanguage: page.targetLanguage,
          showTypewriterEffect: page.showTypewriterEffect,
        );
        
        // 리스트에서 해당 페이지 교체
        final index = _samplePages.indexOf(page);
        _samplePages[index] = updatedPage;
        updatedPageCount++;
      }
    }
    
    // 노트의 firstImageUrl도 업데이트
    bool noteUpdated = false;
    if (_sampleNote != null && _sampleNote!.firstImageUrl == 'images/sample_page_1.png') {
      if (kDebugMode) {
        debugPrint('📷 노트 ${_sampleNote!.id} firstImageUrl 업데이트: ${_sampleNote!.firstImageUrl} → $absolutePath');
      }
      
      _sampleNote = Note(
        id: _sampleNote!.id,
        title: _sampleNote!.title,
        userId: _sampleNote!.userId,
        description: _sampleNote!.description,
        isFavorite: _sampleNote!.isFavorite,
        flashcardCount: _sampleNote!.flashcardCount,
        pageCount: _sampleNote!.pageCount,
        createdAt: _sampleNote!.createdAt,
        updatedAt: _sampleNote!.updatedAt,
        firstImageUrl: absolutePath, // 절대 경로로 변경
      );
      noteUpdated = true;
    }
    
    if (kDebugMode) {
      debugPrint('📷 이미지 경로 업데이트 완료: 페이지 ${updatedPageCount}개, 노트 ${noteUpdated ? 1 : 0}개');
    }
  }
} 