import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flip_card/flip_card.dart';
import '../../models/flash_card.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/tts_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../services/chinese_dictionary_service.dart';
import '../../widgets/flashcard_ui.dart';

/// 플래시카드 화면 전체 위젯 (플래시카드 UI 로드, app bar, bottom controls)
/// 플래시카드 UI interaction 담당 (swipe, flip, tts, delete )
/// 사전 검색 및 플래시카드 내용 추가
///
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
  String? _error; // 오류 메시지

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

    // CardSwiper가 자동으로 인덱스를 업데이트하므로, 현재 인덱스를 사용
    if (currentIndex != null) {
      setState(() {
        _currentIndex = currentIndex;
        _isFlipped = false;
      });
    }

    // 위로 스와이프: 카드 삭제
    if (direction == CardSwiperDirection.top) {
      _deleteCurrentCard();
    }

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
          if (_currentIndex >= _flashCards.length && _flashCards.isNotEmpty) {
            _currentIndex = _flashCards.length - 1;
          }
        });

        // 플래시카드가 모두 삭제된 경우에도 화면에 남아있음
        if (_flashCards.isEmpty) {
          setState(() {});
        }

        // 삭제 완료 메시지 표시
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

  /// 다음 카드 정보 가져오기
  String? _getNextCardInfo() {
    if (_currentIndex < _flashCards.length - 1) {
      return _flashCards[_currentIndex + 1].front;
    }
    return null;
  }

  /// 이전 카드 정보 가져오기
  String? _getPreviousCardInfo() {
    if (_currentIndex > 0) {
      return _flashCards[_currentIndex - 1].front;
    }
    return null;
  }

  /// 단어를 사전에서 검색
  void _searchWordInDictionary(String word) {
    if (!_dictionaryService.isLoaded) {
      _dictionaryService.loadDictionary().then((_) {
        _performDictionarySearch(word);
      });
    } else {
      _performDictionarySearch(word);
    }
  }

  /// 사전 검색 수행
  void _performDictionarySearch(String word) {
    if (!_dictionaryService.isLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사전이 로드되지 않았습니다.')),
      );
      return;
    }

    final entry = _dictionaryService.lookup(word);
    if (entry != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.3,
            maxChildSize: 0.7,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.all(16.0),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Card(
                      margin: const EdgeInsets.only(bottom: 8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.word,
                              style: const TextStyle(
                                fontSize: 24.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              entry.pinyin,
                              style: const TextStyle(
                                fontSize: 18.0,
                                fontStyle: FontStyle.italic,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 8.0),
                            Text(
                              entry.meaning,
                              style: const TextStyle(fontSize: 16.0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\'$word\'에 대한 검색 결과가 없습니다.')),
      );
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
                          // 스와이프 방향 설정
                          allowedSwipeDirection:
                              AllowedSwipeDirection.symmetric(
                            horizontal: true,
                            vertical: true,
                          ),
                          // 스와이프 방향 변경 콜백
                          onSwipeDirectionChange: (_, direction) {
                            debugPrint('스와이프 방향 변경됨: $direction');
                          },
                          // 카드 2개 겹쳐서 보이도록 설정
                          numberOfCardsDisplayed: 2,
                          padding: const EdgeInsets.all(24.0),
                          isLoop: true, // 순환 활성화
                          cardBuilder: (context, index, horizontalThreshold,
                              verticalThreshold) {
                            // 카드 스케일 계산 (현재 카드는 100%, 뒤 카드는 점점 작아짐)
                            final int indexDiff = (index - _currentIndex).abs();
                            final double scale = index == _currentIndex
                                ? 1.0
                                : 1.0 - (0.05 * indexDiff);

                            // 카드 오프셋 계산 (뒤 카드는 아래로 내려감)
                            final double yOffset =
                                index == _currentIndex ? 0 : 20.0 * indexDiff;

                            return FlashCardUI.buildFlashCard(
                              card: _flashCards[index],
                              index: index,
                              currentIndex: _currentIndex,
                              flipCardKey:
                                  index == _currentIndex ? _flipCardKey : null,
                              isSpeaking: _isSpeaking,
                              onFlip: () {
                                setState(() => _isFlipped = !_isFlipped);
                              },
                              onSpeak: _speakCurrentCard,
                              onStopSpeaking: _stopSpeaking,
                              getNextCardInfo: _getNextCardInfo,
                              getPreviousCardInfo: _getPreviousCardInfo,
                              onWordTap: _searchWordInDictionary,
                              scale: scale,
                              offset: Offset(0, yOffset),
                            );
                          },
                        ),
                      ),
                    ),
                    // 하단 버튼 영역
                    FlashCardUI.buildBottomControls(
                        hasCards: _flashCards.isNotEmpty,
                        onDelete: _deleteCurrentCard)
                  ],
                ),
    );
  }
}
