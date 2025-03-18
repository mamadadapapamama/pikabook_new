import 'package:shared_preferences/shared_preferences.dart';
import '../models/text_processing_mode.dart';
import '../utils/language_constants.dart';

/// 사용자 기본 설정을 관리하는 서비스
class UserPreferencesService {
  // 싱글톤 패턴 구현
  static final UserPreferencesService _instance =
      UserPreferencesService._internal();
  factory UserPreferencesService() => _instance;
  UserPreferencesService._internal();

  // SharedPreferences 키
  static const String _textProcessingModeKey = 'text_processing_mode';
  static const String _onboardingCompletedKey = 'onboarding_completed';
  static const String _sourceLanguageKey = 'source_language';
  static const String _targetLanguageKey = 'target_language';
  static const String _userNameKey = 'user_name';
  static const String _learningPurposeKey = 'learning_purpose';
  static const String _defaultNoteViewModeKey = 'default_note_view_mode';
  static const String _defaultNoteSpaceKey = 'default_note_space';
  static const String _noteSpacesKey = 'note_spaces';

  // 노트 뷰 모드 enum
  enum NoteViewMode {
    segmentMode,    // 문장별 학습 뷰(세그먼트 모드)
    fullTextMode    // 원문 전체 번역 뷰(전체 텍스트 모드)
  }

