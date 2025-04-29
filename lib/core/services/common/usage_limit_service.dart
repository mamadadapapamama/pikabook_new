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
      
      await _firestore.collection('users').doc(userId).set({
        'usage': {
          key: value,
          'lastUpdated': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
      
      debugPrint('Firestore 사용량 업데이트: $key=$value');
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
  
  /// 각 기능별 사용량 비율(%) 계산
  Future<Map<String, double>> getUsagePercentages() async {
    try {
      final usageData = await getUserUsage(forceRefresh: true);  // 강제로 최신 데이터 가져오기
      final planType = await planService.getCurrentPlanType();
      final limits = PlanService.PLAN_LIMITS[planType] ?? _getFreePlanLimits();
      
      // 각 항목별 사용량 비율 계산
      final ocrUsage = usageData['ocrPages'] ?? 0;
      final ttsUsage = usageData['ttsRequests'] ?? 0;
      final translatedChars = usageData['translatedChars'] ?? 0;
      final storageUsageBytes = usageData['storageUsageBytes'] ?? 0;
      
      // 디버그 로그 추가
      debugPrint('=== 사용량 계산 디버그 ===');
      debugPrint('현재 플랜: $planType');
      debugPrint('OCR 사용량: $ocrUsage / ${limits['ocrPages']} = ${(ocrUsage / (limits['ocrPages'] ?? 1) * 100).toStringAsFixed(2)}%');
      debugPrint('TTS 사용량: $ttsUsage / ${limits['ttsRequests']} = ${(ttsUsage / (limits['ttsRequests'] ?? 1) * 100).toStringAsFixed(2)}%');
      debugPrint('번역 사용량: $translatedChars / ${limits['translatedChars']} = ${(translatedChars / (limits['translatedChars'] ?? 1) * 100).toStringAsFixed(2)}%');
      debugPrint('저장공간 사용량: $storageUsageBytes / ${limits['storageBytes']} = ${(storageUsageBytes / (limits['storageBytes'] ?? 1) * 100).toStringAsFixed(2)}%');
      debugPrint('전체 사용량 데이터: $usageData');
      debugPrint('제한값: $limits');
      
      // 사용량 비율 계산 (소수점 2자리까지)
      final Map<String, double> percentages = {
        'ocr': double.parse(((ocrUsage / (limits['ocrPages'] ?? 1)) * 100).toStringAsFixed(2)),
        'tts': double.parse(((ttsUsage / (limits['ttsRequests'] ?? 1)) * 100).toStringAsFixed(2)),
        'translation': double.parse(((translatedChars / (limits['translatedChars'] ?? 1)) * 100).toStringAsFixed(2)),
        'storage': double.parse(((storageUsageBytes / (limits['storageBytes'] ?? 1)) * 100).toStringAsFixed(2)),
        'dictionary': 0.0,
        'flashcard': 0.0,
        'note': 0.0,
        'page': 0.0,
      };
      
      debugPrint('계산된 비율: $percentages');
      return percentages;
    } catch (e) {
      debugPrint('사용량 비율 계산 중 오류: $e');
      return {
        'ocr': 0.0,
        'tts': 0.0,
        'translation': 0.0,
        'storage': 0.0,
        'dictionary': 0.0,
        'flashcard': 0.0,
        'note': 0.0,
        'page': 0.0,
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
      Map<String, dynamic> usage = {};
      
      // 'usage' 필드가 있는 경우
      if (data.containsKey('usage') && data['usage'] is Map) {
        usage = Map<String, dynamic>.from(data['usage'] as Map);
      } else {
        // 직접 필드에서 데이터 추출
        usage = {
          'ocrPages': data['ocrPages'] ?? 0,
          'ttsRequests': data['ttsRequests'] ?? 0,
          'translatedChars': data['translatedChars'] ?? 0,
          'storageUsageBytes': data['storageUsageBytes'] ?? 0,
        };
      }
      
      // 데이터 타입 확인 및 변환
      usage = {
        'ocrPages': int.tryParse(usage['ocrPages']?.toString() ?? '0') ?? 0,
        'ttsRequests': int.tryParse(usage['ttsRequests']?.toString() ?? '0') ?? 0,
        'translatedChars': int.tryParse(usage['translatedChars']?.toString() ?? '0') ?? 0,
        'storageUsageBytes': int.tryParse(usage['storageUsageBytes']?.toString() ?? '0') ?? 0,
      };
      
      debugPrint('사용량 데이터 로드 완료: $usage');
      return usage;
    } catch (e) {
      debugPrint('사용량 데이터 로드 중 오류: $e');
      return {};
    }
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
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${appDir.path}/images');
      
      if (!await imageDir.exists()) {
        debugPrint('이미지 디렉토리가 존재하지 않음');
        return 0;
      }
      
      int totalSize = 0;
      int fileCount = 0;
      final limit = _getFreePlanLimit('storageBytes');
      
      debugPrint('저장 공간 사용량 재계산 시작...');
      
      await for (final entity in imageDir.list(recursive: true)) {
        if (entity is File) {
          final fileSize = await entity.length();
          totalSize += fileSize;
          fileCount++;
          
          if (fileCount % 20 == 0) { // 20개 파일마다 로그 출력
            debugPrint('진행 중: $fileCount개 파일 처리, 현재 크기: ${(totalSize / 1024 / 1024).toStringAsFixed(2)}MB');
          }
        }
      }
      
      // 이전 사용량 저장
      final previousUsage = await _loadUsageData();
      final oldStorageUsage = previousUsage['storageUsageBytes'] ?? 0;
      
      // 재계산된 값으로 저장 공간 사용량 업데이트
      await resetStorageUsage();
      await addStorageUsage(totalSize);
      
      final limitInMB = (limit / (1024 * 1024)).toStringAsFixed(0);
      final totalMB = (totalSize / (1024 * 1024)).toStringAsFixed(2);
      final oldMB = (oldStorageUsage / (1024 * 1024)).toStringAsFixed(2);
      final percentUsed = ((totalSize * 100.0) / limit).toStringAsFixed(2);
      
      debugPrint('저장 공간 사용량 재계산 완료: $fileCount개 파일');
      debugPrint('이전: ${oldMB}MB → 현재: ${totalMB}MB (제한: ${limitInMB}MB)');
      debugPrint('총 사용률: $percentUsed% (${totalSize}바이트/${limit}바이트)');
      
      return totalSize;
    } catch (e) {
      debugPrint('저장 공간 사용량 재계산 중 오류: $e');
      return 0;
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
} 