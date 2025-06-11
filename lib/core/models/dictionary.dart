/// 사전 항목 클래스
/// 중국어 단어, 핀인, 의미 등의 정보를 담고 있습니다.
class DictionaryEntry {
  final String word;
  final String pinyin;
  final String? meaningKo;    // 한국어 번역
  final String? meaningEn;    // 영어 번역  
  final String? meaningJa;    // 일본어 번역 (향후 지원)
  final List<String> examples;
  final String? source; // 사전 출처 (JSON, 시스템 사전, 외부 사전 등)

  // 호환성을 위한 기존 meaning getter (한국어 우선)
  String get meaning => meaningKo ?? meaningEn ?? meaningJa ?? '';

  // 다국어 지원 헬퍼 메서드들
  bool get hasKorean => meaningKo != null && meaningKo!.isNotEmpty;
  bool get hasEnglish => meaningEn != null && meaningEn!.isNotEmpty;
  bool get hasJapanese => meaningJa != null && meaningJa!.isNotEmpty;
  
  // 사용 가능한 번역 언어 목록
  List<String> get availableLanguages {
    final languages = <String>[];
    if (hasKorean) languages.add('ko');
    if (hasEnglish) languages.add('en');
    if (hasJapanese) languages.add('ja');
    return languages;
  }
  
  // 특정 언어의 번역 가져오기
  String? getMeaning(String languageCode) {
    switch (languageCode) {
      case 'ko': return meaningKo;
      case 'en': return meaningEn;
      case 'ja': return meaningJa;
      default: return null;
    }
  }
  
  // 표시용 다국어 문자열 (한국어 + 영어)
  String get displayMeaning {
    final parts = <String>[];
    if (hasKorean) parts.add(meaningKo!);
    if (hasEnglish) parts.add('• $meaningEn');
    if (hasJapanese) parts.add('• $meaningJa');
    return parts.join(' ');
  }

  const DictionaryEntry({
    required this.word,
    required this.pinyin,
    this.meaningKo,
    this.meaningEn,
    this.meaningJa,
    this.examples = const [],
    this.source,
  });

  // 기존 코드 호환성을 위한 편의 생성자 (한국어만)
  factory DictionaryEntry.korean({
    required String word,
    required String pinyin,
    required String meaning,
    List<String> examples = const [],
    String? source,
  }) {
    return DictionaryEntry(
      word: word,
      pinyin: pinyin,
      meaningKo: meaning,
      examples: examples,
      source: source,
    );
  }

  // 영어만 있는 경우 (CC-CEDICT용)
  factory DictionaryEntry.english({
    required String word,
    required String pinyin,
    required String meaning,
    List<String> examples = const [],
    String? source,
  }) {
    return DictionaryEntry(
      word: word,
      pinyin: pinyin,
      meaningEn: meaning,
      examples: examples,
      source: source,
    );
  }

  // 한국어 + 영어 모두 있는 경우
  factory DictionaryEntry.multiLanguage({
    required String word,
    required String pinyin,
    String? meaningKo,
    String? meaningEn,
    String? meaningJa,
    List<String> examples = const [],
    String? source,
  }) {
    return DictionaryEntry(
      word: word,
      pinyin: pinyin,
      meaningKo: meaningKo,
      meaningEn: meaningEn,
      meaningJa: meaningJa,
      examples: examples,
      source: source,
    );
  }

  // JSON 직렬화 메서드
  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'pinyin': pinyin,
      'meaningKo': meaningKo,
      'meaningEn': meaningEn,
      'meaningJa': meaningJa,
      'meaning': meaning, // 호환성을 위한 필드
      'examples': examples,
      'source': source,
    };
  }

  // JSON 역직렬화 메서드
  factory DictionaryEntry.fromJson(Map<String, dynamic> json) {
    return DictionaryEntry(
      word: json['word'] as String,
      pinyin: json['pinyin'] as String,
      meaningKo: json['meaningKo'] as String? ?? json['meaning'] as String?, // 호환성
      meaningEn: json['meaningEn'] as String?,
      meaningJa: json['meaningJa'] as String?,
      examples: (json['examples'] as List<dynamic>?)?.cast<String>() ?? [],
      source: json['source'] as String?,
    );
  }

  // 복사 메서드
  DictionaryEntry copyWith({
    String? word,
    String? pinyin,
    String? meaningKo,
    String? meaningEn,
    String? meaningJa,
    List<String>? examples,
    String? source,
  }) {
    return DictionaryEntry(
      word: word ?? this.word,
      pinyin: pinyin ?? this.pinyin,
      meaningKo: meaningKo ?? this.meaningKo,
      meaningEn: meaningEn ?? this.meaningEn,
      meaningJa: meaningJa ?? this.meaningJa,
      examples: examples ?? this.examples,
      source: source ?? this.source,
    );
  }

  @override
  String toString() {
    return 'DictionaryEntry(word: $word, pinyin: $pinyin, meaning: $meaning)';
  }
}
