import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flip_card/flip_card.dart';
import '../../models/flash_card.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/tts_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../services/chinese_dictionary_service.dart';
import '../widgets/flashcard_ui.dart';

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

  // 카드 스와이프 방향 추적
  CardSwiperDirection? _lastSwipeDirection;

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

    // 마지막 스와이프 방향 저장
    _lastSwipeDirection = direction;

    // 현재 인덱스가 null이면 기본값 설정
    int newIndex = currentIndex ?? 0;

    setState(() {
      // 현재 인덱스 업데이트
      _currentIndex = newIndex;

      // 위로 스와이프: 카드 삭제
      if (direction == CardSwiperDirection.top) {
        _deleteCurrentCard();
      }

      // 카드 뒤집힘 상태 초기화
      _isFlipped = false;
    });

    // 복습 횟수 업데이트
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
                          // 카드 2개 겹쳐서 보이도록 설정 (더 명확한 레이어 효과)
                          numberOfCardsDisplayed: 2,
                          backCardOffset: const Offset(0, 20), // 간격 증가
                          scale: 0.90, // 뒤 카드 크기 감소
                          padding: const EdgeInsets.all(24.0),
                          cardBuilder: (context, index, horizontalThreshold,
                              verticalThreshold) {
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
                            );
                          },
                        ),
                      ),
                    ),
                    // 하단 버튼 영역
                    FlashCardUI.buildBottomControls(
                      hasCards: _flashCards.isNotEmpty,
                      onFlip: _flipCard,
                      onDelete: _deleteCurrentCard,
                    ),
                  ],
                ),
    );
  }
}
