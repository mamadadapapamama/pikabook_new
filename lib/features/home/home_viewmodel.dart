import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../core/models/note.dart';
import '../../features/note/services/note_service.dart';
import '../../core/services/cache/cache_manager.dart';
import '../../core/widgets/loading_dialog_experience.dart';
import '../../core/services/common/usage_limit_service.dart';

class HomeViewModel extends ChangeNotifier {
  final NoteService _noteService = NoteService();
  final CacheManager _cacheManager = CacheManager();
  final UsageLimitService _usageLimitService = UsageLimitService();

  List<Note> _notes = [];
  bool _isLoading = true;
  String? _error;
  StreamSubscription<List<Note>>? _notesSubscription;
  
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

  // 생성자에서 노트 목록을 불러옵니다.
  HomeViewModel() {
    _initializeViewModel();
  }

  // ViewModel 초기화
  Future<void> _initializeViewModel() async {
    debugPrint('[HomeViewModel] 초기화 시작');
    try {
      // CacheManager는 App.dart에서 이미 초기화됨
      debugPrint('[HomeViewModel] CacheManager 초기화 스킵 (App.dart에서 이미 초기화됨)');
      
      // 사용량 제한 상태 확인
      await _checkUsageLimits();
      
      // 캐시된 데이터가 있고 유효한 경우 먼저 표시
      final cachedNotes = await _cacheManager.getCachedNotes();
      if (cachedNotes.isNotEmpty) {
        debugPrint('[HomeViewModel] 캐시된 노트 ${cachedNotes.length}개 로드됨');
        _notes = cachedNotes;
        _isLoading = false;
        notifyListeners();

        // 캐시 시간 확인을 위해 로컬 메모리에도 캐싱
        await _cacheManager.updateLastCacheTimeCache();
      } else {
        debugPrint('[HomeViewModel] 캐시된 노트 없음');
      }
      
      // 서버에서 최신 데이터 로드 - 캐시 유효성과 상관없이 항상 백그라운드로 실행
      _loadNotes();
    } catch (e, stackTrace) {
      debugPrint('[HomeViewModel] 초기화 중 오류 발생: $e');
      debugPrint('[HomeViewModel] 스택 트레이스: $stackTrace');
      // 캐시 로드 실패는 무시하고 서버에서 로드 진행
      _loadNotes();
    }
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

  // 캐시 유효성 확인
  bool _isCacheValid() {
    // CacheManager의 메서드 사용
    return _cacheManager.isCacheValid(validDuration: const Duration(minutes: 5));
  }

  // 노트 생성 중인지 확인
  bool _isNoteCreationInProgress() {
    // NoteCreationLoader의 상태를 확인하여 노트 생성 중인지 판단
    return NoteCreationLoader.isVisible;
  }

  // 노트 목록 로드
  void _loadNotes() {
    debugPrint('[HomeViewModel] _loadNotes 시작');
    _error = null;

    // 이미 로드된 캐시가 있는 경우 로딩 상태 표시하지 않음
    if (_notes.isEmpty && !_isLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      // 기존 구독이 있으면 취소
      _cancelSubscription();
      debugPrint('[HomeViewModel] 기존 구독 취소 완료');

      // 모든 노트 목록 구독 시도
      debugPrint('[HomeViewModel] 노트 스트림 구독 시작');
      _notesSubscription = _noteService.getNotes().listen(
        (notesList) {
          debugPrint('[HomeViewModel] 노트 데이터 수신: ${notesList.length}개');
          
          // 노트 생성 중일 때는 리스트 업데이트 스킵
          if (_isNoteCreationInProgress()) {
            debugPrint('[HomeViewModel] 노트 생성 중 - 리스트 업데이트 스킵');
            return;
          }
          
          // 상태가 실제로 변경되었을 때만 notifyListeners 호출
          bool hasChanged = false;
          
          if (_notes.length != notesList.length) {
            hasChanged = true;
          } else {
            // 노트 내용이 변경되었는지 확인 (자주 변경되는 필드만)
            for (int i = 0; i < notesList.length; i++) {
              if (i >= _notes.length || 
                  _notes[i].id != notesList[i].id || 
                  _notes[i].title != notesList[i].title ||
                  _notes[i].flashcardCount != notesList[i].flashcardCount) {
                hasChanged = true;
                break;
              }
            }
          }
          
          _notes = notesList;
          
          if (_isLoading) {
            _isLoading = false;
            hasChanged = true;
          }
          
          if (_error != null) {
            _error = null;
            hasChanged = true;
          }
          
          if (hasChanged) {
            debugPrint('[HomeViewModel] 실제 변경 감지됨 - UI 업데이트');
            notifyListeners();
          } else {
            debugPrint('[HomeViewModel] 변경 없음 - UI 업데이트 스킵');
          }
        },
        onError: (e, stackTrace) {
          debugPrint('[HomeViewModel] 노트 스트림 구독 중 오류: $e');
          debugPrint('[HomeViewModel] 스택 트레이스: $stackTrace');
          
          // 캐시된 데이터가 있으면 오류 표시하지 않음
          if (_notes.isEmpty) {
            bool hasChanged = false;
            
            if (_isLoading) {
              _isLoading = false;
              hasChanged = true;
            }
            
            final errorMessage = '노트 목록을 불러오는 중 오류가 발생했습니다: $e';
            if (_error != errorMessage) {
              _error = errorMessage;
              hasChanged = true;
            }
            
            if (hasChanged) {
              notifyListeners();
            }
          }
        },
      );
    } catch (e, stackTrace) {
      debugPrint('[HomeViewModel] _loadNotes에서 예외 발생: $e');
      debugPrint('[HomeViewModel] 스택 트레이스: $stackTrace');
      
      // 캐시된 데이터가 있으면 오류 표시하지 않음
      if (_notes.isEmpty) {
        bool hasChanged = false;
        
        if (_isLoading) {
          _isLoading = false;
          hasChanged = true;
        }
        
        final errorMessage = '노트 목록을 불러오는 중 오류가 발생했습니다: $e';
        if (_error != errorMessage) {
          _error = errorMessage;
          hasChanged = true;
        }
        
        if (hasChanged) {
          notifyListeners();
        }
      }
    }
  }

  // 노트 목록 새로고침
  Future<void> refreshNotes() async {
    _cancelSubscription();
    _notes = [];
    // 캐시도 삭제하여 완전히 새로운 데이터 가져오기
    await _cacheManager.clearCache();
    _loadNotes();
    return Future.value(); // RefreshIndicator를 위해 Future 반환
  }

  // 구독 취소
  void _cancelSubscription() {
    debugPrint('[HomeViewModel] 구독 취소 시도');
    if (_notesSubscription != null) {
      _notesSubscription!.cancel();
      _notesSubscription = null;
      debugPrint('[HomeViewModel] 구독 취소 완료');
    }
  }

  // 노트 삭제 메서드
  Future<void> deleteNote(String noteId) async {
    try {
      // 로컬 상태 먼저 업데이트 (UI 즉시 반영)
      final index = _notes.indexWhere((note) => note.id == noteId);
      if (index >= 0) {
        final deletedNote = _notes[index];
        _notes.removeAt(index);
        notifyListeners();

        try {
          // 서버에서 삭제
          await _noteService.deleteNote(noteId);
          debugPrint('[HomeViewModel] 노트 삭제 완료: $noteId');
        } catch (e) {
          // 서버 삭제 실패 시 로컬 상태 복원
          _notes.insert(index, deletedNote);
          _error = '노트 삭제 중 오류가 발생했습니다: $e';
          notifyListeners();
          debugPrint('[HomeViewModel] 노트 삭제 실패, 상태 복원: $e');
          
          // 삭제 실패 시 노트 목록 다시 로드
          refreshNotes();
        }
      } else {
        debugPrint('[HomeViewModel] 삭제할 노트를 찾을 수 없음: $noteId');
      }
    } catch (e) {
      debugPrint('[HomeViewModel] 노트 삭제 중 예외 발생: $e');
      _error = '노트 삭제 중 오류가 발생했습니다: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    debugPrint('[HomeViewModel] dispose 호출됨');
    _cancelSubscription();
    super.dispose();
  }
}
