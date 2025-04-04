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
  
  // 베타 기간 동안의 무료 사용 제한 (테스트용)
  static const int MAX_FREE_TRANSLATION_CHARS = 100;  // 번역 최대 글자 수
  static const int MAX_FREE_OCR_PAGES = 5;           // OCR 최대 페이지 수 (요청당 아닌 총 페이지 수)
  static const int MAX_FREE_TTS_REQUESTS = 5;       // TTS 요청 최대 수
  static const int MAX_FREE_STORAGE_BYTES = 100 * 1024 * 1024; // 100MB 스토리지
  
  // 월별 기본 무료 사용 제한 (베타 이후)
  static const int BASIC_FREE_TRANSLATION_CHARS = 500;   // 번역 최대 글자 수
  static const int BASIC_FREE_OCR_PAGES = 10;           // OCR 최대 페이지 수 (월별)
  static const int BASIC_FREE_TTS_REQUESTS = 100;        // TTS 요청 최대 글자 수
  static const int BASIC_FREE_STORAGE_MB = 20;           // 저장 공간 최대 크기 (MB)
  
  // 싱글톤 패턴 구현
  static final UsageLimitService _instance = UsageLimitService._internal();
  factory UsageLimitService() => _instance;
  
  UsageLimitService._internal();
  
  // SharedPreferences 키
  static const String _kOcrPagesKey = 'ocr_pages';
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
  
  // 캐시 변수를 클래스 레벨로 이동
  Map<String, dynamic>? _cachedUsageData;
  DateTime? _lastFetchTime;
  
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
  
  /// OCR 페이지 사용량 증가
  Future<bool> incrementOcrPages(int pageCount) async {
    final usageData = await _loadUsageData();
    final int currentUsage = (usageData['ocrPages'] ?? 0) as int;
    
    // 현재 남은 페이지 수 계산
    final int remainingPages = MAX_FREE_OCR_PAGES - currentUsage;
    
    // 남은 페이지가 없으면 실패 반환
    if (remainingPages <= 0) {
      return false;
    }
    
    // 남은 페이지 내에서 최대한 처리 (초과해도 일단 처리)
    final int newUsage = currentUsage + pageCount;
    usageData['ocrPages'] = newUsage;
    await _saveUsageData(usageData);
    
    debugPrint('OCR 페이지 사용량 증가: $newUsage/$MAX_FREE_OCR_PAGES (요청: $pageCount, 남은 페이지: $remainingPages)');
    
    // 요청을 처리했으므로 true 반환
    return true;
  }
  
  /// OCR 요청을 페이지 수 기준으로 증가 (기존 메서드 유지, 하위 호환성)
  @Deprecated('incrementOcrPages 메서드를 대신 사용하세요')
  Future<bool> incrementOcrCount() async {
    // 이전 버전 호환성을 위해 유지하지만 내부적으로는 페이지 1개로 처리
    return await incrementOcrPages(1);
  }
  
  /// 번역 문자 사용량 증가
  Future<bool> incrementTranslationCharCount(int charCount) async {
    return await _incrementUsage('translatedChars', charCount, MAX_FREE_TRANSLATION_CHARS);
  }
  
  /// TTS 문자 사용량 증가
  Future<bool> incrementTtsCharCount(int charCount) async {
    debugPrint('TTS 사용량 증가 시도: $charCount 문자');
    final usageData = await _loadUsageData();
    final currentUsage = usageData['ttsRequests'] ?? 0;
    
    // 현재 상태 로깅
    debugPrint('TTS 현재 사용량: $currentUsage/$MAX_FREE_TTS_REQUESTS');
    
    // 사용량 제한 확인
    if (currentUsage >= MAX_FREE_TTS_REQUESTS) {
      debugPrint('TTS 사용량 제한 초과: $currentUsage/$MAX_FREE_TTS_REQUESTS');
      return false;
    }
    
    // 실제 증가되는 카운트 (길이에 따라 달라짐)
    final int incrementCount = (charCount / 20).ceil(); // 20자당 1회로 계산
    
    // 사용량 증가 후 값
    final int newUsage = currentUsage + incrementCount;
    
    // 사용량 증가
    usageData['ttsRequests'] = newUsage;
    await _saveUsageData(usageData);
    
    debugPrint('TTS 사용량 증가 완료: $newUsage/$MAX_FREE_TTS_REQUESTS (${incrementCount}회 증가)');
    return newUsage <= MAX_FREE_TTS_REQUESTS;
  }
  
  /// 사전 조회 사용량 증가 (제한 없음)
  Future<bool> incrementDictionaryCount() async {
    // 사전 검색은 제한 없이 항상 성공 반환
    return true;
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
    final ocrUsage = usageData['ocrPages'] ?? 0;
    final ttsUsage = usageData['ttsRequests'] ?? 0;
    final translatedChars = usageData['translatedChars'] ?? 0;
    final storageUsageBytes = usageData['storageUsageBytes'] ?? 0;
    
    // 각 제한 초과 여부 확인
    final bool ocrLimitReached = ocrUsage >= MAX_FREE_OCR_PAGES;
    final bool ttsLimitReached = ttsUsage >= MAX_FREE_TTS_REQUESTS;
    final bool translationLimitReached = translatedChars >= MAX_FREE_TRANSLATION_CHARS;
    final bool storageLimitReached = storageUsageBytes >= MAX_FREE_STORAGE_BYTES;
    
    // 어느 하나라도 제한에 도달했는지 확인
    final bool anyLimitReached = 
        ocrLimitReached ||
        ttsLimitReached ||
        translationLimitReached ||
        storageLimitReached ||
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
      'dictionaryLimitReached': false, 
      'pageLimitReached': false,
      'flashcardLimitReached': false, 
      'noteLimitReached': false, 
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
        'ocrPages': 0,
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
  /// forceRefresh가 true이면 캐시를 무시하고 최신 데이터를 가져옵니다.
  Future<Map<String, dynamic>> getUserUsage({bool forceRefresh = false}) async {
    // 캐시 사용 결정 (5초 이내 요청은 캐시 사용)
    final now = DateTime.now();
    final useCache = !forceRefresh && 
                    _cachedUsageData != null && 
                    _lastFetchTime != null &&
                    now.difference(_lastFetchTime!).inSeconds < 5;
    
    if (useCache) {
      debugPrint('사용량 데이터 캐시 사용 (마지막 갱신: ${now.difference(_lastFetchTime!).inSeconds}초 전)');
      return _cachedUsageData!;
    }
    
    // 기존에 저장된 사용자 사용량 가져오기
    final usageData = await _loadUsageData();
    
    // 결과 캐싱
    _cachedUsageData = {
      'ocrPages': usageData['ocrPages'] ?? 0,
      'ttsRequests': usageData['ttsRequests'] ?? 0,
      'translatedChars': usageData['translatedChars'] ?? 0,
      'storageUsageBytes': usageData['storageUsageBytes'] ?? 0,
      'dictionaryLookups': usageData['dictionaryLookups'] ?? 0,
      'pages': usageData['pages'] ?? 0,
      'flashcards': usageData['flashcards'] ?? 0,
      'notes': usageData['notes'] ?? 0,
    };
    _lastFetchTime = now;
    
    if (forceRefresh) {
      debugPrint('사용량 데이터 강제 새로고침 완료');
    }
    
    return _cachedUsageData!;
  }

  /// 무료 사용량 제한 확인 (전체)
  Future<Map<String, dynamic>> checkFreeLimits() async {
    final limits = await getBetaUsageLimits();
    
    // 결과 맵 생성
    final result = <String, dynamic>{};
    
    // 모든 키에 대해 타입 안전성 확보
    limits.forEach((key, value) {
      if (key.endsWith('LimitReached') || key == 'betaEnded' || key == 'anyLimitReached') {
        // 불리언 값이어야 하는 키들
        if (value is bool) {
          result[key] = value;
        } else if (value is int) {
          // int 타입인 경우 0이 아니면 true로 간주
          result[key] = value != 0;
        } else {
          // 기본값은 false
          result[key] = false;
        }
      } else {
        // 다른 타입의 값들은 그대로 유지
        result[key] = value;
      }
    });
    
    return result;
  }
  
  /// 각 기능별 사용량 비율(%) 계산
  Future<Map<String, double>> getUsagePercentages() async {
    final usageData = await _loadUsageData();
    
    // 각 항목별 사용량 비율 계산
    final ocrUsage = usageData['ocrPages'] ?? 0;
    final ttsUsage = usageData['ttsRequests'] ?? 0;
    final translatedChars = usageData['translatedChars'] ?? 0;
    final storageUsageBytes = usageData['storageUsageBytes'] ?? 0;
    
    return {
      'ocr': (ocrUsage / MAX_FREE_OCR_PAGES) * 100,
      'tts': (ttsUsage / MAX_FREE_TTS_REQUESTS) * 100,
      'translation': (translatedChars / MAX_FREE_TRANSLATION_CHARS) * 100,
      'storage': (storageUsageBytes / MAX_FREE_STORAGE_BYTES) * 100,
      // 제한 없는 기능은 항상 0% 사용량 반환
      'dictionary': 0.0,
      'flashcard': 0.0,
      'note': 0.0,
      'page': 0.0,
    };
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

  /// 범용 사용량 감소 메서드
  Future<void> decrementUsage(String key) async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData[key] ?? 0;
    
    if (currentUsage > 0) {
      usageData[key] = currentUsage - 1;
      await _saveUsageData(usageData);
      debugPrint('$key 사용량 감소: ${currentUsage - 1}');
    }
  }

  /// 플래시카드 사용량 증가
  Future<bool> incrementFlashcardCount() async {
    // 현재는 플래시카드에 제한이 없으므로 항상 true 반환
    final usageData = await _loadUsageData();
    final currentUsage = usageData['flashcards'] ?? 0;
    
    // 사용량 증가
    usageData['flashcards'] = currentUsage + 1;
    await _saveUsageData(usageData);
    
    debugPrint('flashcards 사용량 증가: ${currentUsage + 1}/무제한');
    return true;
  }

  /// 플래시카드 사용량 감소
  Future<void> decrementFlashcardCount() async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['flashcards'] ?? 0;
    
    if (currentUsage > 0) {
      usageData['flashcards'] = currentUsage - 1;
      await _saveUsageData(usageData);
      debugPrint('flashcards 사용량 감소: ${currentUsage - 1}/무제한');
    }
  }

  /// 페이지 추가 가능 여부 확인
  Future<bool> canAddPage(int count) async {
    // 현재는 페이지에 제한이 없으므로 항상 true 반환
    return true;
  }

  /// 페이지 사용량 증가
  Future<bool> incrementPageCount(int count) async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['pages'] ?? 0;
    
    // 사용량 증가
    usageData['pages'] = currentUsage + count;
    await _saveUsageData(usageData);
    
    debugPrint('pages 사용량 증가: ${currentUsage + count}/무제한');
    return true;
  }

  /// 페이지 사용량 감소
  Future<void> decrementPageCount() async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['pages'] ?? 0;
    
    if (currentUsage > 0) {
      usageData['pages'] = currentUsage - 1;
      await _saveUsageData(usageData);
      debugPrint('pages 사용량 감소: ${currentUsage - 1}/무제한');
    }
  }

  /// 남은 OCR 페이지 수 얻기
  Future<int> getRemainingOcrPages() async {
    final usageData = await _loadUsageData();
    final int usedPages = (usageData['ocrPages'] ?? 0) as int;
    final int remaining = MAX_FREE_OCR_PAGES - usedPages;
    return remaining < 0 ? 0 : remaining;
  }

  /// OCR 페이지 사용량 얻기
  Future<int> getUsedOcrPages() async {
    final usageData = await _loadUsageData();
    return usageData['ocrPages'] ?? 0;
  }

  /// OCR 페이지 사용량 감소 (오류 발생 시 롤백에 사용)
  Future<void> decrementOcrPages(int pageCount) async {
    final usageData = await _loadUsageData();
    final currentUsage = usageData['ocrPages'] ?? 0;
    final newValue = (currentUsage - pageCount).clamp(0, double.maxFinite.toInt());
    
    usageData['ocrPages'] = newValue;
    await _saveUsageData(usageData);
    debugPrint('OCR 페이지 사용량 감소: $newValue/$MAX_FREE_OCR_PAGES');
  }

  /// OCR 페이지를 추가할 수 있는지 확인
  Future<bool> canAddOcrPages(int pageCount) async {
    // 0 또는 음수의 페이지 요청은 항상 가능
    if (pageCount <= 0) return true;
    
    final usageData = await _loadUsageData();
    final int currentUsage = (usageData['ocrPages'] ?? 0) as int;
    
    // 현재 남은 페이지 수 계산
    final int remainingPages = MAX_FREE_OCR_PAGES - currentUsage;
    
    // 하나라도 더 추가할 수 있는지 확인 (최소 1페이지 이상 처리 가능해야 함)
    return remainingPages > 0;
  }
}