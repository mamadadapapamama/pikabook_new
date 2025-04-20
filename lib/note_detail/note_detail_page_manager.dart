import 'dart:io';
import 'package:flutter/material.dart';
import '../models/page.dart' as page_model;
import '../services/page_service.dart';
import '../services/image_service.dart';

class NoteDetailPageManager {
  final String noteId;
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  
  List<page_model.Page> pages = [];
  int currentPageIndex = 0;
  
  NoteDetailPageManager({required this.noteId});
  
  page_model.Page? get currentPage => 
      pages.isNotEmpty && currentPageIndex < pages.length ? pages[currentPageIndex] : null;
  
  File? _currentImageFile;
  File? get currentImageFile => _currentImageFile;
  
  // 페이지 로드 메서드
  Future<void> loadPagesFromServer({bool forceReload = false}) async {
    // 서버에서 페이지 로드
    final loadedPages = await _pageService.getPagesForNote(noteId, forceReload: forceReload);
    if (loadedPages.isNotEmpty) {
      pages = loadedPages;
    }
  }
  
  // 페이지 이미지 로드 메서드
  Future<void> loadAllPageImages() async {
    for (var page in pages) {
      if (page.imageUrl != null && page.imageUrl!.isNotEmpty) {
        _imageService.getImageFile(page.imageUrl);
      }
    }
  }
  
  // 페이지 변경 메서드
  void changePage(int index) {
    if (index >= 0 && index < pages.length) {
      currentPageIndex = index;
      // 이미지 로드
      if (pages[index].imageUrl != null) {
        _loadPageImage(pages[index]);
      }
    }
  }
  
  // 현재 페이지의 이미지 로드
  Future<void> _loadPageImage(page_model.Page page) async {
    if (page.imageUrl != null && page.imageUrl!.isNotEmpty) {
      _currentImageFile = await _imageService.getImageFile(page.imageUrl);
    } else {
      _currentImageFile = null;
    }
  }
  
  // 페이지 이미지 업데이트 메서드
  void updateCurrentPageImage(File imageFile, String imageUrl) {
    _currentImageFile = imageFile;
  }
  
  // 현재 페이지 업데이트 메서드
  void updateCurrentPage(page_model.Page page) {
    final indexToUpdate = pages.indexWhere((p) => p.id == page.id);
    if (indexToUpdate != -1) {
      pages[indexToUpdate] = page;
    }
  }
  
  // 인덱스로 페이지 얻기
  page_model.Page? getPageAtIndex(int index) {
    if (index >= 0 && index < pages.length) {
      return pages[index];
    }
    return null;
  }
  
  // 페이지에 대한 이미지 파일 얻기
  File? getImageFileForPage(page_model.Page? page) {
    if (page == null || page.imageUrl == null) return null;
    
    // 같은 페이지면 현재 이미지 반환
    if (page.id == currentPage?.id && _currentImageFile != null) {
      return _currentImageFile;
    }
    
    // 비동기적으로 이미지 로드 시작 (결과는 즉시 반환하지 않음)
    _imageService.getImageFile(page.imageUrl);
    return null;
  }
}
