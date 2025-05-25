/// 텍스트 처리 상태 열거형
enum ProcessingStatus {
  created,           // 페이지만 생성됨
  textExtracted,     // OCR + 정리 완료
  segmentsReady,     // 분리 완료
  translating,       // LLM 번역 중
  completed,         // 모든 처리 완료
  failed,           // 처리 실패
  retrying,         // 재시도 중
}

/// ProcessingStatus 확장 메서드
extension ProcessingStatusExtension on ProcessingStatus {
  /// 한국어 표시명
  String get displayName {
    switch (this) {
      case ProcessingStatus.created:
        return '생성됨';
      case ProcessingStatus.textExtracted:
        return '텍스트 추출 완료';
      case ProcessingStatus.segmentsReady:
        return '분리 완료';
      case ProcessingStatus.translating:
        return '번역 중';
      case ProcessingStatus.completed:
        return '처리 완료';
      case ProcessingStatus.failed:
        return '처리 실패';
      case ProcessingStatus.retrying:
        return '재시도 중';
    }
  }

  /// 진행률 (0.0 ~ 1.0)
  double get progress {
    switch (this) {
      case ProcessingStatus.created:
        return 0.1;
      case ProcessingStatus.textExtracted:
        return 0.3;
      case ProcessingStatus.segmentsReady:
        return 0.5;
      case ProcessingStatus.translating:
        return 0.8;
      case ProcessingStatus.completed:
        return 1.0;
      case ProcessingStatus.failed:
        return 0.0;
      case ProcessingStatus.retrying:
        return 0.2;
    }
  }

  /// 완료 여부
  bool get isCompleted => this == ProcessingStatus.completed;

  /// 처리 중 여부
  bool get isProcessing => [
    ProcessingStatus.translating,
    ProcessingStatus.retrying,
  ].contains(this);

  /// 실패 여부
  bool get isFailed => this == ProcessingStatus.failed;
} 