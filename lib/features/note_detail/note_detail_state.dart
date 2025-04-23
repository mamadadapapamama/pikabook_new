import '../../core/models/note.dart';
import '../../core/models/page.dart' as page_model;
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

/// 로딩 상태를 표현하는 열거형
enum LoadingState {
  initial,       // 초기 로딩 중
  pageProcessing, // 페이지 처리 중
  imageLoading,  // 이미지 로딩 중
  contentReady,  // 컨텐츠 준비 완료
  error          // 오류 발생
}

enum ComponentState {
  loading,
  ready,
  error
}

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
  
  // 로딩 상태 관리 필드 추가
  LoadingState loadingState = LoadingState.initial;
  Map<String, LoadingState> pageLoadingStates = {}; // 페이지 ID별 로딩 상태
  int processingPageIndex = -1; // 현재 처리 중인 페이지 인덱스
  
  // 상태 업데이트 메서드
  void updateNote(Note note) {
    debugPrint('📝 NoteDetailState.updateNote 호출:');
    debugPrint('  - 기존 노트: ${this.note?.id}, 페이지 수: ${this.note?.pages?.length ?? 0}');
    debugPrint('  - 새 노트: ${note.id}, 페이지 수: ${note.pages?.length ?? 0}, imageCount: ${note.imageCount ?? 0}');
    
    this.note = note;
    this.isFavorite = note.isFavorite;
  }
  
  void setLoading(bool loading) {
    // 로딩 상태 변경 로깅
    debugPrint('🔄 setLoading 호출: 현재 isLoading=$isLoading -> 새 값=$loading');
    isLoading = loading;
    
    // 로딩 상태 업데이트
    if (loading) {
      loadingState = LoadingState.initial;
    } else if (error != null) {
      loadingState = LoadingState.error;
    } else {
      loadingState = LoadingState.contentReady;
    }
  }
  
  void setError(String? error) {
    this.error = error;
    if (error != null) {
      loadingState = LoadingState.error;
    }
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
    if (processing) {
      loadingState = LoadingState.pageProcessing;
    } else if (!isLoading && error == null) {
      loadingState = LoadingState.contentReady;
    }
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
  
  // 페이지 로딩 상태 관리 메서드 추가
  void setPageLoadingState(String pageId, LoadingState state) {
    pageLoadingStates[pageId] = state;
  }
  
  LoadingState getPageLoadingState(String pageId) {
    return pageLoadingStates[pageId] ?? LoadingState.initial;
  }
  
  void setProcessingPageIndex(int index) {
    processingPageIndex = index;
  }
  
  bool isPageProcessing(int index) {
    return processingPageIndex == index;
  }
  
  // 글로벌 로딩 상태 업데이트
  void updateGlobalLoadingState() {
    if (isLoading) {
      loadingState = LoadingState.initial;
      return;
    }
    
    if (error != null) {
      loadingState = LoadingState.error;
      return;
    }
    
    if (isProcessingText) {
      loadingState = LoadingState.pageProcessing;
      return;
    }
    
    // 모든 페이지가 준비된 상태인지 확인
    bool anyPageProcessing = pageLoadingStates.values.any(
      (state) => state == LoadingState.pageProcessing || state == LoadingState.imageLoading
    );
    
    if (anyPageProcessing) {
      loadingState = LoadingState.pageProcessing;
    } else {
      loadingState = LoadingState.contentReady;
    }
  }
}
