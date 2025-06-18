import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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
      
      // 샘플 이미지를 로컬 디렉토리에 복사
      await _copySampleImages();
      
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
  
  /// 샘플 이미지를 로컬 디렉토리에 복사
  Future<void> _copySampleImages() async {
    try {
      // 앱 문서 디렉토리 가져오기
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/images');
      
      // images 디렉토리 생성
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      
      // 샘플 이미지 파일 경로
      final localImagePath = '${appDir.path}/images/sample_page_1.png';
      final localImageFile = File(localImagePath);
      
      // 이미 파일이 존재하면 복사하지 않음
      if (await localImageFile.exists()) {
        if (kDebugMode) {
          debugPrint('📷 샘플 이미지가 이미 존재함: $localImagePath');
        }
        
        // 페이지 데이터의 imageUrl을 절대 경로로 업데이트
        _updateImagePaths(localImagePath);
        return;
      }
      
      // assets에서 이미지 로드
      final byteData = await rootBundle.load('assets/images/sample_page_1.png');
      final bytes = byteData.buffer.asUint8List();
      
      // 로컬 파일로 저장
      await localImageFile.writeAsBytes(bytes);
      
      if (kDebugMode) {
        debugPrint('📷 샘플 이미지 복사 완료: $localImagePath');
      }
      
      // 페이지 데이터의 imageUrl을 절대 경로로 업데이트
      _updateImagePaths(localImagePath);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 샘플 이미지 복사 실패: $e');
      }
    }
  }
  
  /// 페이지 데이터의 이미지 경로를 절대 경로로 업데이트
  void _updateImagePaths(String absolutePath) {
    for (var page in _samplePages) {
      if (page.imageUrl == 'images/sample_page_1.png') {
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
      }
    }
    
    // 노트의 firstImageUrl도 업데이트
    if (_sampleNote != null && _sampleNote!.firstImageUrl == 'images/sample_page_1.png') {
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
    }
  }
} 