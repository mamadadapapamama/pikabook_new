import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

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

  // 온보딩 완료 여부 가져오기
  Future<bool> getOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompletedKey) ?? false;
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
    return prefs.getString(_defaultNoteSpaceKey) ?? '기본 노트';
  }

  // 기본 노트 스페이스 설정
  Future<void> setDefaultNoteSpace(String noteSpace) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultNoteSpaceKey, noteSpace);
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
        await setDefaultNoteSpace(newName);
      }
      return true; // 이름 변경 성공
    } else {
      // 기존 이름이 없다면 새 이름 추가 시도
      if (!noteSpaces.contains(newName)) {
         await addNoteSpace(newName);
         // 기본 노트 스페이스도 새 이름으로 설정할 수 있음 (선택적)
         // await setDefaultNoteSpace(newName);
         return false; // 이름 변경이 아닌 추가로 처리됨
      }
      return false; // 이미 존재하는 이름
    }
  }

  // 사용자 이름 가져오기
  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  // 사용자 이름 설정
  Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
  }

  // 학습 목적 가져오기
  Future<String?> getLearningPurpose() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_learningPurposeKey);
  }

  // 학습 목적 설정
  Future<void> setLearningPurpose(String purpose) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_learningPurposeKey, purpose);
  }

  // 세그먼트 모드 사용 여부 가져오기
  Future<bool> getUseSegmentMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useSegmentModeKey) ?? false;
  }

  // 세그먼트 모드 사용 여부 설정
  Future<void> setUseSegmentMode(bool useSegmentMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useSegmentModeKey, useSegmentMode);
  }

  // getDefaultNoteViewMode 추가 (getUseSegmentMode 와 동일하게 동작)
  Future<String> getDefaultNoteViewMode() async {
    final useSegment = await getUseSegmentMode();
    return useSegment ? 'segment' : 'full';
  }

  // 노트 스페이스 목록 가져오기
  Future<List<String>> getNoteSpaces() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_noteSpacesKey) ?? ['기본 노트'];
  }

  // 노트 스페이스 추가
  Future<void> addNoteSpace(String noteSpace) async {
    final prefs = await SharedPreferences.getInstance();
    final noteSpaces = await getNoteSpaces();
    if (!noteSpaces.contains(noteSpace)) {
      noteSpaces.add(noteSpace);
      await prefs.setStringList(_noteSpacesKey, noteSpaces);
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
    return prefs.getString(_sourceLanguageKey) ?? 'zh'; // 기본값: 중국어
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
      
      debugPrint('모든 사용자 설정이 초기화되었습니다.');
    } catch (e) {
      debugPrint('사용자 설정 초기화 중 오류 발생: $e');
      rethrow;
    }
  }
} 