import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flip_card/flip_card.dart';
import 'package:pinyin/pinyin.dart';
import '../../models/flash_card.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/tts_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../services/chinese_dictionary_service.dart';

/// 플래시카드 화면 위젯
/// 사용자가 생성한 플래시카드를 보여주고 관리하는 화면
class FlashCardScreen extends StatefulWidget {
  final String? noteId; // 특정 노트의 플래시카드만 표시할 때 사용

  const FlashCardScreen({super.key, this.noteId});

  @override
  State<FlashCardScreen> createState() => _FlashCardScreenState();
}

class _FlashCardScreenState extends State<FlashCardScreen> {
  final FlashCardService _flashCardService = FlashCardService();
  final TtsService _ttsService = TtsService();
  final ChineseDictionaryService _dictionaryService =
      ChineseDictionaryService();
  final CardSwiperController _cardController = CardSwiperController();
  final GlobalKey<FlipCardState> _flipCardKey = GlobalKey<FlipCardState>();

  List<FlashCard> _flashCards = []; // 플래시카드 목록
  bool _isLoading = true; // 로딩 상태
  int _currentIndex = 0; // 현재 보고 있는 카드 인덱스
  bool _isFlipped = false; // 카드 뒤집힘 상태
  bool _isSpeaking = false; // TTS 실행 중 상태

  @override
  void initState() {
    super.initState();
    _loadFlashCards(); // 플래시카드 로드
    _initTts(); // TTS 초기화
    _dictionaryService.loadDictionary(); // 중국어 사전 로드
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _cardController.dispose();
    super.dispose();
  }

  /// TTS 서비스 초기화
  Future<void> _initTts() async {
    try {
      await _ttsService.init();
    } catch (e) {
      debugPrint('TTS 초기화 중 오류 발생: $e');
    }
  }

  /// 플래시카드 목록 로드
  Future<void> _loadFlashCards() async {
    setState(() => _isLoading = true);

    try {
      // noteId가 있으면 해당 노트의 플래시카드만, 없으면 모든 플래시카드 로드
      _flashCards = widget.noteId != null
          ? await _flashCardService.getFlashCardsForNote(widget.noteId!)
          : await _flashCardService.getAllFlashCards();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentIndex = 0;
          _isFlipped = false;
        });

        // 플래시카드가 있으면 첫 번째 카드의 복습 횟수 업데이트
        if (_flashCards.isNotEmpty) _updateFlashCardReviewCount();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // 오류 메시지를 SnackBar로 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('플래시카드를 불러오는 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  /// 플래시카드 복습 횟수 업데이트
  Future<void> _updateFlashCardReviewCount() async {
    if (_flashCards.isEmpty || _currentIndex >= _flashCards.length) return;

    try {
      final updatedCard =
          await _flashCardService.updateFlashCard(_flashCards[_currentIndex]);

      if (mounted) {
        setState(() {
          _flashCards[_currentIndex] = updatedCard;
        });
      }
    } catch (e) {
      debugPrint('플래시카드 복습 횟수 업데이트 중 오류 발생: $e');
    }
  }

  /// 카드 뒤집기
  void _flipCard() {
    _flipCardKey.currentState?.toggleCard();
    setState(() => _isFlipped = !_isFlipped);
  }

