import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../../models/user_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import '../cache/event_cache_manager.dart'; // 캐시 제거
import 'dart:async'; // Completer 추가

/// 사용자 설정을 관리하는 서비스 (캐시 없이 직접 DB 조회)

class UserPreferencesService {
  static const String _preferencesKey = 'user_preferences';
  static const String _currentUserIdKey = 'current_user_id';
  static const String _loginHistoryKey = 'has_login_history';
    
  // 현재 사용자 ID
  String? _currentUserId;

  // 🎯 메모리 캐시 (세션 기반)
  UserPreferences? _cachedPreferences;
  
  // 🎯 중복 호출 방지
  Future<UserPreferences>? _ongoingLoadOperation;
  

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
    
  // 싱글톤 패턴
  static final UserPreferencesService _instance = UserPreferencesService._internal();
  factory UserPreferencesService() => _instance;
  UserPreferencesService._internal();

  /// 현재 사용자 ID 설정
  Future<void> setCurrentUserId(String userId) async {
    if (userId.isEmpty) {
      debugPrint('⚠️ 빈 사용자 ID가 전달됨 - 무시됨');
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    
    // 이전 사용자 ID 가져오기
    final previousUserId = _currentUserId ?? prefs.getString(_currentUserIdKey);
    
    // 사용자 변경 여부 확인
    final bool isUserChanged = previousUserId != null && previousUserId != userId;
    
    // 🎯 로그 출력 최소화: 디버그 모드에서만
    if (kDebugMode) {
    // 첫 로그인 또는 사용자 변경인 경우 로그 출력
    if (previousUserId == null) {
      debugPrint('🔑 새로운 사용자 로그인: $userId');
    } else if (isUserChanged) {
      debugPrint('🔄 사용자 전환 감지: $previousUserId → $userId');
    } else {
      debugPrint('🔒 동일 사용자 재인증: $userId');
      }
    }
    
    // 사용자가 변경된 경우에만 데이터 초기화 및 캐시 무효화
    if (isUserChanged) {
      if (kDebugMode) {
      debugPrint('📝 사용자 전환으로 이전 사용자 데이터 초기화 중...');
      }
      await clearUserData(); // clearUserData가 캐시를 무효화함
      if (kDebugMode) {
      debugPrint('✅ 사용자 데이터 초기화 완료');
      }
    }
    
    // 새 사용자 ID 저장
    _currentUserId = userId;
    await prefs.setString(_currentUserIdKey, userId);
    debugPrint('🔐 캐시 서비스에 현재 사용자 ID 설정: $userId');
  }
  
  /// 현재 사용자 ID 가져오기
  Future<String?> getCurrentUserId() async {
    if (_currentUserId != null) return _currentUserId;
    
    final prefs = await SharedPreferences.getInstance();
    _currentUserId = prefs.getString(_currentUserIdKey);
    return _currentUserId;
  }

  /// 사용자 설정 가져오기 (캐시 없이 항상 SharedPreferences에서 직접 조회)
  Future<UserPreferences> getPreferences() async {
    // 🎯 캐시 확인 (세션 동안 유효)
    if (_cachedPreferences != null) {
      if (kDebugMode) {
        debugPrint('✅ [UserPreferences] 캐시에서 설정 로드 완료');
      }
      return _cachedPreferences!;
    }
    
    // 🎯 중복 호출 방지
    if (_ongoingLoadOperation != null) {
      if (kDebugMode) {
        debugPrint('⏭️ [UserPreferences] 진행 중인 로드 작업 대기');
      }
      return await _ongoingLoadOperation!;
    }
    
    final completer = Completer<UserPreferences>();
    _ongoingLoadOperation = completer.future;

    try {
      final result = await _getPreferencesInternal();
      completer.complete(result);
      return result;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _ongoingLoadOperation = null;
    }
  }
  
  /// 내부 사용자 설정 조회 메서드
  Future<UserPreferences> _getPreferencesInternal() async {
    final userId = await getCurrentUserId();
    
    if (kDebugMode) {
      debugPrint('📦 [UserPreferences] SharedPreferences에서 설정 직접 조회: $userId');
    }
    
    final prefs = await SharedPreferences.getInstance();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_preferencesKey}_$userId' : _preferencesKey;
    final jsonString = prefs.getString(key);
    
    UserPreferences preferences;
    if (jsonString != null) {
      try {
        preferences = UserPreferences.fromJson(jsonDecode(jsonString));
      } catch (e) {
        debugPrint('⚠️ 사용자 설정 파싱 중 오류: $e');
        preferences = UserPreferences.defaults();
      }
    } else {
      preferences = UserPreferences.defaults();
    }
    
    // 🎯 캐시에 저장
    _cachedPreferences = preferences;

    if (kDebugMode) {
      debugPrint('✅ [UserPreferences] SharedPreferences에서 설정 로드 완료 및 캐시 저장');
    }
    
    return preferences;
  }

