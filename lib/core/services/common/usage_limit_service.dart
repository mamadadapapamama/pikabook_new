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
        };
      }
      
      // Firebase에서 최신 사용량 가져오기
      final usage = await _loadUsageDataFromFirebase();
      final limits = await _loadLimitsFromFirebase();
      
      // 제한 도달 여부 확인
      final limitStatus = {
        'ocrLimitReached': (usage['ocrPages'] ?? 0) >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': (usage['ttsRequests'] ?? 0) >= (limits['ttsRequests'] ?? 0),
      };
      
      debugPrint('앱 시작시 제한 확인 결과: $limitStatus');
      return limitStatus;
      
    } catch (e) {
      debugPrint('앱 시작시 제한 확인 중 오류: $e');
      return {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
      };
    }
  }
  
  /// 2. 노트 생성 후 사용량 업데이트 및 제한 확인
  /// 사용량을 Firebase에 업데이트하고 제한 도달 여부를 반환
  Future<Map<String, bool>> updateUsageAfterNoteCreation({
    int ocrPages = 0,
    int ttsRequests = 0,
  }) async {
    try {
      debugPrint('노트 생성 후 사용량 업데이트 시작');
      
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('사용자 ID가 없음 - 업데이트 실패');
        return {
          'ocrLimitReached': false,
          'ttsLimitReached': false,
        };
      }
      
      // 현재 사용량 가져오기
      final currentUsage = await _loadUsageDataFromFirebase();
      
      // 새로운 사용량 계산
      final newUsage = {
        'ocrPages': (currentUsage['ocrPages'] ?? 0) + ocrPages,
        'ttsRequests': (currentUsage['ttsRequests'] ?? 0) + ttsRequests,
      };
      
      // Firebase에 업데이트
      await _firestore.collection('users').doc(userId).update({
        'usage.ocrPages': newUsage['ocrPages'],
        'usage.ttsRequests': newUsage['ttsRequests'],
        'usage.lastUpdated': FieldValue.serverTimestamp(),
      });
      
      debugPrint('사용량 업데이트 완료: $newUsage');
      
      // 제한 확인
      final limits = await _loadLimitsFromFirebase();
      final limitStatus = {
        'ocrLimitReached': (newUsage['ocrPages'] ?? 0) >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': (newUsage['ttsRequests'] ?? 0) >= (limits['ttsRequests'] ?? 0),
      };
      
      debugPrint('노트 생성 후 제한 확인 결과: $limitStatus');
      return limitStatus;
      
    } catch (e) {
      debugPrint('노트 생성 후 사용량 업데이트 중 오류: $e');
      return {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
      };
    }
  }
  
  /// 3. 설정 화면에서 사용량 조회
  /// 사용자가 명시적으로 사용량을 확인할 때 사용
  Future<Map<String, dynamic>> getUserUsageForSettings() async {
    try {
      debugPrint('📊 [UsageLimitService] 설정 화면 사용량 조회 시작');
      
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('❌ [UsageLimitService] 사용자 ID가 없음 - 기본값 반환');
        return _getDefaultUsageInfo();
      }
      
      debugPrint('📊 [UsageLimitService] 사용자 ID: $userId');
      
      // Firebase에서 최신 데이터 가져오기 (설정 화면에서는 항상 최신 정보)
      final usage = await _loadUsageDataFromFirebase();
      debugPrint('📊 [UsageLimitService] Firebase 사용량 데이터: $usage');
      
      final limits = await _loadLimitsFromFirebase(forceRefresh: true);
      debugPrint('📊 [UsageLimitService] Firebase 제한 데이터: $limits');
      
      // 제한 도달 여부
      final limitStatus = {
        'ocrLimitReached': (usage['ocrPages'] ?? 0) >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': (usage['ttsRequests'] ?? 0) >= (limits['ttsRequests'] ?? 0),
        'ocrLimit': limits['ocrPages'] ?? 0,
        'ttsLimit': limits['ttsRequests'] ?? 0,
      };
      
      // 사용량 퍼센트 계산
      final ocrPercentage = (limits['ocrPages'] ?? 0) > 0 ? 
        ((usage['ocrPages'] ?? 0).toDouble() / (limits['ocrPages'] ?? 1).toDouble() * 100.0).clamp(0.0, 100.0) : 0.0;
      final ttsPercentage = (limits['ttsRequests'] ?? 0) > 0 ? 
        ((usage['ttsRequests'] ?? 0).toDouble() / (limits['ttsRequests'] ?? 1).toDouble() * 100.0).clamp(0.0, 100.0) : 0.0;
        
      debugPrint('📊 [UsageLimitService] 계산된 퍼센트 - OCR: $ocrPercentage%, TTS: $ttsPercentage%');
      
      final result = {
        'usage': usage,
        'limits': limits,
        'usagePercentages': <String, double>{
          'ocr': ocrPercentage,
          'tts': ttsPercentage,
        },
        'limitStatus': limitStatus,
      };
      
      debugPrint('✅ [UsageLimitService] 설정 화면 사용량 조회 완료: $result');
      return result;
      
    } catch (e, stackTrace) {
      debugPrint('❌ [UsageLimitService] 설정 화면 사용량 조회 중 오류: $e');
      debugPrint('❌ [UsageLimitService] 스택 트레이스: $stackTrace');
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
        debugPrint('🔍 [UsageLimitService] _loadUsageDataFromFirebase: 사용자 ID 없음');
        return _getDefaultUsageData();
      }
      
      debugPrint('🔍 [UsageLimitService] _loadUsageDataFromFirebase: 사용자 ID $userId로 Firestore 조회');
      
      final doc = await _firestore.collection('users').doc(userId).get();
      
      if (!doc.exists) {
        debugPrint('🔍 [UsageLimitService] _loadUsageDataFromFirebase: 사용자 문서가 존재하지 않음');
        return _getDefaultUsageData();
      }
      
      final data = doc.data() as Map<String, dynamic>;
      debugPrint('🔍 [UsageLimitService] _loadUsageDataFromFirebase: 원본 문서 데이터: $data');
      
      // 'usage' 필드에서 데이터 추출
      Map<String, int> usageData = {};
      
      if (data.containsKey('usage') && data['usage'] is Map) {
        final usage = data['usage'] as Map<String, dynamic>;
        debugPrint('🔍 [UsageLimitService] _loadUsageDataFromFirebase: usage 필드 발견: $usage');
        usageData = {
          'ocrPages': _parseIntSafely(usage['ocrPages']),
          'ttsRequests': _parseIntSafely(usage['ttsRequests']),
        };
      } else {
        debugPrint('🔍 [UsageLimitService] _loadUsageDataFromFirebase: usage 필드 없음, 최상위 필드에서 확인');
        // 최상위 필드에서 확인
        usageData = {
          'ocrPages': _parseIntSafely(data['ocrPages']),
          'ttsRequests': _parseIntSafely(data['ttsRequests']),
        };
      }
      
      debugPrint('✅ [UsageLimitService] _loadUsageDataFromFirebase: 최종 사용량 데이터: $usageData');
      return usageData;
    } catch (e, stackTrace) {
      debugPrint('❌ [UsageLimitService] Firebase에서 사용량 데이터 로드 중 오류: $e');
      debugPrint('❌ [UsageLimitService] 스택 트레이스: $stackTrace');
      return _getDefaultUsageData();
    }
  }
  
  /// Firebase에서 제한 데이터 로드 (캐시 없음)
  Future<Map<String, int>> _loadLimitsFromFirebase({bool forceRefresh = false}) async {
    try {
      debugPrint('🔍 [UsageLimitService] _loadLimitsFromFirebase 시작');
      
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('🔍 [UsageLimitService] _loadLimitsFromFirebase: 사용자 ID 없음, 기본 제한 반환');
        return _getDefaultLimits();
      }
      
      debugPrint('🔍 [UsageLimitService] _loadLimitsFromFirebase: 사용자 ID $userId');
      
      // 1. 사용자별 커스텀 제한 확인
      debugPrint('🔍 [UsageLimitService] _loadLimitsFromFirebase: 1단계 - 커스텀 제한 확인');
      final customLimits = await _getUserCustomLimits(userId);
      debugPrint('🔍 [UsageLimitService] _loadLimitsFromFirebase: 커스텀 제한 결과: $customLimits');
      if (customLimits.isNotEmpty) {
        debugPrint('✅ [UsageLimitService] _loadLimitsFromFirebase: 커스텀 제한 사용: $customLimits');
        return customLimits;
      }
      
      // 2. 플랜 기반 제한 적용
      debugPrint('🔍 [UsageLimitService] _loadLimitsFromFirebase: 2단계 - 플랜 기반 제한 확인');
      final planService = PlanService();
      final planType = await planService.getCurrentPlanType(forceRefresh: forceRefresh);
      
      debugPrint('🔍 [UsageLimitService] _loadLimitsFromFirebase: 확인한 플랜 타입: $planType');
      debugPrint('🔍 [UsageLimitService] _loadLimitsFromFirebase: 해당 플랜의 제한값: ${PlanService.PLAN_LIMITS[planType]}');
      
      final limits = PlanService.PLAN_LIMITS[planType];
      if (limits != null) {
        final result = Map<String, int>.from(limits);
        debugPrint('✅ [UsageLimitService] _loadLimitsFromFirebase: 플랜 기반 제한 사용: $result');
        return result;
      }
      
      // 3. 기본 제한 적용
      debugPrint('🔍 [UsageLimitService] _loadLimitsFromFirebase: 3단계 - 기본 제한 적용');
      final defaultLimits = _getDefaultLimits();
      debugPrint('✅ [UsageLimitService] _loadLimitsFromFirebase: 기본 제한 사용: $defaultLimits');
      return defaultLimits;
    } catch (e, stackTrace) {
      debugPrint('❌ [UsageLimitService] _loadLimitsFromFirebase 오류: $e');
      debugPrint('❌ [UsageLimitService] _loadLimitsFromFirebase 스택 트레이스: $stackTrace');
      final defaultLimits = _getDefaultLimits();
      debugPrint('🔄 [UsageLimitService] _loadLimitsFromFirebase: 오류로 인한 기본 제한 사용: $defaultLimits');
      return defaultLimits;
    }
  }
  
  /// 사용자별 커스텀 제한 가져오기
  Future<Map<String, int>> _getUserCustomLimits(String userId) async {
    try {
      debugPrint('🔍 [UsageLimitService] _getUserCustomLimits: $userId로 user_limits 컬렉션 조회');
      
      final doc = await _firestore
          .collection(_CUSTOM_LIMITS_COLLECTION)
          .doc(userId)
          .get();
          
      if (!doc.exists) {
        debugPrint('🔍 [UsageLimitService] _getUserCustomLimits: user_limits 문서가 존재하지 않음');
        return {};
      }
      
      final data = doc.data() as Map<String, dynamic>;
      debugPrint('🔍 [UsageLimitService] _getUserCustomLimits: user_limits 문서 데이터: $data');
      
      final limits = <String, int>{};
      
      if (data.containsKey('ocrPages')) limits['ocrPages'] = _parseIntSafely(data['ocrPages']);
      if (data.containsKey('ttsRequests')) limits['ttsRequests'] = _parseIntSafely(data['ttsRequests']);
      
      debugPrint('✅ [UsageLimitService] _getUserCustomLimits: 파싱된 커스텀 제한: $limits');
      return limits;
    } catch (e, stackTrace) {
      debugPrint('❌ [UsageLimitService] _getUserCustomLimits 오류: $e');
      debugPrint('❌ [UsageLimitService] _getUserCustomLimits 스택 트레이스: $stackTrace');
      return {};
    }
  }
  
  /// 기본 사용량 데이터 (PlanService에서 가져오기)
  Map<String, int> _getDefaultUsageData() {
    return {
      'ocrPages': 0,
      'ttsRequests': 0,
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
      'usagePercentages': <String, double>{
        'ocr': 0.0,
        'tts': 0.0,
      },
      'limitStatus': {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'ocrLimit': defaultLimits['ocrPages'] ?? 10,
        'ttsLimit': defaultLimits['ttsRequests'] ?? 30,
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
    final noteExceed = limitStatus['ocrLimitReached'] ?? false;
    
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
  
  /// 사용량 한도 도달 여부 확인 (배너용)
  Future<bool> hasReachedAnyLimit() async {
    try {
      final limitStatus = await checkInitialLimitStatus();
      final ocrReached = limitStatus['ocrLimitReached'] ?? false;
      final ttsReached = limitStatus['ttsLimitReached'] ?? false;
      
      return ocrReached || ttsReached;
    } catch (e) {
      debugPrint('사용량 한도 확인 중 오류: $e');
      return false;
    }
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
  
  
} 