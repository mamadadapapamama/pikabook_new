import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 사용자 설정을 관리하는 서비스
/// SharedPreferences를 사용하여 로컬에 설정을 저장하고 관리합니다.
class UserPreferencesService {
  static const String _onboardingCompletedKey = 'onboarding_completed';
  static const String _defaultNoteSpaceKey = 'default_note_space';
  static const String _userNameKey = 'user_name';
  static const String _learningPurposeKey = 'learning_purpose';
  static const String _useSegmentModeKey = 'use_segment_mode';
  static const String _noteSpacesKey = 'note_spaces';
  static const String _loginHistoryKey = 'login_history';
  static const String _sourceLanguageKey = 'source_language';
  static const String _targetLanguageKey = 'target_language';
  static const String _currentUserIdKey = 'current_user_id'; // 현재 로그인된 사용자 ID 저장 키

  // 온보딩 완료 여부 가져오기
  Future<bool> getOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. 저장된 온보딩 상태 확인 (이제 기본값 true로 설정)
    final onboardingCompleted = prefs.getBool(_onboardingCompletedKey);
    
    // 2. 로컬에 설정된 값이 있으면 그 값 사용
    if (onboardingCompleted != null) {
      return onboardingCompleted;
    }
    
    // 3. 로그인 기록 확인 - 로그인 기록이 있으면 온보딩 완료로 간주
    final hasLoginHistory = prefs.getBool(_loginHistoryKey) ?? false;
    if (hasLoginHistory) {
      // 로그인 기록이 있는 기존 사용자는 온보딩 완료로 간주하고 저장
      await setOnboardingCompleted(true);
      debugPrint('📝 로그인 기록 있는 사용자 - 온보딩 완료 상태로 자동 설정');
      return true;
    }
    