  /// 사용자 설정 저장 (캐시 없이 항상 SharedPreferences + Firestore 직접 저장)
  Future<void> savePreferences(UserPreferences preferences) async {
    // 🎯 캐시 무효화
    _cachedPreferences = null;
    
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_preferencesKey}_$userId' : _preferencesKey;
    await prefs.setString(key, jsonEncode(preferences.toJson()));
    
    // 🔄 Firestore 저장 최적화: 중요한 설정 변경시에만 저장
    if (userId != null && userId.isNotEmpty) {
      try {
        // 온보딩 완료, 언어 설정 등 중요한 변경사항만 Firestore에 저장
        final importantFields = {
          'onboardingCompleted': preferences.onboardingCompleted,
          'sourceLanguage': preferences.sourceLanguage,
          'targetLanguage': preferences.targetLanguage,
          'useSegmentMode': preferences.useSegmentMode,
        };
        
        await FirebaseFirestore.instance.collection('users').doc(userId).set(
          importantFields, 
          SetOptions(merge: true) // 기존 필드들 보존
        );
        
        if (kDebugMode) {
          debugPrint('✅ [UserPreferences] 중요 설정만 Firestore 저장 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [UserPreferences] Firestore 저장 실패 (로컬 저장은 성공): $e');
        }
      }
    }
    