  // 기본 텍스트 처리 모드 (온보딩에서 설정)
  Future<void> setDefaultTextProcessingMode(TextProcessingMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_textProcessingModeKey, mode.index);
  }

  // 현재 텍스트 처리 모드 가져오기
  Future<TextProcessingMode> getTextProcessingMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_textProcessingModeKey);

    // 저장된 값이 없으면 기본값 반환
    if (modeIndex == null) {
      return TextProcessingMode.languageLearning; // 기본값
    }

    // 저장된 인덱스가 유효한지 확인
    if (modeIndex >= 0 && modeIndex < TextProcessingMode.values.length) {
      return TextProcessingMode.values[modeIndex];
    }

    return TextProcessingMode.languageLearning; // 기본값
  }

  // 온보딩 완료 여부 설정
  Future<void> setOnboardingCompleted(bool completed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompletedKey, completed);
  }

  // 온보딩 완료 여부 확인
  Future<bool> isOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompletedKey) ?? false;
  }

  // 소스 언어 설정 (학습하려는 언어)
  // MARK: 다국어 지원을 위한 확장 포인트
  Future<void> setSourceLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceLanguageKey, languageCode);
  }

  // 소스 언어 가져오기
  Future<String> getSourceLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sourceLanguageKey) ?? SourceLanguage.DEFAULT;
  }

  // 타겟 언어 설정 (번역 결과 언어)
  // MARK: 다국어 지원을 위한 확장 포인트
  Future<void> setTargetLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_targetLanguageKey, languageCode);
  }

  // 타겟 언어 가져오기
  Future<String> getTargetLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_targetLanguageKey) ?? TargetLanguage.DEFAULT;
  }

  // 사용자 이름 설정
  Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
  }

  // 사용자 이름 가져오기
  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  // 학습 목적 설정
  Future<void> setLearningPurpose(String purpose) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_learningPurposeKey, purpose);
  }

  // 학습 목적 가져오기
  Future<String?> getLearningPurpose() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_learningPurposeKey);
  }

  // 기본 노트 뷰 모드 설정 (문장별 또는 전체 텍스트)
  Future<void> setDefaultNoteViewMode(NoteViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_defaultNoteViewModeKey, mode.index);
  }

  // 기본 노트 뷰 모드 가져오기
  Future<NoteViewMode> getDefaultNoteViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_defaultNoteViewModeKey);

    // 저장된 값이 없으면 기본값 반환
    if (modeIndex == null) {
      return NoteViewMode.segmentMode; // 기본값은 세그먼트 모드
    }

    // 저장된 인덱스가 유효한지 확인
    if (modeIndex >= 0 && modeIndex < NoteViewMode.values.length) {
      return NoteViewMode.values[modeIndex];
    }

    return NoteViewMode.segmentMode; // 기본값
  }

  // 노트 스페이스 목록 가져오기
  Future<List<String>> getNoteSpaces() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_noteSpacesKey) ?? ['기본 노트 스페이스'];
  }

  // 노트 스페이스 추가
  Future<void> addNoteSpace(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final spaces = await getNoteSpaces();
    
    // 이미 존재하는 이름이면 추가하지 않음
    if (!spaces.contains(name)) {
      spaces.add(name);
      await prefs.setStringList(_noteSpacesKey, spaces);
    }
  }

  // 노트 스페이스 이름 변경
  Future<bool> renameNoteSpace(String oldName, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final spaces = await getNoteSpaces();
    
    // 이름이 이미 존재하면 변경 불가
    if (spaces.contains(newName) && oldName != newName) {
      return false;
    }
    
    final index = spaces.indexOf(oldName);
    if (index != -1) {
      spaces[index] = newName;
      await prefs.setStringList(_noteSpacesKey, spaces);
      
      // 기본 노트 스페이스가 변경된 경우 업데이트
      final defaultSpace = await getDefaultNoteSpace();
      if (defaultSpace == oldName) {
        await setDefaultNoteSpace(newName);
      }
      
      return true;
    }
    
    return false;
  }

  // 노트 스페이스 삭제
  Future<bool> deleteNoteSpace(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final spaces = await getNoteSpaces();
    
    // 마지막 노트 스페이스는 삭제 불가
    if (spaces.length <= 1) {
      return false;
    }
    
    final success = spaces.remove(name);
    if (success) {
      await prefs.setStringList(_noteSpacesKey, spaces);
      
      // 기본 노트 스페이스가 삭제된 경우 첫 번째 항목으로 설정
      final defaultSpace = await getDefaultNoteSpace();
      if (defaultSpace == name) {
        await setDefaultNoteSpace(spaces.first);
      }
    }
    
    return success;
  }

  // 기본 노트 스페이스 설정
  Future<void> setDefaultNoteSpace(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultNoteSpaceKey, name);
  }

  // 기본 노트 스페이스 가져오기
  Future<String> getDefaultNoteSpace() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultSpace = prefs.getString(_defaultNoteSpaceKey);
    
    if (defaultSpace != null) {
      // 기본 노트 스페이스가 존재하는지 확인
      final spaces = await getNoteSpaces();
      if (spaces.contains(defaultSpace)) {
        return defaultSpace;
      }
    }
    
    // 기본값이 없거나 유효하지 않으면 첫 번째 노트 스페이스 반환
    final spaces = await getNoteSpaces();
    return spaces.first;
  }

  // 모든 언어 관련 설정 초기화 (기본값으로)
  // MARK: 다국어 지원을 위한 확장 포인트
  Future<void> resetLanguageSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceLanguageKey, SourceLanguage.DEFAULT);
    await prefs.setString(_targetLanguageKey, TargetLanguage.DEFAULT);
  }

  // 모든 사용자 설정 초기화
  Future<void> resetAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    // 기본 노트 스페이스 다시 설정
    await prefs.setStringList(_noteSpacesKey, ['기본 노트 스페이스']);
    await prefs.setString(_defaultNoteSpaceKey, '기본 노트 스페이스');
    
    // 기본 언어 설정
    await prefs.setString(_sourceLanguageKey, SourceLanguage.DEFAULT);
    await prefs.setString(_targetLanguageKey, TargetLanguage.DEFAULT);
    
    // 기본 노트 뷰 모드
    await prefs.setInt(_defaultNoteViewModeKey, NoteViewMode.segmentMode.index);
    
    // 기본 텍스트 처리 모드
    await prefs.setInt(_textProcessingModeKey, TextProcessingMode.languageLearning.index);
  }

  // 사용자 설정 정보를 Map으로 반환 (디버깅용)
  Future<Map<String, dynamic>> getAllPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final textProcessingMode = await getTextProcessingMode();
    final noteViewMode = await getDefaultNoteViewMode();
    final noteSpaces = await getNoteSpaces();
    final defaultNoteSpace = await getDefaultNoteSpace();
    
    return {
      'onboardingCompleted': prefs.getBool(_onboardingCompletedKey) ?? false,
      'textProcessingMode': textProcessingMode.toString(),
      'sourceLanguage': prefs.getString(_sourceLanguageKey) ?? SourceLanguage.DEFAULT,
      'targetLanguage': prefs.getString(_targetLanguageKey) ?? TargetLanguage.DEFAULT,
      'userName': prefs.getString(_userNameKey) ?? '',
      'learningPurpose': prefs.getString(_learningPurposeKey) ?? '',
      'defaultNoteViewMode': noteViewMode.toString(),
      'noteSpaces': noteSpaces,
      'defaultNoteSpace': defaultNoteSpace,
    };
  }
}
