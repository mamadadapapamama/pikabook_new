class ChineseText {
  final String originalText;
  final List<ChineseSentence> sentences;

  ChineseText({required this.originalText, required this.sentences});

  static ChineseText empty() => ChineseText(originalText: '', sentences: []);
}

class ChineseSentence {
  final String original;
  final String translation;
  final String pinyin;

  ChineseSentence({required this.original, required this.translation, required this.pinyin});
} 