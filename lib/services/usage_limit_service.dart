import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class UsageLimitService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 무료 사용자의 최대 번역 글자 수
  static const int MAX_FREE_TRANSLATION_CHARS = 1000;
  
  // 무료 사용자의 최대 노트 개수
  static const int MAX_FREE_NOTES = 3;
  
  // 현재 사용자의 사용량 정보 가져오기
  Future<Map<String, dynamic>> getUserUsage() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    final docSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('usage')
        .doc('stats')
        .get();
    
    if (!docSnapshot.exists) {
      // 사용량 정보가 없으면 초기값 생성
      await _initializeUserUsage(user.uid);
      return {
        'translatedChars': 0,
        'noteCount': 0,
        'isPremium': false,
      };
    }
    
    return docSnapshot.data() ?? {
      'translatedChars': 0,
      'noteCount': 0,
      'isPremium': false,
    };
  }
  
  // 사용자 사용량 초기화
  Future<void> _initializeUserUsage(String userId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('usage')
        .doc('stats')
        .set({
      'translatedChars': 0,
      'noteCount': 0,
      'isPremium': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
  
  // 번역 글자 수 추가
  Future<bool> addTranslatedChars(int chars) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    // 현재 사용량 확인
    final usage = await getUserUsage();
    final bool isPremium = usage['isPremium'] ?? false;
    
    // 프리미엄 사용자는 제한 없음
    if (isPremium) {
      await _updateTranslatedChars(user.uid, chars);
      return true;
    }
    
    // 무료 사용자는 제한 확인
    final int currentChars = usage['translatedChars'] ?? 0;
    if (currentChars + chars > MAX_FREE_TRANSLATION_CHARS) {
      return false; // 제한 초과
    }
    
    // 사용량 업데이트
    await _updateTranslatedChars(user.uid, chars);
    return true;
  }
  
  // 번역 글자 수 업데이트
  Future<void> _updateTranslatedChars(String userId, int chars) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('usage')
        .doc('stats')
        .set({
      'translatedChars': FieldValue.increment(chars),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  
  // 노트 추가 가능 여부 확인
  Future<bool> canAddNote() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    // 현재 사용량 확인
    final usage = await getUserUsage();
    final bool isPremium = usage['isPremium'] ?? false;
    
    // 프리미엄 사용자는 제한 없음
    if (isPremium) {
      return true;
    }
    
    // 무료 사용자는 제한 확인
    final int noteCount = usage['noteCount'] ?? 0;
    return noteCount < MAX_FREE_NOTES;
  }
  
  // 노트 개수 증가
  Future<void> incrementNoteCount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('usage')
        .doc('stats')
        .set({
      'noteCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  
  // 노트 개수 감소
  Future<void> decrementNoteCount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    final usage = await getUserUsage();
    final int noteCount = usage['noteCount'] ?? 0;
    
    if (noteCount > 0) {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('usage')
          .doc('stats')
          .set({
        'noteCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
  
  // 프리미엄 상태 설정
  Future<void> setPremiumStatus(bool isPremium) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('usage')
        .doc('stats')
        .set({
      'isPremium': isPremium,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  
  // 무료 사용량 제한에 도달했는지 확인
  Future<Map<String, bool>> checkFreeLimits() async {
    final usage = await getUserUsage();
    final bool isPremium = usage['isPremium'] ?? false;
    
    // 프리미엄 사용자는 제한 없음
    if (isPremium) {
      return {
        'translationLimitReached': false,
        'noteLimitReached': false,
      };
    }
    
    final int translatedChars = usage['translatedChars'] ?? 0;
    final int noteCount = usage['noteCount'] ?? 0;
    
    return {
      'translationLimitReached': translatedChars >= MAX_FREE_TRANSLATION_CHARS,
      'noteLimitReached': noteCount >= MAX_FREE_NOTES,
    };
  }
} 