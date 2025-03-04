import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../models/note.dart';
import '../repositories/note_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final NoteRepository _noteRepository = NoteRepository();
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final notes = await _noteRepository.getNotes();
      setState(() {
        _notes = notes;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading notes: $e');
      setState(() {
        _isLoading = false;
      });

      // 오류 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트를 불러오는 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Pikabook',
          style: TypographyTokens.headline2,
        ),
        backgroundColor: ColorTokens.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotes,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _notes.isEmpty
              ? Center(
                  child: Text(
                    '노트가 없습니다. + 버튼을 눌러 노트를 추가하세요.',
                    style: TypographyTokens.body1,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notes.length,
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        title: Text(
                          note.title,
                          style: TypographyTokens.headline3,
                        ),
                        subtitle: Text(
                          '플래시카드: ${note.flashcardCount}개',
                          style: TypographyTokens.body2,
                        ),
                        onTap: () {
                          // 노트 상세 화면으로 이동 (아직 구현 안 됨)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${note.title} 선택됨')),
                          );
                        },
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // 노트 추가 기능 구현 예정
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('노트 추가 기능 준비 중입니다.')),
          );
        },
        backgroundColor: ColorTokens.primary,
        child: const Icon(Icons.add),
      ),
    );
  }
}
