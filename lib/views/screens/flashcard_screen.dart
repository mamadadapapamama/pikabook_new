import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../../models/flash_card.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/tts_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../services/dictionary_service.dart';
import '../../widgets/dictionary_popup.dart';

class FlashCardScreen extends StatefulWidget {
  final String? noteId; // 특정 노트의 플래시카드만 표시하려면 noteId 전달

  const FlashCardScreen({Key? key, this.noteId}) : super(key: key);

  @override
  State<FlashCardScreen> createState() => _FlashCardScreenState();
}

class _FlashCardScreenState extends State<FlashCardScreen> {
  final FlashCardService _flashCardService = FlashCardService();
  final TtsService _ttsService = TtsService();

  List<FlashCard> _flashCards = [];
  bool _isLoading = true;
  String? _error;
  int _currentIndex = 0;
  bool _isFlipped = false; // 카드가 뒤집혔는지 여부
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadFlashCards();
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }

  Future<void> _initTts() async {
    try {
      await _ttsService.init();
    } catch (e) {
      debugPrint('TTS 초기화 중 오류 발생: $e');
    }
  }

  Future<void> _loadFlashCards() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<FlashCard> flashCards;

      if (widget.noteId != null) {
        // 특정 노트의 플래시카드만 가져오기
        try {
          flashCards =
              await _flashCardService.getFlashCardsForNote(widget.noteId!);
        } catch (e) {
          debugPrint('노트별 플래시카드 조회 중 오류 발생: $e');
          // 인덱스 오류 발생 시 대체 방법으로 모든 플래시카드를 가져와서 필터링
          final allCards = await _flashCardService.getAllFlashCards();
          flashCards =
              allCards.where((card) => card.noteId == widget.noteId).toList();
        }
      } else {
        // 모든 플래시카드 가져오기
        flashCards = await _flashCardService.getAllFlashCards();
      }

      if (mounted) {
        setState(() {
          _flashCards = flashCards;
          _isLoading = false;
          _currentIndex = 0;
          _isFlipped = false;
        });

        // 플래시카드가 있으면 첫 번째 카드의 복습 횟수 업데이트
        if (_flashCards.isNotEmpty) {
          _updateFlashCardReviewCount();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '플래시카드를 불러오는 중 오류가 발생했습니다: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateFlashCardReviewCount() async {
    if (_flashCards.isEmpty || _currentIndex >= _flashCards.length) return;

    try {
      final updatedCard = await _flashCardService.updateFlashCard(
        _flashCards[_currentIndex],
      );

      if (mounted) {
        setState(() {
          _flashCards[_currentIndex] = updatedCard;
        });
      }
    } catch (e) {
      debugPrint('플래시카드 복습 횟수 업데이트 중 오류 발생: $e');
    }
  }

  Future<void> _speakCurrentCard() async {
    if (_flashCards.isEmpty || _currentIndex >= _flashCards.length) return;

    final textToSpeak = _isFlipped
        ? _flashCards[_currentIndex].back
        : _flashCards[_currentIndex].front;

    if (textToSpeak.isEmpty) return;

    setState(() {
      _isSpeaking = true;
    });

    try {
      await _ttsService.speak(textToSpeak);
    } catch (e) {
      debugPrint('TTS 실행 중 오류 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성 재생 중 오류가 발생했습니다: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    }
  }

  Future<void> _stopSpeaking() async {
    if (!_isSpeaking) return;

    try {
      await _ttsService.stop();
      setState(() {
        _isSpeaking = false;
      });
    } catch (e) {
      debugPrint('TTS 중지 중 오류 발생: $e');
    }
  }

  void _flipCard() {
    setState(() {
      _isFlipped = !_isFlipped;
    });
  }

  void _nextCard() {
    if (_currentIndex < _flashCards.length - 1) {
      setState(() {
        _currentIndex++;
        _isFlipped = false;
      });
      _updateFlashCardReviewCount();
    }
  }

  void _previousCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _isFlipped = false;
      });
      _updateFlashCardReviewCount();
    }
  }

  Future<void> _deleteCurrentCard() async {
    if (_flashCards.isEmpty || _currentIndex >= _flashCards.length) return;

    final flashCardId = _flashCards[_currentIndex].id;
    final noteId = _flashCards[_currentIndex].noteId;

    try {
      await _flashCardService.deleteFlashCard(flashCardId, noteId: noteId);

      if (mounted) {
        setState(() {
          _flashCards.removeAt(_currentIndex);
          if (_currentIndex >= _flashCards.length) {
            _currentIndex = _flashCards.isEmpty ? 0 : _flashCards.length - 1;
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('플래시카드가 삭제되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('플래시카드 삭제 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('플래시카드'),
        actions: [
          if (_flashCards.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  '${_currentIndex + 1}/${_flashCards.length}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const LoadingIndicator(message: '플래시카드 불러오는 중...')
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadFlashCards,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : _flashCards.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.school_outlined,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            '저장된 플래시카드가 없습니다.\n노트 상세 화면에서 텍스트를 선택하여 플래시카드를 추가해보세요!',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('돌아가기'),
                          ),
                        ],
                      ),
                    )
                  : _buildFlashCardContent(),
    );
  }

  Widget _buildFlashCardContent() {
    final currentCard = _flashCards[_currentIndex];

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _flipCard,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: _isFlipped
                      ? _buildCardBack(currentCard)
                      : _buildCardFront(currentCard),
                ),
              ),
            ),
          ),
        ),
        _buildCardControls(),
      ],
    );
  }

  Widget _buildCardFront(FlashCard card) {
    return Container(
      key: const ValueKey<String>('front'),
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '중국어',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onLongPress: () => _showDictionaryPopup(card.front),
            child: Text(
              card.front,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: _buildWordChips(card.front),
          ),
          const SizedBox(height: 16),
          Text(
            card.pinyin,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[700],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const Text(
            '탭하여 뒤집기',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // 단어 칩 위젯 생성
  List<Widget> _buildWordChips(String text) {
    final dictionaryService = DictionaryService();
    final words = dictionaryService.segmentChineseText(text);

    return words.map((word) {
      final entry = dictionaryService.lookupWord(word);
      return ActionChip(
        label: Text(word),
        backgroundColor:
            entry != null ? Colors.blue.shade50 : Colors.grey.shade200,
        onPressed: () => _showDictionaryPopup(word),
      );
    }).toList();
  }

  // 사전 팝업 표시
  void _showDictionaryPopup(String word) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: DictionaryPopup(
          word: word,
          onClose: () => Navigator.of(context).pop(),
          onAddToFlashcard: (word, pinyin, meaning) {
            Navigator.of(context).pop();
            _addToFlashcard(word, pinyin, meaning);
          },
        ),
      ),
    );
  }

  // 플래시카드 추가
  void _addToFlashcard(String word, String pinyin, String meaning) async {
    try {
      setState(() => _isLoading = true);

      final flashCardService = FlashCardService();
      final userId = FirebaseAuth.instance.currentUser?.uid;

      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인이 필요합니다')),
        );
        return;
      }

      await flashCardService.createFlashCard(
        front: word,
        back: meaning,
        noteId: widget.noteId,
      );

      // 플래시카드 목록 새로고침
      await _loadFlashCards();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('플래시카드가 추가되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('플래시카드 추가 실패: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildCardBack(FlashCard card) {
    return Container(
      key: const ValueKey<String>('back'),
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '번역',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            card.back,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const Text(
            '탭하여 뒤집기',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardControls() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _currentIndex > 0 ? _previousCard : null,
            tooltip: '이전 카드',
            iconSize: 32,
          ),
          IconButton(
            icon: Icon(_isSpeaking ? Icons.stop : Icons.volume_up),
            onPressed: _isSpeaking ? _stopSpeaking : _speakCurrentCard,
            tooltip: _isSpeaking ? '음성 중지' : '음성으로 듣기',
            iconSize: 32,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteCurrentCard,
            tooltip: '카드 삭제',
            iconSize: 32,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed:
                _currentIndex < _flashCards.length - 1 ? _nextCard : null,
            tooltip: '다음 카드',
            iconSize: 32,
          ),
        ],
      ),
    );
  }
}
