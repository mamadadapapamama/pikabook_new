import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flip_card/flip_card.dart';
import 'package:pinyin/pinyin.dart';
import '../../models/flash_card.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/tts_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../services/dictionary_service.dart' hide DictionaryEntry;
import '../../services/chinese_dictionary_service.dart';
import '../../services/pinyin_creation_service.dart';

class FlashCardScreen extends StatefulWidget {
  final String? noteId; // 특정 노트의 플래시카드만 표시하려면 noteId 전달

  const FlashCardScreen({Key? key, this.noteId}) : super(key: key);

  @override
  State<FlashCardScreen> createState() => _FlashCardScreenState();
}

class _FlashCardScreenState extends State<FlashCardScreen> {
  final FlashCardService _flashCardService = FlashCardService();
  final TtsService _ttsService = TtsService();
  final PinyinCreationService _pinyinService = PinyinCreationService();
  final CardSwiperController _cardController = CardSwiperController();
  final GlobalKey<FlipCardState> _flipCardKey = GlobalKey<FlipCardState>();

  List<FlashCard> _flashCards = [];
  bool _isLoading = true;
  String? _error;
  int _currentIndex = 0;
  bool _isFlipped = false; // 카드가 뒤집혔는지 여부
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _loadFlashCards();
    _initTts();