    if (kDebugMode) {
      debugPrint('💾 [UserPreferences] 설정 저장 완료 (캐시 없이 직접 저장)');
    }
  }

  /// 사용자 데이터 초기화 (캐시 없이 직접 SharedPreferences에서 삭제)
  Future<void> clearUserData() async {
    // 🎯 캐시 무효화
    _cachedPreferences = null;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = await getCurrentUserId();
      
      if (userId == null) {
        debugPrint('⚠️ 초기화할 사용자 ID가 없습니다');
        return;
      }
      
      // 사용자 설정 직접 삭제
      await prefs.remove('${_preferencesKey}_$userId');
      
      if (kDebugMode) {
        debugPrint('⚠️ 사용자 설정이 초기화되었습니다: $userId');
        debugPrint('🗑️ 캐시 없이 직접 SharedPreferences에서 삭제');
      }
    } catch (e) {
      debugPrint('⚠️ 사용자 데이터 초기화 중 오류 발생: $e');
    }
  }

  /// Firestore에서 사용자 설정 로드 (캐시 없이 SharedPreferences에만 저장)
  Future<void> loadUserSettingsFromFirestore({bool forceRefresh = false}) async {
    // 🎯 캐시 무효화
    _cachedPreferences = null;

    final userId = await getCurrentUserId();
    if (userId == null || userId.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ [UserPreferences] Firestore 로드할 사용자 ID 없음');
      }
      return;
    }
    
    // 앱 첫 진입 시 (forceRefresh = true)에만 Firestore에서 로드
    if (!forceRefresh) {
      if (kDebugMode) {
        debugPrint('🔄 [UserPreferences] 앱 첫 진입이 아니므로 Firestore 로드 건너뜀');
      }
      return;
    }
    
    if (kDebugMode) {
      debugPrint('🔄 [UserPreferences] 앱 첫 진입 - Firestore에서 설정 로드');
    }
    
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      
      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData == null) return;
        
        // 🎯 읽기 전용: SharedPreferences에만 저장
        final preferences = UserPreferences.fromJson(userData);
        
        // 로컬 SharedPreferences에만 저장
        final prefs = await SharedPreferences.getInstance();
        final key = '${_preferencesKey}_$userId';
        await prefs.setString(key, jsonEncode(preferences.toJson()));
        
        if (kDebugMode) {
          debugPrint('✅ [UserPreferences] Firestore 설정 로드 완료 (캐시 없이 직접 저장)');
        }
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ [UserPreferences] Firestore에 사용자 문서 없음: $userId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [UserPreferences] Firestore 로드 실패: $e');
      }
    }
  }

  /// 로그인 이력이 있는지 확인
  Future<bool> hasLoginHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loginHistoryKey) ?? false;
  }
  
  /// 로그인 이력 저장
  Future<void> setLoginHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loginHistoryKey, true);
  }
  
  /// 온보딩 완료 여부 확인
  Future<bool> getOnboardingCompleted() async {
    final prefs = await getPreferences();
    final isCompleted = prefs.onboardingCompleted;
    
    if (kDebugMode) {
      debugPrint('🔍 [UserPreferences] 온보딩 상태 확인: $isCompleted');
    }
    
    return isCompleted;
  }
  
  /// 온보딩 완료 상태 저장
  Future<void> setOnboardingCompleted(bool completed) async {
    final prefs = await getPreferences();
    await savePreferences(prefs.copyWith(onboardingCompleted: completed));
  }
  
  /// 🎯 온보딩 완료 상태 직접 저장 (캐시 시스템 우회)
  /// 온보딩은 일회성 설정이므로 이벤트 캐시를 사용하지 않음
  Future<void> setOnboardingCompletedDirect(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_preferencesKey}_$userId' : _preferencesKey;
    
    // 기존 설정 가져오기
    final jsonString = prefs.getString(key);
    UserPreferences preferences;
    
    if (jsonString != null) {
      try {
        preferences = UserPreferences.fromJson(jsonDecode(jsonString));
      } catch (e) {
        preferences = UserPreferences.defaults();
      }
    } else {
      preferences = UserPreferences.defaults();
    }
    
    // 온보딩 완료 플래그만 업데이트
    final updatedPreferences = preferences.copyWith(onboardingCompleted: completed);
    
    // SharedPreferences에만 저장 (캐시 이벤트 발생 안 함)
    await prefs.setString(key, jsonEncode(updatedPreferences.toJson()));
    
    if (kDebugMode) {
      debugPrint('✅ [UserPreferences] 온보딩 완료 플래그 직접 저장 완료 (캐시 우회): $completed');
    }
  }
  
  /// 사용자 이름 설정
  Future<void> setUserName(String name) async {
    final prefs = await getPreferences();
    await savePreferences(prefs.copyWith(userName: name));
  }
  
  /// 기본 노트스페이스 가져오기
  Future<String> getDefaultNoteSpace() async {
    final prefs = await getPreferences();
    return prefs.defaultNoteSpace.isEmpty ? '학습 노트' : prefs.defaultNoteSpace;
  }
  
  /// 기본 노트스페이스 설정
  Future<void> setDefaultNoteSpace(String spaceId) async {
    final prefs = await getPreferences();
    await savePreferences(prefs.copyWith(defaultNoteSpace: spaceId));
  }
  
  /// 노트스페이스 이름 변경
  Future<void> renameNoteSpace(String oldName, String newName) async {
    final prefs = await getPreferences();
    final spaces = List<String>.from(prefs.noteSpaces);
    final index = spaces.indexOf(oldName);
    if (index != -1) {
      spaces[index] = newName;
      await savePreferences(prefs.copyWith(noteSpaces: spaces));
    }
  }
  
  /// 소스 언어 설정
  Future<void> setSourceLanguage(String language) async {
    final prefs = await getPreferences();
    await savePreferences(prefs.copyWith(sourceLanguage: language));
  }
  
  /// 타겟 언어 설정
  Future<void> setTargetLanguage(String language) async {
    final prefs = await getPreferences();
    await savePreferences(prefs.copyWith(targetLanguage: language));
  }
  
  /// 세그먼트 모드 설정
  Future<void> setUseSegmentMode(bool useSegmentMode) async {
    final prefs = await getPreferences();
    await savePreferences(prefs.copyWith(useSegmentMode: useSegmentMode));
  }
  
  /// 노트 스페이스 추가
  Future<void> addNoteSpace(String spaceName) async {
    final prefs = await getPreferences();
    final spaces = List<String>.from(prefs.noteSpaces);
    
    // 이미 존재하는 경우 추가하지 않음
    if (!spaces.contains(spaceName)) {
      spaces.add(spaceName);
      await savePreferences(prefs.copyWith(noteSpaces: spaces));
      
      // Firestore에도 업데이트
      final userId = await getCurrentUserId();
      if (userId != null && userId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('users').doc(userId).update({
            'noteSpaces': FieldValue.arrayUnion([spaceName])
          });
        } catch (e) {
          debugPrint('⚠️ Firestore 노트 스페이스 추가 실패: $e');
        }
      }
    }
  }
  
  /// 학습 목적 설정
  Future<void> setLearningPurpose(String purpose) async {
    final prefs = await getPreferences();
    await savePreferences(prefs.copyWith(learningPurpose: purpose));
  }
  
  /// 온보딩 여부 설정
  Future<void> setHasOnboarded(bool hasOnboarded) async {
    final prefs = await getPreferences();
    final updatedPrefs = prefs.copyWith(hasLoginHistory: hasOnboarded);
    await savePreferences(updatedPrefs);
    
    // Firestore에도 업데이트
    final userId = await getCurrentUserId();
    if (userId != null && userId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(userId).update({
          'hasOnboarded': hasOnboarded
        });
      } catch (e) {
        debugPrint('⚠️ Firestore 온보딩 상태 업데이트 실패: $e');
      }
    }
  }

  /// 세그먼트 모드 반전 (디버깅 테스트용)
  Future<bool> toggleSegmentMode() async {
    try {
      final prefs = await getPreferences();
      final newValue = !prefs.useSegmentMode;
      
      if (kDebugMode) {
        debugPrint('🔄 세그먼트 모드 반전: ${prefs.useSegmentMode} → $newValue');
      }
      
      await savePreferences(prefs.copyWith(useSegmentMode: newValue));
      return newValue;
    } catch (e) {
      debugPrint('⚠️ 세그먼트 모드 반전 실패: $e');
      return false;
    }
  }
} 