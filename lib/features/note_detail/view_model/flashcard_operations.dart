import 'package:flutter/foundation.dart';
import '../../../core/models/flash_card.dart';
import '../../../core/models/note.dart';
import '../../../core/services/content/note_service.dart';
import '../../flashcard/flashcard_service.dart';
import 'text_view_model.dart';

/// 플래시카드 관련 작업을 담당하는 클래스
class FlashcardOperations {
  // 서비스 인스턴스
  final FlashCardService _flashCardService;
  final NoteService _noteService;
  
  // 플래시카드 목록
  List<FlashCard> _flashcards = [];
  
  // 노트 정보
  final String _noteId;
  Note? _note;
  
  // TextViewModel 맵에 대한 참조
  final Map<String, TextViewModel> _textViewModels;
  
  FlashcardOperations({
    required String noteId,
    required Map<String, TextViewModel> textViewModels,
    Note? note,
    FlashCardService? flashCardService,
    NoteService? noteService,
  }) : 
    _noteId = noteId,
    _note = note,
    _textViewModels = textViewModels,
    _flashCardService = flashCardService ?? FlashCardService(),
    _noteService = noteService ?? NoteService();
  
  // Getters
  List<FlashCard> get flashcards => _flashcards;
  int get flashcardCount => _note?.flashcardCount ?? 0;
  
  /// 플래시카드 목록 로드
  Future<void> loadFlashcardsForNote() async {
    try {
      final cards = await _flashCardService.getFlashCardsForNote(_noteId);
      _flashcards = cards;
      
      // 모든 텍스트 뷰모델에 플래시카드 단어 전달
      for (final textViewModel in _textViewModels.values) {
        textViewModel.extractFlashcardWords(_flashcards);
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ 플래시카드 로드 중 오류: $e");
      }
    }
  }
  
  /// 플래시카드 카운트 업데이트
  Future<void> updateFlashcardCount(int count) async {
    if (_note == null) return;
    
    // 노트 객체의 플래시카드 카운트 업데이트
    _note = _note!.copyWith(flashcardCount: count);
    
    // UI 차단 방지를 위해 백그라운드에서 Firestore 업데이트
    Future.microtask(() async {
      await _noteService.updateNote(_note!.id!, _note!);
    });
  }
  
  /// 플래시카드 목록 업데이트
  void updateFlashcards(List<FlashCard> flashcards) {
    _flashcards = flashcards;
    
    // 모든 텍스트 뷰모델에 플래시카드 단어 전달
    for (final textViewModel in _textViewModels.values) {
      textViewModel.extractFlashcardWords(_flashcards);
    }
  }
  
  /// 현재 페이지에 해당하는 플래시카드 목록 반환
  List<FlashCard> getFlashcardsForCurrentPage() {
    return _flashcards;
  }
  
  /// 노트 업데이트
  void updateNote(Note note) {
    _note = note;
  }
} 