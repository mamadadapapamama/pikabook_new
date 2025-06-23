import 'package:flutter/foundation.dart';
import '../../core/models/dictionary.dart';
import 'dictionary_service.dart';

/// 사전 검색 기능을 담당하는 ViewModel
class DictionaryViewModel extends ChangeNotifier {
  // 서비스 인스턴스
  final DictionaryService _dictionaryService = DictionaryService();
  
  // 상태 변수
  bool _isLoading = false;
  String? _error;
  DictionaryEntry? _currentEntry;
  String _searchQuery = '';
  List<String> _recentSearches = [];
  
  // Getters
  bool get isLoading => _isLoading;
  String? get error => _error;
  DictionaryEntry? get currentEntry => _currentEntry;
  String get searchQuery => _searchQuery;
  List<String> get recentSearches => _recentSearches;
  
  // 사전 검색 (간단한 버전)
  Future<DictionaryEntry?> lookupWord(String word) async {
    if (word.isEmpty) {
      setError('검색할 단어가 비어있습니다');
      return null;
    }
    
    _searchQuery = word;
    setLoading(true);
    setError(null);
    
    try {
      // 간단한 사전 검색 (내부 사전에서만)
      final entry = await _dictionaryService.lookup(word);
      
      if (entry != null) {
        _currentEntry = entry;
        _addToRecentSearches(word);
        setLoading(false);
        notifyListeners();
        return entry;
      }
      
      // 검색 실패
      setError('단어를 찾을 수 없습니다: $word');
      setLoading(false);
      return null;
    } catch (e) {
      setError('사전 검색 중 오류 발생: $e');
      setLoading(false);
      return null;
    }
  }
  
  // 최근 검색어에 추가
  void _addToRecentSearches(String word) {
    // 이미 존재하는 경우 제거 후 맨 앞에 추가
    _recentSearches.remove(word);
    _recentSearches.insert(0, word);
    
    // 최대 10개만 유지
    if (_recentSearches.length > 10) {
      _recentSearches = _recentSearches.sublist(0, 10);
    }
    
    notifyListeners();
  }
  
  // 최근 검색어 목록 지우기
  void clearRecentSearches() {
    _recentSearches.clear();
    notifyListeners();
  }
  
  // 단어 검색 기록 가져오기
  Future<void> loadRecentSearches() async {
    // TODO: 최근 검색어 기능이 필요하면 구현
    // 현재는 빈 구현
  }
  
  // 로딩 상태 변경
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  // 오류 설정
  void setError(String? errorMessage) {
    _error = errorMessage;
    notifyListeners();
  }
  
  // 현재 사전 항목 지우기
  void clearCurrentEntry() {
    _currentEntry = null;
    notifyListeners();
  }
}
