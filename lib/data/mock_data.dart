import 'package:pikabook_new/models/note.dart';
import 'package:pikabook_new/models/flash_card.dart';

class MockData {
  static List<Note> getNotes() {
    final now = DateTime.now();

    return [
      Note(
        id: '1',
        spaceId: 'space1',
        userId: 'user1',
        title: '중국어 기초 단어',
        content: '중국어 기초 단어 학습 노트',
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 2)),
        flashCards: [
          FlashCard(
            id: 'card1',
            front: '你好',
            back: '안녕하세요',
            pinyin: 'nǐ hǎo',
            createdAt: now.subtract(const Duration(days: 5)),
            reviewCount: 3,
          ),
          FlashCard(
            id: 'card2',
            front: '谢谢',
            back: '감사합니다',
            pinyin: 'xiè xiè',
            createdAt: now.subtract(const Duration(days: 4)),
            reviewCount: 2,
          ),
        ],
        pages: ['page1', 'page2'],
        imageUrl: '',
        extractedText: '你好\n谢谢',
        translatedText: '안녕하세요\n감사합니다',
        isDeleted: false,
        flashcardCount: 2,
        reviewCount: 5,
      ),
      Note(
        id: '2',
        spaceId: 'space1',
        userId: 'user1',
        title: '중국어 회화 표현',
        content: '중국어 일상 회화 표현 노트',
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 1)),
        flashCards: [
          FlashCard(
            id: 'card3',
            front: '我很好',
            back: '저는 잘 지내요',
            pinyin: 'wǒ hěn hǎo',
            createdAt: now.subtract(const Duration(days: 3)),
            reviewCount: 1,
          ),
        ],
        pages: ['page3'],
        imageUrl: '',
        extractedText: '我很好',
        translatedText: '저는 잘 지내요',
        isDeleted: false,
        flashcardCount: 1,
        reviewCount: 1,
      ),
    ];
  }
}
