import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';
import 'plan_service.dart';

/// 사용량 제한 관리 서비스 (개선된 버전)
/// 3가지 호출 시점에 최적화:
/// 1. 앱 시작시 (Initialization)
/// 2. 노트 생성 후 (Post Note Creation)  
/// 3. 설정 화면 (Settings Screen)
/// 4. TTS 재생 완료 후 (사용량 증가만)

class UsageLimitService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // 싱글톤 패턴 구현
  static final UsageLimitService _instance = UsageLimitService._internal();
  factory UsageLimitService() => _instance;
  
  UsageLimitService._internal();
  
  // 사용자별 커스텀 제한 설정을 위한 Firestore 컬렉션
  static const String _CUSTOM_LIMITS_COLLECTION = 'user_limits';
  
  // 현재 사용자 ID 가져오기
  String? get _currentUserId => _auth.currentUser?.uid;
  
  /// 1. 앱 시작시 제한 확인 (캐시 없이 새로 확인)
  /// 제한 도달 시 UI 상태를 결정하기 위한 메서드
  Future<Map<String, bool>> checkInitialLimitStatus() async {
    try {
      debugPrint('앱 시작시 제한 확인 시작 (캐시 없이 새로 확인)');
      
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('사용자 ID가 없음 - 모든 제한 false 반환');
        return {
          'ocrLimitReached': false,
          'ttsLimitReached': false,
          'translationLimitReached': false,
          'storageLimitReached': false,
        };
      }
      
      // Firebase에서 최신 사용량 가져오기
      final usage = await _loadUsageDataFromFirebase();
      final limits = await _loadLimitsFromFirebase();
      
      // 제한 도달 여부 확인
      final limitStatus = {
        'ocrLimitReached': (usage['ocrPages'] ?? 0) >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': (usage['ttsRequests'] ?? 0) >= (limits['ttsRequests'] ?? 0),
        'translationLimitReached': (usage['translatedChars'] ?? 0) >= (limits['translatedChars'] ?? 0),
        'storageLimitReached': (usage['storageUsageBytes'] ?? 0) >= (limits['storageBytes'] ?? 0),
      };
      
      debugPrint('앱 시작시 제한 확인 결과: $limitStatus');
      return limitStatus;
      
    } catch (e) {
      debugPrint('앱 시작시 제한 확인 중 오류: $e');
      return {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'translationLimitReached': false,
        'storageLimitReached': false,
      };
    }
  }
  
  /// 2. 노트 생성 후 사용량 업데이트 및 제한 확인
  /// 사용량을 Firebase에 업데이트하고 제한 도달 여부를 반환
  Future<Map<String, bool>> updateUsageAfterNoteCreation({
    int ocrPages = 0,
    int ttsRequests = 0,
    int translatedChars = 0,
    int storageBytes = 0,
  }) async {
    try {
      debugPrint('노트 생성 후 사용량 업데이트 시작');
      
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('사용자 ID가 없음 - 업데이트 실패');
        return {
          'ocrLimitReached': false,
          'ttsLimitReached': false,
          'translationLimitReached': false,
          'storageLimitReached': false,
        };
      }
      
      // 현재 사용량 가져오기
      final currentUsage = await _loadUsageDataFromFirebase();
      
      // 새로운 사용량 계산
      final newUsage = {
        'ocrPages': (currentUsage['ocrPages'] ?? 0) + ocrPages,
        'ttsRequests': (currentUsage['ttsRequests'] ?? 0) + ttsRequests,
        'translatedChars': (currentUsage['translatedChars'] ?? 0) + translatedChars,
        'storageUsageBytes': (currentUsage['storageUsageBytes'] ?? 0) + storageBytes,
      };
      
      // Firebase에 업데이트
      await _firestore.collection('users').doc(userId).update({
        'usage.ocrPages': newUsage['ocrPages'],
        'usage.ttsRequests': newUsage['ttsRequests'],
        'usage.translatedChars': newUsage['translatedChars'],
        'usage.storageUsageBytes': newUsage['storageUsageBytes'],
        'usage.lastUpdated': FieldValue.serverTimestamp(),
      });
      
      debugPrint('사용량 업데이트 완료: $newUsage');
      
      // 제한 확인
      final limits = await _loadLimitsFromFirebase();
      final limitStatus = {
        'ocrLimitReached': (newUsage['ocrPages'] ?? 0) >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': (newUsage['ttsRequests'] ?? 0) >= (limits['ttsRequests'] ?? 0),
        'translationLimitReached': (newUsage['translatedChars'] ?? 0) >= (limits['translatedChars'] ?? 0),
        'storageLimitReached': (newUsage['storageUsageBytes'] ?? 0) >= (limits['storageBytes'] ?? 0),
      };
      
      debugPrint('노트 생성 후 제한 확인 결과: $limitStatus');
      return limitStatus;
      
    } catch (e) {
      debugPrint('노트 생성 후 사용량 업데이트 중 오류: $e');
      return {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'translationLimitReached': false,
        'storageLimitReached': false,
      };
    }
  }
  
  /// 3. 설정 화면에서 사용량 조회
  /// 사용자가 명시적으로 사용량을 확인할 때 사용
  Future<Map<String, dynamic>> getUserUsageForSettings() async {
    try {
      debugPrint('설정 화면 사용량 조회 시작');
      
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('사용자 ID가 없음 - 기본값 반환');
        return _getDefaultUsageInfo();
      }
      
      // Firebase에서 최신 데이터 가져오기
      final usage = await _loadUsageDataFromFirebase();
      final limits = await _loadLimitsFromFirebase();
      
      // 사용률 계산
      final usagePercentages = {
        'ocr': (limits['ocrPages'] ?? 0) > 0 ? ((usage['ocrPages'] ?? 0) / (limits['ocrPages'] ?? 1) * 100).clamp(0, 100) : 0.0,
        'tts': (limits['ttsRequests'] ?? 0) > 0 ? ((usage['ttsRequests'] ?? 0) / (limits['ttsRequests'] ?? 1) * 100).clamp(0, 100) : 0.0,
        'translation': (limits['translatedChars'] ?? 0) > 0 ? ((usage['translatedChars'] ?? 0) / (limits['translatedChars'] ?? 1) * 100).clamp(0, 100) : 0.0,
        'storage': (limits['storageBytes'] ?? 0) > 0 ? ((usage['storageUsageBytes'] ?? 0) / (limits['storageBytes'] ?? 1) * 100).clamp(0, 100) : 0.0,
      };
      
      // 제한 도달 여부
      final limitStatus = {
        'ocrLimitReached': (usage['ocrPages'] ?? 0) >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': (usage['ttsRequests'] ?? 0) >= (limits['ttsRequests'] ?? 0),
        'translationLimitReached': (usage['translatedChars'] ?? 0) >= (limits['translatedChars'] ?? 0),
        'storageLimitReached': (usage['storageUsageBytes'] ?? 0) >= (limits['storageBytes'] ?? 0),
        'ocrLimit': limits['ocrPages'] ?? 0,
        'ttsLimit': limits['ttsRequests'] ?? 0,
        'translationLimit': limits['translatedChars'] ?? 0,
        'storageLimit': limits['storageBytes'] ?? 0,
      };
      
      final result = {
        'usage': usage,
        'limits': limits,
        'usagePercentages': usagePercentages,
        'limitStatus': limitStatus,
      };
      
      debugPrint('설정 화면 사용량 조회 완료: $result');
      return result;
      
    } catch (e) {
      debugPrint('설정 화면 사용량 조회 중 오류: $e');
      return _getDefaultUsageInfo();
    }
  }
  
  /// 4. TTS 재생 완료 후 사용량 증가
  /// TTS 재생이 성공적으로 완료된 후 호출하여 사용량을 1 증가시킴
  Future<bool> incrementTtsUsageAfterPlayback() async {
    try {
      debugPrint('TTS 재생 완료 후 사용량 증가 시작');
      
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('사용자 ID가 없음 - 사용량 증가 건너뜀');
        return true;
      }
      
      // 현재 사용량 가져오기
      final currentUsage = await _loadUsageDataFromFirebase();
      final newTtsUsage = (currentUsage['ttsRequests'] ?? 0) + 1;
      
      // Firebase에 업데이트
      await _firestore.collection('users').doc(userId).update({
        'usage.ttsRequests': newTtsUsage,
        'usage.lastUpdated': FieldValue.serverTimestamp(),
      });
      
      debugPrint('TTS 사용량 증가 완료: $newTtsUsage');
      return true;
      
    } catch (e) {
      debugPrint('TTS 사용량 증가 중 오류: $e');
      return false;
    }
  }
  
  /// Firebase에서 사용량 데이터 로드 (캐시 없음)
  Future<Map<String, int>> _loadUsageDataFromFirebase() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return _getDefaultUsageData();
      }
      
      final doc = await _firestore.collection('users').doc(userId).get();
      
      if (!doc.exists) {
        return _getDefaultUsageData();
      }
      
      final data = doc.data() as Map<String, dynamic>;
      
      // 'usage' 필드에서 데이터 추출
      Map<String, int> usageData = {};
      
      if (data.containsKey('usage') && data['usage'] is Map) {
        final usage = data['usage'] as Map<String, dynamic>;
        usageData = {
          'ocrPages': _parseIntSafely(usage['ocrPages']),
          'ttsRequests': _parseIntSafely(usage['ttsRequests']),
          'translatedChars': _parseIntSafely(usage['translatedChars']),
          'storageUsageBytes': _parseIntSafely(usage['storageUsageBytes']),
        };
      } else {
        // 최상위 필드에서 확인
        usageData = {
          'ocrPages': _parseIntSafely(data['ocrPages']),
          'ttsRequests': _parseIntSafely(data['ttsRequests']),
          'translatedChars': _parseIntSafely(data['translatedChars']),
          'storageUsageBytes': _parseIntSafely(data['storageUsageBytes']),
        };
      }
      
      return usageData;
    } catch (e) {
      debugPrint('Firebase에서 사용량 데이터 로드 중 오류: $e');
      return _getDefaultUsageData();
    }
  }
  
  /// Firebase에서 제한 데이터 로드 (캐시 없음)
  Future<Map<String, int>> _loadLimitsFromFirebase() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return _getDefaultLimits();
      }
      
      // 1. 사용자별 커스텀 제한 확인
      final customLimits = await _getUserCustomLimits(userId);
      if (customLimits.isNotEmpty) {
        return customLimits;
      }
      
      // 2. 플랜 기반 제한 적용
      final planService = PlanService();
      final planType = await planService.getCurrentPlanType();
      
      final limits = PlanService.PLAN_LIMITS[planType];
      if (limits != null) {
        return Map<String, int>.from(limits);
      }
      
      // 3. 기본 제한 적용
      return _getDefaultLimits();
    } catch (e) {
      debugPrint('Firebase에서 제한 데이터 로드 중 오류: $e');
      return _getDefaultLimits();
    }
  }
  
  /// 사용자별 커스텀 제한 가져오기
  Future<Map<String, int>> _getUserCustomLimits(String userId) async {
    try {
      final doc = await _firestore
          .collection(_CUSTOM_LIMITS_COLLECTION)
          .doc(userId)
          .get();
          
      if (!doc.exists) {
        return {};
      }
      
      final data = doc.data() as Map<String, dynamic>;
      final limits = <String, int>{};
      
      if (data.containsKey('ocrPages')) limits['ocrPages'] = _parseIntSafely(data['ocrPages']);
      if (data.containsKey('ttsRequests')) limits['ttsRequests'] = _parseIntSafely(data['ttsRequests']);
      if (data.containsKey('translatedChars')) limits['translatedChars'] = _parseIntSafely(data['translatedChars']);
      if (data.containsKey('storageBytes')) limits['storageBytes'] = _parseIntSafely(data['storageBytes']);
      
      return limits;
    } catch (e) {
      debugPrint('커스텀 제한 로드 오류: $e');
      return {};
    }
  }
  
  /// 기본 사용량 데이터 (PlanService에서 가져오기)
  Map<String, int> _getDefaultUsageData() {
    return {
      'ocrPages': 0,
      'ttsRequests': 0,
      'translatedChars': 0,
      'storageUsageBytes': 0,
    };
  }
  
  /// 기본 제한 값 (PlanService에서 가져오기)
  Map<String, int> _getDefaultLimits() {
    return Map<String, int>.from(PlanService.PLAN_LIMITS[PlanService.PLAN_FREE]!);
  }
  
  /// 기본 사용량 정보 (설정 화면용)
  Map<String, dynamic> _getDefaultUsageInfo() {
    final defaultLimits = _getDefaultLimits();
    return {
      'usage': _getDefaultUsageData(),
      'limits': defaultLimits,
      'usagePercentages': {
        'ocr': 0.0,
        'tts': 0.0,
        'translation': 0.0,
        'storage': 0.0,
      },
      'limitStatus': {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'translationLimitReached': false,
        'storageLimitReached': false,
        'ocrLimit': defaultLimits['ocrPages'] ?? 30,
        'ttsLimit': defaultLimits['ttsRequests'] ?? 100,
        'translationLimit': defaultLimits['translatedChars'] ?? 10000,
        'storageLimit': defaultLimits['storageBytes'] ?? 52428800,
      },
    };
  }
  
  /// 안전한 정수 파싱
  int _parseIntSafely(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }
  
  // ========== PlanService 호환성을 위한 메서드들 ==========
  
  /// 사용량 비율 계산 (PlanService 호환성)
  Future<Map<String, double>> getUsagePercentages() async {
    final result = await getUserUsageForSettings();
    return Map<String, double>.from(result['usagePercentages'] as Map);
  }
  
  /// 제한 상태 확인 (PlanService 호환성)
  Future<Map<String, dynamic>> checkFreeLimits({bool withBuffer = false}) async {
    final result = await getUserUsageForSettings();
    return result['limitStatus'] as Map<String, dynamic>;
  }
  
  // ========== 기존 호환성을 위한 메서드들 (향후 제거 예정) ==========
  
  /// 기존 코드 호환성을 위한 메서드 (deprecated)
  /// TODO: PlanService.getCurrentUsage()에서 사용 중 - 교체 후 제거 예정
  @deprecated
  Future<Map<String, dynamic>> getUserUsage({bool forceRefresh = false}) async {
    debugPrint('⚠️ getUserUsage는 deprecated입니다. getUserUsageForSettings()를 사용하세요.');
    final result = await getUserUsageForSettings();
    return result['usage'] as Map<String, dynamic>;
  }
  
  /// 기존 코드 호환성을 위한 메서드 (deprecated)
  /// TODO: 사용처 확인 후 제거 예정
  @deprecated
  Future<Map<String, int>> getCurrentLimits() async {
    debugPrint('⚠️ getCurrentLimits는 deprecated입니다. _loadLimitsFromFirebase()를 사용하세요.');
    return await _loadLimitsFromFirebase();
  }
  
  /// 기존 코드 호환성을 위한 메서드 (deprecated)
  /// TODO: 사용처 확인 후 제거 예정
  @deprecated
  Future<Map<String, int>> getUserLimits() async {
    debugPrint('⚠️ getUserLimits는 deprecated입니다. _loadLimitsFromFirebase()를 사용하세요.');
    return await _loadLimitsFromFirebase();
  }
  
  /// 기존 코드 호환성을 위한 메서드 (deprecated)
  /// TODO: 새로운 updateUsageAfterNoteCreation() 방식으로 교체 후 제거 예정
  @deprecated
  Future<bool> incrementUsage(String key, int amount, {bool allowOverLimit = false}) async {
    debugPrint('⚠️ incrementUsage는 deprecated입니다. updateUsageAfterNoteCreation()를 사용하세요.');
    
    Map<String, int> updates = {};
    updates[key] = amount;
    
    await updateUsageAfterNoteCreation(
      ocrPages: updates['ocrPages'] ?? 0,
      ttsRequests: updates['ttsRequests'] ?? 0,
      translatedChars: updates['translatedChars'] ?? 0,
      storageBytes: updates['storageUsageBytes'] ?? 0,
    );
    
    return true;
  }
  
  /// 기존 코드 호환성을 위한 메서드 (deprecated)
  /// TODO: app.dart에서 사용 중 - checkInitialLimitStatus()로 교체 후 제거 예정
  @deprecated
  Future<Map<String, bool>> checkUsageLimitFlags({bool withBuffer = false}) async {
    debugPrint('⚠️ checkUsageLimitFlags는 deprecated입니다. checkInitialLimitStatus()를 사용하세요.');
    final limitStatus = await checkInitialLimitStatus();
    
    final ttsExceed = limitStatus['ttsLimitReached'] ?? false;
    final noteExceed = 
        (limitStatus['ocrLimitReached'] ?? false) ||
        (limitStatus['translationLimitReached'] ?? false) ||
        (limitStatus['storageLimitReached'] ?? false);
    
    return {
      'ttsExceed': ttsExceed,
      'noteExceed': noteExceed,
    };
  }
  
  /// 기존 코드 호환성을 위한 메서드 (deprecated)
  /// TODO: UsageDialog, app.dart에서 사용 중 - getUserUsageForSettings()로 교체 후 제거 예정
  @deprecated
  Future<Map<String, dynamic>> getUsageInfo({bool withBuffer = false}) async {
    debugPrint('⚠️ getUsageInfo는 deprecated입니다. getUserUsageForSettings()를 사용하세요.');
    final result = await getUserUsageForSettings();
    return {
      'percentages': result['usagePercentages'],
      'limitStatus': result['limitStatus'],
    };
  }
  
  /// 모든 사용량 초기화
  Future<void> resetAllUsage() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return;
      
      await _firestore.collection('users').doc(userId).update({
        'usage.ocrPages': 0,
        'usage.ttsRequests': 0,
        'usage.translatedChars': 0,
        'usage.storageUsageBytes': 0,
        'usage.lastUpdated': FieldValue.serverTimestamp(),
      });
      
      debugPrint('모든 사용량 초기화 완료');
    } catch (e) {
      debugPrint('사용량 초기화 중 오류: $e');
    }
  }
  
  /// 월간 사용량 초기화 (Free 플랜)
  Future<void> resetMonthlyUsage() async {
    try {
      final planService = PlanService();
      final planType = await planService.getCurrentPlanType();
      
      if (planType != PlanService.PLAN_FREE) {
        debugPrint('Free 플랜이 아니므로 월간 초기화 건너뜀');
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final resetKey = 'monthly_reset_${_currentUserId ?? 'anonymous'}';
      final lastResetStr = prefs.getString(resetKey);
      
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      
      if (lastResetStr == null) {
        await resetAllUsage();
        await prefs.setString(resetKey, currentMonth.toIso8601String());
        debugPrint('최초 월간 사용량 초기화 완료');
        return;
      }
      
      try {
        final lastReset = DateTime.parse(lastResetStr);
        
        if (lastReset.year != currentMonth.year || lastReset.month != currentMonth.month) {
          await resetAllUsage();
          await prefs.setString(resetKey, currentMonth.toIso8601String());
          debugPrint('월간 사용량 초기화 완료');
        }
      } catch (e) {
        await resetAllUsage();
        await prefs.setString(resetKey, currentMonth.toIso8601String());
        debugPrint('날짜 오류로 인한 월간 사용량 초기화');
      }
    } catch (e) {
      debugPrint('월간 사용량 초기화 중 오류: $e');
    }
  }
  
  /// 탈퇴 시 Firebase Storage 데이터 삭제
  Future<bool> deleteFirebaseStorageData(String userId) async {
    try {
      if (userId.isEmpty) {
        debugPrint('Firebase Storage 데이터 삭제 실패: 사용자 ID가 비어있음');
        return false;
      }
      
      final userFolderRef = _storage.ref().child('users/$userId');
      
      try {
        final result = await userFolderRef.listAll();
        debugPrint('탈퇴한 사용자의 Firebase Storage 파일 ${result.items.length}개, 폴더 ${result.prefixes.length}개 발견');
        
        for (final item in result.items) {
          await item.delete();
          debugPrint('파일 삭제됨: ${item.fullPath}');
        }
        
        for (final prefix in result.prefixes) {
          final subResult = await prefix.listAll();
          
          for (final subItem in subResult.items) {
            await subItem.delete();
            debugPrint('하위 폴더 파일 삭제됨: ${subItem.fullPath}');
          }
        }
        
        debugPrint('Firebase Storage 데이터 삭제 완료');
        return true;
      } catch (e) {
        debugPrint('Firebase Storage 데이터 삭제 중 오류: $e');
        return false;
      }
    } catch (e) {
      debugPrint('Firebase Storage 데이터 삭제 실패: $e');
      return false;
    }
  }
  
  // ========== TTS 관련 기존 호환성을 위한 메서드들 (향후 제거 예정) ==========
  
  /// 기존 코드 호환성을 위한 메서드 (deprecated)
  /// TODO: TtsApiService에서 사용 중 - incrementTtsUsageAfterPlayback()로 교체 후 제거 예정
  @deprecated
  Future<bool> incrementTtsCharCount(int count) async {
    debugPrint('⚠️ incrementTtsCharCount는 deprecated입니다. incrementTtsUsageAfterPlayback()를 사용하세요.');
    return await incrementTtsUsageAfterPlayback();
  }
  
  /// 기존 코드 호환성을 위한 메서드 (deprecated)
  /// TODO: TtsApiService에서 사용 중 - getCurrentTtsUsage()로 교체 후 제거 예정
  @deprecated
  Future<int> getTtsUsage() async {
    debugPrint('⚠️ getTtsUsage는 deprecated입니다. getCurrentTtsUsage()를 사용하세요.');
    final usage = await _loadUsageDataFromFirebase();
    return usage['ttsRequests'] ?? 0;
  }
  
  /// 기존 코드 호환성을 위한 메서드 (deprecated)
  /// TODO: 캐시 시스템 제거로 인해 더 이상 필요 없음
  @deprecated
  void invalidateCache() {
    debugPrint('⚠️ invalidateCache는 deprecated입니다. 캐시 시스템이 제거되었습니다.');
    // 아무것도 하지 않음 - 캐시가 없으므로
  }
} 