    // 4. 기본값은 false
    return false;
  }

  // 온보딩 완료 여부 설정
  Future<void> setOnboardingCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, completed);
  }

  // setHasOnboarded 추가 (setOnboardingCompleted 와 동일하게 동작)
  Future<void> setHasOnboarded(bool completed) async {
    await setOnboardingCompleted(completed);
  }

  // 기본 노트 스페이스 가져오기
  Future<String> getDefaultNoteSpace() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_defaultNoteSpaceKey}_$userId' : _defaultNoteSpaceKey;
    return prefs.getString(key) ?? '기본 노트';
  }

  // 기본 노트 스페이스 설정
  Future<void> setDefaultNoteSpace(String noteSpace) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_defaultNoteSpaceKey}_$userId' : _defaultNoteSpaceKey;
    await prefs.setString(key, noteSpace);
    
    // Firestore에도 노트 스페이스 이름 업데이트
    try {
      if (userId != null && userId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update({
          'defaultNoteSpace': noteSpace
        });
        debugPrint('✅ Firestore에 노트 스페이스 이름 업데이트: $noteSpace, 사용자: $userId');
      }
    } catch (e) {
      debugPrint('⚠️ Firestore 노트 스페이스 이름 업데이트 실패: $e');
    }
  }

  // 노트 스페이스 이름 변경 추가
  Future<bool> renameNoteSpace(String oldName, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final noteSpaces = await getNoteSpaces();
    
    if (noteSpaces.contains(oldName)) {
      final index = noteSpaces.indexOf(oldName);
      noteSpaces[index] = newName;
      await prefs.setStringList(_noteSpacesKey, noteSpaces);
      
      // 기본 노트 스페이스 이름도 변경되었는지 확인 후 업데이트
      final defaultNoteSpace = await getDefaultNoteSpace();
      if (defaultNoteSpace == oldName) {
        await setDefaultNoteSpace(newName); // 이 메서드가 이제 Firestore도 업데이트함
      } else {
        // 기본 노트 스페이스가 아닌 경우에도 Firestore 업데이트 시도
        try {
          final userId = await getCurrentUserId();
          if (userId != null && userId.isNotEmpty) {
            // 노트 스페이스 배열 업데이트
            await FirebaseFirestore.instance.collection('users').doc(userId).update({
              'noteSpaces': noteSpaces
            });
            debugPrint('✅ Firestore에 노트 스페이스 목록 업데이트: $noteSpaces');
          }
        } catch (e) {
          debugPrint('⚠️ Firestore 노트 스페이스 목록 업데이트 실패: $e');
        }
      }
      return true; // 이름 변경 성공
    } else {
      // 기존 이름이 없다면 새 이름 추가 시도
      if (!noteSpaces.contains(newName)) {
         await addNoteSpace(newName);
         return false; // 이름 변경이 아닌 추가로 처리됨
      }
      return false; // 이미 존재하는 이름
    }
  }

  // 사용자 이름 가져오기
  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_userNameKey}_$userId' : _userNameKey;
    return prefs.getString(key);
  }

  // 사용자 이름 설정
  Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_userNameKey}_$userId' : _userNameKey;
    await prefs.setString(key, name);
    
    // Firestore에도 사용자 이름 업데이트
    try {
      if (userId != null && userId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update({
          'userName': name
        });
        debugPrint('✅ Firestore에 사용자 이름 업데이트: $name, 사용자: $userId');
      }
    } catch (e) {
      debugPrint('⚠️ Firestore 사용자 이름 업데이트 실패: $e');
    }
  }

  // 학습 목적 가져오기
  Future<String?> getLearningPurpose() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_learningPurposeKey}_$userId' : _learningPurposeKey;
    return prefs.getString(key);
  }

  // 학습 목적 설정
  Future<void> setLearningPurpose(String purpose) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_learningPurposeKey}_$userId' : _learningPurposeKey;
    await prefs.setString(key, purpose);
    
    // Firestore에도 학습 목적 업데이트
    try {
      if (userId != null && userId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update({
          'learningPurpose': purpose
        });
        debugPrint('✅ Firestore에 학습 목적 업데이트: $purpose, 사용자: $userId');
      }
    } catch (e) {
      debugPrint('⚠️ Firestore 학습 목적 업데이트 실패: $e');
    }
  }

  // 세그먼트 모드 사용 여부 가져오기
  Future<bool> getUseSegmentMode() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_useSegmentModeKey}_$userId' : _useSegmentModeKey;
    return prefs.getBool(key) ?? false;
  }

  // 세그먼트 모드 사용 여부 설정
  Future<void> setUseSegmentMode(bool useSegmentMode) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_useSegmentModeKey}_$userId' : _useSegmentModeKey;
    await prefs.setBool(key, useSegmentMode);
    
    // Firestore에도 세그먼트 모드 업데이트
    try {
      if (userId != null && userId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(userId).update({
          'translationMode': useSegmentMode ? 'segment' : 'full'
        });
        debugPrint('✅ Firestore에 세그먼트 모드 업데이트: $useSegmentMode, 사용자: $userId');
      }
    } catch (e) {
      debugPrint('⚠️ Firestore 세그먼트 모드 업데이트 실패: $e');
    }
  }

  // getDefaultNoteViewMode 추가 (getUseSegmentMode 와 동일하게 동작)
  Future<String> getDefaultNoteViewMode() async {
    final useSegment = await getUseSegmentMode();
    return useSegment ? 'segment' : 'full';
  }

  // 노트 스페이스 목록 가져오기
  Future<List<String>> getNoteSpaces() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_noteSpacesKey}_$userId' : _noteSpacesKey;
    return prefs.getStringList(key) ?? ['기본 노트'];
  }

  // 노트 스페이스 추가
  Future<void> addNoteSpace(String noteSpace) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getCurrentUserId();
    
    // 사용자 ID별 키 생성
    final key = userId != null ? '${_noteSpacesKey}_$userId' : _noteSpacesKey;
    
    final noteSpaces = await getNoteSpaces();
    if (!noteSpaces.contains(noteSpace)) {
      noteSpaces.add(noteSpace);
      await prefs.setStringList(key, noteSpaces);
      
      // Firestore에도 노트 스페이스 목록 업데이트
      try {
        if (userId != null && userId.isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(userId).update({
            'noteSpaces': noteSpaces
          });
          debugPrint('✅ Firestore에 노트 스페이스 목록 업데이트: $noteSpaces, 사용자: $userId');
        }
      } catch (e) {
        debugPrint('⚠️ Firestore 노트 스페이스 목록 업데이트 실패: $e');
      }
    }
  }

  // 노트 스페이스 삭제
  Future<void> removeNoteSpace(String noteSpace) async {
    final prefs = await SharedPreferences.getInstance();
    final noteSpaces = await getNoteSpaces();
    if (noteSpaces.contains(noteSpace)) {
      noteSpaces.remove(noteSpace);
      await prefs.setStringList(_noteSpacesKey, noteSpaces);
    }
  }

  // 언어 설정 추가
  Future<String> getSourceLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sourceLanguageKey) ?? 'zh-CN'; // 기본값: 중국어 간체자
  }

  Future<void> setSourceLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceLanguageKey, language);
  }

  Future<String> getTargetLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_targetLanguageKey) ?? 'ko'; // 기본값: 한국어
  }

  Future<void> setTargetLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_targetLanguageKey, language);
  }

  // 로그인 기록 저장
  Future<void> saveLoginHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loginHistoryKey, true);
  }

  // 로그인 기록 확인
  Future<bool> hasLoginHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loginHistoryKey) ?? false;
  }

  // 현재 사용자 ID 설정
  Future<void> setCurrentUserId(String userId) async {
    if (userId.isEmpty) {
      debugPrint('⚠️ 빈 사용자 ID가 전달됨 - 무시됨');
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    
    // 이전 사용자 ID 가져오기
    final previousUserId = prefs.getString(_currentUserIdKey);
    
    // 사용자 변경 여부 확인
    final bool isUserChanged = previousUserId != null && previousUserId != userId;
    
    // 첫 로그인 또는 사용자 변경인 경우 로그 출력
    if (previousUserId == null) {
      debugPrint('🔑 새로운 사용자 로그인: $userId');
    } else if (isUserChanged) {
      debugPrint('🔄 사용자 전환 감지: $previousUserId → $userId');
    } else {
      debugPrint('🔒 동일 사용자 재인증: $userId');
    }
    
    // 사용자가 변경된 경우에만 데이터 초기화
    if (isUserChanged) {
      debugPrint('📝 사용자 전환으로 이전 사용자 데이터 초기화 중...');
      
      // 이전 사용자 데이터 모두 초기화
      await clearUserData();
      
      debugPrint('✅ 사용자 데이터 초기화 완료');
    }
    
    // 새 사용자 ID 저장
    await prefs.setString(_currentUserIdKey, userId);
    debugPrint('🔐 캐시 서비스에 현재 사용자 ID 설정: $userId');
  }
  
  // 현재 사용자 ID 가져오기
  Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentUserIdKey);
  }
  
  // 사용자 데이터만 초기화 (로그인 ID 관련 정보만 유지)
  Future<void> clearUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = await getCurrentUserId();
      
      if (userId == null) {
        debugPrint('⚠️ 초기화할 사용자 ID가 없습니다');
        return;
      }
      
      // 사용자 데이터 관련 키 모두 삭제 (사용자 ID별)
      await prefs.remove('${_onboardingCompletedKey}_$userId');
      await prefs.remove('${_defaultNoteSpaceKey}_$userId');
      await prefs.remove('${_userNameKey}_$userId');
      await prefs.remove('${_learningPurposeKey}_$userId');
      await prefs.remove('${_useSegmentModeKey}_$userId');
      await prefs.remove('${_noteSpacesKey}_$userId');
      await prefs.remove('${_sourceLanguageKey}_$userId');
      await prefs.remove('${_targetLanguageKey}_$userId');
      
      // 일반 키도 삭제 (이전 버전 호환성을 위해)
      await prefs.remove(_onboardingCompletedKey);
      await prefs.remove(_defaultNoteSpaceKey);
      await prefs.remove(_userNameKey);
      await prefs.remove(_learningPurposeKey);
      await prefs.remove(_useSegmentModeKey);
      await prefs.remove(_noteSpacesKey);
      await prefs.remove(_sourceLanguageKey);
      await prefs.remove(_targetLanguageKey);
      
      // 'hasShownTooltip' 키도 초기화 (홈 화면 툴팁)
      await prefs.remove('hasShownTooltip');
      await prefs.remove('hasShownTooltip_$userId');
      
      debugPrint('⚠️ 사용자 전환 - 모든 사용자별 설정 데이터가 초기화되었습니다: $userId');
    } catch (e) {
      debugPrint('⚠️ 사용자 데이터 초기화 중 오류 발생: $e');
    }
  }

  // 모든 사용자 설정 초기화
  Future<void> clearAllUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 모든 설정 키 삭제
      await prefs.remove(_onboardingCompletedKey);
      await prefs.remove(_defaultNoteSpaceKey);
      await prefs.remove(_userNameKey);
      await prefs.remove(_learningPurposeKey);
      await prefs.remove(_useSegmentModeKey);
      await prefs.remove(_noteSpacesKey);
      await prefs.remove(_loginHistoryKey);
      await prefs.remove(_currentUserIdKey); // 사용자 ID도 초기화
      
      debugPrint('모든 사용자 설정이 초기화되었습니다.');
    } catch (e) {
      debugPrint('사용자 설정 초기화 중 오류 발생: $e');
      rethrow;
    }
  }

  // Firestore에서 사용자 설정 로드
  Future<void> loadUserSettingsFromFirestore() async {
    final userId = await getCurrentUserId();
    if (userId == null || userId.isEmpty) {
      debugPrint('⚠️ Firestore에서 설정을 로드할 사용자 ID가 없습니다');
      return;
    }
    
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      
      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData == null) return;
        
        // 설정 로드
        if (userData['userName'] != null) {
          await setUserName(userData['userName']);
          debugPrint('✅ Firestore에서 사용자 이름 로드: ${userData['userName']}');
        }
        
        if (userData['defaultNoteSpace'] != null) {
          await setDefaultNoteSpace(userData['defaultNoteSpace']);
          debugPrint('✅ Firestore에서 노트 스페이스 로드: ${userData['defaultNoteSpace']}');
        }
        
        if (userData['learningPurpose'] != null) {
          await setLearningPurpose(userData['learningPurpose']);
          debugPrint('✅ Firestore에서 학습 목적 로드: ${userData['learningPurpose']}');
        }
        
        if (userData['translationMode'] != null) {
          final bool useSegment = userData['translationMode'] == 'segment';
          await setUseSegmentMode(useSegment);
          debugPrint('✅ Firestore에서 번역 모드 로드: ${userData['translationMode']}');
        }
        
        if (userData['noteSpaces'] != null && userData['noteSpaces'] is List) {
          final noteSpaces = List<String>.from(userData['noteSpaces']);
          final prefs = await SharedPreferences.getInstance();
          final key = '${_noteSpacesKey}_$userId';
          await prefs.setStringList(key, noteSpaces);
          debugPrint('✅ Firestore에서 노트 스페이스 목록 로드: $noteSpaces');
        }
        
        if (userData['onboardingCompleted'] != null) {
          final bool completed = userData['onboardingCompleted'] == true;
          await setOnboardingCompleted(completed);
          debugPrint('✅ Firestore에서 온보딩 완료 여부 로드: $completed');
        }
        
        debugPrint('✅ Firestore에서 사용자 설정 로드 완료');
      } else {
        debugPrint('⚠️ Firestore에 사용자 문서가 없습니다: $userId');
      }
    } catch (e) {
      debugPrint('⚠️ Firestore에서 사용자 설정 로드 실패: $e');
    }
  }
} 