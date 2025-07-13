import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../core/models/note.dart';
import '../../features/note/services/note_service.dart';
import '../../core/services/common/usage_limit_service.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeViewModel extends ChangeNotifier {
  final NoteService _noteService = NoteService();
  final UsageLimitService _usageLimitService = UsageLimitService();

  List<Note> _notes = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription<List<Note>>? _notesSubscription;
  StreamSubscription<User?>? _authStateSubscription; // 🎯 사용자 변경 감지용
  
  // 🆕 신규 사용자 플래그 (환영 모달 완료 전까지 최소 서비스 호출)
  bool _isNewUser = false;
  
  // 사용량 제한 상태
  bool _ocrLimitReached = false;
  bool _translationLimitReached = false;
  bool _ttsLimitReached = false;
  bool _storageLimitReached = false;

  // Getter
  List<Note> get notes => _notes;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasNotes => _notes.isNotEmpty;
  
  // 사용량 제한 상태 getters
  bool get ocrLimitReached => _ocrLimitReached;
  bool get translationLimitReached => _translationLimitReached;
  bool get ttsLimitReached => _ttsLimitReached;
  bool get storageLimitReached => _storageLimitReached;
  
  // 스마트노트 만들기 버튼 활성화 여부
  bool get canCreateNote => !_ocrLimitReached;

  // 생성자
  HomeViewModel() {
    _initializeViewModel();
  }

  /// 🆕 신규 사용자 설정 (환영 모달 완료 전까지 최소 서비스 호출)
  void setNewUser(bool isNewUser) {
    final wasNewUser = _isNewUser;
    _isNewUser = isNewUser;
    if (kDebugMode) {
      debugPrint('[HomeViewModel] 신규 사용자 플래그 설정: $wasNewUser → $_isNewUser');
    }
    
    // 🎉 환영 모달 완료 후 신규 사용자 → 기존 사용자로 전환 시 사용량 체크 시작
    if (wasNewUser && !isNewUser) {
      if (kDebugMode) {
        debugPrint('[HomeViewModel] 🎉 환영 모달 완료 - 이제 사용량 체크 시작');
      }
      _checkUsageLimits();
    }
  }

  // ViewModel 초기화 (단순한 Firestore 스트림)
  Future<void> _initializeViewModel() async {
    debugPrint('[HomeViewModel] 초기화 시작');
    try {
      // 🎯 사용자 변경 감지 리스너 설정
      _setupAuthStateListener();
      
      // 🚨 신규 사용자가 아닐 때만 사용량 제한 상태 확인
      if (!_isNewUser) {
        await _checkUsageLimits();
      } else {
        if (kDebugMode) {
          debugPrint('[HomeViewModel] 🆕 신규 사용자 - 사용량 체크 건너뜀');
        }
      }
      
      // Firestore 실시간 스트림 구독
      _subscribeToNoteService();
    } catch (e, stackTrace) {
      debugPrint('[HomeViewModel] 초기화 중 오류 발생: $e');
      debugPrint('[HomeViewModel] 스택 트레이스: $stackTrace');
      _handleError('노트 목록을 불러오는 중 오류가 발생했습니다: $e');
    }
  }

  /// 🎯 사용자 변경 감지 리스너 설정
  void _setupAuthStateListener() {
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (User? user) async {
        if (kDebugMode) {
          debugPrint('🔔 [HomeViewModel] 사용자 변경 감지: ${user?.uid ?? "로그아웃"}');
        }
        
        if (user == null) {
          // 로그아웃 시 상태 초기화
          _resetUsageLimits();
          if (kDebugMode) {
            debugPrint('🔄 [HomeViewModel] 로그아웃 - 사용량 상태 초기화');
          }
        } else {
          // 새 사용자 로그인 시 온보딩 상태 확인 후 사용량 상태 체크
          await _checkUsageLimitsAfterUserChange();
        }
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ [HomeViewModel] 사용자 변경 감지 오류: $error');
        }
      },
    );
  }

  /// 🔄 사용량 상태 초기화 (로그아웃 시)
  void _resetUsageLimits() {
    _ocrLimitReached = false;
    _translationLimitReached = false;
    _ttsLimitReached = false;
    _storageLimitReached = false;
    notifyListeners();
  }

  /// 🎯 사용자 변경 후 온보딩 상태 확인하여 사용량 체크
  Future<void> _checkUsageLimitsAfterUserChange() async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [HomeViewModel] 사용자 변경 후 온보딩 상태 확인');
      }
      
      // 🆕 신규 사용자도 사용량 체크는 수행 (이미 구독이 있을 수 있음)
      if (_isNewUser) {
        if (kDebugMode) {
          debugPrint('🔄 [HomeViewModel] 🆕 신규 사용자지만 사용량 체크는 수행 (이미 구독이 있을 수 있음)');
        }
        // 환영 모달은 여전히 표시하되, 사용량 체크는 정상 진행
      }
      
      // UserPreferencesService import 필요
      final userPrefsService = UserPreferencesService();
      final preferences = await userPrefsService.getPreferences();
      final hasCompletedOnboarding = preferences.onboardingCompleted;
      
      if (!hasCompletedOnboarding) {
        if (kDebugMode) {
          debugPrint('🔄 [HomeViewModel] 🆕 온보딩 미완료 사용자지만 사용량 상태는 체크 (이미 구독이 있을 수 있음)');
        }
        // 온보딩 미완료라도 사용량 상태는 정상 체크
      }
      
      if (kDebugMode) {
        debugPrint('🔄 [HomeViewModel] ✅ 기존 사용자 (온보딩 완료) - 사용량 상태 재체크');
      }
      
      // 온보딩 완료된 사용자만 사용량 상태 체크
      await _checkUsageLimits();
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeViewModel] 사용자 변경 후 사용량 체크 실패: $e');
      }
      // 오류 시 안전하게 제한 없음으로 설정
      _resetUsageLimits();
    }
  }

  /// NoteService 데이터 구독 (최적화된 업데이트)
  void _subscribeToNoteService() {
    _notesSubscription = _noteService.getNotes().listen(
      (notesList) {
        // 새로 받은 노트 수와 기존 노트 수 비교
        final newCount = notesList.length;
        final oldCount = _notes.length;
        
        if (kDebugMode) {
          debugPrint('[HomeViewModel] 📱 노트 데이터 수신: $newCount개 (이전: $oldCount개)');
        }
        
                 // 노트가 새로 추가된 경우 (1개 증가)
         if (newCount > oldCount && newCount == oldCount + 1) {
           // 새로운 노트 찾기 (가장 최근 생성된 노트)
           final newNotes = notesList.where((note) => 
             !_notes.any((existingNote) => existingNote.id == note.id)
           ).toList();
           
           if (newNotes.isNotEmpty) {
             // 새로운 노트를 리스트 맨 앞에 추가 (최신순 정렬 유지)
             _notes.insert(0, newNotes.first);
             if (kDebugMode) {
               debugPrint('[HomeViewModel] ✅ 새 노트 추가됨: ${newNotes.first.title}');
             }
           } else {
             // 새로운 노트를 찾지 못한 경우 전체 교체
             _notes = notesList;
             if (kDebugMode) {
               debugPrint('[HomeViewModel] 📱 전체 리스트 업데이트 (새 노트 미발견)');
             }
           }
         } else if (newCount == oldCount) {
           // 같은 수의 노트: 메타데이터 업데이트만 발생 (OCR 처리 등)
           // 전체 리빌드를 피하고 변경된 노트만 업데이트
           bool hasChanges = false;
           
           for (int i = 0; i < notesList.length && i < _notes.length; i++) {
             final newNote = notesList[i];
             final oldNote = _notes[i];
        
             // 같은 ID의 노트에서 메타데이터가 변경된 경우
             if (newNote.id == oldNote.id && 
                 (newNote.updatedAt != oldNote.updatedAt || 
                  newNote.pageCount != oldNote.pageCount ||
                  newNote.firstImageUrl != oldNote.firstImageUrl)) {
               _notes[i] = newNote;
               hasChanges = true;
               if (kDebugMode) {
                 debugPrint('[HomeViewModel] 📝 노트 메타데이터 업데이트: ${newNote.title}');
               }
             }
           }
           
           // 변경사항이 없으면 전체 교체 (안전장치)
           if (!hasChanges) {
             _notes = notesList;
             if (kDebugMode) {
               debugPrint('[HomeViewModel] 📱 전체 리스트 업데이트 (변경사항 미감지)');
             }
           }
         } else {
           // 기타 경우 (삭제, 대량 변경, 초기 로드 등)는 전체 교체
        _notes = notesList;
           if (kDebugMode) {
             if (newCount < oldCount) {
               debugPrint('[HomeViewModel] 🗑️ 노트 삭제됨 (전체 리스트 업데이트)');
             } else {
               debugPrint('[HomeViewModel] 📱 초기 로드 또는 대량 변경 (전체 리스트 업데이트)');
             }
           }
         }
        
        _isLoading = false;
        _error = null;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[HomeViewModel] 스트림 오류: $e');
        _handleError('노트 목록을 불러오는 중 오류가 발생했습니다: $e');
      },
    );
  }

  /// 오류 처리
  void _handleError(String errorMessage) {
    _isLoading = false;
    _error = errorMessage;
    notifyListeners();
  }

  /// 사용량 제한 상태 확인
  Future<void> _checkUsageLimits() async {
    try {
      final limits = await _usageLimitService.checkInitialLimitStatus();
      
      _ocrLimitReached = limits['ocrLimitReached'] ?? false;
      _translationLimitReached = limits['translationLimitReached'] ?? false;
      _ttsLimitReached = limits['ttsLimitReached'] ?? false;
      _storageLimitReached = limits['storageLimitReached'] ?? false;
      
      if (kDebugMode) {
        debugPrint('[HomeViewModel] 사용량 제한 상태 확인 완료:');
        debugPrint('   OCR 제한: $_ocrLimitReached');
        debugPrint('   번역 제한: $_translationLimitReached');
        debugPrint('   TTS 제한: $_ttsLimitReached');
        debugPrint('   스토리지 제한: $_storageLimitReached');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('[HomeViewModel] 사용량 제한 확인 중 오류: $e');
      // 오류 발생 시 기본값 유지 (제한 없음으로 가정)
    }
  }

  /// 사용량 제한 상태 새로고침 (노트 생성 후 호출)
  Future<void> refreshUsageLimits() async {
    await _checkUsageLimits();
  }

  /// 새로운 노트를 로컬 리스트에 즉시 추가 (UI 응답성 향상)
  void addNoteToList(Note newNote) {
    // 이미 존재하는 노트인지 확인
    if (_notes.any((note) => note.id == newNote.id)) {
      if (kDebugMode) {
        debugPrint('[HomeViewModel] 노트가 이미 존재함: ${newNote.id}');
      }
      return;
    }

    // 새로운 노트를 리스트 맨 앞에 추가 (최신순)
    _notes.insert(0, newNote);
    
    if (kDebugMode) {
      debugPrint('[HomeViewModel] ⚡ 새 노트 즉시 추가: ${newNote.title} (총 ${_notes.length}개)');
    }
    
    notifyListeners();
  }

  // 노트 삭제 메서드
  Future<void> deleteNote(String noteId) async {
    try {
      await _noteService.deleteNote(noteId);
      if (kDebugMode) {
        debugPrint('[HomeViewModel] 노트 삭제 요청 완료: $noteId');
      }
    } catch (e) {
      debugPrint('[HomeViewModel] 노트 삭제 중 예외 발생: $e');
      _handleError('노트 삭제 중 오류가 발생했습니다: $e');
    }
  }

  // 노트 목록 새로고침 (단순한 스트림 재구독)
  Future<void> refreshNotes() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // 기존 구독 취소 후 재구독 (Firestore가 새 데이터 가져옴)
      _notesSubscription?.cancel();
      _subscribeToNoteService();
      
      if (kDebugMode) {
        debugPrint('[HomeViewModel] 📱 노트 목록 새로고침 완료');
      }
    } catch (e) {
      debugPrint('[HomeViewModel] 새로고침 중 오류: $e');
      _handleError('새로고침 중 오류가 발생했습니다: $e');
    }
  }

  @override
  void dispose() {
    debugPrint('[HomeViewModel] dispose 호출됨');
    _notesSubscription?.cancel();
    _authStateSubscription?.cancel(); // 🎯 사용자 변경 감지 구독 취소
    super.dispose();
  }
}