  /// 현재 카드 음성 재생
  Future<void> _speakCurrentCard() async {
    if (_flashCards.isEmpty || _currentIndex >= _flashCards.length) return;

    // 항상 중국어(front)만 읽도록 수정
    final textToSpeak = _flashCards[_currentIndex].front;

    if (textToSpeak.isEmpty) return;

    setState(() {
      _isSpeaking = true;
    });

    try {
      // 항상 중국어 발음으로 설정
      await _ttsService.setLanguage('zh-CN');
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

  /// TTS 중지
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

  /// 카드 스와이프 처리
  bool _onSwipe(
      int? previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (_flashCards.isEmpty) return false;

    debugPrint(
        '스와이프: 이전 인덱스=$previousIndex, 현재 인덱스=$currentIndex, 방향=$direction');

    setState(() {
      // 왼쪽으로 스와이프: 다음 카드
      if (direction == CardSwiperDirection.left &&
          _currentIndex < _flashCards.length - 1) {
        _currentIndex++;
      }
      // 오른쪽으로 스와이프: 이전 카드
      else if (direction == CardSwiperDirection.right && _currentIndex > 0) {
        _currentIndex--;
      }
      // 위로 스와이프: 카드 삭제
      else if (direction == CardSwiperDirection.top) {
        _deleteCurrentCard();
      }
      _isFlipped = false;
    });

    _updateFlashCardReviewCount();
    return true;
  }

  /// 현재 카드 삭제
  Future<void> _deleteCurrentCard() async {
    if (_flashCards.isEmpty || _currentIndex >= _flashCards.length) return;

    final flashCardId = _flashCards[_currentIndex].id;
    final noteId = _flashCards[_currentIndex].noteId;

    try {
      // 플래시카드 서비스를 통해 카드 삭제
      await _flashCardService.deleteFlashCard(flashCardId, noteId: noteId);

      if (mounted) {
        setState(() {
          _flashCards.removeAt(_currentIndex);
          if (_currentIndex >= _flashCards.length) {
            _currentIndex = _flashCards.length - 1;
          }
        });

        if (_flashCards.isEmpty) {
          setState(() {});
        }

        // 노트 페이지로 돌아갈 때 변경 사항을 알리기 위해 결과 설정
        Navigator.of(context).pop(true);
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
                  '${_currentIndex + 1} / ${_flashCards.length}',
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
          ? const Center(child: LoadingIndicator(message: '플래시카드 로딩 중...'))
          : _flashCards.isEmpty
              ? const Center(child: Text('플래시카드가 없습니다.'))
              : Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: CardSwiper(
                          controller: _cardController,
                          cardsCount: _flashCards.length,
                          onSwipe: _onSwipe,
                          // 스와이프 방향 설정 수정
                          allowedSwipeDirection:
                              AllowedSwipeDirection.symmetric(
                            horizontal: true,
                            vertical: true,
                          ),
                          // 스와이프 방향 변경 콜백 수정
                          onSwipeDirectionChange: (_, direction) {
                            debugPrint('스와이프 방향 변경됨: $direction');
                          },
                          // 카드 3개 겹쳐서 보이도록 설정
                          numberOfCardsDisplayed: 3,
                          backCardOffset: const Offset(0, 10),
                          padding: const EdgeInsets.all(24.0),
                          cardBuilder: (context, index, _, __) {
                            return _buildFlashCard(index);
                          },
                        ),
                      ),
                    ),
                    // 하단 버튼 영역
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.flip),
                            onPressed:
                                _flashCards.isNotEmpty ? _flipCard : null,
                            iconSize: 32.0,
                            color: _flashCards.isNotEmpty
                                ? Colors.blue
                                : Colors.grey,
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: _flashCards.isNotEmpty
                                ? _deleteCurrentCard
                                : null,
                            iconSize: 32.0,
                            color: _flashCards.isNotEmpty
                                ? Colors.red
                                : Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  /// 플래시카드 위젯 생성
  Widget _buildFlashCard(int index) {
    if (index >= _flashCards.length) return Container();

    final card = _flashCards[index];

    return FlipCard(
      key: index == _currentIndex ? _flipCardKey : null,
      direction: FlipDirection.HORIZONTAL,
      speed: 300,
      onFlipDone: (isFront) => setState(() => _isFlipped = !isFront),
      front: _buildCardSide(
        card.front,
        card.pinyin,
        Colors.white,
        Colors.blue.shade800,
        true,
      ),
      back: _buildCardSide(
        card.back,
        card.pinyin,
        Colors.blue.shade50,
        Colors.blue.shade800,
        false,
      ),
    );
  }

  /// 카드 앞/뒷면 위젯 생성
  Widget _buildCardSide(String text, String? pinyin, Color bgColor,
      Color textColor, bool isFront) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 32.0,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (pinyin != null && pinyin.isNotEmpty) ...[
                    const SizedBox(height: 16.0),
                    Text(
                      pinyin,
                      style: TextStyle(
                        fontSize: 20.0,
                        color: textColor.withOpacity(0.7),
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // TTS 버튼은 앞면(중국어)에서만 표시
          if (isFront)
            Positioned(
              top: 16.0,
              right: 16.0,
              child: IconButton(
                icon: Icon(
                  _isSpeaking ? Icons.volume_up : Icons.volume_up_outlined,
                  color: textColor,
                ),
                onPressed: _isSpeaking ? _stopSpeaking : _speakCurrentCard,
              ),
            ),
          Positioned(
            bottom: 16.0,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                isFront ? '왼쪽으로 스와이프하여 다음 카드, 오른쪽으로 이전 카드' : '탭하여 단어 보기',
                style: TextStyle(
                  fontSize: 12.0,
                  color: textColor.withOpacity(0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
