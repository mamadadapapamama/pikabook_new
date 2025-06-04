import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../core/models/note.dart';
import '../../features/note/services/note_service.dart';
import '../../core/services/common/usage_limit_service.dart';

class HomeViewModel extends ChangeNotifier {
  final NoteService _noteService = NoteService();
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

  // 생성자
  HomeViewModel() {
    _initializeViewModel();
  }

  // ViewModel 초기화 (단순한 Firestore 스트림)
  Future<void> _initializeViewModel() async {
    debugPrint('[HomeViewModel] 초기화 시작');
    try {
      // 사용량 제한 상태 확인
      await _checkUsageLimits();
      
      // Firestore 실시간 스트림 구독
      _subscribeToNoteService();
    } catch (e, stackTrace) {
      debugPrint('[HomeViewModel] 초기화 중 오류 발생: $e');
      debugPrint('[HomeViewModel] 스택 트레이스: $stackTrace');
      _handleError('노트 목록을 불러오는 중 오류가 발생했습니다: $e');
    }
  }

  /// NoteService 데이터 구독 (간단한 Firestore 스트림)
  void _subscribeToNoteService() {
    _notesSubscription = _noteService.getNotes().listen(
      (notesList) {
        debugPrint('[HomeViewModel] 📱 노트 ${notesList.length}개 수신');
        
        // UI 상태만 관리
        _notes = notesList;
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
    super.dispose();
  }
}
