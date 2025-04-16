// 사전 서비스 관련 모듈을 한 번에 내보내는 인덱스 파일

export './internal_cn_dictionary_service.dart';
export './dictionary_service.dart';
export '../chinese_segmenter_service.dart';
export '../pinyin_creation_service.dart';
export './external_cn_dictionary_service.dart' hide ExternalCnDictType;

/// 사전 서비스 모듈
/// 
/// 사용 방법:
/// ```dart
/// import 'package:pikabook/services/dictionary/index.dart';
/// 
/// // 모든 사전 서비스를 사용할 수 있습니다.
/// final dictionaryService = DictionaryService();             // 범용 사전 서비스 (다국어 지원)
/// final internalCnDictionaryService = InternalCnDictionaryService(); // 내부 중국어 사전
/// final externalCnDictionaryService = ExternalCnDictionaryService(); // 외부 API 연동 중국어 사전
/// final segmenterService = ChineseSegmenterService();        // 중국어 문장 분절 서비스
/// final pinyinService = PinyinCreationService();             // 중국어 병음 생성 서비스
/// ``` 