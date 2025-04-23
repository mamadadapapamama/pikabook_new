import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/content/note_service.dart';
import '../../services/storage/unified_cache_service.dart';

/// 즐겨찾기 관리 서비스
class FavoritesService {
  // 싱글톤 패턴
  static final FavoritesService _instance = FavoritesService._internal();
  factory FavoritesService() => _instance;

  // Firebase 인스턴스
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();

  FavoritesService._internal();
  
  /// 즐겨찾기 상태 토글
  Future<bool> toggleFavorite(String noteId, bool isFavorite) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }
      
      // 노트 문서 업데이트
      await _firestore.collection('notes').doc(noteId).update({
        'isFavorite': isFavorite,
      });
      
      // 관련 캐시 갱신
      await _cacheService.removeCachedNote(noteId);
      
      return isFavorite;
    } catch (e) {
      debugPrint('즐겨찾기 상태 토글 중 오류: $e');
      throw Exception('즐겨찾기 상태를 변경할 수 없습니다.');
    }
  }
  
  /// 즐겨찾기 여부 확인
  Future<bool> isFavorite(String noteId) async {
    try {
      final noteDoc = await _firestore.collection('notes').doc(noteId).get();
      
      if (!noteDoc.exists) {
        return false;
      }
      
      final data = noteDoc.data();
      return data?['isFavorite'] as bool? ?? false;
    } catch (e) {
      debugPrint('즐겨찾기 상태 확인 중 오류: $e');
      return false;
    }
  }
  
  /// 즐겨찾기 목록 가져오기
  Future<List<Map<String, dynamic>>> getFavorites() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }
      
      final querySnapshot = await _firestore
          .collection('notes')
          .where('userId', isEqualTo: user.uid)
          .where('isFavorite', isEqualTo: true)
          .orderBy('updatedAt', descending: true)
          .get();
      
      final favorites = querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // ID 추가
        return data;
      }).toList();
      
      return favorites;
    } catch (e) {
      debugPrint('즐겨찾기 목록 조회 중 오류: $e');
      return [];
    }
  }
} 