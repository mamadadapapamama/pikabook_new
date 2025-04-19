import 'dart:io';
import 'package:flutter/material.dart';

import '../../../../models/page.dart' as page_model;
import '../../../../services/note/page_service.dart';
import '../../../../widgets/note_page_manager.dart';
import '../../../../widgets/note_segment_manager.dart';

/// 페이지 관리 로직을 담당하는 클래스
/// 
/// 이 클래스는 노트의 페이지 로드, 변경, 내비게이션 등의 로직을 처리합니다.
/// 기존 NotePageManager와 NoteSegmentManager를 감싸서 관리합니다.

class NotePageManagerWrapper {
  final String noteId;
  final Function(int) onPageChanged;
  
  // 기존 매니저 클래스들
  late NotePageManager _pageManager;
  late NoteSegmentManager _segmentManager;
  
  // 상태 변수
  int _currentPageIndex = 0;
  int _expectedTotalPages = 0;
  late PageController _pageController;
  
  NotePageManagerWrapper({
    required this.noteId,
    required this.onPageChanged,
  }) {
    _pageManager = NotePageManager(noteId: noteId);
    _segmentManager = NoteSegmentManager();
    _pageController = PageController();
  }
  
  // 예상 총 페이지 수 설정
  void setExpectedTotalPages(int count) {
    _expectedTotalPages = count;
  }
  
  // 페이지 로드
  Future<void> loadPages({bool forceReload = false}) async {
    await _pageManager.loadPagesFromServer(forceReload: forceReload);
    _currentPageIndex = _pageManager.currentPageIndex;
  }
  
  // 페이지 다시 로드
  Future<void> reloadPages() async {
    await loadPages(forceReload: true);
  }
  
  // 페이지 변경
  Future<void> changePage(int pageIndex) async {
    if (pageIndex < 0 || pageIndex >= _pageManager.pages.length) {
      return;
    }
    
    _pageManager.setCurrentPageIndex(pageIndex);
    _currentPageIndex = pageIndex;
    
    // 페이지 컨트롤러 애니메이션
    if (_pageController.hasClients) {
      await _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    
    onPageChanged(pageIndex);
  }
  
  // 다음 페이지로 이동
  Future<void> nextPage() async {
    if (_currentPageIndex < _pageManager.pages.length - 1) {
      await changePage(_currentPageIndex + 1);
    }
  }
  
  // 이전 페이지로 이동
  Future<void> previousPage() async {
    if (_currentPageIndex > 0) {
      await changePage(_currentPageIndex - 1);
    }
  }
  
  // 현재 페이지 가져오기
  page_model.Page? getCurrentPage() {
    if (_pageManager.pages.isEmpty) {
      return null;
    }
    
    if (_currentPageIndex >= _pageManager.pages.length) {
      return null;
    }
    
    return _pageManager.pages[_currentPageIndex];
  }
  
  // 현재 페이지 인덱스 가져오기
  int getCurrentPageIndex() {
    return _currentPageIndex;
  }
  
  // 총 페이지 수 가져오기
  int getTotalPageCount() {
    return _expectedTotalPages > 0 
      ? Math.max(_pageManager.pages.length, _expectedTotalPages)
      : _pageManager.pages.length;
  }
  
  // 현재 페이지의 이미지 파일 가져오기
  File? getCurrentImageFile() {
    return _pageManager.currentImageFile;
  }
  
  // 페이지 컨트롤러 가져오기
  PageController getPageController() {
    return _pageController;
  }
  
  // 모든 페이지 가져오기
  List<page_model.Page> getPages() {
    return _pageManager.pages;
  }
  
  // 리소스 정리
  Future<void> dispose() async {
    _pageController.dispose();
    await _pageManager.dispose();
  }
} 