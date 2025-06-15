import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/models/dictionary.dart';
import 'dictionary_service.dart';

/// 통합 사전 서비스 (래퍼)
/// 로그인 상태에 따라 적절한 사전 서비스를 사용합니다.
/// - 로그인 전: 사전 기능 제한 (프리미엄 기능)
/// - 로그인 후: DictionaryService (완전한 기능)
class UnifiedDictionaryService {
  // 싱글톤 패턴
  static final UnifiedDictionaryService _instance = UnifiedDictionaryService._internal();
  factory UnifiedDictionaryService() => _instance;
  UnifiedDictionaryService._internal();

  // 서비스 인스턴스들
  final DictionaryService _dictionaryService = DictionaryService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 초기화 상태
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) {
        debugPrint('🔗 [UnifiedDictionary] 통합 사전 서비스 초기화 시작');
      }

      // 로그인 상태에 따라 적절한 서비스 초기화
      if (_isLoggedIn) {
        if (kDebugMode) {
          debugPrint('👤 [UnifiedDictionary] 로그인 상태 - DictionaryService 초기화');
        }
        await _dictionaryService.initialize();
      } else {
        if (kDebugMode) {
          debugPrint('🏠 [UnifiedDictionary] 비로그인 상태 - 사전 기능 제한');
        }
        // 비로그인 상태에서는 사전 기능을 제한
      }

      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('✅ [UnifiedDictionary] 초기화 완료 (로그인: $_isLoggedIn)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedDictionary] 초기화 실패: $e');
      }
      rethrow;
    }
  }

  /// 로그인 상태 확인
  bool get _isLoggedIn => _auth.currentUser != null;

  /// 단어 검색 (통합 인터페이스)
  Future<Map<String, dynamic>> lookupWord(String word) async {
    await _ensureInitialized();

    if (kDebugMode) {
      debugPrint('🔍 [UnifiedDictionary] 단어 검색: "$word" (로그인: $_isLoggedIn)');
    }

    try {
      if (_isLoggedIn) {
        // 로그인 상태 - 완전한 사전 기능 사용
        return await _dictionaryService.lookupWord(word);
      } else {
        // 비로그인 상태 - 샘플 모드에서 제한적 사전 기능 사용
        return await _dictionaryService.lookupWord(word);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedDictionary] 검색 실패: $e');
      }
      return {
        'success': false,
        'message': '단어 검색 중 오류가 발생했습니다: $e',
      };
    }
  }

  /// 단순 검색 인터페이스 (DictionaryEntry 반환)
  Future<DictionaryEntry?> lookup(String word) async {
    final result = await lookupWord(word);
    return result['success'] == true ? result['entry'] as DictionaryEntry? : null;
  }

  /// 사전에 단어 추가 (로그인 상태에서만 가능)
  Future<void> addEntry(DictionaryEntry entry) async {
    if (!_isLoggedIn) {
      if (kDebugMode) {
        debugPrint('⚠️ [UnifiedDictionary] 비로그인 상태에서 단어 추가 시도 무시');
      }
      return;
    }

    await _ensureInitialized();
    await _dictionaryService.addEntry(entry);
  }

  /// 사전 업데이트 리스너 관리 (로그인 상태에서만)
  void addDictionaryUpdateListener(Function() listener) {
    if (_isLoggedIn) {
      _dictionaryService.addDictionaryUpdateListener(listener);
    }
  }

  void removeDictionaryUpdateListener(Function() listener) {
    if (_isLoggedIn) {
      _dictionaryService.removeDictionaryUpdateListener(listener);
    }
  }

  /// 캐시 정리
  Future<void> clearCache() async {
    try {
      if (_isLoggedIn) {
        await _dictionaryService.clearCache();
      }
      if (kDebugMode) {
        debugPrint('🧹 [UnifiedDictionary] 캐시 정리 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedDictionary] 캐시 정리 실패: $e');
      }
    }
  }

  /// 로그인 상태 변경 시 재초기화
  Future<void> onAuthStateChanged() async {
    if (kDebugMode) {
      debugPrint('🔄 [UnifiedDictionary] 로그인 상태 변경 감지 - 재초기화');
    }
    
    _isInitialized = false;
    await initialize();
  }

  /// 초기화 확인
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// 현재 사용 중인 서비스 타입 (디버깅용)
  String get currentServiceType => _isLoggedIn ? 'DictionaryService' : 'Limited';

  /// 샘플 모드에서 사용 가능한 단어 목록 (비로그인 상태에서는 빈 목록)
  List<String> getSampleWords() {
    return [];
  }
} 