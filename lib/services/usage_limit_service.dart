import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// 사용량 제한 관리 서비스
/// 베타 기간 동안 사용자의 사용량을 추적하고 제한을 적용합니다.
class UsageLimitService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 베타 기간 정보
  static const String BETA_END_DATE_STR = '2025-04-30'; // 베타 기간 종료일 (연도-월-일)
  static const int BETA_PERIOD_DAYS = 30; // 베타 기간 (30일)
  
  // 베타 기간 동안의 무료 사용 제한
  static const int MAX_FREE_TRANSLATION_CHARS = 100000;  // 번역 최대 글자 수
  static const int MAX_FREE_PAGES = 50;                 // OCR 페이지 최대 개수
  static const int MAX_FREE_OCR_REQUESTS = 50;          // OCR 요청 최대 수
  static const int MAX_FREE_DICTIONARY_LOOKUPS = 200;   // 사전 검색 최대 수
  static const int MAX_FREE_TTS_REQUESTS = 50000;       // TTS 요청 최대 수
  static const int MAX_FREE_STORAGE_BYTES = 100 * 1024 * 1024; // 100MB 스토리지
  static const int MAX_FREE_FLASHCARDS = 300;           // 플래시카드 최대 수
  static const int MAX_FREE_NOTES = 50;                 // 노트 최대 수
  
  // 월별 기본 무료 사용 제한 (베타 이후)
  static const int BASIC_FREE_TRANSLATION_CHARS = 500;   // 번역 최대 글자 수
  static const int BASIC_FREE_PAGES = 5;                 // OCR 페이지 최대 개수
  static const int BASIC_FREE_OCR_REQUESTS = 5;          // OCR 요청 최대 횟수
  static const int BASIC_FREE_DICTIONARY_LOOKUPS = 50;   // 외부 사전 조회 최대 횟수
  static const int BASIC_FREE_TTS_REQUESTS = 100;        // TTS 요청 최대 글자 수
  static const int BASIC_FREE_STORAGE_MB = 20;           // 저장 공간 최대 크기 (MB)
  
  // 싱글톤 패턴 구현
  static final UsageLimitService _instance = UsageLimitService._internal();
  factory UsageLimitService() => _instance;
  
  UsageLimitService._internal();
  
  // SharedPreferences 키
  static const String _kOcrCountKey = 'ocr_count';
  static const String _kTranslationCharCountKey = 'translation_char_count';
  static const String _kTtsCharCountKey = 'tts_char_count';
  static const String _kDictionaryCountKey = 'dictionary_count';
  static const String _kStorageUsageKey = 'storage_usage';
  static const String _kResetDateKey = 'usage_reset_date';
  static const String _kMonthlyLimitsKey = 'monthly_limits';
  static const String _kBetaPeriodEndKey = 'beta_period_end';
  
  // 사용량 데이터 키
  static const String _USAGE_KEY = 'user_usage_data';
  
  // 현재 사용자 ID 가져오기
  String? get _currentUserId => _auth.currentUser?.uid;
  
  /// 베타 기간 종료 날짜 가져오기
  Future<DateTime> getBetaPeriodEndDate() async {
    final prefs = await SharedPreferences.getInstance();
    final endDateStr = prefs.getString(_kBetaPeriodEndKey) ?? BETA_END_DATE_STR;
    
    try {
      return DateFormat('yyyy-MM-dd').parse(endDateStr);
    } catch (e) {
      debugPrint('베타 기간 종료일 파싱 오류: $e');
      // 기본값: 문자열 상수에서 파싱
      return DateFormat('yyyy-MM-dd').parse(BETA_END_DATE_STR);
    }
  }
  
  /// 베타 기간 남은 일수 계산
  Future<int> getRemainingBetaDays() async {
    final endDate = await getBetaPeriodEndDate();
    final today = DateTime.now();
    
    final difference = endDate.difference(today).inDays;
    return difference > 0 ? difference : 0;
  }
  
  /// 베타 기간 종료 여부 확인
  Future<bool> isBetaPeriodEnded() async {
    final endDate = await getBetaPeriodEndDate();
    final today = DateTime.now();
    
    return today.isAfter(endDate);
  }
  
  /// 사용자별 키 생성
  String _getUserKey(String baseKey) {
    final userId = _currentUserId;
    return userId != null ? '${userId}_$baseKey' : baseKey;
  }
  
  /// OCR 사용량 증가
  Future<bool> incrementOcrCount() async {
    return await _incrementUsage('ocrRequests', 1, MAX_FREE_OCR_REQUESTS);
  }
  
  /// 번역 문자 사용량 증가
  Future<bool> incrementTranslationCharCount(int charCount) async {
    return await _incrementUsage('translatedChars', charCount, MAX_FREE_TRANSLATION_CHARS);
  }
  
  /// TTS 문자 사용량 증가
  Future<bool> incrementTtsCharCount(int charCount) async {
    return await _incrementUsage('ttsRequests', charCount, MAX_FREE_TTS_REQUESTS);
  }
  
  /// 사전 조회 사용량 증가
  Future<bool> incrementDictionaryCount() async {
    return await _incrementUsage('dictionaryLookups', 1, MAX_FREE_DICTIONARY_LOOKUPS);
  }
  
  /// 범용 사용량 증가 메서드
  Future<bool> _incrementUsage(String key, int amount, int limit) async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData[key] ?? 0;
    
    // 사용량 제한 확인
    if (currentUsage >= limit) {
      return false;
    }
    
    // 사용량 증가
    usageData[key] = currentUsage + amount;
    await _saveUsageData(usageData);
    
    debugPrint('$key 사용량 증가: ${currentUsage + amount}/$limit');
    return (currentUsage + amount) <= limit;
  }
  
  /// 저장 공간 사용량 증가
  Future<bool> addStorageUsage(int bytes) async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['storageUsageBytes'] ?? 0;
    
    // 사용량 제한 확인
    if (currentUsage >= MAX_FREE_STORAGE_BYTES) {
      return false;
    }
    
    // 사용량 증가
    usageData['storageUsageBytes'] = currentUsage + bytes;
    await _saveUsageData(usageData);
    
    final usageInMB = ((currentUsage + bytes) / (1024 * 1024)).toStringAsFixed(2);
    final limitInMB = (MAX_FREE_STORAGE_BYTES / (1024 * 1024)).toStringAsFixed(0);
    debugPrint('저장 공간 사용량 증가: ${usageInMB}MB/${limitInMB}MB');
    
    return (currentUsage + bytes) <= MAX_FREE_STORAGE_BYTES;
  }
  
  /// 저장 공간 사용량 감소
  Future<void> reduceStorageUsage(int bytes) async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['storageUsageBytes'] ?? 0;
    
    final newUsage = (currentUsage - bytes).clamp(0, double.maxFinite.toInt());
    usageData['storageUsageBytes'] = newUsage;
    await _saveUsageData(usageData);
    
    final usageInMB = (newUsage / (1024 * 1024)).toStringAsFixed(2);
    final limitInMB = (MAX_FREE_STORAGE_BYTES / (1024 * 1024)).toStringAsFixed(0);
    debugPrint('저장 공간 사용량 감소: ${usageInMB}MB/${limitInMB}MB');
  }
  
  /// 베타 기간 사용량 및 제한 확인
  Future<Map<String, dynamic>> getBetaUsageLimits() async {
    final usageData = await _loadUsageData();
    
    // 베타 시작 날짜 확인
    DateTime? betaStartDate;
    if (usageData['betaStartDate'] != null) {
      betaStartDate = DateTime.parse(usageData['betaStartDate']);
    } else {
      // 처음 사용할 때 베타 시작 날짜 설정
      betaStartDate = DateTime.now();
      usageData['betaStartDate'] = betaStartDate.toIso8601String();
      await _saveUsageData(usageData);
    }
    
    // 베타 종료일 계산
    final betaEndDate = betaStartDate.add(Duration(days: BETA_PERIOD_DAYS));
    final now = DateTime.now();
    
    // 베타 기간 남은 일수 계산
    final remainingDays = betaEndDate.difference(now).inDays;
    
    // 베타 기간이 종료되었는지 확인
    final bool betaEnded = now.isAfter(betaEndDate);
    
    // 현재 사용량
    final ocrUsage = usageData['ocrRequests'] ?? 0;
    final ttsUsage = usageData['ttsRequests'] ?? 0;
    final translatedChars = usageData['translatedChars'] ?? 0;
    final storageUsageBytes = usageData['storageUsageBytes'] ?? 0;
    final dictionaryLookups = usageData['dictionaryLookups'] ?? 0;
    final pages = usageData['pages'] ?? 0;
    final flashcards = usageData['flashcards'] ?? 0;
    final notes = usageData['notes'] ?? 0;
    
    // 각 제한 초과 여부 확인
    final bool ocrLimitReached = ocrUsage >= MAX_FREE_OCR_REQUESTS;
    final bool ttsLimitReached = ttsUsage >= MAX_FREE_TTS_REQUESTS;
    final bool translationLimitReached = translatedChars >= MAX_FREE_TRANSLATION_CHARS;
    final bool storageLimitReached = storageUsageBytes >= MAX_FREE_STORAGE_BYTES;
    final bool dictionaryLimitReached = dictionaryLookups >= MAX_FREE_DICTIONARY_LOOKUPS;
    final bool pageLimitReached = pages >= MAX_FREE_PAGES;
    final bool flashcardLimitReached = flashcards >= MAX_FREE_FLASHCARDS;
    final bool noteLimitReached = notes >= MAX_FREE_NOTES;
    
    // 어느 하나라도 제한에 도달했는지 확인
    final bool anyLimitReached = 
        ocrLimitReached ||
        ttsLimitReached ||
        translationLimitReached ||
        storageLimitReached ||
        dictionaryLimitReached ||
        pageLimitReached ||
        flashcardLimitReached ||
        noteLimitReached ||
        betaEnded;
    
    return {
      'betaStartDate': betaStartDate.toIso8601String(),
      'betaEndDate': betaEndDate.toIso8601String(),
      'remainingDays': remainingDays,
      'betaEnded': betaEnded,
      'ocrLimitReached': ocrLimitReached,
      'ttsLimitReached': ttsLimitReached,
      'translationLimitReached': translationLimitReached,
      'storageLimitReached': storageLimitReached,
      'dictionaryLimitReached': dictionaryLimitReached,
      'pageLimitReached': pageLimitReached,
      'flashcardLimitReached': flashcardLimitReached,
      'noteLimitReached': noteLimitReached,
      'anyLimitReached': anyLimitReached,
    };
  }
  
  /// 모든 사용량 초기화 (테스트용)
  Future<void> resetAllUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _currentUserId;
    
    if (userId != null) {
      // 사용량 데이터 초기화
      await _saveUsageData({
        'betaStartDate': DateTime.now().toIso8601String(),
        'ocrRequests': 0,
        'ttsRequests': 0,
        'translatedChars': 0,
        'storageUsageBytes': 0,
        'dictionaryLookups': 0,
        'pages': 0,
        'flashcards': 0,
        'notes': 0,
      });
    }
    
    debugPrint('모든 사용량 초기화 완료');
  }
  
  /// 월간 사용량 제한 설정 (프리미엄 사용자용)
  Future<void> setMonthlyLimits({
    int? ocrLimit,
    int? translationCharLimit,
    int? ttsCharLimit,
    int? dictionaryLimit,
    int? storageLimit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getUserKey(_kMonthlyLimitsKey);
    
    // 기존 설정 불러오기
    final Map<String, dynamic> currentLimits = 
        json.decode(prefs.getString(key) ?? '{}') as Map<String, dynamic>;
    
    // 새 설정 업데이트
    if (ocrLimit != null) currentLimits['ocrLimit'] = ocrLimit;
    if (translationCharLimit != null) currentLimits['translationCharLimit'] = translationCharLimit;
    if (ttsCharLimit != null) currentLimits['ttsCharLimit'] = ttsCharLimit;
    if (dictionaryLimit != null) currentLimits['dictionaryLimit'] = dictionaryLimit;
    if (storageLimit != null) currentLimits['storageLimit'] = storageLimit;
    
    // 설정 저장
    await prefs.setString(key, json.encode(currentLimits));
    
    debugPrint('월간 사용량 제한 설정 완료: $currentLimits');
  }
  
  /// 월간 사용량 초기화 (매월 1일에 호출)
  Future<void> resetMonthlyUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final resetDateKey = _getUserKey(_kResetDateKey);
    
    // 마지막 초기화 날짜 확인
    final lastResetDateStr = prefs.getString(resetDateKey);
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    
    // 마지막 초기화 날짜가 없거나 이번 달 1일보다 이전이면 초기화
    if (lastResetDateStr == null) {
      await _doResetMonthlyUsage(prefs);
      await prefs.setString(resetDateKey, currentMonthStart.toIso8601String());
      return;
    }
    
    try {
      final lastResetDate = DateTime.parse(lastResetDateStr);
      if (lastResetDate.isBefore(currentMonthStart)) {
        await _doResetMonthlyUsage(prefs);
        await prefs.setString(resetDateKey, currentMonthStart.toIso8601String());
      }
    } catch (e) {
      debugPrint('날짜 파싱 오류: $e');
      // 오류 발생 시 그냥 초기화
      await _doResetMonthlyUsage(prefs);
      await prefs.setString(resetDateKey, currentMonthStart.toIso8601String());
    }
  }
  
  /// 실제 월간 사용량 초기화 작업
  Future<void> _doResetMonthlyUsage(SharedPreferences prefs) async {
    // 베타 기간이 끝났는지 확인
    final isBetaEnded = await isBetaPeriodEnded();
    if (!isBetaEnded) {
      // 베타 기간 중에는 모든 사용량 초기화
      await resetAllUsage();
      return;
    }
    
    // 베타 기간 종료 후에는 무료 사용자와 프리미엄 사용자 구분하여 처리
    // TODO: 프리미엄 사용자 확인 및 처리 로직 추가
    
    // 일단은 모든 사용자 초기화
    await resetAllUsage();
    debugPrint('월간 사용량 초기화 완료');
  }
  
  /// 현재 베타 기간인지 확인
  Future<bool> isBetaPeriod() async {
    return !(await isBetaPeriodEnded());
  }
  
  /// 베타 기간 정보 제공
  Future<Map<String, dynamic>> getBetaPeriodInfo() async {
    final remainingDays = await getRemainingBetaDays();
    final isBeta = await isBetaPeriod();
    
    return {
      'isBetaPeriod': isBeta,
      'remainingDays': remainingDays,
      'betaEndDate': BETA_END_DATE_STR,
    };
  }

  /// 사용자의 현재 사용량 가져오기 (전체)
  Future<Map<String, dynamic>> getUserUsage() async {
    // 기존에 저장된 사용자 사용량 가져오기
    final usageData = await _loadUsageData();
    
    return {
      'ocrRequests': usageData['ocrRequests'] ?? 0,
      'ttsRequests': usageData['ttsRequests'] ?? 0,
      'translatedChars': usageData['translatedChars'] ?? 0,
      'storageUsageBytes': usageData['storageUsageBytes'] ?? 0,
      'dictionaryLookups': usageData['dictionaryLookups'] ?? 0,
      'pages': usageData['pages'] ?? 0,
      'flashcards': usageData['flashcards'] ?? 0,
      'betaStartDate': usageData['betaStartDate'],
      'notes': usageData['notes'] ?? 0,
    };
  }

  /// 무료 사용량 제한 확인 (전체)
  Future<Map<String, bool>> checkFreeLimits() async {
    final limits = await getBetaUsageLimits();
    return {
      'ocrLimitReached': limits['ocrLimitReached'] ?? false,
      'ttsLimitReached': limits['ttsLimitReached'] ?? false,
      'translationLimitReached': limits['translationLimitReached'] ?? false,
      'storageLimitReached': limits['storageLimitReached'] ?? false,
      'dictionaryLimitReached': limits['dictionaryLimitReached'] ?? false,
      'pageLimitReached': limits['pageLimitReached'] ?? false,
      'flashcardLimitReached': limits['flashcardLimitReached'] ?? false,
      'noteLimitReached': limits['noteLimitReached'] ?? false,
      'anyLimitReached': limits['anyLimitReached'] ?? false,
      'betaEnded': limits['betaEnded'] ?? false,
      'remainingDays': limits['remainingDays'] ?? 0,
    };
  }
  
  /// 각 기능별 사용량 비율(%) 계산
  Future<Map<String, double>> getUsagePercentages() async {
    final usageData = await _loadUsageData();
    
    // 각 항목별 사용량 비율 계산
    final ocrUsage = usageData['ocrRequests'] ?? 0;
    final ttsUsage = usageData['ttsRequests'] ?? 0;
    final translatedChars = usageData['translatedChars'] ?? 0;
    final storageUsageBytes = usageData['storageUsageBytes'] ?? 0;
    final dictionaryLookups = usageData['dictionaryLookups'] ?? 0;
    final pages = usageData['pages'] ?? 0;
    final flashcards = usageData['flashcards'] ?? 0;
    final notes = usageData['notes'] ?? 0;
    
    return {
      'ocr': (ocrUsage / MAX_FREE_OCR_REQUESTS) * 100,
      'tts': (ttsUsage / MAX_FREE_TTS_REQUESTS) * 100,
      'translation': (translatedChars / MAX_FREE_TRANSLATION_CHARS) * 100,
      'storage': (storageUsageBytes / MAX_FREE_STORAGE_BYTES) * 100,
      'dictionary': (dictionaryLookups / MAX_FREE_DICTIONARY_LOOKUPS) * 100,
      'page': (pages / MAX_FREE_PAGES) * 100,
      'flashcard': (flashcards / MAX_FREE_FLASHCARDS) * 100,
      'note': (notes / MAX_FREE_NOTES) * 100,
    };
  }

  /// 페이지 추가 가능 여부 확인
  Future<bool> canAddPage(int count) async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['pages'] ?? 0;
    
    // 추가하려는 페이지 수를 포함했을 때 제한을 초과하는지 확인
    return (currentUsage + count) <= MAX_FREE_PAGES;
  }
  
  /// 페이지 수 증가
  Future<bool> incrementPageCount(int count) async {
    return await _incrementUsage('pages', count, MAX_FREE_PAGES);
  }
  
  /// 페이지 수 감소 (페이지 삭제 시)
  Future<void> decrementPageCount() async {
    await _decrementUsage('pages');
  }
  
  /// 플래시카드 수 증가
  Future<bool> incrementFlashcardCount() async {
    return await _incrementUsage('flashcards', 1, MAX_FREE_FLASHCARDS);
  }
  
  /// 플래시카드 수 감소 (플래시카드 삭제 시)
  Future<void> decrementFlashcardCount() async {
    await _decrementUsage('flashcards');
  }
  
  /// 범용 사용량 감소 메서드
  Future<void> _decrementUsage(String key) async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData[key] ?? 0;
    
    if (currentUsage > 0) {
      usageData[key] = currentUsage - 1;
      await _saveUsageData(usageData);
      debugPrint('$key 사용량 감소: ${currentUsage - 1}');
    }
  }

  /// 사용자 사용량 데이터 로드
  Future<Map<String, dynamic>> _loadUsageData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonData = prefs.getString(_getUserKey(_USAGE_KEY));
      
      if (jsonData == null || jsonData.isEmpty) {
        return {};
      }
      
      return json.decode(jsonData);
    } catch (e) {
      debugPrint('사용량 데이터 로드 중 오류: $e');
      return {};
    }
  }
  
  /// 사용자 사용량 데이터 저장
  Future<void> _saveUsageData(Map<String, dynamic> usageData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String jsonData = json.encode(usageData);
      await prefs.setString(_getUserKey(_USAGE_KEY), jsonData);
    } catch (e) {
      debugPrint('사용량 데이터 저장 중 오류: $e');
    }
  }
} 