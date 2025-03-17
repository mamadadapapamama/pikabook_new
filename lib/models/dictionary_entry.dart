/// 사전 항목 클래스
/// 중국어 단어, 핀인, 의미 등의 정보를 담고 있습니다.
class DictionaryEntry {
  final String word;
  final String pinyin;
  final String meaning;
  final List<String> examples;
  final String? source; // 사전 출처 (JSON, 시스템 사전, 외부 사전 등)

  const DictionaryEntry({
    required this.word,
    required this.pinyin,
    required this.meaning,
    this.examples = const [],
    this.source,
  });

  // JSON 직렬화 메서드
  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'pinyin': pinyin,
      'meaning': meaning,
      'examples': examples,
      'source': source,
    };
  }

  // JSON 역직렬화 메서드
  factory DictionaryEntry.fromJson(Map<String, dynamic> json) {
    return DictionaryEntry(
      word: json['word'] as String,
      pinyin: json['pinyin'] as String,
      meaning: json['meaning'] as String,
      examples: (json['examples'] as List<dynamic>?)?.cast<String>() ?? [],
      source: json['source'] as String?,
    );
  }

  // 복사 메서드
  DictionaryEntry copyWith({
    String? word,
    String? pinyin,
    String? meaning,
    List<String>? examples,
    String? source,
  }) {
    return DictionaryEntry(
      word: word ?? this.word,
      pinyin: pinyin ?? this.pinyin,
      meaning: meaning ?? this.meaning,
      examples: examples ?? this.examples,
      source: source ?? this.source,
    );
  }

  @override
  String toString() {
    return 'DictionaryEntry(word: $word, pinyin: $pinyin, meaning: $meaning)';
  }
}
