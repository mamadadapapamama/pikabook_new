// 언어 및 OCR 관련 서비스 모듈을 한 번에 내보내는 인덱스 파일
export './translation_service.dart';
export './tts_service.dart';
export './pinyin_creation_service.dart';
export './text_cleaner_service.dart';
export './enhanced_ocr_service.dart';
export './text_reader_service.dart';
export './internal_cn_segmenter_service.dart';
export './.language_service_interface.dart';

/// 언어 및 OCR 서비스 모듈
/// 
/// 사용 방법:
/// ```dart
/// import 'package:pikabook/services/language/index.dart';
/// 
/// // 언어 및 OCR 관련 서비스를 사용할 수 있습니다.
/// final translationService = TranslationService();
/// final ttsService = TtsService();
/// final enhancedOcrService = EnhancedOcrService();
/// // ... 그 외 필요한 서비스
/// ```
