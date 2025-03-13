import 'package:flutter/material.dart';
import '../../models/processed_text.dart';
import '../../models/text_segment.dart';
import '../../models/flash_card.dart';
import '../../widgets/processed_text_widget.dart';

class ContextMenuTestScreen extends StatefulWidget {
  const ContextMenuTestScreen({super.key});

  @override
  State<ContextMenuTestScreen> createState() => _ContextMenuTestScreenState();
}

class _ContextMenuTestScreenState extends State<ContextMenuTestScreen> {
  // 테스트용 플래시카드 단어 목록
  final List<FlashCard> _flashcards = [
    FlashCard(
      id: 'card1',
      front: '公园',
      back: '공원',
      pinyin: 'gōngyuán',
      createdAt: DateTime.now(),
    ),
    FlashCard(
      id: 'card2',
      front: '书',
      back: '책',
      pinyin: 'shū',
      createdAt: DateTime.now(),
    ),
  ];

  // 테스트용 중국어 문장
  final String chineseSentence1 = "我今天去了公园，天气非常好";
  final String chineseSentence2 = "这本书很有趣，我已经读了两遍。";

  // 처리된 텍스트 객체
  late ProcessedText _processedText1;
  late ProcessedText _processedText2;

  @override
  void initState() {
    super.initState();
    _initProcessedTexts();
  }

  // 처리된 텍스트 초기화
  void _initProcessedTexts() {
    // 첫 번째 문장 처리
    _processedText1 = ProcessedText(
      fullOriginalText: chineseSentence1,
      fullTranslatedText: "오늘 나는 공원에 갔어요, 날씨가 매우 좋았어요",
      segments: [
        TextSegment(
          originalText: "我今天去了公园，",
          pinyin: "wǒ jīntiān qùle gōngyuán,",
          translatedText: "오늘 나는 공원에 갔어요,",
        ),
        TextSegment(
          originalText: "天气非常好",
          pinyin: "tiānqì fēicháng hǎo",
          translatedText: "날씨가 매우 좋았어요",
        ),
      ],
      showFullText: false,
    );

    // 두 번째 문장 처리
    _processedText2 = ProcessedText(
      fullOriginalText: chineseSentence2,
      fullTranslatedText: "이 책은 매우 재미있어요, 나는 이미 두 번 읽었어요.",
      segments: [
        TextSegment(
          originalText: "这本书很有趣，",
          pinyin: "zhè běn shū hěn yǒuqù,",
          translatedText: "이 책은 매우 재미있어요,",
        ),
        TextSegment(
          originalText: "我已经读了两遍。",
          pinyin: "wǒ yǐjīng dúle liǎng biàn.",
          translatedText: "나는 이미 두 번 읽었어요.",
        ),
      ],
      showFullText: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('컨텍스트 메뉴 테스트'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _showInfoDialog();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 현재 플래시카드 단어 목록 표시
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '현재 플래시카드 단어 목록:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_flashcards.map((card) => card.front).join(', ')),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _flashcards.clear();
                            });
                          },
                          child: const Text('단어 목록 비우기'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 테스트 설명
            const Text(
              '아래 텍스트를 길게 눌러 컨텍스트 메뉴를 테스트하세요:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            // 첫 번째 중국어 문장 (ProcessedTextWidget 사용)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '첫 번째 문장 테스트:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ProcessedTextWidget 사용
                    ProcessedTextWidget(
                      processedText: _processedText1,
                      onDictionaryLookup: _showDictionaryResult,
                      onCreateFlashCard: _addToFlashcard,
                      flashCards: _flashcards,
                      showTranslation: true,
                      onTts: _speakText,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 두 번째 중국어 문장 (ProcessedTextWidget 사용)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '두 번째 문장 테스트:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ProcessedTextWidget 사용
                    ProcessedTextWidget(
                      processedText: _processedText2,
                      onDictionaryLookup: _showDictionaryResult,
                      onCreateFlashCard: _addToFlashcard,
                      flashCards: _flashcards,
                      showTranslation: true,
                      onTts: _speakText,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 사전 검색 결과 표시
  void _showDictionaryResult(String word) {
    debugPrint('사전 검색: $word');

    // 간단한 사전 결과 표시
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                word,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '발음: ${_getMockPinyin(word)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '의미: ${_getMockMeaning(word)}',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 읽기 버튼 추가
                  ElevatedButton.icon(
                    onPressed: () {
                      _speakText(word);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.volume_up),
                    label: const Text('읽기'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('닫기'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      _addToFlashcard(word, _getMockMeaning(word),
                          pinyin: _getMockPinyin(word));
                      Navigator.pop(context);
                    },
                    child: const Text('플래시카드에 추가'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // 플래시카드에 추가
  void _addToFlashcard(String word, String meaning, {String? pinyin}) {
    setState(() {
      // 이미 있는 단어인지 확인
      bool exists = _flashcards.any((card) => card.front == word);

      if (!exists) {
        _flashcards.add(FlashCard(
          id: 'card${_flashcards.length + 1}',
          front: word,
          back: meaning,
          pinyin: pinyin ?? '',
          createdAt: DateTime.now(),
        ));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('플래시카드에 추가됨: $word'),
          ),
        );
      }
    });
  }

  // TTS로 텍스트 읽기 (실제 구현은 생략)
  void _speakText(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('TTS 실행: $text'),
      ),
    );
  }

  // 테스트용 가짜 발음 생성
  String _getMockPinyin(String word) {
    const Map<String, String> mockPinyinMap = {
      '我': 'wǒ',
      '今天': 'jīntiān',
      '去了': 'qùle',
      '公园': 'gōngyuán',
      '天气': 'tiānqì',
      '非常': 'fēicháng',
      '好': 'hǎo',
      '这': 'zhè',
      '本': 'běn',
      '书': 'shū',
      '很': 'hěn',
      '有趣': 'yǒuqù',
      '已经': 'yǐjīng',
      '读了': 'dúle',
      '两遍': 'liǎngbiàn',
    };

    return mockPinyinMap[word] ?? 'pinyin';
  }

  // 테스트용 가짜 의미 생성
  String _getMockMeaning(String word) {
    const Map<String, String> mockMeaningMap = {
      '我': '나',
      '今天': '오늘',
      '去了': '갔다',
      '公园': '공원',
      '天气': '날씨',
      '非常': '매우',
      '好': '좋다',
      '这': '이',
      '本': '(책을 세는 단위)',
      '书': '책',
      '很': '매우',
      '有趣': '재미있다',
      '已经': '이미',
      '读了': '읽었다',
      '两遍': '두 번',
    };

    return mockMeaningMap[word] ?? '의미';
  }

  // 정보 다이얼로그 표시
  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('테스트 방법'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1. 중국어 텍스트를 길게 눌러 컨텍스트 메뉴를 표시합니다.'),
              SizedBox(height: 8),
              Text('2. 단어를 선택하여 컨텍스트 메뉴의 동작을 확인합니다.'),
              SizedBox(height: 8),
              Text('3. 플래시카드에 추가된 단어(하이라이트된 단어)는 탭하면 바로 사전 결과가 표시됩니다.'),
              SizedBox(height: 8),
              Text('4. 일반 단어는 선택 후 컨텍스트 메뉴가 표시됩니다.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }
}
