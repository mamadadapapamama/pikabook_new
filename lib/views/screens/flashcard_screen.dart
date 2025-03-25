import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flip_card/flip_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/flash_card.dart';
import '../../models/note.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/tts_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../services/chinese_dictionary_service.dart';
import '../../widgets/flashcard_ui.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';

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
    // 중국어 사전은 필요할 때만 로드하도록 변경
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
          _error = '플래시카드를 불러오는 중 오류가 발생했습니다: $e';
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
    if (_isSpeaking) {
      await _stopSpeaking();
      return;
    }

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

      // 음성 재생이 완료되면 상태 업데이트
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _isSpeaking) {
          setState(() {
            _isSpeaking = false;
          });
        }
      });
    } catch (e) {
      debugPrint('TTS 실행 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성 재생 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  /// TTS 중지
  Future<void> _stopSpeaking() async {
    if (!_isSpeaking) return;

    try {
      await _ttsService.stop();
    } catch (e) {
      debugPrint('TTS 중지 중 오류 발생: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    }
  }

  /// 카드 스와이프 처리
  bool _onSwipe(
      int? previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (_flashCards.isEmpty) return false;

    debugPrint(
        '스와이프: 이전 인덱스=$previousIndex, 현재 인덱스=$currentIndex, 방향=$direction');

    // 플래시카드가 1개일 때 특별 처리
    if (_flashCards.length == 1) {
      // 위로 스와이프: 카드 삭제
      if (direction == CardSwiperDirection.top) {
        _deleteCurrentCard();
      }
      // 다른 방향으로 스와이프: 무시
      return false; // 스와이프 취소
    }

    // 플래시카드가 2개 이상일 때 일반 처리
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
      // 삭제 전 플래시카드 개수 확인
      final int cardCountBeforeDelete = _flashCards.length;

      // 플래시카드 서비스를 통해 카드 삭제
      await _flashCardService.deleteFlashCard(flashCardId, noteId: noteId);

      if (mounted) {
        setState(() {
          _flashCards.removeAt(_currentIndex);
          if (_currentIndex >= _flashCards.length && _flashCards.isNotEmpty) {
            _currentIndex = _flashCards.length - 1;
          }
        });

        // 플래시카드가 모두 삭제된 경우 노트 디테일 화면으로 돌아감
        if (_flashCards.isEmpty && widget.noteId != null) {
          // 노트 정보 업데이트 후 노트 디테일 화면으로 돌아감
          await _updateNoteInfoAndNavigateBack(widget.noteId!);
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

  /// 노트 정보 업데이트 후 노트 디테일 화면으로 돌아감
  Future<void> _updateNoteInfoAndNavigateBack(String noteId) async {
    try {
      // Firestore에서 직접 노트 가져오기
      final noteDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(noteId)
          .get();

      if (noteDoc.exists && mounted) {
        // 노트 정보 업데이트 (앱바 카운터 업데이트를 위해)
        final updatedNote = Note.fromFirestore(noteDoc);

        // 결과 값 설정 (노트 디테일 화면으로 돌아갈 때 사용)
        Navigator.of(context).pop(updatedNote);
      } else {
        // 노트 문서가 없는 경우 그냥 돌아감
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      debugPrint('노트 정보 업데이트 중 오류 발생: $e');
      // 오류 발생 시에도 화면은 돌아가도록 함
      if (mounted) {
        Navigator.of(context).pop(true);
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
    if (word.isEmpty) return;

    if (!_dictionaryService.isLoaded) {
      setState(() => _isLoading = true);

      _dictionaryService.loadDictionary().then((_) {
        if (mounted) {
          setState(() => _isLoading = false);
          _performDictionarySearch(word);
        }
      }).catchError((e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('사전 로드 중 오류가 발생했습니다: $e')),
          );
        }
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
    // 상태 표시줄 색상을 검정으로 설정
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    
    return WillPopScope(
      // 화면을 나갈 때 노트 정보 업데이트
      onWillPop: () async {
        // noteId가 있고 플래시카드가 있는 경우에만 노트 정보 업데이트
        if (widget.noteId != null && _flashCards.isNotEmpty) {
          await _updateNoteInfoAndNavigateBack(widget.noteId!);
          return false; // Navigator.pop이 이미 호출되었으므로 false 반환
        }
        return true; // 일반적인 뒤로 가기 동작 수행
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(76), // 홈 스크린 + 4px
          child: Column(
            children: [
              // AppBar 내용
              SizedBox(
                height: 76, // 앱바 높이 조정 (홈 스크린 + 4px)
                child: Padding(
                  padding: const EdgeInsets.only(top: 44.0, left: 24.0, right: 24.0),
                  child: Row(
                    children: [
                      // 뒤로가기 버튼
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_rounded,
                          color: Colors.black,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.of(context).pop(_error != null ? false : true),
                      ),
                      const SizedBox(width: 4),
                      
                      // 타이틀
                      Text(
                        '플래시카드',
                        style: TypographyTokens.subtitle1.copyWith(
                          fontWeight: FontWeight.w500,
                          color: ColorTokens.textPrimary,
                        ),
                      ),
                      
                      // 카드 카운터 표시
                      if (_flashCards.isNotEmpty)
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: 28,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFD53C),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Center(
                                  child: Text(
                                    '${_currentIndex + 1} / ${_flashCards.length}',
                                    style: TypographyTokens.button.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF1B4F46),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: LoadingIndicator(message: '플래시카드 로딩 중...'))
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
                    ? const Center(child: Text('플래시카드가 없습니다.'))
                    : Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  // 플래시카드가 1개일 때 안내 메시지 표시
                                  if (_flashCards.length == 1)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16.0),
                                      child: Text(
                                        '위로 스와이프하여 삭제할 수 있습니다',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .secondary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: CardSwiper(
                                      controller: _cardController,
                                      cardsCount: _flashCards.length,
                                      onSwipe: _onSwipe,
                                      // 스와이프 방향 설정 (카드가 1개일 때는 위로만 스와이프 가능)
                                      allowedSwipeDirection: _flashCards
                                                  .length ==
                                              1
                                          ? const AllowedSwipeDirection.only(
                                              up: true)
                                          : AllowedSwipeDirection.symmetric(
                                              horizontal: true,
                                              vertical: true,
                                            ),
                                      // 스와이프 방향 변경 콜백 (불필요한 로그 제거)
                                      onSwipeDirectionChange: (_, __) {},
                                      // 카드 개수에 따라 표시할 카드 수 조정 (1개일 때는 1개만, 그 외에는 2개)
                                      numberOfCardsDisplayed:
                                          _flashCards.length == 1 ? 1 : 2,
                                      padding: const EdgeInsets.all(24.0),
                                      isLoop: _flashCards.length >
                                          1, // 카드가 2개 이상일 때만 순환 활성화
                                      cardBuilder: (context,
                                          index,
                                          horizontalThreshold,
                                          verticalThreshold) {
                                        // 카드 스케일 계산 (현재 카드는 100%, 뒤 카드는 점점 작아짐)
                                        // 플래시카드가 1개일 때는 스케일링 없이 표시
                                        final double scale;
                                        final double yOffset;

                                        if (_flashCards.length == 1) {
                                          // 카드가 1개일 때는 스케일링과 오프셋 없음
                                          scale = 1.0;
                                          yOffset = 0.0;
                                        } else {
                                          // 카드가 2개 이상일 때 스케일링과 오프셋 적용
                                          final int indexDiff =
                                              (index - _currentIndex).abs();
                                          scale = index == _currentIndex
                                              ? 1.0
                                              : 1.0 - (0.05 * indexDiff);
                                          yOffset = index == _currentIndex
                                              ? 0
                                              : 20.0 * indexDiff;
                                        }

                                        return FlashCardUI.buildFlashCard(
                                          card: _flashCards[index],
                                          index: index,
                                          currentIndex: _currentIndex,
                                          flipCardKey: index == _currentIndex
                                              ? _flipCardKey
                                              : null,
                                          isSpeaking: _isSpeaking,
                                          onFlip: () {
                                            setState(
                                                () => _isFlipped = !_isFlipped);
                                          },
                                          onSpeak: _speakCurrentCard,
                                          onStopSpeaking: _stopSpeaking,
                                          getNextCardInfo: _getNextCardInfo,
                                          getPreviousCardInfo:
                                              _getPreviousCardInfo,
                                          onWordTap: _searchWordInDictionary,
                                          scale: scale,
                                          offset: Offset(0, yOffset),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 하단 버튼 영역
                          FlashCardUI.buildBottomControls(
                              hasCards: _flashCards.isNotEmpty,
                              onDelete: _deleteCurrentCard)
                        ],
                      ),
      ),
    );
  }
}
