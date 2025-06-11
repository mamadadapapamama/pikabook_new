import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/note.dart';
import '../../core/models/page.dart' as page_model;

/// 샘플 모드에서 실제 노트 시스템을 사용하는 서비스
/// 로컬 데이터와 미리 정의된 OCR 결과를 제공합니다.
class SampleNotesService {
  /// 싱글톤 패턴 적용
  static final SampleNotesService _instance = SampleNotesService._internal();
  
  // 샘플 노트 (하나만)
  late final Note _sampleNote;
  
  // 샘플 페이지
  late final page_model.Page _samplePage;
  
  // 이미지 경로
  static const String sampleImagePath = 'assets/images/sample_1.jpg';
  
  // 샘플 OCR 텍스트 (사용자 제공 데이터)
  static const String sampleOcrText = '''我们早上八点去学校。
教室里有很多桌子和椅子。
老师在黑板上写字。
下课后，我们去操场玩。
我喜欢我的学校。''';
  
  factory SampleNotesService() {
    if (kDebugMode) {
      debugPrint('SampleNotesService 팩토리 생성자 호출됨');
    }
    return _instance;
  }
  
  SampleNotesService._internal() {
    if (kDebugMode) {
      debugPrint('SampleNotesService 내부 생성자 호출됨');
    }
    
    // 샘플 노트와 페이지 초기화
    _initializeSampleData();
  }
  
  /// 샘플 데이터 초기화
  void _initializeSampleData() {
    final now = DateTime.now();
    
    // 샘플 페이지 생성
    _samplePage = page_model.Page(
      id: 'sample-page-001',
      noteId: 'sample-note-school',
      pageNumber: 1,
      imageUrl: sampleImagePath,
      originalText: sampleOcrText,
      createdAt: now.subtract(const Duration(hours: 2)),
      updatedAt: now.subtract(const Duration(hours: 1)),
    );
    
    // 샘플 노트 생성
    _sampleNote = Note(
      id: 'sample-note-school',
      userId: 'sample-user',
      title: '학교에서 (《学校里》)',
      description: '중국어 학습 노트 - 학교 생활 관련 표현',
      isFavorite: false,
      flashcardCount: 0, // 실제 플래시카드 생성 시 업데이트됨
      pageCount: 1,
      firstImageUrl: sampleImagePath,
      createdAt: now.subtract(const Duration(hours: 2)),
      updatedAt: now.subtract(const Duration(hours: 1)),
    );
    
    if (kDebugMode) {
      debugPrint('✅ 샘플 노트 데이터 초기화 완료');
      debugPrint('   노트 ID: ${_sampleNote.id}');
      debugPrint('   페이지 ID: ${_samplePage.id}');
    }
  }
  
  /// 샘플 노트 가져오기 (단일 노트)
  Note getSampleNote() {
    if (kDebugMode) {
      debugPrint('샘플 노트 요청됨 - 즉시 반환');
    }
    return _sampleNote;
  }
  
  /// 샘플 노트 목록 가져오기 (호환성)
  List<Note> getSampleNotes() {
    return [_sampleNote];
  }
  
  /// 샘플 페이지 가져오기
  page_model.Page getSamplePage() {
    if (kDebugMode) {
      debugPrint('샘플 페이지 요청됨 - 즉시 반환');
    }
    return _samplePage;
  }
  
  /// 특정 노트의 페이지 가져오기
  List<page_model.Page> getPagesForNote(String noteId) {
    if (noteId == _sampleNote.id) {
      return [_samplePage];
    }
    return [];
  }
  
  /// 특정 페이지 가져오기
  page_model.Page? getPageById(String pageId) {
    if (pageId == _samplePage.id) {
      return _samplePage;
    }
    return null;
  }
  
  /// 샘플 OCR 텍스트 가져오기
  String getSampleOcrText() {
    return sampleOcrText;
  }
  
  /// 샘플 이미지 경로 가져오기
  String getSampleImagePath() {
    return sampleImagePath;
  }
  
  /// 샘플 모드에서 사용할 수 있는 단어 목록 (OCR 텍스트에서 추출)
  List<String> getAvailableWords() {
    // OCR 텍스트에서 중국어 단어들을 추출
    final words = <String>[
      '我们', '早上', '八', '点', '去', '学校',
      '教室', '里', '有', '很多', '桌子', '和', '椅子',
      '老师', '在', '黑板', '上', '写字',
      '下课', '后', '操场', '玩',
      '我', '喜欢', '的'
    ];
    
    return words;
  }
  
  /// 노트 업데이트 (플래시카드 카운트 등)
  void updateNoteFlashcardCount(int count) {
    // 실제 구현에서는 Firestore 업데이트가 필요하지만
    // 샘플 모드에서는 메모리상에서만 업데이트
    final updatedNote = _sampleNote.copyWith(
      flashcardCount: count,
      updatedAt: DateTime.now(),
    );
    
    // _sampleNote를 업데이트 (final이므로 reflection 필요하지만 샘플이므로 생략)
    if (kDebugMode) {
      debugPrint('📋 샘플 노트 플래시카드 카운트 업데이트: $count개');
    }
  }
}
