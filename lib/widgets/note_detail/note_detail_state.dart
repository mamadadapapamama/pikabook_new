import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import 'dart:io';
import 'dart:async';

class NoteDetailState {
  Note? note;
  bool isLoading = true;
  String? error;
  bool isFavorite = false;
  bool isCreatingFlashCard = false;
  bool isProcessingText = false;
  File? imageFile;
  Set<int> previouslyVisitedPages = <int>{};
  bool showTooltip = false;
  int tooltipStep = 1;
  final int totalTooltipSteps = 3;
  bool isEditingTitle = false;
  int expectedTotalPages = 0;
  bool isProcessingBackground = false;
  Timer? backgroundCheckTimer;
  
  // 상태 업데이트 메서드
  void updateNote(Note note) {
    this.note = note;
    this.isFavorite = note.isFavorite;
  }
  
  void setLoading(bool loading) {
    isLoading = loading;
  }
  
  void setError(String? error) {
    this.error = error;
  }
  
  void toggleFavorite() {
    isFavorite = !isFavorite;
  }
  
  void markPageVisited(int pageIndex) {
    previouslyVisitedPages.add(pageIndex);
  }
  
  bool isPageVisited(int pageIndex) {
    return previouslyVisitedPages.contains(pageIndex);
  }
  
  void setProcessingText(bool processing) {
    isProcessingText = processing;
  }
  
  void setCurrentImageFile(File? file) {
    imageFile = file;
  }
  
  void setTooltipStep(int step) {
    if (step >= 1 && step <= totalTooltipSteps) {
      tooltipStep = step;
    }
  }
  
  void showEditTitle(bool show) {
    isEditingTitle = show;
  }
  
  void setBackgroundProcessingFlag(bool isProcessing) {
    isProcessingBackground = isProcessing;
  }
  
  void clearVisitedPages() {
    previouslyVisitedPages.clear();
  }
  
  void cancelBackgroundTimer() {
    backgroundCheckTimer?.cancel();
    backgroundCheckTimer = null;
  }
}