    // 중국어 사전 로드
    _loadChineseDictionary();
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _cardController.dispose();
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
    _flipCardKey.currentState?.toggleCard();
    setState(() {
      _isFlipped = !_isFlipped;
    });
  }

  void _nextCard() {
    if (_currentIndex < _flashCards.length - 1) {
      _cardController.swipe(CardSwiperDirection.left);
    }
  }

  void _previousCard() {
    if (_currentIndex > 0) {
      _cardController.swipe(CardSwiperDirection.right);
    }
  }

  Future<void> _deleteCurrentCard() async {
    if (_flashCards.isEmpty || _currentIndex >= _flashCards.length) return;

    final flashCardId = _flashCards[_currentIndex].id;
    final noteId = _flashCards[_currentIndex].noteId;

    try {
      // 플래시카드 삭제
      await _flashCardService.deleteFlashCard(flashCardId, noteId: noteId);

      if (mounted) {
        // 현재 인덱스 저장
        final currentIdx = _currentIndex;

        setState(() {
          // 플래시카드 목록에서 제거
          _flashCards.removeAt(currentIdx);

          // 인덱스 조정
          if (_flashCards.isEmpty) {
            _currentIndex = 0;
          } else if (currentIdx >= _flashCards.length) {
            _currentIndex = _flashCards.length - 1;
          } else {
            _currentIndex = currentIdx;
          }
        });

        // 카드가 모두 삭제된 경우 화면 갱신
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

  // 중국어 사전 로드
  Future<void> _loadChineseDictionary() async {
    final dictionaryService = ChineseDictionaryService();
    await dictionaryService.loadDictionary();
  }

  // 중국어 사전에서 단어 정보 가져오기 (중복 코드 제거를 위한 메서드 추출)
  DictionaryEntry? _getDictionaryEntry(String word) {
    final dictionaryService = ChineseDictionaryService();
    return dictionaryService.lookup(word);
  }

  // 카드 스와이프 처리
  bool _onSwipe(
      int? previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (currentIndex != null && currentIndex < _flashCards.length) {
      setState(() {
        _currentIndex = currentIndex;
        _isFlipped = false;
      });

      _updateFlashCardReviewCount();
    }

    // 위로 스와이프하는 경우 카드 삭제
    if (direction == CardSwiperDirection.top) {
      _deleteCurrentCard();
    }

    return true; // 스와이프 동작 허용
  }

  // 핑인 업데이트 메서드 추가
  Future<void> _updatePinyin() async {
    if (_flashCards.isEmpty || _currentIndex >= _flashCards.length) return;

    try {
      setState(() {
        _isLoading = true;
      });

      final currentCard = _flashCards[_currentIndex];
      final chineseText = currentCard.front;

      // 성조가 포함된 핑인 생성
      final updatedPinyin = PinyinHelper.getPinyin(chineseText,
          separator: ' ', format: PinyinFormat.WITH_TONE_MARK);

      // 플래시카드 업데이트
      final updatedCard = currentCard.copyWith(pinyin: updatedPinyin);

      // Firestore 업데이트
      await FirebaseFirestore.instance
          .collection('flashcards')
          .doc(currentCard.id)
          .update({'pinyin': updatedPinyin});

      // 로컬 상태 업데이트
      setState(() {
        _flashCards[_currentIndex] = updatedCard;
        _isLoading = false;
      });

      // 성공 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('핑인이 업데이트되었습니다.')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('핑인 업데이트 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('플래시카드'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // 플래시카드 변경 여부를 결과로 전달
            Navigator.of(context).pop(true);
          },
        ),
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
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loadFlashCards,
                          child: const Text('다시 시도'),
                        ),
                      ],
                    ),
                  ),
                )
              : _flashCards.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.blue,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '플래시카드가 없습니다.\n단어를 선택하고 플래시카드에 추가해보세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('돌아가기'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: CardSwiper(
                              controller: _cardController,
                              cardsCount: _flashCards.length,
                              onSwipe: _onSwipe,
                              allowedSwipeDirection:
                                  AllowedSwipeDirection.all(),
                              onUndo:
                                  (previousIndex, currentIndex, direction) =>
                                      true,
                              numberOfCardsDisplayed: 1,
                              backCardOffset: const Offset(0, 0),
                              padding: const EdgeInsets.all(24.0),
                              cardBuilder: (context, index, percentThresholdX,
                                  percentThresholdY) {
                                return _buildFlashCard(index);
                              },
                              onSwipeDirectionChange: null,
                            ),
                          ),
                        ),
                        _buildControlButtons(),
                      ],
                    ),
    );
  }

  Widget _buildFlashCard(int index) {
    if (index >= _flashCards.length) return Container();

    final card = _flashCards[index];

    return FlipCard(
      key: index == _currentIndex ? _flipCardKey : null,
      direction: FlipDirection.HORIZONTAL,
      speed: 300,
      onFlipDone: (isFront) {
        setState(() {
          _isFlipped = !isFront;
        });
      },
      front: _buildCardSide(
        card.front,
        card.pinyin,
        Colors.white,
        Colors.blue.shade800,
        true,
      ),
      back: _buildCardSide(
        card.back,
        null,
        Colors.blue.shade50,
        Colors.blue.shade800,
        false,
      ),
    );
  }

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
                  if (isFront && pinyin != null && pinyin.isNotEmpty) ...[
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

  Widget _buildControlButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _currentIndex > 0 ? _previousCard : null,
            iconSize: 32.0,
            color: _currentIndex > 0 ? Colors.blue : Colors.grey,
          ),
          IconButton(
            icon: const Icon(Icons.flip),
            onPressed: _flashCards.isNotEmpty ? _flipCard : null,
            iconSize: 32.0,
            color: _flashCards.isNotEmpty ? Colors.blue : Colors.grey,
          ),
          IconButton(
            icon: const Icon(Icons.volume_up),
            onPressed: _flashCards.isNotEmpty ? _speakCurrentCard : null,
            iconSize: 32.0,
            color: _flashCards.isNotEmpty ? Colors.blue : Colors.grey,
          ),
          // 핑인 업데이트 버튼 추가
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _flashCards.isNotEmpty ? _updatePinyin : null,
            iconSize: 32.0,
            tooltip: '핑인 업데이트',
            color: _flashCards.isNotEmpty ? Colors.green : Colors.grey,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _flashCards.isNotEmpty ? _deleteCurrentCard : null,
            iconSize: 32.0,
            color: _flashCards.isNotEmpty ? Colors.red : Colors.grey,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed:
                _currentIndex < _flashCards.length - 1 ? _nextCard : null,
            iconSize: 32.0,
            color: _currentIndex < _flashCards.length - 1
                ? Colors.blue
                : Colors.grey,
          ),
        ],
      ),
    );
  }
}
