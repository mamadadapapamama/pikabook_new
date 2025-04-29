import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'plan_service.dart';

/// 사용량 제한 관리 서비스
/// 사용자의 사용량을 추적하고 제한을 적용합니다.
class UsageLimitService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  PlanService? _planService;
  
  // 사용자별 커스텀 제한 설정을 위한 Firestore 컬렉션
  static const String _CUSTOM_LIMITS_COLLECTION = 'user_limits';
  
  // 싱글톤 패턴 구현
  static final UsageLimitService _instance = UsageLimitService._internal();
  factory UsageLimitService() => _instance;
  
  UsageLimitService._internal();
  
  // PlanService lazy getter
  PlanService get planService {
    _planService ??= PlanService();
    return _planService!;
  }
  
  // SharedPreferences 키
  static const String _kOcrPagesKey = 'ocr_pages';
  static const String _kTranslationCharCountKey = 'translation_char_count';
  static const String _kTtsCharCountKey = 'tts_char_count';
  static const String _kDictionaryCountKey = 'dictionary_count';
  static const String _kStorageUsageKey = 'storage_usage';
  static const String _kResetDateKey = 'usage_reset_date';
  static const String _kMonthlyLimitsKey = 'monthly_limits';
  
  // 사용량 데이터 키
  static const String _USAGE_KEY = 'user_usage_data';
  
  // 현재 사용자 ID 가져오기
  String? get _currentUserId => _auth.currentUser?.uid;
  
  // 캐시 변수를 클래스 레벨로 이동
  Map<String, dynamic>? _cachedUsageData;
  DateTime? _lastFetchTime;
  
  /// 사용자별 키 생성
  String _getUserKey(String baseKey) {
    final userId = _currentUserId;
    return userId != null ? '${userId}_$baseKey' : baseKey;
  }
  
  /// 안전하게 플랜 제한값 가져오기
  Map<String, int> _getFreePlanLimits() {
    final freePlanLimits = PlanService.PLAN_LIMITS[PlanService.PLAN_FREE];
    if (freePlanLimits == null) {
      // 기본값 반환
      return {
        'ocrPages': 30,
        'translatedChars': 3000,
        'ttsRequests': 100,
        'storageBytes': 52428800, // 50MB
      };
    }
    return Map<String, int>.from(freePlanLimits);
  }

  /// 특정 제한값 안전하게 가져오기
  int _getFreePlanLimit(String key) {
    return _getFreePlanLimits()[key] ?? 0;
  }

  /// 특정 사용자의 사용량 제한 가져오기
  Future<Map<String, int>> getUserLimits() async {
    try {
    final userId = _currentUserId;
      if (userId == null) {
        return _getDefaultLimits();
      }

      // Firestore에서 사용자별 제한 확인
      final doc = await _firestore
          .collection(_CUSTOM_LIMITS_COLLECTION)
          .doc(userId)
          .get();

      if (!doc.exists) {
        return _getDefaultLimits();
      }

      final data = doc.data() as Map<String, dynamic>;
      final defaultLimits = await _getDefaultLimits();
      
      return {
        'translatedChars': data['translatedChars'] ?? defaultLimits['translatedChars']!,
        'ocrPages': data['ocrPages'] ?? defaultLimits['ocrPages']!,
        'ttsRequests': data['ttsRequests'] ?? defaultLimits['ttsRequests']!,
        'storageBytes': data['storageBytes'] ?? defaultLimits['storageBytes']!,
      };
    } catch (e) {
      debugPrint('사용자 제한 로드 중 오류: $e');
      return _getDefaultLimits();
    }
  }

  /// 기본 제한 값 반환
  Future<Map<String, int>> _getDefaultLimits() async {
    final planType = await planService.getCurrentPlanType();
    final limits = PlanService.PLAN_LIMITS[planType] ?? _getFreePlanLimits();
    return Map<String, int>.from(limits);
  }

  /// 특정 사용자의 사용량 제한 설정
  Future<void> setUserLimits(String userId, {
    int? translationChars,
    int? ocrPages,
    int? ttsRequests,
    int? storageBytes,
  }) async {
    try {
      final Map<String, dynamic> limits = {};
      
      if (translationChars != null) limits['translatedChars'] = translationChars;
      if (ocrPages != null) limits['ocrPages'] = ocrPages;
      if (ttsRequests != null) limits['ttsRequests'] = ttsRequests;
      if (storageBytes != null) limits['storageBytes'] = storageBytes;
      
      if (limits.isNotEmpty) {
        await _firestore
            .collection(_CUSTOM_LIMITS_COLLECTION)
            .doc(userId)
            .set(limits, SetOptions(merge: true));
            
        debugPrint('사용자 $userId의 제한이 업데이트됨: $limits');
      }
    } catch (e) {
      debugPrint('사용자 제한 설정 중 오류: $e');
      rethrow;
    }
  }

  /// 사용자 사용량 데이터 저장
  Future<void> _saveUsageData(Map<String, dynamic> usageData) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('사용량 데이터 저장: 사용자 ID가 없음');
        return;
      }

      // Firestore에 저장
      await _firestore.collection('users').doc(userId).set({
        'usage': usageData,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // SharedPreferences에도 백업으로 저장
      final prefs = await SharedPreferences.getInstance();
      final String jsonData = json.encode(usageData);
      await prefs.setString(_USAGE_KEY, jsonData);
      
      debugPrint('사용량 데이터 저장 완료 (Firestore + SharedPreferences)');
      
      // 캐시 업데이트
      _cachedUsageData = Map<String, dynamic>.from(usageData);
      _lastFetchTime = DateTime.now();
    } catch (e) {
      debugPrint('사용량 데이터 저장 중 오류: $e');
    }
  }

  /// 캐시 무효화 및 새로고침
  void invalidateCache() {
    _cachedUsageData = null;
    _lastFetchTime = null;
    debugPrint('사용량 데이터 캐시 무효화됨');
  }

  /// 캐시 새로고침
  Future<Map<String, dynamic>> refreshCache() async {
    invalidateCache();
    return await getUserUsage(forceRefresh: true);
  }

  /// 사용량 제한 통합 체크
  Future<bool> checkLimit(String key, int amount) async {
    final limits = await getUserLimits();
    final currentUsage = await getUserUsage();
    final currentAmount = currentUsage[key] as int? ?? 0;
    final limit = limits[key] ?? 0;
    
    debugPrint('제한 확인: $key, 현재=${currentAmount}, 추가=$amount, 제한=$limit');
    return (currentAmount + amount) <= limit;
  }

  /// 범용 사용량 증가 메서드
  Future<bool> _incrementUsage(String key, int amount) async {
    try {
      // 제한 체크
      if (!await checkLimit(key, amount)) {
        debugPrint('$key 사용량 제한 초과');
      return false;
    }
    
      final usageData = await _loadUsageData();
      final currentUsage = usageData[key] ?? 0;
      final newUsage = currentUsage + amount;
      
      // 사용량 업데이트
      usageData[key] = newUsage;
    await _saveUsageData(usageData);
    
      // Firestore에 직접 업데이트 (중요 지표)
      await _updateFirestoreUsage(key, newUsage);
  
      debugPrint('$key 사용량 증가: $currentUsage → $newUsage');
    return true;
    } catch (e) {
      debugPrint('사용량 증가 중 오류: $e');
      return false;
    }
  }
  
  /// 범용 사용량 감소 메서드
  Future<void> _decrementUsage(String key, int amount) async {
    try {
    final usageData = await _loadUsageData();
    final currentUsage = usageData[key] ?? 0;
      final newUsage = (currentUsage - amount).clamp(0, double.maxFinite.toInt());
      
      // 사용량 업데이트
      usageData[key] = newUsage;
    await _saveUsageData(usageData);
    
      // Firestore에 직접 업데이트
      await _updateFirestoreUsage(key, newUsage);
      
      debugPrint('$key 사용량 감소: $currentUsage → $newUsage');
    } catch (e) {
      debugPrint('사용량 감소 중 오류: $e');
    }
  }

  /// Firestore 사용량 업데이트
  Future<void> _updateFirestoreUsage(String key, int value) async {
    try {
      final userId = _currentUserId;
      if (userId == null) return;
      
      debugPrint('Firestore 업데이트 시작: $key = $value');
      
      // 현재 전체 사용량 데이터 로드
      final currentUsage = await _loadUsageData();
      currentUsage[key] = value;
      
      final updateData = {
        'usage': {
          ...currentUsage,
          'lastUpdated': FieldValue.serverTimestamp(),
        }
      };
      
      debugPrint('업데이트할 데이터: $updateData');
      
      // 전체 사용량 데이터를 한 번에 업데이트
      await _firestore.collection('users').doc(userId).set(
        updateData,
        SetOptions(merge: true)
      );
      
      debugPrint('Firestore 사용량 업데이트 완료');
      
      // 캐시 무효화
      invalidateCache();
    } catch (e) {
      debugPrint('Firestore 업데이트 실패: $e');
    }
  }

  /// OCR 페이지 사용량 증가
  Future<bool> incrementOcrPages(int pageCount) async {
    return await _incrementUsage('ocrPages', pageCount);
  }

  /// OCR 페이지 사용량 감소
  Future<void> decrementOcrPages(int pageCount) async {
    await _decrementUsage('ocrPages', pageCount);
  }

  /// 번역 문자 사용량 증가
  Future<bool> incrementTranslationCharCount(int charCount) async {
    return await _incrementUsage('translatedChars', charCount);
  }

  /// TTS 요청 사용량 증가
  Future<bool> incrementTtsCharCount(int charCount) async {
    return await _incrementUsage('ttsRequests', 1); // 텍스트 길이와 관계없이 1회로 카운트
  }

  /// 저장 공간 사용량 증가
  Future<bool> addStorageUsage(int bytes) async {
    return await _incrementUsage('storageUsageBytes', bytes);
  }

  /// 저장 공간 사용량 감소
  Future<void> reduceStorageUsage(int bytes) async {
    await _decrementUsage('storageUsageBytes', bytes);
  }

  /// 사전 조회 사용량 증가 (제한 없음)
  Future<bool> incrementDictionaryCount() async {
    // 사전 검색은 제한 없이 항상 성공 반환
    return true;
  }

  /// 사용량 제한 체크 메서드들
  Future<bool> checkOcrLimit(int pages) async {
    return await checkLimit('ocrPages', pages);
  }

  Future<bool> checkTranslationLimit(int chars) async {
    return await checkLimit('translatedChars', chars);
  }

  Future<bool> checkTtsLimit(int requests) async {
    return await checkLimit('ttsRequests', requests);
  }

  Future<bool> checkStorageLimit(int bytes) async {
    return await checkLimit('storageBytes', bytes);
  }

  /// 모든 사용량 초기화
  Future<void> resetAllUsage() async {
    try {
    final userId = _currentUserId;
      if (userId == null) return;
    
      final resetData = {
        'ocrPages': 0,
        'ttsRequests': 0,
        'translatedChars': 0,
        'storageUsageBytes': 0,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      // Firestore 업데이트
      await _firestore.collection('users').doc(userId).set({
        'usage': resetData
      }, SetOptions(merge: true));

      // 캐시 초기화
      await refreshCache();
      
      debugPrint('모든 사용량 초기화 완료');
    } catch (e) {
      debugPrint('사용량 초기화 중 오류: $e');
    }
  }

  /// 월간 사용량 초기화
  Future<void> resetMonthlyUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final resetDateKey = _getUserKey(_kResetDateKey);
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    
    // 마지막 초기화 날짜 확인
    final lastResetDateStr = prefs.getString(resetDateKey);
    
    if (lastResetDateStr == null) {
      await resetAllUsage();
      await prefs.setString(resetDateKey, currentMonthStart.toIso8601String());
      return;
    }
    
    try {
      final lastResetDate = DateTime.parse(lastResetDateStr);
      if (lastResetDate.isBefore(currentMonthStart)) {
        await resetAllUsage();
        await prefs.setString(resetDateKey, currentMonthStart.toIso8601String());
      }
    } catch (e) {
      debugPrint('날짜 파싱 오류: $e');
      await resetAllUsage();
      await prefs.setString(resetDateKey, currentMonthStart.toIso8601String());
    }
  }

  /// 사용자의 현재 사용량 가져오기 (전체)
  /// forceRefresh가 true이면 캐시를 무시하고 최신 데이터를 가져옵니다.
  Future<Map<String, dynamic>> getUserUsage({bool forceRefresh = false}) async {
    // 캐시 사용 결정 (1초 이내 요청은 캐시 사용)
    final now = DateTime.now();
    final useCache = !forceRefresh && 
                    _cachedUsageData != null && 
                    _lastFetchTime != null &&
                    now.difference(_lastFetchTime!).inSeconds < 1;
    
    if (useCache) {
      debugPrint('사용량 데이터 캐시 사용 (마지막 갱신: ${now.difference(_lastFetchTime!).inSeconds}초 전)');
      return Map<String, dynamic>.from(_cachedUsageData!);
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
    
    return Map<String, dynamic>.from(_cachedUsageData!);
  }

  /// 무료 사용량 제한 확인 (전체)
  Future<Map<String, dynamic>> checkFreeLimits() async {
    final limits = await getUserLimits();
    
    // 결과 맵 생성
    final result = <String, dynamic>{};
    
    // 모든 키에 대해 타입 안전성 확보
    limits.forEach((key, value) {
      if (key.endsWith('LimitReached') || key == 'anyLimitReached') {
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
  
  /// 사용량 비율 계산
  Future<Map<String, double>> getUsagePercentages() async {
    try {
      final usageData = await getUserUsage(forceRefresh: true);
      final planType = await planService.getCurrentPlanType();
      final limits = PlanService.PLAN_LIMITS[planType] ?? _getFreePlanLimits();
      
      // 디버그 로그 추가
      debugPrint('=== 사용량 계산 디버그 ===');
      debugPrint('현재 플랜: $planType');
      debugPrint('현재 사용량: $usageData');
      debugPrint('현재 제한: $limits');
    
    // 각 항목별 사용량 비율 계산
      final Map<String, double> percentages = {};
      
      // OCR 사용량 (Firebase Storage 기반)
      final ocrPages = await recalculateOcrPages();
      final ocrLimit = limits['ocrPages'] ?? 1;
      percentages['ocr'] = double.parse(((ocrPages / ocrLimit) * 100).clamp(0.0, 100.0).toStringAsFixed(2));
      debugPrint('OCR 사용량: $ocrPages / $ocrLimit = ${percentages['ocr']}%');
      
      // 저장 공간 사용량 (Firebase Storage 기반)
      final storageBytes = await recalculateStorageUsage();
      final storageLimit = limits['storageBytes'] ?? 1;
      percentages['storage'] = double.parse(((storageBytes / storageLimit) * 100).clamp(0.0, 100.0).toStringAsFixed(2));
      debugPrint('저장 공간 사용량: ${storageBytes / 1024 / 1024}MB / ${storageLimit / 1024 / 1024}MB = ${percentages['storage']}%');
      
      // TTS 사용량
      final ttsUsage = _parseIntSafely(usageData['ttsRequests']);
      final ttsLimit = limits['ttsRequests'] ?? 1;
      percentages['tts'] = double.parse(((ttsUsage / ttsLimit) * 100).clamp(0.0, 100.0).toStringAsFixed(2));
      debugPrint('TTS 사용량: $ttsUsage / $ttsLimit = ${percentages['tts']}%');
      
      // 번역 사용량
      final translationUsage = _parseIntSafely(usageData['translatedChars']);
      final translationLimit = limits['translatedChars'] ?? 1;
      percentages['translation'] = double.parse(((translationUsage / translationLimit) * 100).clamp(0.0, 100.0).toStringAsFixed(2));
      debugPrint('번역 사용량: $translationUsage / $translationLimit = ${percentages['translation']}%');
      
      debugPrint('계산된 최종 비율: $percentages');
      return percentages;
    } catch (e) {
      debugPrint('사용량 비율 계산 중 오류: $e');
    return {
        'ocr': 0.0,
        'tts': 0.0,
        'translation': 0.0,
        'storage': 0.0,
      };
    }
  }

  /// 제한 상태 확인
  Future<Map<String, dynamic>> checkLimitStatus() async {
    try {
      final usageData = await getUserUsage(forceRefresh: true);
      final planType = await planService.getCurrentPlanType();
      final limits = PlanService.PLAN_LIMITS[planType] ?? _getFreePlanLimits();
      
      // OCR과 저장공간은 Firebase Storage에서 직접 계산
      final ocrPages = await recalculateOcrPages();
      final storageBytes = await recalculateStorageUsage();
      
      return {
        'ocrLimitReached': ocrPages >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': _parseIntSafely(usageData['ttsRequests']) >= (limits['ttsRequests'] ?? 0),
        'translationLimitReached': _parseIntSafely(usageData['translatedChars']) >= (limits['translatedChars'] ?? 0),
        'storageLimitReached': storageBytes >= (limits['storageBytes'] ?? 0),
        // 제한값도 함께 전달
        'ocrLimit': limits['ocrPages'],
        'ttsLimit': limits['ttsRequests'],
        'translationLimit': limits['translatedChars'],
        'storageLimit': limits['storageBytes'],
      };
    } catch (e) {
      debugPrint('제한 상태 확인 중 오류: $e');
      return {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'translationLimitReached': false,
        'storageLimitReached': false,
        'ocrLimit': 30,
        'ttsLimit': 100,
        'translationLimit': 3000,
        'storageLimit': 104857600, // 100MB
      };
    }
  }

  /// 사용량 정보 가져오기 (비율과 제한 상태)
  Future<Map<String, dynamic>> getUsageInfo() async {
    try {
      final percentages = await getUsagePercentages();
      final limitStatus = await checkLimitStatus();
      
      debugPrint('=== 사용량 정보 ===');
      debugPrint('사용 비율: $percentages');
      debugPrint('제한 상태: $limitStatus');
      
      return {
        'percentages': percentages,
        'limitStatus': limitStatus,
      };
    } catch (e) {
      debugPrint('사용량 정보 가져오기 중 오류: $e');
      return {
        'percentages': {
          'ocr': 0.0,
          'tts': 0.0,
          'translation': 0.0,
          'storage': 0.0,
        },
        'limitStatus': await checkLimitStatus(),
      };
    }
  }

  /// 사용자 사용량 데이터 로드
  Future<Map<String, dynamic>> _loadUsageData() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('사용량 데이터 로드: 사용자 ID가 없음');
        return {};
      }
      
      debugPrint('사용량 데이터 로드 시작: userId=$userId');

      // Firestore에서 사용량 데이터 가져오기
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .get();

      if (!doc.exists) {
        debugPrint('사용량 데이터 로드: 문서가 존재하지 않음');
      return {};
    }

      final data = doc.data() as Map<String, dynamic>;
      debugPrint('Firestore 원본 데이터: $data');

      Map<String, dynamic> usage = {};
      
      // 'usage' 필드에서 데이터 추출 시도
      if (data.containsKey('usage') && data['usage'] is Map) {
        final usageData = data['usage'] as Map<String, dynamic>;
        usage = {
          'ocrPages': _parseIntSafely(usageData['ocrPages']),
          'ttsRequests': _parseIntSafely(usageData['ttsRequests']),
          'translatedChars': _parseIntSafely(usageData['translatedChars']),
          'storageUsageBytes': _parseIntSafely(usageData['storageUsageBytes']),
        };
      } else {
        // 최상위 필드에서도 확인
        usage = {
          'ocrPages': _parseIntSafely(data['ocrPages']),
          'ttsRequests': _parseIntSafely(data['ttsRequests']),
          'translatedChars': _parseIntSafely(data['translatedChars']),
          'storageUsageBytes': _parseIntSafely(data['storageUsageBytes']),
        };
      }
      
      debugPrint('로드된 사용량 데이터: $usage');
      return usage;
    } catch (e) {
      debugPrint('사용량 데이터 로드 중 오류: $e');
      return {};
    }
  }

  /// 안전한 정수 파싱
  int _parseIntSafely(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }

  /// 플래시카드 사용량 증가
  Future<bool> incrementFlashcardCount() async {
    // 플래시카드 사용량은 추적하지 않고 항상 true 반환
    // 실제 사용량 증가 코드 주석 처리
    /* 
    final usageData = await _loadUsageData();
    final currentUsage = usageData['flashcards'] ?? 0;
    
    // 사용량 증가
    usageData['flashcards'] = currentUsage + 1;
    await _saveUsageData(usageData);
    
    debugPrint('flashcards 사용량 증가: ${currentUsage + 1}/무제한');
    */
    return true;
  }
  
  /// 플래시카드 사용량 감소
  Future<void> decrementFlashcardCount() async {
    // 플래시카드 사용량은 추적하지 않음
    // 실제 사용량 감소 코드 주석 처리
    /*
    final usageData = await _loadUsageData();
    final currentUsage = usageData['flashcards'] ?? 0;
    
    if (currentUsage > 0) {
      usageData['flashcards'] = currentUsage - 1;
      await _saveUsageData(usageData);
      debugPrint('flashcards 사용량 감소: ${currentUsage - 1}/무제한');
    }
    */
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
    final int limit = _getFreePlanLimit('ocrPages');
    final int remaining = limit - usedPages;
    return remaining < 0 ? 0 : remaining;
  }

  /// OCR 페이지 사용량 얻기
  Future<int> getUsedOcrPages() async {
    final usageData = await _loadUsageData();
    return usageData['ocrPages'] ?? 0;
  }

  /// OCR 페이지를 추가할 수 있는지 확인
  Future<bool> canAddOcrPages(int pageCount) async {
    // 0 또는 음수의 페이지 요청은 항상 가능
    if (pageCount <= 0) return true;
    
    final usageData = await _loadUsageData();
    final int currentUsage = (usageData['ocrPages'] ?? 0) as int;
    final limit = _getFreePlanLimit('ocrPages');
    
    // 현재 남은 페이지 수 계산
    final int remainingPages = limit - currentUsage;
    
    // 하나라도 더 추가할 수 있는지 확인 (최소 1페이지 이상 처리 가능해야 함)
    return remainingPages > 0;
  }

  /// 저장 공간 사용량 재계산
  Future<int> recalculateStorageUsage() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return 0;
      
      debugPrint('저장 공간 사용량 재계산 시작: userId=$userId');
      
      // Firebase Storage에서 사용자 폴더 참조
      final storageRef = FirebaseStorage.instance.ref().child('users/$userId');
      int totalSize = 0;

      try {
        // 모든 파일 리스트 가져오기 (재귀적으로)
        Future<int> calculateFolderSize(Reference ref) async {
          int size = 0;
          try {
            final result = await ref.listAll();
            debugPrint('폴더 ${ref.fullPath}의 파일 수: ${result.items.length}');

            // 파일 크기 계산
            for (final item in result.items) {
              try {
                final metadata = await item.getMetadata();
                size += metadata.size ?? 0;
                debugPrint('파일 크기 추가: ${item.name} = ${metadata.size ?? 0} bytes');
              } catch (e) {
                debugPrint('파일 메타데이터 가져오기 실패: ${item.fullPath} - $e');
              }
            }

            // 하위 폴더 처리
            for (final prefix in result.prefixes) {
              size += await calculateFolderSize(prefix);
            }
          } catch (e) {
            debugPrint('폴더 처리 중 오류: ${ref.fullPath} - $e');
          }
          return size;
        }

        totalSize = await calculateFolderSize(storageRef);
        debugPrint('계산된 총 저장 공간: ${totalSize / 1024 / 1024}MB');

        // Firestore에 업데이트
        await _updateFirestoreUsage('storageUsageBytes', totalSize);
        
        return totalSize;
      } catch (e) {
        debugPrint('Firebase Storage 접근 실패: $e');
        return 0;
      }
    } catch (e) {
      debugPrint('저장 공간 계산 중 오류: $e');
      return 0;
    }
  }

  /// OCR 페이지 수 재계산 (업로드된 모든 이미지 수)
  Future<int> recalculateOcrPages() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return 0;

      debugPrint('OCR 페이지 수 재계산 시작: userId=$userId');

      // Firebase Storage에서 사용자의 이미지 폴더 참조
      final storageRef = FirebaseStorage.instance.ref().child('users/$userId');
      int totalPages = 0;

      try {
        // 재귀적으로 모든 이미지 파일 찾기
        Future<int> countImagesInFolder(Reference ref) async {
          int count = 0;
          try {
            final result = await ref.listAll();
            debugPrint('폴더 ${ref.fullPath}의 파일 수: ${result.items.length}');

            // 이미지 파일 카운트
            for (final item in result.items) {
              if (item.name.toLowerCase().endsWith('.jpg') || 
                  item.name.toLowerCase().endsWith('.jpeg') || 
                  item.name.toLowerCase().endsWith('.png')) {
                count++;
                debugPrint('이미지 파일 발견: ${item.name}');
              }
            }

            // 하위 폴더 처리
            for (final prefix in result.prefixes) {
              count += await countImagesInFolder(prefix);
            }
          } catch (e) {
            debugPrint('폴더 처리 중 오류: ${ref.fullPath} - $e');
          }
          return count;
        }

        totalPages = await countImagesInFolder(storageRef);
        debugPrint('계산된 총 OCR 페이지 수: $totalPages');

        // Firestore에 업데이트
        await _updateFirestoreUsage('ocrPages', totalPages);
        
        return totalPages;
      } catch (e) {
        debugPrint('Firebase Storage 접근 실패: $e');
        return 0;
      }
    } catch (e) {
      debugPrint('OCR 페이지 수 계산 중 오류: $e');
      return 0;
    }
  }

  /// 사용량 데이터 새로고침 (전체)
  Future<void> refreshAllUsage() async {
    try {
      debugPrint('전체 사용량 데이터 새로고침 시작');
      
      // 저장 공간과 OCR 페이지 수 재계산
      final storageUsage = await recalculateStorageUsage();
      final ocrPages = await recalculateOcrPages();
      
      debugPrint('재계산된 저장 공간: ${storageUsage / 1024 / 1024}MB');
      debugPrint('재계산된 OCR 페이지 수: $ocrPages');
      
      // 캐시 초기화
      await refreshCache();
      
      debugPrint('전체 사용량 데이터 새로고침 완료');
    } catch (e) {
      debugPrint('사용량 데이터 새로고침 중 오류: $e');
    }
  }

  /// 저장 공간 사용량 증가 (Firebase Storage 기반)
  Future<bool> checkAndAddStorageUsage(int bytes) async {
    try {
      // 현재 저장 공간 사용량 가져오기
      final currentUsage = await recalculateStorageUsage();
      final limit = _getFreePlanLimit('storageBytes');
      
      // 제한 체크
      if (currentUsage + bytes > limit) {
        debugPrint('저장 공간 한도 초과: ${currentUsage + bytes} > $limit');
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('저장 공간 사용량 증가 중 오류: $e');
      return false;
    }
  }

  /// OCR 페이지 사용량 증가 (Firebase Storage 기반)
  Future<bool> checkAndIncrementOcrPages(int pageCount) async {
    try {
      // 현재 OCR 페이지 수 가져오기
      final currentPages = await recalculateOcrPages();
      final limit = _getFreePlanLimit('ocrPages');
      
      // 제한 체크
      if (currentPages + pageCount > limit) {
        debugPrint('OCR 페이지 한도 초과: ${currentPages + pageCount} > $limit');
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('OCR 페이지 사용량 증가 중 오류: $e');
      return false;
    }
  }

  /// 저장 공간 사용량 초기화
  Future<void> resetStorageUsage() async {
    final usageData = await _loadUsageData();
    usageData['storageUsageBytes'] = 0;
    await _saveUsageData(usageData);
    debugPrint('저장 공간 사용량 초기화 완료');
    
    // 캐시 무효화
    invalidateCache();
  }

  /// 탈퇴 시 Firebase Storage 데이터 삭제
  Future<bool> deleteFirebaseStorageData(String userId) async {
    try {
      if (userId.isEmpty) {
        debugPrint('Firebase Storage 데이터 삭제 실패: 사용자 ID가 비어있음');
        return false;
      }
      
      // Firebase Storage 참조
      final FirebaseStorage storage = FirebaseStorage.instance;
      
      // 사용자별 경로 지정: users/{userId}/
      final userFolderRef = storage.ref().child('users/$userId');
      
      try {
        // 1. 사용자 폴더 모든 파일 리스트 가져오기
        final ListResult result = await userFolderRef.listAll();
        debugPrint('탈퇴한 사용자의 Firebase Storage 파일 ${result.items.length}개, 폴더 ${result.prefixes.length}개 발견');
        
        // 2. 모든 파일 삭제
        for (final Reference ref in result.items) {
          await ref.delete();
          debugPrint('파일 삭제됨: ${ref.fullPath}');
        }
        
        // 3. 하위 폴더 재귀적으로 처리
        for (final Reference prefix in result.prefixes) {
          // 하위 폴더 처리 (일반적으로 images 폴더가 있음)
          final ListResult subResult = await prefix.listAll();
          
          // 하위 폴더의 모든 파일 삭제
          for (final Reference subRef in subResult.items) {
            await subRef.delete();
            debugPrint('하위 폴더 파일 삭제됨: ${subRef.fullPath}');
          }
        }
        
        debugPrint('Firebase Storage에서 사용자 $userId의 데이터 삭제 완료');
        return true;
      } catch (e) {
        // 폴더가 없거나 권한이 없는 경우 등
        debugPrint('Firebase Storage 데이터 삭제 중 오류: $e');
        return false;
      }
    } catch (e) {
      debugPrint('Firebase Storage 데이터 삭제 실패: $e');
      return false;
    }
  }

  /// 앱 시작시 사용량 초기화
  Future<void> initializeUsage() async {
    await refreshAllUsage();
  }
} 