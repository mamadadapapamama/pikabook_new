import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';
import 'plan_service.dart';

/// 사용량 제한 관리 서비스
/// 사용자의 사용량을 추적하고 제한을 적용합니다.
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
  
  // 캐시 관련 변수
  Map<String, dynamic>? _cachedUsageData;
  DateTime? _lastFetchTime;
  
  /// 사용량 데이터 가져오기 (캐시 사용)
  Future<Map<String, dynamic>> getUserUsage({bool forceRefresh = false}) async {
    // 캐시 사용 여부 결정
    final now = DateTime.now();
    final useCache = !forceRefresh && 
                    _cachedUsageData != null && 
                    _lastFetchTime != null &&
                    now.difference(_lastFetchTime!).inSeconds < 5; // 5초 캐시
    
    if (useCache) {
      debugPrint('사용량 데이터 캐시 사용');
      return Map<String, dynamic>.from(_cachedUsageData!);
    }
    
    // 사용량 데이터 로드
    final usageData = await _loadUsageData();
    
    // 결과 캐싱
    _cachedUsageData = usageData;
    _lastFetchTime = now;
    
    return usageData;
  }
  
  /// Firestore에서 사용량 데이터 로드
  Future<Map<String, dynamic>> _loadUsageData() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('사용량 데이터 로드: 사용자 ID가 없음');
        return _getDefaultUsageData();
      }
      
      debugPrint('Firestore에서 사용량 데이터 로드 시작: userId=$userId');
      
      // Firestore에서 사용자 문서 가져오기
      final doc = await _firestore.collection('users').doc(userId).get();
      
      if (!doc.exists) {
        debugPrint('사용자 문서가 존재하지 않음');
        return _getDefaultUsageData();
      }
      
      final data = doc.data() as Map<String, dynamic>;
      
      // 'usage' 필드에서 데이터 추출
      Map<String, dynamic> usageData = {};
      
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
      
      debugPrint('로드된 사용량 데이터: $usageData');
      return usageData;
    } catch (e) {
      debugPrint('사용량 데이터 로드 중 오류: $e');
      return _getDefaultUsageData();
    }
  }
  
  /// 기본 사용량 데이터
  Map<String, dynamic> _getDefaultUsageData() {
    return {
      'ocrPages': 0,
      'ttsRequests': 0,
      'translatedChars': 0,
      'storageUsageBytes': 0,
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
  
  /// 현재 플랜 제한 가져오기
  Future<Map<String, int>> getCurrentLimits() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return _getDefaultLimits();
      }
      
      // 1. 사용자별 커스텀 제한 확인
      final customLimits = await _getUserCustomLimits(userId);
      if (customLimits.isNotEmpty) {
        debugPrint('사용자별 커스텀 제한 적용: $customLimits');
        return customLimits;
      }
      
      // 2. 플랜 기반 제한 적용
      final planService = PlanService();
      final planType = await planService.getCurrentPlanType();
      
      final limits = PlanService.PLAN_LIMITS[planType];
      if (limits != null) {
        debugPrint('플랜 기반 제한 적용 ($planType): $limits');
        return Map<String, int>.from(limits);
      }
      
      // 3. 기본 제한 적용
      return _getDefaultLimits();
    } catch (e) {
      debugPrint('제한 가져오기 오류: $e');
      return _getDefaultLimits();
    }
  }
  
  /// 사용자 제한값 가져오기 (TTS 서비스 호환용)
  Future<Map<String, int>> getUserLimits() async {
    // 내부적으로 getCurrentLimits() 호출
    return await getCurrentLimits();
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
  
  /// 기본 제한 값
  Map<String, int> _getDefaultLimits() {
    return {
      'ocrPages': 30,
      'ttsRequests': 100,
      'translatedChars': 3000,
      'storageBytes': 52428800, // 50MB
    };
  }
  
  /// 사용량 증가
  Future<bool> incrementUsage(String key, int amount) async {
    try {
      // 1. 현재 사용량 가져오기
      final usage = await getUserUsage();
      final currentValue = usage[key] ?? 0;
      
      // 2. 제한 확인
      final limits = await getCurrentLimits();
      final limitKey = key == 'storageUsageBytes' ? 'storageBytes' : key;
      final limit = limits[limitKey] ?? 0;
      
      // 3. 제한 체크
      if (currentValue + amount > limit) {
        debugPrint('$key 사용량 제한 초과: ${currentValue + amount} > $limit');
        return false;
      }
      
      // 4. 사용량 증가
      final newValue = currentValue + amount;
      await _updateUsage(key, newValue);
      
      debugPrint('$key 사용량 증가: $currentValue → $newValue (제한: $limit)');
      return true;
    } catch (e) {
      debugPrint('사용량 증가 중 오류: $e');
      return false;
    }
  }
  
  /// 사용량 업데이트
  Future<void> _updateUsage(String key, int value) async {
    try {
      final userId = _currentUserId;
      if (userId == null) return;
      
      // 1. Firestore 업데이트
      await _firestore.collection('users').doc(userId).update({
        'usage.$key': value,
        'usage.lastUpdated': FieldValue.serverTimestamp(),
      });
      
      // 2. 캐시 무효화
      _cachedUsageData = null;
      _lastFetchTime = null;
      
      debugPrint('사용량 업데이트 완료: $key = $value');
    } catch (e) {
      debugPrint('사용량 업데이트 중 오류: $e');
    }
  }
  
  /// OCR 페이지 수 계산
  /// 삭제된 노트나 페이지에 대한 OCR 사용량도 카운트하기 위해
  /// Firestore에 저장된 카운터를 우선적으로 사용합니다.
  Future<int> _calculateOcrPages() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return 0;
      
      debugPrint('OCR 페이지 수 계산 시작 (Firestore 카운터 우선)');
      
      // 1. Firestore에서 저장된 OCR 사용량 가져오기
      final usage = await getUserUsage();
      final ocrPagesFromFirestore = usage['ocrPages'] ?? 0;
      
      debugPrint('Firestore에 저장된 OCR 페이지 수: $ocrPagesFromFirestore');
      
      // 2. OCR 카운터가 이미 저장되어 있으면 그대로 사용
      // 삭제된 노트나 파일의 OCR 사용량도 계속 유지됨
      if (ocrPagesFromFirestore > 0) {
        return ocrPagesFromFirestore;
      }
      
      // 3. Firestore에 저장된 값이 없는 경우에만 메모리 캐시 확인 (레거시 지원)
      final memoryCache = await _getMemoryCachedImageCount();
      if (memoryCache > 0) {
        debugPrint('메모리 캐시에서 발견한 이미지 파일: $memoryCache개');
        // 캐시 값을 Firestore에 업데이트
        await _updateUsage('ocrPages', memoryCache);
        return memoryCache;
      }
      
      // 4. 마지막 수단으로 Firebase Storage에서 계산 (초기 설정용)
      // 이 방식은 현재 Storage에 있는 파일만 카운트하므로, 삭제된 노트의 OCR은 포함하지 않음
      // 이후부터는 incrementOcrPageCount 메서드로 추적
      int count = 0;
      
      try {
        // 메인 이미지 폴더 확인
        final imagesRef = _storage.ref().child('users/$userId/images');
        final mainFolderResult = await imagesRef.listAll();
        
        // 모든 .jpg, .jpeg, .png 파일 카운트
        for (final item in mainFolderResult.items) {
          final name = item.name.toLowerCase();
          if (name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png')) {
            count++;
          }
        }
        
        debugPrint('Firebase Storage에서 발견한 이미지 파일: $count개');
        
        // Storage에서 계산한 값을 Firestore에 저장 (앞으로의 기준점)
        if (count > 0) {
          await _updateUsage('ocrPages', count);
        }
      } catch (e) {
        debugPrint('Firebase Storage 접근 중 오류: $e');
      }
      
      return count;
    } catch (e) {
      debugPrint('OCR 페이지 수 계산 중 오류: $e');
      return 0;
    }
  }
  
  /// OCR 페이지 수 증가
  /// 이 메서드는 OCR을 사용할 때마다 호출되어야 함
  /// 삭제된 노트나 페이지에 대한 OCR 사용량도 카운트하기 위해
  /// Firestore에 직접 저장된 카운터를 증가시킵니다.
  Future<bool> incrementOcrPageCount(int pages) async {
    try {
      if (pages <= 0) return true; // 0 이하는 무시
      
      // OCR을 사용한 페이지 수를 Firestore에 직접 증가
      final result = await incrementUsage('ocrPages', pages);
      
      if (result) {
        debugPrint('OCR 페이지 수 증가: $pages페이지 추가됨 (삭제되어도 카운트 유지)');
      } else {
        debugPrint('OCR 페이지 수 증가 실패: 사용량 제한 초과');
      }
      
      return result;
    } catch (e) {
      debugPrint('OCR 페이지 수 증가 중 오류: $e');
      return false;
    }
  }
  
  /// 번역 문자 수 증가
  Future<bool> incrementTranslationCharCount(int chars) async {
    return await incrementUsage('translatedChars', chars);
  }
  
  /// TTS 요청 수 증가
  Future<bool> incrementTtsCharCount(int chars) async {
    // 텍스트 길이와 상관없이 요청 1회로 카운트
    return await incrementUsage('ttsRequests', 1);
  }
  
  /// 저장 공간 사용량 증가
  Future<bool> addStorageUsage(int bytes) async {
    return await incrementUsage('storageUsageBytes', bytes);
  }
  
  /// 사용량 비율 계산
  Future<Map<String, double>> getUsagePercentages() async {
    try {
      // 1. 실제 사용량 계산
      final Map<String, int> actualUsage = await _calculateActualUsage();
      
      // 2. 제한 가져오기
      final limits = await getCurrentLimits();
      
      // 3. 비율 계산
      final Map<String, double> percentages = {};
      
      // OCR 사용량
      final ocrLimit = limits['ocrPages'] ?? 1;
      percentages['ocr'] = double.parse(
        ((actualUsage['ocrPages']! / ocrLimit) * 100).clamp(0.0, 100.0).toStringAsFixed(1)
      );
      
      // TTS 사용량
      final ttsLimit = limits['ttsRequests'] ?? 1;
      percentages['tts'] = double.parse(
        ((actualUsage['ttsRequests']! / ttsLimit) * 100).clamp(0.0, 100.0).toStringAsFixed(1)
      );
      
      // 번역 사용량
      final translationLimit = limits['translatedChars'] ?? 1;
      percentages['translation'] = double.parse(
        ((actualUsage['translatedChars']! / translationLimit) * 100).clamp(0.0, 100.0).toStringAsFixed(1)
      );
      
      // 저장 공간 사용량
      final storageLimit = limits['storageBytes'] ?? 1;
      percentages['storage'] = double.parse(
        ((actualUsage['storageUsageBytes']! / storageLimit) * 100).clamp(0.0, 100.0).toStringAsFixed(1)
      );
      
      debugPrint('=== 사용량 비율 ===');
      debugPrint('OCR: ${actualUsage['ocrPages']}/$ocrLimit = ${percentages['ocr']}%');
      debugPrint('TTS: ${actualUsage['ttsRequests']}/$ttsLimit = ${percentages['tts']}%');
      debugPrint('번역: ${actualUsage['translatedChars']}/$translationLimit = ${percentages['translation']}%');
      
      // null 안전성 체크 추가
      final storageUsageBytes = actualUsage['storageUsageBytes'] ?? 0;
      debugPrint('저장공간: ${storageUsageBytes / 1024 / 1024}MB/${storageLimit / 1024 / 1024}MB = ${percentages['storage']}%');
      
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
  
  /// 실제 사용량 계산 (Firebase Storage 기반)
  Future<Map<String, int>> _calculateActualUsage() async {
    try {
      // 1. Firestore에서 기존 데이터 가져오기
      final usage = await getUserUsage(forceRefresh: true);
      
      // 2. Firebase Storage에서 실제 OCR 페이지 수와 저장공간 계산
      final ocrPages = await _calculateOcrPages();
      final storageBytes = await _calculateStorageUsage();
      
      // 3. 결과 합치기
      final result = {
        'ocrPages': ocrPages,
        'ttsRequests': _parseIntSafely(usage['ttsRequests']),
        'translatedChars': _parseIntSafely(usage['translatedChars']),
        'storageUsageBytes': storageBytes,
      };
      
      // 4. 결과가 Firestore와 다르면 업데이트
      if (ocrPages != usage['ocrPages']) {
        await _updateUsage('ocrPages', ocrPages);
      }
      
      if (storageBytes != usage['storageUsageBytes']) {
        await _updateUsage('storageUsageBytes', storageBytes);
      }
      
      return result;
    } catch (e) {
      debugPrint('실제 사용량 계산 중 오류: $e');
      return {
        'ocrPages': 0,
        'ttsRequests': 0,
        'translatedChars': 0,
        'storageUsageBytes': 0,
      };
    }
  }
  
  /// 저장 공간 사용량 계산 (Firebase Storage 기반)
  Future<int> _calculateStorageUsage() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return 0;
      
      debugPrint('저장 공간 사용량 계산 시작');
      
      // 1. 이미지 크기 추정
      final imageCount = await _calculateOcrPages();
      final estimatedImageSize = imageCount * 200 * 1024; // 평균 200KB로 추정
      
      debugPrint('이미지 파일 수: $imageCount, 추정 크기: ${estimatedImageSize / 1024 / 1024}MB');
      
      // 2. 기타 저장 공간 (예: 오디오 파일 등) - 실제 구현에 맞게 조정
      const otherStorageSize = 1 * 1024 * 1024; // 1MB로 가정
      
      // 3. 총 저장 공간
      final totalStorage = estimatedImageSize + otherStorageSize;
      
      debugPrint('총 저장 공간 사용량: ${totalStorage / 1024 / 1024}MB');
      return totalStorage;
    } catch (e) {
      debugPrint('저장 공간 계산 중 오류: $e');
      return 0;
    }
  }
  
  /// 제한 상태 확인
  Future<Map<String, dynamic>> checkLimitStatus() async {
    try {
      // 1. 실제 사용량 계산
      final usage = await _calculateActualUsage();
      
      // 2. 제한 가져오기
      final limits = await getCurrentLimits();
      
      // 3. 제한 상태 확인
      return {
        'ocrLimitReached': usage['ocrPages']! >= limits['ocrPages']!,
        'ttsLimitReached': usage['ttsRequests']! >= limits['ttsRequests']!,
        'translationLimitReached': usage['translatedChars']! >= limits['translatedChars']!,
        'storageLimitReached': usage['storageUsageBytes']! >= limits['storageBytes']!,
        // 제한값 포함
        'ocrLimit': limits['ocrPages'],
        'ttsLimit': limits['ttsRequests'],
        'translationLimit': limits['translatedChars'],
        'storageLimit': limits['storageBytes'],
      };
    } catch (e) {
      debugPrint('제한 상태 확인 중 오류: $e');
      final limits = _getDefaultLimits();
      return {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'translationLimitReached': false,
        'storageLimitReached': false,
        'ocrLimit': limits['ocrPages'],
        'ttsLimit': limits['ttsRequests'],
        'translationLimit': limits['translatedChars'],
        'storageLimit': limits['storageBytes'],
      };
    }
  }
  
  /// 사용량 정보 가져오기
  Future<Map<String, dynamic>> getUsageInfo() async {
    try {
      // 1. 사용량 비율 계산
      final percentages = await getUsagePercentages();
      
      // 2. 제한 상태 확인
      final limitStatus = await checkLimitStatus();
      
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
        'limitStatus': {
          'ocrLimitReached': false,
          'ttsLimitReached': false,
          'translationLimitReached': false,
          'storageLimitReached': false,
          'ocrLimit': 30,
          'ttsLimit': 100,
          'translationLimit': 3000,
          'storageLimit': 52428800,
        },
      };
    }
  }
  
  /// 모든 사용량 초기화
  Future<void> resetAllUsage() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return;
      
      // 1. Firestore 업데이트
      await _firestore.collection('users').doc(userId).update({
        'usage.ocrPages': 0,
        'usage.ttsRequests': 0,
        'usage.translatedChars': 0,
        'usage.storageUsageBytes': 0,
        'usage.lastUpdated': FieldValue.serverTimestamp(),
      });
      
      // 2. 캐시 무효화
      _cachedUsageData = null;
      _lastFetchTime = null;
      
      debugPrint('모든 사용량 초기화 완료');
    } catch (e) {
      debugPrint('사용량 초기화 중 오류: $e');
    }
  }
  
  /// 월간 사용량 초기화 (Free 플랜)
  Future<void> resetMonthlyUsage() async {
    try {
      // 1. 현재 플랜 확인
      final planService = PlanService();
      final planType = await planService.getCurrentPlanType();
      
      // Free 플랜만 월간 초기화
      if (planType != PlanService.PLAN_FREE) {
        debugPrint('Free 플랜이 아니므로 월간 초기화 건너뜀');
        return;
      }
      
      // 2. 마지막 초기화 날짜 확인
      final prefs = await SharedPreferences.getInstance();
      final resetKey = 'monthly_reset_${_currentUserId ?? 'anonymous'}';
      final lastResetStr = prefs.getString(resetKey);
      
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      
      // 최초 또는 이번 달 초기화 안 했으면 초기화
      if (lastResetStr == null) {
        await resetAllUsage();
        await prefs.setString(resetKey, currentMonth.toIso8601String());
        debugPrint('최초 월간 사용량 초기화 완료');
        return;
      }
      
      // 마지막 초기화 날짜 파싱
      try {
        final lastReset = DateTime.parse(lastResetStr);
        
        // 다른 달이면 초기화
        if (lastReset.year != currentMonth.year || lastReset.month != currentMonth.month) {
          await resetAllUsage();
          await prefs.setString(resetKey, currentMonth.toIso8601String());
          debugPrint('월간 사용량 초기화 완료 (마지막 초기화: ${lastReset.year}-${lastReset.month})');
        } else {
          debugPrint('이번 달에 이미 초기화됨 (${currentMonth.year}-${currentMonth.month})');
        }
      } catch (e) {
        // 날짜 파싱 오류 시 초기화
        await resetAllUsage();
        await prefs.setString(resetKey, currentMonth.toIso8601String());
        debugPrint('날짜 오류로 인한 월간 사용량 초기화');
      }
    } catch (e) {
      debugPrint('월간 사용량 초기화 중 오류: $e');
    }
  }
  
  /// 사용량 캐시 무효화
  void invalidateCache() {
    _cachedUsageData = null;
    _lastFetchTime = null;
  }
  
  /// 이미지 캐시 정보 업데이트
  Future<void> updateImageCacheInfo(int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheInfo = {
        'count': count,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString('image_cache_info', json.encode(cacheInfo));
      debugPrint('이미지 캐시 정보 업데이트: $count개');
    } catch (e) {
      debugPrint('이미지 캐시 정보 업데이트 중 오류: $e');
    }
  }
  
  /// PlanService와의 호환성을 위한 메서드
  Future<Map<String, dynamic>> checkFreeLimits() async {
    // checkLimitStatus와 동일한 형식으로 결과 반환
    return await checkLimitStatus();
  }
  
  /// 탈퇴 시 Firebase Storage 데이터 삭제
  Future<bool> deleteFirebaseStorageData(String userId) async {
    try {
      if (userId.isEmpty) {
        debugPrint('Firebase Storage 데이터 삭제 실패: 사용자 ID가 비어있음');
        return false;
      }
      
      // Firebase Storage 참조
      final userFolderRef = _storage.ref().child('users/$userId');
      
      try {
        // 1. 사용자 폴더 모든 파일 리스트 가져오기
        final result = await userFolderRef.listAll();
        debugPrint('탈퇴한 사용자의 Firebase Storage 파일 ${result.items.length}개, 폴더 ${result.prefixes.length}개 발견');
        
        // 2. 모든 파일 삭제
        for (final item in result.items) {
          await item.delete();
          debugPrint('파일 삭제됨: ${item.fullPath}');
        }
        
        // 3. 하위 폴더 처리
        for (final prefix in result.prefixes) {
          // 하위 폴더의 모든 파일 가져오기
          final subResult = await prefix.listAll();
          
          // 하위 폴더의 모든 파일 삭제
          for (final subItem in subResult.items) {
            await subItem.delete();
            debugPrint('하위 폴더 파일 삭제됨: ${subItem.fullPath}');
          }
        }
        
        debugPrint('Firebase Storage에서 사용자 $userId의 데이터 삭제 완료');
        return true;
      } catch (e) {
        // 폴더가 없거나 권한이 없는 경우 등
        debugPrint('Firebase Storage 접근 중 오류: $e');
        return false;
      }
    } catch (e) {
      debugPrint('Firebase Storage 데이터 삭제 실패: $e');
      return false;
    }
  }
  
  /// 메모리 캐시에 있는 이미지 파일 수 가져오기
  Future<int> _getMemoryCachedImageCount() async {
    try {
      // 여기에 메모리 캐시 카운팅 로직 구현
      // SharedPreferences나 앱 내부 캐시에서 정보 가져오기
      final prefs = await SharedPreferences.getInstance();
      final cacheData = prefs.getString('image_cache_info');
      
      if (cacheData != null) {
        try {
          final cache = json.decode(cacheData) as Map<String, dynamic>;
          if (cache.containsKey('count') && cache['count'] is int) {
            return cache['count'];
          }
        } catch (e) {
          debugPrint('캐시 데이터 파싱 오류: $e');
        }
      }
      
      return 0;
    } catch (e) {
      debugPrint('메모리 캐시 확인 중 오류: $e');
      return 0;
    }
  }
} 