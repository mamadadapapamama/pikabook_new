import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../managers/page_manager.dart';

/// 페이지 로드 로직 테스트를 위한 화면
class PageTestScreen extends StatefulWidget {
  const PageTestScreen({Key? key}) : super(key: key);

  @override
  _PageTestScreenState createState() => _PageTestScreenState();
}

class _PageTestScreenState extends State<PageTestScreen> {
  final TextEditingController _noteIdController = TextEditingController();
  
  // 테스트 결과 상태 변수들
  bool _isLoading = false;
  String _statusMessage = '';
  List<page_model.Page> _loadedPages = [];
  Note? _loadedNote;
  String _errorMessage = '';

  // 로그 메시지
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 기본값으로 로그에 설정
    _log('테스트 화면이 준비되었습니다.');
    _log('노트 ID를 입력하고 테스트 버튼을 클릭하세요.');
  }

  @override
  void dispose() {
    _noteIdController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  // 로그 추가 함수
  void _log(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().split('.').first}] $message');
    });
    
    // 로그를 추가한 후 스크롤을 맨 아래로 이동
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Firestore에서 직접 노트 로드
  Future<void> _loadNoteDirectly() async {
    final noteId = _noteIdController.text.trim();
    if (noteId.isEmpty) {
      _log('❌ 노트 ID를 입력하세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '노트 로드 중...';
      _loadedPages = [];
      _loadedNote = null;
      _errorMessage = '';
    });

    _log('🔍 노트 로드 시작: noteId=$noteId');

    try {
      // 1. Firestore에서 노트 문서 로드
      _log('📄 Firestore에서 노트 문서 로드 중...');
      final noteDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(noteId)
          .get()
          .timeout(const Duration(seconds: 5));

      if (!noteDoc.exists) {
        _log('❌ 노트 문서를 찾을 수 없습니다: $noteId');
        setState(() {
          _isLoading = false;
          _statusMessage = '노트를 찾을 수 없습니다.';
          _errorMessage = '해당 ID의 노트가 존재하지 않습니다.';
        });
        return;
      }

      _log('✅ 노트 문서 로드 성공: ${noteDoc.id}');
      
      // 노트 객체 생성
      final note = Note.fromFirestore(noteDoc);
      _log('📝 노트 제목: ${note.originalText}');
      _log('📝 노트 이미지 URL: ${note.imageUrl ?? "없음"}');
      _log('📝 노트 페이지 수: ${note.pages.length}');

      // 2. Firestore에서 페이지 문서 로드
      _log('📚 Firestore에서 페이지 문서 로드 중...');
      final pagesSnapshot = await FirebaseFirestore.instance
          .collection('pages')
          .where('noteId', isEqualTo: noteId)
          .orderBy('pageNumber')
          .get()
          .timeout(const Duration(seconds: 5));

      _log('✅ 페이지 문서 로드 결과: ${pagesSnapshot.docs.length}개 문서');

      // 페이지 객체 생성
      final pages = pagesSnapshot.docs
          .map((doc) => page_model.Page.fromFirestore(doc))
          .toList();

      // 페이지 번호순으로 정렬
      pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

      // 3. PageManager로 테스트
      _log('🔄 PageManager 테스트 시작...');
      final pageManager = PageManager(
        noteId: noteId,
        initialNote: null,
        useCacheFirst: false,
      );

      _log('📥 PageManager에 loadPagesFromServer 호출...');
      final loadedPages = await pageManager.loadPagesFromServer(forceRefresh: true);
      _log('✅ PageManager 로드 결과: ${loadedPages.length}개 페이지');

      // 결과 업데이트
      setState(() {
        _isLoading = false;
        _loadedNote = note;
        _loadedPages = pages;
        _statusMessage = '로드 완료: ${pages.length}개 페이지';
      });

      // 각 페이지 정보 로깅
      for (int i = 0; i < pages.length; i++) {
        final page = pages[i];
        _log('📄 페이지[$i]: ID=${page.id}, 번호=${page.pageNumber}, 내용길이=${page.originalText.length}, 이미지=${page.imageUrl != null ? "있음" : "없음"}');
      }

    } catch (e, stackTrace) {
      _log('❌ 오류 발생: $e');
      _log('스택 트레이스: $stackTrace');
      setState(() {
        _isLoading = false;
        _statusMessage = '오류 발생';
        _errorMessage = e.toString();
      });
    }
  }

  // PageManager만 사용하여 페이지 로드 테스트
  Future<void> _testPageManager() async {
    final noteId = _noteIdController.text.trim();
    if (noteId.isEmpty) {
      _log('❌ 노트 ID를 입력하세요.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'PageManager 테스트 중...';
      _loadedPages = [];
      _loadedNote = null;
      _errorMessage = '';
    });

    _log('🔄 PageManager 테스트 시작: noteId=$noteId');

    try {
      final pageManager = PageManager(
        noteId: noteId,
        initialNote: null,
        useCacheFirst: false,
      );

      _log('📥 PageManager에 loadPagesFromServer 호출...');
      final loadedPages = await pageManager.loadPagesFromServer(forceRefresh: true);
      
      setState(() {
        _isLoading = false;
        _loadedPages = loadedPages;
        _statusMessage = 'PageManager 테스트 완료: ${loadedPages.length}개 페이지';
      });

      _log('✅ PageManager 로드 결과: ${loadedPages.length}개 페이지');

      // 각 페이지 정보 로깅
      for (int i = 0; i < loadedPages.length; i++) {
        final page = loadedPages[i];
        _log('📄 페이지[$i]: ID=${page.id}, 번호=${page.pageNumber}, 내용길이=${page.originalText.length}, 이미지=${page.imageUrl != null ? "있음" : "없음"}');
      }

    } catch (e, stackTrace) {
      _log('❌ 오류 발생: $e');
      _log('스택 트레이스: $stackTrace');
      setState(() {
        _isLoading = false;
        _statusMessage = 'PageManager 테스트 오류';
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('페이지 로드 테스트'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              setState(() {
                _logs.clear();
                _log('로그가 초기화되었습니다.');
              });
            },
            tooltip: '로그 지우기',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 노트 ID 입력 필드
            TextField(
              controller: _noteIdController,
              decoration: const InputDecoration(
                labelText: '노트 ID',
                hintText: '테스트할 노트 ID를 입력하세요',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            // 테스트 버튼들
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _loadNoteDirectly,
                    child: const Text('직접 Firestore에서 로드'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _testPageManager,
                    child: const Text('PageManager로 테스트'),
                  ),
                ),
              ],
            ),
            
            // 상태 표시
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _errorMessage.isNotEmpty ? Colors.red : Colors.blue,
                ),
              ),
            ),
            
            // 에러 메시지
            if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  '오류: $_errorMessage',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            
            // 로드된 페이지 정보
            if (_loadedPages.isNotEmpty) ...[
              const Divider(),
              Text(
                '로드된 페이지: ${_loadedPages.length}개',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  itemCount: _loadedPages.length,
                  itemBuilder: (context, index) {
                    final page = _loadedPages[index];
                    return ListTile(
                      dense: true,
                      title: Text('페이지 ${page.pageNumber + 1}'),
                      subtitle: Text('ID: ${page.id}'),
                      trailing: page.imageUrl != null
                          ? const Icon(Icons.image, color: Colors.green)
                          : const Icon(Icons.no_photography, color: Colors.grey),
                    );
                  },
                ),
              ),
            ],
            
            // 로그 영역
            const Divider(),
            const Text('로그:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(8),
                child: ListView.builder(
                  controller: _logScrollController,
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    Color textColor = Colors.white;
                    
                    // 로그 타입에 따라 색상 지정
                    if (log.contains('❌')) {
                      textColor = Colors.red;
                    } else if (log.contains('✅')) {
                      textColor = Colors.green;
                    } else if (log.contains('⚠️')) {
                      textColor = Colors.yellow;
                    } else if (log.contains('🔍') || log.contains('📄') || log.contains('🔄')) {
                      textColor = Colors.cyan;
                    }
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        log,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: textColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 