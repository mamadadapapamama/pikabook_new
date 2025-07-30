import 'text_unit.dart';

/// 텍스트 처리 모드
enum TextProcessingMode {
  segment,   // 문장 단위 처리
  paragraph, // 문단 단위 처리
}

/// 텍스트 표시 모드
enum TextDisplayMode {
  full,      // 원문 + 병음 + 번역 표시
  noPinyin,  // 원문 + 번역만 표시 (병음 없음)
}

/// 스트리밍 상태
enum StreamingStatus {
  preparing,    // 준비 중
  streaming,    // 스트리밍 중
  completed,    // 완료
  failed,       // 실패
}

/// 처리된 텍스트를 나타내는 모델입니다.
class ProcessedText {
  final TextProcessingMode mode;
  final TextDisplayMode displayMode;
  final String fullOriginalText;
  final String fullTranslatedText;
  final List<TextUnit> units;
  final String sourceLanguage;
  final String targetLanguage;
  
  // 스트리밍 관련 필드
  final StreamingStatus streamingStatus;
  final int completedUnits;
  final double progress;

  ProcessedText({
    required this.mode,
    required this.displayMode,
    required this.fullOriginalText,
    required this.fullTranslatedText,
    required this.units,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.streamingStatus = StreamingStatus.completed,
    this.completedUnits = 0,
    this.progress = 1.0,
  });

  /// 원문만 있는 초기 ProcessedText 생성 (스트리밍 시작용)
  factory ProcessedText.withOriginalOnly({
    required TextProcessingMode mode,
    required List<String> originalSegments,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    final units = originalSegments.map((segment) => TextUnit(
      originalText: segment,
      translatedText: '', // 빈 번역
      pinyin: '', // 빈 병음
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    )).toList();

    return ProcessedText(
      mode: mode,
      displayMode: TextDisplayMode.full,
      fullOriginalText: originalSegments.join(''),
      fullTranslatedText: '',
      units: units,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      streamingStatus: StreamingStatus.streaming,
      completedUnits: 0,
      progress: 0.0,
    );
  }

  /// JSON에서 ProcessedText 생성
  factory ProcessedText.fromJson(Map<String, dynamic> json) {
    return ProcessedText(
      mode: TextProcessingMode.values[json['mode'] as int],
      displayMode: TextDisplayMode.values[json['displayMode'] as int],
      fullOriginalText: json['fullOriginalText'] as String,
      fullTranslatedText: json['fullTranslatedText'] as String,
      units: (json['units'] as List)
          .map((e) => TextUnit.fromJson(e as Map<String, dynamic>))
          .toList(),
      sourceLanguage: json['sourceLanguage'] as String,
      targetLanguage: json['targetLanguage'] as String,
      streamingStatus: StreamingStatus.values[json['streamingStatus'] as int? ?? StreamingStatus.completed.index],
      completedUnits: json['completedUnits'] as int? ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 1.0,
    );
  }

  /// ProcessedText를 JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.index,
      'displayMode': displayMode.index,
      'fullOriginalText': fullOriginalText,
      'fullTranslatedText': fullTranslatedText,
      'units': units.map((e) => e.toJson()).toList(),
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'streamingStatus': streamingStatus.index,
      'completedUnits': completedUnits,
      'progress': progress,
    };
  }

  /// ProcessedText 복사
  ProcessedText copyWith({
    TextProcessingMode? mode,
    TextDisplayMode? displayMode,
    String? fullOriginalText,
    String? fullTranslatedText,
    List<TextUnit>? units,
    String? sourceLanguage,
    String? targetLanguage,
    StreamingStatus? streamingStatus,
    int? completedUnits,
    double? progress,
  }) {
    return ProcessedText(
      mode: mode ?? this.mode,
      displayMode: displayMode ?? this.displayMode,
      fullOriginalText: fullOriginalText ?? this.fullOriginalText,
      fullTranslatedText: fullTranslatedText ?? this.fullTranslatedText,
      units: units ?? this.units,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      streamingStatus: streamingStatus ?? this.streamingStatus,
      completedUnits: completedUnits ?? this.completedUnits,
      progress: progress ?? this.progress,
    );
  }

  /// 특정 유닛의 번역 업데이트
  ProcessedText updateUnit(int index, TextUnit updatedUnit) {
    if (index < 0 || index >= units.length) return this;
    
    final newUnits = List<TextUnit>.from(units);
    newUnits[index] = updatedUnit;
    
    // 완료된 유닛 수 계산
    final completed = newUnits.where((unit) => 
      unit.translatedText != null && unit.translatedText!.isNotEmpty
    ).length;
    
    // 진행률 계산
    final newProgress = units.isEmpty ? 1.0 : completed / units.length;
    
    // 스트리밍 상태 업데이트
    final newStatus = completed == units.length 
        ? StreamingStatus.completed 
        : StreamingStatus.streaming;
    
    // 전체 번역 텍스트 재계산
    final newFullTranslatedText = newUnits
        .map((unit) => unit.translatedText ?? '')
        .join('');

    return copyWith(
      units: newUnits,
      fullTranslatedText: newFullTranslatedText,
      streamingStatus: newStatus,
      completedUnits: completed,
      progress: newProgress,
    );
  }

  /// 표시 모드 전환
  ProcessedText toggleDisplayMode() {
    return copyWith(
      displayMode: displayMode == TextDisplayMode.full ? TextDisplayMode.noPinyin : TextDisplayMode.full,
    );
  }
  
  /// 스트리밍 중인지 확인
  bool get isStreaming => streamingStatus == StreamingStatus.streaming;
  
  /// 완료되었는지 확인
  bool get isCompleted => streamingStatus == StreamingStatus.completed;
  
  /// 디버그 정보 문자열 반환
  @override
  String toString() {
    return 'ProcessedText(mode=$mode, '
        'displayMode=$displayMode, '
        'fullOriginalText=$fullOriginalText, '
        'fullTranslatedText=$fullTranslatedText, '
        'units=${units.length} items, '
        'sourceLanguage=$sourceLanguage, '
        'targetLanguage=$targetLanguage, '
        'streamingStatus=$streamingStatus, '
        'completedUnits=$completedUnits, '
        'progress=$progress)';
  }
}
