import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/note.dart';
import '../../core/models/flash_card.dart';

/// 샘플 모드에서 사용할 노트 데이터를 제공하는 서비스
/// 모든 데이터는 메모리에 미리 로드되어 즉시 반환됩니다.
class SampleNotesService {
  /// 싱글톤 패턴 적용
  static final SampleNotesService _instance = SampleNotesService._internal();
  
  // 미리 생성된 샘플 노트 목록
  late final List<Note> _sampleNotes;
  
  // 샘플 플래시카드 목록
  late final List<FlashCard> _schoolFlashcards;
  
  // 이미지 경로 상수
  static const String sampleImagePath = 'assets/images/sample_1.jpg';
  static const String sampleAnimalImage1 = 'assets/images/sample_2.jpg';
  static const String sampleAnimalImage2 = 'assets/images/sample_3.jpg';
  
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
    
    // 샘플 플래시카드 초기화
    _schoolFlashcards = _createSampleFlashcards();
    
    // 샘플 노트 초기화
    _sampleNotes = [
      _createSampleAnimalBookNote(),
      _createSampleChineseNote()
    ];
  }
  
  /// 샘플 노트 목록 가져오기 (즉시 반환)
  List<Note> getSampleNotes() {
    if (kDebugMode) {
      debugPrint('샘플 노트 목록 요청됨 - 즉시 반환');
    }
    return _sampleNotes;
  }
  
  /// 샘플 플래시카드 가져오기 (즉시 반환)
  List<FlashCard> getSampleFlashcards() {
    return _schoolFlashcards;
  }
  
  /// 중국어 동물 동화책 샘플 노트 생성
  Note _createSampleAnimalBookNote() {
    if (kDebugMode) {
      debugPrint('중국어 동물 동화책 샘플 노트 생성');
    }
    
    return Note(
      id: 'sample-animal-book',
      userId: 'sample-user',
      title: '동물 친구들의 과일 파티',
      description: '중국어 동화책 샘플',
      isFavorite: false,
      flashcardCount: 0,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 12)),
    );
  }
  
  /// 중국어 학교 관련 샘플 노트 생성
  Note _createSampleChineseNote() {
    if (kDebugMode) {
      debugPrint('중국어 샘플 노트 생성');
    }
    
    return Note(
      id: 'sample-note-2',
      userId: 'sample-user',
      title: '1과 복습: 학교에서',
      description: '중국어 학습 노트 - 제7과 학교에서',
      isFavorite: false,
      flashcardCount: _schoolFlashcards.length,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
    );
  }
  
  /// 샘플 플래시카드 생성
  List<FlashCard> _createSampleFlashcards() {
    return [
      FlashCard(
        id: 'sample-school-card-1',
        front: '学校',
        back: '학교',
        pinyin: 'xuéxiào',
        createdAt: DateTime.now(),
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
        noteId: 'sample-note-2',
      ),
      FlashCard(
        id: 'sample-school-card-2',
        front: '老师',
        back: '선생님',
        pinyin: 'lǎoshī',
        createdAt: DateTime.now(),
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
        noteId: 'sample-note-2',
      ),
      FlashCard(
        id: 'sample-school-card-3',
        front: '同学',
        back: '학우, 급우',
        pinyin: 'tóngxué',
        createdAt: DateTime.now(),
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
        noteId: 'sample-note-2',
      ),
      FlashCard(
        id: 'sample-school-card-4',
        front: '认真',
        back: '성실하다',
        pinyin: 'rènzhēn',
        createdAt: DateTime.now(),
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
        noteId: 'sample-note-2',
      ),
      FlashCard(
        id: 'sample-school-card-5',
        front: '专心',
        back: '집중하다',
        pinyin: 'zhuānxīn',
        createdAt: DateTime.now(),
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
        noteId: 'sample-note-2',
      ),
    ];
  }
  
  /// 특정 노트의 플래시카드 가져오기
  List<FlashCard> getFlashcardsForNote(String noteId) {
    if (noteId == 'sample-note-2') {
      return _schoolFlashcards;
    }
    return [];
  }
  
  // 샘플 노트 페이지의 이미지 파일 경로 가져오기
  String? getImagePathForNote(String noteId) {
    if (noteId == 'sample-note-2') {
      return sampleImagePath;
    } else if (noteId == 'sample-animal-book') {
      return sampleAnimalImage1;
    }
    return null;
  }
}
