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
  
  // 베타 기간 종료일 (2025년 4월 30일)
  static final DateTime BETA_END_DATE = DateTime(2025, 4, 30);
  
  // 베타 기간 동안의 무료 사용 제한
  static const int MAX_FREE_TRANSLATION_CHARS = 1000;  // 번역 최대 글자 수
  static const int MAX_FREE_PAGES = 2;                // OCR 페이지 최대 개수
  static const int MAX_FREE_OCR_REQUESTS = 2;         // OCR 요청 최대 수
  static const int MAX_FREE_DICTIONARY_LOOKUPS = 200;    // 사전 검색 최대 수
  static const int MAX_FREE_TTS_REQUESTS = 200;         // TTS 요청 최대 수
  static const int MAX_FREE_STORAGE_BYTES = 50 * 1024 * 1024; // 50MB 스토리지
  static const int MAX_FREE_FLASHCARDS = 300;          // 플래시카드 최대 수
  static const int MAX_FREE_NOTES = 50;                // 노트 최대 수
  
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
  
  // 베타 기간 정보
  static const String _kBetaPeriodEnd = '2025-04-30'; // 베타 기간 종료일 (연도-월-일)
  
  // 무료 사용 제한 (베타 기간)
  static const int _kFreeOcrLimit = 50; // OCR 노트 생성 수
  static const int _kFreeTranslationCharLimit = 100000; // 번역 문자 수
  static const int _kFreeTtsCharLimit = 50000; // TTS 문자 수
  static const int _kFreeDictionaryLimit = 200; // 외부 사전 조회 수
  static const int _kFreeStorageLimit = 100 * 1024 * 1024; // 저장 공간 (100MB)
  
  // 베타 기간 (30일)
  static const int BETA_PERIOD_DAYS = 30;
  
  // 사용량 데이터 키
  static const String _USAGE_KEY = 'user_usage_data';
  
  // 현재 사용자 ID 가져오기
  String? get _currentUserId => _auth.currentUser?.uid;
  
  /// 베타 기간 종료 날짜 가져오기
  Future<DateTime> getBetaPeriodEndDate() async {
    final prefs = await SharedPreferences.getInstance();
    final endDateStr = prefs.getString(_kBetaPeriodEndKey) ?? _kBetaPeriodEnd;
    
    try {
      return DateFormat('yyyy-MM-dd').parse(endDateStr);
    } catch (e) {
      debugPrint('베타 기간 종료일 파싱 오류: $e');
      // 기본값: 2025년 4월 30일
      return DateTime(2025, 4, 30);
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
    // 먼저 제한 확인
    final usage = await getBetaUsageLimits();
    if (usage['ocrLimitReached'] == true) {
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final key = _getUserKey(_kOcrCountKey);
    
    int count = prefs.getInt(key) ?? 0;
    count++;
    
    await prefs.setInt(key, count);
    debugPrint('OCR 사용량 증가: $count/$_kFreeOcrLimit');
    
    return count <= _kFreeOcrLimit;
  }
  
  /// 번역 문자 사용량 증가
  Future<bool> incrementTranslationCharCount(int charCount) async {
    // 먼저 제한 확인
    final usage = await getBetaUsageLimits();
    if (usage['translationLimitReached'] == true) {
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final key = _getUserKey(_kTranslationCharCountKey);
    
    int count = prefs.getInt(key) ?? 0;
    count += charCount;
    
    await prefs.setInt(key, count);
    debugPrint('번역 문자 사용량 증가: $count/$_kFreeTranslationCharLimit');
    
    return count <= _kFreeTranslationCharLimit;
  }
  
  /// TTS 문자 사용량 증가
  Future<bool> incrementTtsCharCount(int charCount) async {
    // 먼저 제한 확인
    final usage = await getBetaUsageLimits();
    if (usage['ttsLimitReached'] == true) {
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final key = _getUserKey(_kTtsCharCountKey);
    
    int count = prefs.getInt(key) ?? 0;
    count += charCount;
    
    await prefs.setInt(key, count);
    debugPrint('TTS 문자 사용량 증가: $count/$_kFreeTtsCharLimit');
    
    return count <= _kFreeTtsCharLimit;
  }
  
  /// 사전 조회 사용량 증가
  Future<bool> incrementDictionaryCount() async {
    // 먼저 제한 확인
    final usage = await getBetaUsageLimits();
    if (usage['dictionaryLimitReached'] == true) {
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final key = _getUserKey(_kDictionaryCountKey);
    
    int count = prefs.getInt(key) ?? 0;
    count++;
    
    await prefs.setInt(key, count);
    debugPrint('사전 조회 사용량 증가: $count/$_kFreeDictionaryLimit');
    
    return count <= _kFreeDictionaryLimit;
  }
  
  /// 저장 공간 사용량 증가
  Future<bool> addStorageUsage(int bytes) async {
    // 먼저 제한 확인
    final usage = await getBetaUsageLimits();
    if (usage['storageLimitReached'] == true) {
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final key = _getUserKey(_kStorageUsageKey);
    
    int currentUsage = prefs.getInt(key) ?? 0;
    currentUsage += bytes;
    
    await prefs.setInt(key, currentUsage);
    
    final usageInMB = (currentUsage / (1024 * 1024)).toStringAsFixed(2);
    final limitInMB = (_kFreeStorageLimit / (1024 * 1024)).toStringAsFixed(0);
    debugPrint('저장 공간 사용량 증가: ${usageInMB}MB/${limitInMB}MB');
    
    return currentUsage <= _kFreeStorageLimit;
  }
  
  /// 저장 공간 사용량 감소
  Future<void> reduceStorageUsage(int bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getUserKey(_kStorageUsageKey);
    
    int currentUsage = prefs.getInt(key) ?? 0;
    currentUsage = (currentUsage - bytes).clamp(0, double.maxFinite.toInt());
    
    await prefs.setInt(key, currentUsage);
    
    final usageInMB = (currentUsage / (1024 * 1024)).toStringAsFixed(2);
    final limitInMB = (_kFreeStorageLimit / (1024 * 1024)).toStringAsFixed(0);
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
    final ocrKey = _getUserKey(_kOcrCountKey);
    final translationKey = _getUserKey(_kTranslationCharCountKey);
    final ttsKey = _getUserKey(_kTtsCharCountKey);
    final dictionaryKey = _getUserKey(_kDictionaryCountKey);
    final storageKey = _getUserKey(_kStorageUsageKey);
    
    await prefs.setInt(ocrKey, 0);
    await prefs.setInt(translationKey, 0);
    await prefs.setInt(ttsKey, 0);
    await prefs.setInt(dictionaryKey, 0);
    await prefs.setInt(storageKey, 0);
    
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
      'betaEndDate': _kBetaPeriodEnd,
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

  /// TTS 요청 추가
  Future<bool> addTtsRequest() async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['ttsRequests'] ?? 0;
    
    // 사용량 제한 확인
    if (currentUsage >= MAX_FREE_TTS_REQUESTS) {
      return false;
    }
    
    // 사용량 증가
    usageData['ttsRequests'] = currentUsage + 1;
    await _saveUsageData(usageData);
    return true;
  }

  /// 번역된 문자 수 추가
  Future<bool> addTranslatedChars(int charCount) async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['translatedChars'] ?? 0;
    
    // 문자 수 제한은 일단 없음 (사용량만 추적)
    usageData['translatedChars'] = currentUsage + charCount;
    await _saveUsageData(usageData);
    return true;
  }

  /// 사전 검색 횟수 증가
  Future<bool> incrementDictionaryLookupCount() async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['dictionaryLookups'] ?? 0;
    
    // 사용량 제한 확인
    if (currentUsage >= MAX_FREE_DICTIONARY_LOOKUPS) {
      return false;
    }
    
    // 사용량 증가
    usageData['dictionaryLookups'] = currentUsage + 1;
    await _saveUsageData(usageData);
    return true;
  }
  
  /// 사전 검색 횟수 감소 (이미 캐시에 있는 경우)
  Future<void> decrementDictionaryLookupCount() async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['dictionaryLookups'] ?? 0;
    
    if (currentUsage > 0) {
      usageData['dictionaryLookups'] = currentUsage - 1;
      await _saveUsageData(usageData);
    }
  }
  
  /// OCR 요청 추가
  Future<bool> addOcrRequest() async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['ocrRequests'] ?? 0;
    
    // 사용량 제한 확인
    if (currentUsage >= MAX_FREE_OCR_REQUESTS) {
      return false;
    }
    
    // 사용량 증가
    usageData['ocrRequests'] = currentUsage + 1;
    await _saveUsageData(usageData);
    return true;
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
    final usageData = await _loadUsageData();
    final currentUsage = usageData['pages'] ?? 0;
    
    // 사용량 제한 확인
    if (currentUsage + count > MAX_FREE_PAGES) {
      return false;
    }
    
    // 사용량 증가
    usageData['pages'] = currentUsage + count;
    await _saveUsageData(usageData);
    return true;
  }
  
  /// 페이지 수 감소 (페이지 삭제 시)
  Future<void> decrementPageCount() async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['pages'] ?? 0;
    
    if (currentUsage > 0) {
      usageData['pages'] = currentUsage - 1;
      await _saveUsageData(usageData);
    }
  }
  
  /// 플래시카드 수 증가
  Future<bool> incrementFlashcardCount() async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['flashcards'] ?? 0;
    
    // 사용량 제한 확인
    if (currentUsage >= MAX_FREE_FLASHCARDS) {
      return false;
    }
    
    // 사용량 증가
    usageData['flashcards'] = currentUsage + 1;
    await _saveUsageData(usageData);
    return true;
  }
  
  /// 플래시카드 수 감소 (플래시카드 삭제 시)
  Future<void> decrementFlashcardCount() async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['flashcards'] ?? 0;
    
    if (currentUsage > 0) {
      usageData['flashcards'] = currentUsage - 1;
      await _saveUsageData(usageData);
    }
  }

  /// 사용자 사용량 데이터 로드
  Future<Map<String, dynamic>> _loadUsageData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonData = prefs.getString(_USAGE_KEY);
      
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
      await prefs.setString(_USAGE_KEY, jsonData);
    } catch (e) {
      debugPrint('사용량 데이터 저장 중 오류: $e');
    }
  }
} 