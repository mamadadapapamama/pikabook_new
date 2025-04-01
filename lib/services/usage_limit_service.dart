import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// 사용량 제한 및 추적 서비스
/// 무료 사용자와 프리미엄 사용자의 사용량을 추적하고 제한 여부를 확인합니다.
class UsageLimitService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 월별 무료 사용 제한
  static const int MAX_FREE_TRANSLATION_CHARS = 5000;   // 번역 최대 글자 수
  static const int MAX_FREE_NOTES = 10;                 // 노트 최대 개수
  static const int MAX_FREE_OCR_REQUESTS = 10;          // OCR 요청 최대 횟수
  static const int MAX_FREE_DICTIONARY_LOOKUPS = 50;    // 외부 사전 조회 최대 횟수
  static const int MAX_FREE_FLASHCARDS = 30;            // 플래시카드 최대 개수
  
  // 현재 월 정보 가져오기
  String _getCurrentMonth() {
    final now = DateTime.now();
    return DateFormat('yyyy-MM').format(now);
  }
  
  // 현재 사용자의 사용량 정보 가져오기
  Future<Map<String, dynamic>> getUserUsage() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    final currentMonth = _getCurrentMonth();
    final docSnapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('usage')
        .doc(currentMonth)
        .get();
    
    if (!docSnapshot.exists) {
      // 사용량 정보가 없으면 초기값 생성
      await _initializeUserUsage(user.uid, currentMonth);
      return {
        'translatedChars': 0,
        'noteCount': 0,
        'ocrRequests': 0,
        'dictionaryLookups': 0,
        'flashcardCount': 0,
        'isPremium': false,
        'lastPaymentDate': null,
        'subscriptionTier': 'free',
      };
    }
    
    return docSnapshot.data() ?? {
      'translatedChars': 0,
      'noteCount': 0,
      'ocrRequests': 0,
      'dictionaryLookups': 0,
      'flashcardCount': 0,
      'isPremium': false,
      'lastPaymentDate': null,
      'subscriptionTier': 'free',
    };
  }
  
  // 사용자 사용량 초기화
  Future<void> _initializeUserUsage(String userId, String month) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('usage')
        .doc(month)
        .set({
      'translatedChars': 0,
      'noteCount': 0,
      'ocrRequests': 0,
      'dictionaryLookups': 0,
      'flashcardCount': 0,
      'isPremium': false,
      'lastPaymentDate': null,
      'subscriptionTier': 'free',
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
      await _updateUsageField(user.uid, 'translatedChars', chars);
      return true;
    }
    
    // 무료 사용자는 제한 확인
    final int currentChars = usage['translatedChars'] ?? 0;
    if (currentChars + chars > MAX_FREE_TRANSLATION_CHARS) {
      return false; // 제한 초과
    }
    
    // 사용량 업데이트
    await _updateUsageField(user.uid, 'translatedChars', chars);
    return true;
  }
  
  // OCR 요청 횟수 추가
  Future<bool> addOcrRequest() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    // 현재 사용량 확인
    final usage = await getUserUsage();
    final bool isPremium = usage['isPremium'] ?? false;
    
    // 프리미엄 사용자는 제한 없음
    if (isPremium) {
      await _updateUsageField(user.uid, 'ocrRequests', 1);
      return true;
    }
    
    // 무료 사용자는 제한 확인
    final int currentRequests = usage['ocrRequests'] ?? 0;
    if (currentRequests >= MAX_FREE_OCR_REQUESTS) {
      return false; // 제한 초과
    }
    
    // 사용량 업데이트
    await _updateUsageField(user.uid, 'ocrRequests', 1);
    return true;
  }
  
  // 사전 조회 횟수 추가
  Future<bool> addDictionaryLookup() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    // 현재 사용량 확인
    final usage = await getUserUsage();
    final bool isPremium = usage['isPremium'] ?? false;
    
    // 프리미엄 사용자는 제한 없음
    if (isPremium) {
      await _updateUsageField(user.uid, 'dictionaryLookups', 1);
      return true;
    }
    
    // 무료 사용자는 제한 확인
    final int currentLookups = usage['dictionaryLookups'] ?? 0;
    if (currentLookups >= MAX_FREE_DICTIONARY_LOOKUPS) {
      return false; // 제한 초과
    }
    
    // 사용량 업데이트
    await _updateUsageField(user.uid, 'dictionaryLookups', 1);
    return true;
  }
  
  // 사전 조회 횟수 추가 (다른 이름 - 호환성 유지)
  Future<bool> incrementDictionaryLookupCount() async {
    return addDictionaryLookup();
  }
  
  // 플래시카드 추가 가능 여부 확인
  Future<bool> canAddFlashcard() async {
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
    final int flashcardCount = usage['flashcardCount'] ?? 0;
    return flashcardCount < MAX_FREE_FLASHCARDS;
  }
  
  // 플래시카드 개수 증가
  Future<bool> incrementFlashcardCount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    // 현재 사용량 확인
    final usage = await getUserUsage();
    final bool isPremium = usage['isPremium'] ?? false;
    
    // 프리미엄 사용자는 제한 없음
    if (isPremium) {
      await _updateUsageField(user.uid, 'flashcardCount', 1);
      return true;
    }
    
    // 무료 사용자는 제한 확인
    final int currentCount = usage['flashcardCount'] ?? 0;
    if (currentCount >= MAX_FREE_FLASHCARDS) {
      return false; // 제한 초과
    }
    
    // 사용량 업데이트
    await _updateUsageField(user.uid, 'flashcardCount', 1);
    return true;
  }
  
  // 사용량 필드 업데이트 공통 함수
  Future<void> _updateUsageField(String userId, String field, int increment) async {
    final currentMonth = _getCurrentMonth();
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('usage')
        .doc(currentMonth)
        .set({
      field: FieldValue.increment(increment),
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
  Future<bool> incrementNoteCount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    // 현재 사용량 확인
    final usage = await getUserUsage();
    final bool isPremium = usage['isPremium'] ?? false;
    
    // 프리미엄 사용자는 제한 없음
    if (isPremium) {
      await _updateUsageField(user.uid, 'noteCount', 1);
      return true;
    }
    
    // 무료 사용자는 제한 확인
    final int currentCount = usage['noteCount'] ?? 0;
    if (currentCount >= MAX_FREE_NOTES) {
      return false; // 제한 초과
    }
    
    // 사용량 업데이트
    await _updateUsageField(user.uid, 'noteCount', 1);
    return true;
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
      await _updateUsageField(user.uid, 'noteCount', -1);
    }
  }
  
  // 플래시카드 개수 감소
  Future<void> decrementFlashcardCount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    final usage = await getUserUsage();
    final int flashcardCount = usage['flashcardCount'] ?? 0;
    
    if (flashcardCount > 0) {
      await _updateUsageField(user.uid, 'flashcardCount', -1);
    }
  }
  
  // 프리미엄 상태 설정
  Future<void> setPremiumStatus(bool isPremium, {String tier = 'standard'}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }
    
    final currentMonth = _getCurrentMonth();
    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('usage')
        .doc(currentMonth)
        .set({
      'isPremium': isPremium,
      'subscriptionTier': isPremium ? tier : 'free',
      'lastPaymentDate': isPremium ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // 사용자 문서에도 프리미엄 상태 업데이트
    await _firestore
        .collection('users')
        .doc(user.uid)
        .set({
      'isPremium': isPremium,
      'subscriptionTier': isPremium ? tier : 'free',
      'lastPaymentDate': isPremium ? FieldValue.serverTimestamp() : null,
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
        'ocrLimitReached': false,
        'dictionaryLimitReached': false,
        'flashcardLimitReached': false,
        'anyLimitReached': false,
      };
    }
    
    final int translatedChars = usage['translatedChars'] ?? 0;
    final int noteCount = usage['noteCount'] ?? 0;
    final int ocrRequests = usage['ocrRequests'] ?? 0;
    final int dictionaryLookups = usage['dictionaryLookups'] ?? 0;
    final int flashcardCount = usage['flashcardCount'] ?? 0;
    
    final bool translationLimitReached = translatedChars >= MAX_FREE_TRANSLATION_CHARS;
    final bool noteLimitReached = noteCount >= MAX_FREE_NOTES;
    final bool ocrLimitReached = ocrRequests >= MAX_FREE_OCR_REQUESTS;
    final bool dictionaryLimitReached = dictionaryLookups >= MAX_FREE_DICTIONARY_LOOKUPS;
    final bool flashcardLimitReached = flashcardCount >= MAX_FREE_FLASHCARDS;
    
    final bool anyLimitReached = translationLimitReached || 
                               noteLimitReached || 
                               ocrLimitReached || 
                               dictionaryLimitReached || 
                               flashcardLimitReached;
    
    return {
      'translationLimitReached': translationLimitReached,
      'noteLimitReached': noteLimitReached,
      'ocrLimitReached': ocrLimitReached,
      'dictionaryLimitReached': dictionaryLimitReached,
      'flashcardLimitReached': flashcardLimitReached,
      'anyLimitReached': anyLimitReached,
    };
  }
  
  // 사용량 퍼센트 (0.0-1.0) 확인
  Future<Map<String, double>> getUsagePercentages() async {
    final usage = await getUserUsage();
    final bool isPremium = usage['isPremium'] ?? false;
    
    // 프리미엄 사용자는 항상 0% 사용 (무제한)
    if (isPremium) {
      return {
        'translationPercent': 0.0,
        'notePercent': 0.0,
        'ocrPercent': 0.0,
        'dictionaryPercent': 0.0,
        'flashcardPercent': 0.0,
        'overallPercent': 0.0,
      };
    }
    
    final int translatedChars = usage['translatedChars'] ?? 0;
    final int noteCount = usage['noteCount'] ?? 0;
    final int ocrRequests = usage['ocrRequests'] ?? 0;
    final int dictionaryLookups = usage['dictionaryLookups'] ?? 0;
    final int flashcardCount = usage['flashcardCount'] ?? 0;
    
    final double translationPercent = translatedChars / MAX_FREE_TRANSLATION_CHARS;
    final double notePercent = noteCount / MAX_FREE_NOTES;
    final double ocrPercent = ocrRequests / MAX_FREE_OCR_REQUESTS;
    final double dictionaryPercent = dictionaryLookups / MAX_FREE_DICTIONARY_LOOKUPS;
    final double flashcardPercent = flashcardCount / MAX_FREE_FLASHCARDS;
    
    // 전체 사용량은 가장 높은 사용량으로 계산
    final double overallPercent = [
      translationPercent,
      notePercent,
      ocrPercent,
      dictionaryPercent,
      flashcardPercent,
    ].reduce((curr, next) => curr > next ? curr : next);
    
    return {
      'translationPercent': translationPercent,
      'notePercent': notePercent,
      'ocrPercent': ocrPercent,
      'dictionaryPercent': dictionaryPercent,
      'flashcardPercent': flashcardPercent,
      'overallPercent': overallPercent,
    };
  }
} 