import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/page.dart' as page_model;

/// 페이지 처리 상태 모니터링 클래스
class PageMonitor {
  // Firebase 인스턴스
  final FirebaseFirestore _firestore;
  
  // 페이지 처리 상태
  final Map<String, bool> _processedPageStatus = {};
  
  // Firestore 리스너
  List<StreamSubscription<DocumentSnapshot>?> _pageListeners = [];
  StreamSubscription? _pagesSubscription;
  
  // 페이지 처리 완료 콜백
  Function(int, page_model.Page)? _onPageProcessed;
  
  PageMonitor({
    FirebaseFirestore? firestore,
    Function(int, page_model.Page)? onPageProcessed,
  }) : 
    _firestore = firestore ?? FirebaseFirestore.instance,
    _onPageProcessed = onPageProcessed;
  
  /// 콜백 설정
  void setPageProcessedCallback(Function(int, page_model.Page) callback) {
    _onPageProcessed = callback;
  }
  
  /// 페이지 처리 상태 모니터링 시작
  void startMonitoring(List<page_model.Page> pages) {
    // 기존 리스너 정리
    cancelMonitoring();
    
    if (kDebugMode) {
      print('📱 페이지 처리 상태 리스너 설정: ${pages.length}개 페이지');
    }
    
    // 초기 상태 설정
    for (var page in pages) {
      if (page.id != null) {
        _processedPageStatus[page.id!] = true; // 기본적으로 모든 페이지는 처리됨으로 간주
      }
    }
    
    // 각 페이지에 대한 리스너 설정
    for (var page in pages) {
      if (page.id == null) continue;
      
      // 페이지 문서 변경 감지 리스너
      final listener = _firestore
          .collection('pages')
          .doc(page.id)
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.exists) return;
        
        final updatedPage = page_model.Page.fromFirestore(snapshot);
        final pageIndex = pages.indexWhere((p) => p.id == page.id);
        if (pageIndex < 0) return;
        
        // 텍스트가 처리되었는지 확인
        final wasProcessing = _processedPageStatus[page.id!] == false;
        final isNowProcessed = true; // 모든 페이지는 처리된 것으로 간주
        
        // 처리 상태가 변경된 경우에만 업데이트
        if (wasProcessing && isNowProcessed) {
          if (kDebugMode) {
            print('✅ 페이지 처리 완료 감지됨: ${page.id}');
          }
          
          _processedPageStatus[page.id!] = true;
          
          // 콜백 호출 (처리 완료 알림)
          if (_onPageProcessed != null) {
            _onPageProcessed!(pageIndex, updatedPage);
          }
        }
      });
      
      _pageListeners.add(listener);
    }
  }
  
  /// 페이지 처리 상태 모니터링 중지
  void cancelMonitoring() {
    for (var listener in _pageListeners) {
      listener?.cancel();
    }
    _pageListeners.clear();
    
    _pagesSubscription?.cancel();
    _pagesSubscription = null;
  }
  
  /// 페이지 처리 상태 확인
  List<bool> getProcessedPagesStatus(List<page_model.Page>? pages) {
    if (pages == null || pages.isEmpty) {
      return [];
    }
    
    List<bool> processedStatus = List.filled(pages.length, false);
    
    // 각 페이지의 처리 상태 설정
    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (page.id != null && _processedPageStatus.containsKey(page.id!)) {
        processedStatus[i] = _processedPageStatus[page.id!] ?? false;
      } else {
        // 상태 정보가 없는 경우, 처리된 것으로 간주
        processedStatus[i] = true;
      }
    }
    
    return processedStatus;
  }
  
  /// 페이지가 처리 중인지 확인
  bool isPageProcessing(page_model.Page page) {
    if (page.id == null) return false;
    return !(_processedPageStatus[page.id!] ?? true);
  }
  
  /// 리소스 정리
  void dispose() {
    cancelMonitoring();
    _processedPageStatus.clear();
  }
} 