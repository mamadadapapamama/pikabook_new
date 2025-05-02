import '../../core/models/note.dart';
import '../../core/utils/language_constants.dart';

/// 샘플 모드에서 사용할 노트 데이터를 제공하는 서비스
class SampleNotesService {
  /// 싱글톤 패턴 적용
  static final SampleNotesService _instance = SampleNotesService._internal();
  
  factory SampleNotesService() {
    return _instance;
  }
  
  SampleNotesService._internal();
  
  /// 샘플 노트 목록 가져오기
  List<Note> getSampleNotes() {
    return [
      _getSampleEnglishNote(),
      _getSampleChineseNote(),
    ];
  }
  
  /// 영어 샘플 노트
  Note _getSampleEnglishNote() {
    return Note(
      id: 'sample-note-1',
      originalText: '영어 원서 학습 노트',
      translatedText: '영어 원서 학습 노트',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now().subtract(const Duration(days: 2)),
      imageUrl: null,
      sourceLanguage: SourceLanguage.ENGLISH,
      targetLanguage: TargetLanguage.KOREAN,
      processingCompleted: true,
      isProcessingBackground: false,
      extractedText: '샘플 영어 원서 내용입니다.',
    );
  }
  
  /// 중국어 샘플 노트
  Note _getSampleChineseNote() {
    return Note(
      id: 'sample-note-2',
      originalText: '중국어 학습 노트',
      translatedText: '중국어 학습 노트',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      imageUrl: null,
      sourceLanguage: SourceLanguage.CHINESE,
      targetLanguage: TargetLanguage.KOREAN,
      processingCompleted: true,
      isProcessingBackground: false,
      extractedText: '샘플 중국어 교재 내용입니다.',
    );
  }
} 