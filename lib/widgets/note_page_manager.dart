import 'dart:io';
import 'package:flutter/material.dart';
import '../models/page.dart' as page_model;
import '../services/page_service.dart';
import '../services/image_service.dart';
import '../services/unified_cache_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 노트 페이지 관리 클래스
/// 페이지 로드, 병합, 이미지 로드 등의 기능 제공
class NotePageManager {
  final String noteId;
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  
  List<page_model.Page> _pages = [];
  List<File?> _imageFiles = [];
  int _currentPageIndex = 0;
  
  NotePageManager({required this.noteId});
  
  // 상태 접근자
  List<page_model.Page> get pages => _pages;
  List<File?> get imageFiles => _imageFiles;
  int get currentPageIndex => _currentPageIndex;
  page_model.Page? get currentPage => 
    _currentPageIndex >= 0 && _currentPageIndex < _pages.length 
    ? _pages[_currentPageIndex] 
    : null;
  File? get currentImageFile => 
    _currentPageIndex >= 0 && _currentPageIndex < _imageFiles.length 
    ? _imageFiles[_currentPageIndex] 
    : null;
    
  // 페이지 인덱스 변경
  void changePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _currentPageIndex = index;
    
    // 이미지 로드
    _loadPageImage(_currentPageIndex);
  }
  
  // 페이지 설정
  void setPages(List<page_model.Page> pages) {
    final oldPages = List<page_model.Page>.from(_pages);
    _pages = pages;
    
    // 이미지 파일 배열 업데이트
    final oldImageFiles = List<File?>.from(_imageFiles);
    _imageFiles = _updateImageFilesForPages(_pages, oldPages, oldImageFiles);
    
    // 현재 페이지 인덱스 확인
    _currentPageIndex = _currentPageIndex >= 0 && _currentPageIndex < _pages.length
        ? _currentPageIndex
        : (_pages.isNotEmpty ? 0 : -1);
  }
  
  // 페이지 병합
  void mergePages(List<page_model.Page> serverPages) {
    final oldPages = List<page_model.Page>.from(_pages);
    _pages = _mergePagesById(oldPages, serverPages);
    
    // 이미지 파일 배열 업데이트
    final oldImageFiles = List<File?>.from(_imageFiles);
    _imageFiles = _updateImageFilesForPages(_pages, oldPages, oldImageFiles);
    
    // 현재 페이지 인덱스 확인
    _currentPageIndex = _currentPageIndex >= 0 && _currentPageIndex < _pages.length
        ? _currentPageIndex
        : (_pages.isNotEmpty ? 0 : -1);
  }
  
  // 페이지 병합 로직
  List<page_model.Page> _mergePagesById(
      List<page_model.Page> localPages, List<page_model.Page> serverPages) {
    // 페이지 ID를 기준으로 병합
    final Map<String, page_model.Page> pageMap = {};

    // 기존 페이지를 맵에 추가
    for (final page in localPages) {
      if (page.id != null) {
        pageMap[page.id!] = page;
      }
    }

    // 새 페이지로 맵 업데이트 (기존 페이지 덮어쓰기)
    for (final page in serverPages) {
      if (page.id != null) {
        pageMap[page.id!] = page;
      }
    }

    // 맵에서 페이지 목록 생성
    final mergedPages = pageMap.values.toList();

    // 페이지 번호 순으로 정렬
    mergedPages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

    debugPrint(
        '페이지 병합 결과: 로컬=${localPages.length}개, 서버=${serverPages.length}개, 병합 후=${mergedPages.length}개');

    return mergedPages;
  }

  // 이미지 파일 배열 업데이트 로직
  List<File?> _updateImageFilesForPages(List<page_model.Page> newPages,
      List<page_model.Page> oldPages, List<File?> oldImageFiles) {
    if (oldPages.isEmpty) {
      return List<File?>.filled(newPages.length, null);
    }
    
    final newImageFiles = List<File?>.filled(newPages.length, null);

    // 페이지 ID를 기준으로 이미지 파일 매핑
    for (int i = 0; i < newPages.length; i++) {
      final pageId = newPages[i].id;
      if (pageId != null) {
        // 기존 페이지 목록에서 같은 ID를 가진 페이지의 인덱스 찾기
        for (int j = 0; j < oldPages.length; j++) {
          if (j < oldPages.length &&
              oldPages[j].id == pageId &&
              j < oldImageFiles.length) {
            newImageFiles[i] = oldImageFiles[j];
            break;
          }
        }
      }
    }

    return newImageFiles;
  }
  
  // 서버에서 페이지 로드
  Future<List<page_model.Page>> loadPagesFromServer() async {
    final serverPages = await _pageService.getPagesForNote(noteId);
    mergePages(serverPages);
    return _pages;
  }
  
  // 모든 페이지 이미지 로드
  Future<void> loadAllPageImages() async {
    if (_pages.isEmpty) return;

    // 현재 페이지 이미지 우선 로드 (동기적으로 처리)
    if (_currentPageIndex >= 0 && _currentPageIndex < _pages.length) {
      await _loadPageImage(_currentPageIndex);
    }

    // 다음 페이지와 이전 페이지 이미지 미리 로드 (비동기적으로 처리)
    Future.microtask(() async {
      // 다음 페이지 로드
      if (_currentPageIndex + 1 < _pages.length) {
        await _loadPageImage(_currentPageIndex + 1);
      }

      // 이전 페이지 로드
      if (_currentPageIndex - 1 >= 0) {
        await _loadPageImage(_currentPageIndex - 1);
      }

      // 나머지 페이지 이미지는 백그라운드에서 로드
      for (int i = 0; i < _pages.length; i++) {
        if (i != _currentPageIndex &&
            i != _currentPageIndex + 1 &&
            i != _currentPageIndex - 1) {
          await _loadPageImage(i);
        }
      }
    });
  }
  
  // 단일 페이지 이미지 로드
  Future<void> _loadPageImage(int index) async {
    if (index < 0 || index >= _pages.length) return;
    if (_imageFiles.length <= index) return;

    final page = _pages[index];
    if (page.imageUrl == null || page.imageUrl!.isEmpty) return;
    if (_imageFiles[index] != null) return; // 이미 로드된 경우 스킵

    try {
      final imageFile = await _imageService.getImageFile(page.imageUrl);
      // 인덱스 범위 확인
      if (index < _imageFiles.length) {
        _imageFiles[index] = imageFile;
        debugPrint('페이지 $index 이미지 로드 완료: ${page.imageUrl}');
      }
    } catch (e) {
      debugPrint('이미지 로드 중 오류 발생: $e');
    }
  }
  
  // 페이지 캐시 업데이트
  Future<void> updatePageCache(page_model.Page page) async {
    await _cacheService.cachePage(noteId, page);
  }
  
  // 현재 페이지 업데이트
  void updateCurrentPage(page_model.Page updatedPage) {
    if (_currentPageIndex >= 0 && _currentPageIndex < _pages.length) {
      _pages[_currentPageIndex] = updatedPage;
    }
  }
} 