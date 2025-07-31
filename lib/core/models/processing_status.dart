/// 🔄 통합 텍스트 처리 상태 열거형
/// ProcessingStatus와 StreamingStatus를 통합하여 중복을 제거합니다.
enum ProcessingStatus {
  // 전체 페이지 처리 상태
  created,           // 페이지만 생성됨
  textExtracted,     // OCR + 정리 완료
  segmentsReady,     // 분리 완료
  
  // 번역/스트리밍 상태 (StreamingStatus 통합)
  preparing,         // 번역 준비 중 (구 StreamingStatus.preparing)
  translating,       // LLM 번역 중 (스트리밍 진행)
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
      case ProcessingStatus.preparing:
        return '번역 준비 중';
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
      case ProcessingStatus.preparing:
        return 0.6;
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
    ProcessingStatus.preparing,
    ProcessingStatus.translating,
    ProcessingStatus.retrying,
  ].contains(this);

  /// 실패 여부
  bool get isFailed => this == ProcessingStatus.failed;
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔄 StreamingStatus 호환성 메서드들
  // ────────────────────────────────────────────────────────────────────────
  
  /// 스트리밍 중인지 확인 (StreamingStatus.streaming과 호환)
  bool get isStreaming => this == ProcessingStatus.translating;
  
  /// 스트리밍 준비 중인지 확인 (StreamingStatus.preparing과 호환)
  bool get isPreparing => this == ProcessingStatus.preparing;
  
  /// StreamingStatus로부터 ProcessingStatus 생성
  static ProcessingStatus fromStreamingStatus(StreamingStatus streamingStatus) {
    switch (streamingStatus) {
      case StreamingStatus.preparing:
        return ProcessingStatus.preparing;
      case StreamingStatus.streaming:
        return ProcessingStatus.translating;
      case StreamingStatus.completed:
        return ProcessingStatus.completed;
      case StreamingStatus.failed:
        return ProcessingStatus.failed;
    }
  }
  
  /// StreamingStatus로 변환 (하위 호환성)
  StreamingStatus toStreamingStatus() {
    switch (this) {
      case ProcessingStatus.preparing:
        return StreamingStatus.preparing;
      case ProcessingStatus.translating:
        return StreamingStatus.streaming;
      case ProcessingStatus.completed:
        return StreamingStatus.completed;
      case ProcessingStatus.failed:
        return StreamingStatus.failed;
      default:
        // 다른 상태들은 준비 중으로 매핑
        return StreamingStatus.preparing;
    }
  }
}

// ────────────────────────────────────────────────────────────────────────
// 🔄 하위 호환성을 위한 StreamingStatus 타입 별칭
// ────────────────────────────────────────────────────────────────────────

/// @deprecated ProcessingStatus 사용 권장
enum StreamingStatus {
  preparing,    // 준비 중
  streaming,    // 스트리밍 중
  completed,    // 완료
  failed,       // 실패
} 