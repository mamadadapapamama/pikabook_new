import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 백그라운드 처리 로직을 담당하는 클래스
/// 
/// 이 클래스는 백그라운드에서 실행되는 처리 작업을 관리하고,
/// 처리 상태를 확인하는 로직을 담당합니다.

class BackgroundProcessingManager {
  final String noteId;
  final VoidCallback onProcessingCompleted;
  
  // 상태 변수
  bool _isProcessing = false;
  Timer? _backgroundCheckTimer;
  
  BackgroundProcessingManager({
    required this.noteId,
    required this.onProcessingCompleted,
  });
  
  // 백그라운드 처리 상태 가져오기
  bool get isProcessing => _isProcessing;
  
  // 처리 상태 설정
  void _setProcessing(bool value) {
    _isProcessing = value;
  }
  
  // 백그라운드 처리 상태 확인 설정
  void setupBackgroundProcessingCheck() {
    // 이미 타이머가 있으면 취소
    _backgroundCheckTimer?.cancel();
    
    // 새 타이머 생성 (5초마다 처리 상태 확인)
    _backgroundCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => checkProcessingStatus(),
    );
    
    // 즉시 한 번 상태 확인
    checkProcessingStatus();
  }
  
  // 백그라운드 처리 상태 확인
  Future<void> checkProcessingStatus() async {
    try {
      // 로컬에서 먼저 확인
      final localCompleted = await _checkLocalProcessingCompletedStatus();
      
      if (localCompleted) {
        _handleProcessingCompleted();
        return;
      }
      
      // Firestore에서 확인
      final noteDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(noteId)
          .get();
          
      if (noteDoc.exists) {
        final data = noteDoc.data();
        final bool processingCompleted = data?['processingCompleted'] as bool? ?? false;
        
        if (processingCompleted) {
          _handleProcessingCompleted();
          
          // 로컬에도 완료 상태 저장
          await _setLocalProcessingCompletedStatus(true);
        } else {
          _setProcessing(true);
        }
      }
    } catch (e) {
      debugPrint('백그라운드 처리 상태 확인 중 오류: $e');
    }
  }
  
  // 처리 완료 핸들러
  void _handleProcessingCompleted() {
    _setProcessing(false);
    onProcessingCompleted();
    
    // 타이머 중지
    _backgroundCheckTimer?.cancel();
    _backgroundCheckTimer = null;
  }
  
  // 로컬 처리 완료 상태 확인
  Future<bool> _checkLocalProcessingCompletedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'processing_completed_note_$noteId';
      return prefs.getBool(key) ?? false;
    } catch (e) {
      debugPrint('로컬 처리 완료 상태 확인 중 오류: $e');
      return false;
    }
  }
  
  // 로컬 처리 완료 상태 설정
  Future<void> _setLocalProcessingCompletedStatus(bool completed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'processing_completed_note_$noteId';
      await prefs.setBool(key, completed);
    } catch (e) {
      debugPrint('로컬 처리 완료 상태 설정 중 오류: $e');
    }
  }
  
  // 리소스 정리
  Future<void> dispose() async {
    _backgroundCheckTimer?.cancel();
    _backgroundCheckTimer = null;
  }
} 