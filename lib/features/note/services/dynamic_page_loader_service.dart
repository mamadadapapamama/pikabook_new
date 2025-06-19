import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/page.dart' as page_model;

/// 새로운 페이지가 Firestore에 추가되거나 상태가 변경될 때 콜백으로 알려주는 서비스
class DynamicPageLoaderService {
  final String noteId;
  final void Function(page_model.Page page) onNewOrUpdatedPage;
  final Map<String, StreamSubscription<DocumentSnapshot>> _listeners = {};
  StreamSubscription<QuerySnapshot>? _pagesQueryListener;
  bool _disposed = false;

  DynamicPageLoaderService({
    required this.noteId,
    required this.onNewOrUpdatedPage,
  });

  /// 시작: noteId에 해당하는 모든 페이지 문서에 리스너를 붙임
  Future<void> start() async {
    // 전체 페이지 목록을 실시간으로 감지
    _pagesQueryListener = FirebaseFirestore.instance
        .collection('pages')
        .where('noteId', isEqualTo: noteId)
        .snapshots()
        .listen((querySnapshot) {
      if (_disposed) return;
      for (final doc in querySnapshot.docs) {
        _setupPageListener(doc.id);
      }
    });
  }

  void _setupPageListener(String pageId) {
    if (_listeners.containsKey(pageId)) return; // 이미 리스너가 있으면 중복 방지
    _listeners[pageId] = FirebaseFirestore.instance
        .collection('pages')
        .doc(pageId)
        .snapshots()
        .listen((snapshot) {
      if (_disposed || !snapshot.exists) return;
      final page = page_model.Page.fromFirestore(snapshot);
      onNewOrUpdatedPage(page);
    });
  }

  void dispose() {
    _disposed = true;
    for (final l in _listeners.values) {
      l.cancel();
    }
    _listeners.clear();
    _pagesQueryListener?.cancel();
  }
} 