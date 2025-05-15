import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/page.dart' as pika_page;

class PageProcessingState extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String noteId;
  final Function(int, pika_page.Page) onPageProcessed;
  
  // 페이지 상태 저장 맵
  final Map<String, bool> processedPageStatus = {};
  
  // Firestore 페이지 문서 변경 이벤트 구독
  List<StreamSubscription<DocumentSnapshot>?> _pageListeners = [];
  
  // 문서 전체 리스너
  StreamSubscription? _pagesSubscription;
  
  PageProcessingState({
    required this.noteId,
    required this.onPageProcessed,
  });
  
  void startMonitoring(List<pika_page.Page> pages) {
    // 기존 리스너 정리
    stopMonitoring();
    
    if (kDebugMode) {
      debugPrint('📱 페이지 처리 상태 리스너 설정: ${pages.length}개 페이지');
    }
    
    // 초기 상태 설정
    for (var page in pages) {
      if (page.id != null) {
        processedPageStatus[page.id!] = page.originalText != '___PROCESSING___' && 
                                        page.originalText.isNotEmpty;
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
        
        final updatedPage = pika_page.Page.fromFirestore(snapshot);
        final pageIndex = pages.indexWhere((p) => p.id == page.id);
        if (pageIndex < 0) return;
        
        // 텍스트가 처리되었는지 확인
        final wasProcessing = processedPageStatus[page.id!] == false;
        final isNowProcessed = updatedPage.originalText != '___PROCESSING___' && 
                              updatedPage.originalText.isNotEmpty;
        
        // 처리 상태가 변경된 경우에만 업데이트
        if (wasProcessing && isNowProcessed) {
          if (kDebugMode) {
            debugPrint('✅ 페이지 처리 완료 감지됨: ${page.id}');
          }
          
          processedPageStatus[page.id!] = true;
          
          // 콜백 호출 (처리 완료 알림)
          onPageProcessed(pageIndex, updatedPage);
          
          // 상태 변경 알림
          notifyListeners();
        }
      });
      
      _pageListeners.add(listener);
    }
    
    // 노트에 새 페이지가 추가될 경우를 위한 컬렉션 리스너
    _pagesSubscription = _firestore
        .collection('pages')
        .where('noteId', isEqualTo: noteId)
        .snapshots()
        .listen((snapshot) {
          // 새 페이지 추가 감지 로직은 필요 시 구현
        });
  }
  
  // 페이지 처리 상태 확인
  List<bool> getProcessedPagesStatus(List<pika_page.Page> pages) {
    if (pages.isEmpty) return [];
    
    List<bool> processedStatus = List.filled(pages.length, false);
    
    // 각 페이지의 처리 상태 설정
    for (int i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (page.id != null && processedPageStatus.containsKey(page.id!)) {
        processedStatus[i] = processedPageStatus[page.id!] ?? false;
      } else {
        // 상태 정보가 없는 경우, 원본 텍스트로 판단
        processedStatus[i] = page.originalText != '___PROCESSING___' && 
                             page.originalText.isNotEmpty;
      }
    }
    
    if (kDebugMode) {
      final processed = processedStatus.where((status) => status).length;
      final total = processedStatus.length;
      debugPrint("📊 페이지 처리 상태: $processed/$total 페이지 처리됨");
    }
    
    return processedStatus;
  }
  
  void stopMonitoring() {
    for (var listener in _pageListeners) {
      listener?.cancel();
    }
    _pageListeners.clear();
    
    _pagesSubscription?.cancel();
    _pagesSubscription = null;
  }
  
  void updatePageStatus(String pageId, bool isProcessed) {
    processedPageStatus[pageId] = isProcessed;
    notifyListeners();
  }
  
  bool isPageProcessed(String pageId) {
    return processedPageStatus[pageId] ?? false;
  }
  
  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
} 