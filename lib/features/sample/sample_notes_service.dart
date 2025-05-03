import '../../core/models/note.dart';
import '../../core/models/page.dart' as pika_page;
import '../../core/models/processed_text.dart';
import '../../core/models/text_segment.dart';
import '../../core/utils/language_constants.dart';
import 'package:flutter/foundation.dart';

/// 샘플 모드에서 사용할 노트 데이터를 제공하는 서비스
class SampleNotesService {
  /// 싱글톤 패턴 적용
  static final SampleNotesService _instance = SampleNotesService._internal();
  
  factory SampleNotesService() {
    if (kDebugMode) {
      debugPrint('SampleNotesService 팩토리 생성자 호출됨');
    }
    return _instance;
  }
  
  SampleNotesService._internal() {
    if (kDebugMode) {
      debugPrint('SampleNotesService 내부 생성자 호출됨');
    }
  }
  
  // 이미지 경로 상수
  static const String sampleImagePath = 'assets/images/sample_1.jpg';
  
  /// 샘플 노트 목록 가져오기
  List<Note> getSampleNotes() {
    if (kDebugMode) {
      debugPrint('샘플 노트 목록 요청됨');
    }
    return [
      _getSampleChineseNote()
    ];
  }
  
  /// 중국어 샘플 노트
  Note _getSampleChineseNote() {
    if (kDebugMode) {
      debugPrint('중국어 샘플 노트 생성');
    }
    
    final chineseContent = '''小一预备第七课 学校里
开学了，我去学校上课。看见
老师，我对他说："早安！" 看见
同学，我对他们说："你好！"
老师说："好学生读书要认真，
写字要专心。"我们一定要听老师
的话，认真读书，专心写字，和同学
相亲相爱，做个好学生。''';
    
    final koreanTranslation = '''초등 1학년 준비 제7과 학교에서
개학했어요. 저는 학교에 가서 수업을 들어요. 선생님을 만나면
그분께 말합니다: "안녕하세요!" 학우들을 만나면
그들에게 말합니다: "안녕!"
선생님이 말씀하셨어요: "좋은 학생은 공부할 때 성실하게 하고,
글씨를 쓸 때 집중해야 합니다." 우리는 꼭 선생님의
말씀을 듣고, 성실하게 공부하고, 집중해서 글씨를 쓰고, 학우들과
사이좋게 지내야, 좋은 학생이 될 수 있어요.''';
    
    return Note(
      id: 'sample-note-2',
      originalText: '중국어 학습 노트',
      translatedText: '중국어 학습 노트 - 제7과 학교에서',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      imageUrl: sampleImagePath,
      sourceLanguage: SourceLanguage.CHINESE,
      targetLanguage: TargetLanguage.KOREAN,
      processingCompleted: true,
      isProcessingBackground: false,
      extractedText: chineseContent,
      pages: [
        pika_page.Page(
          id: 'sample-page-2',
          originalText: chineseContent,
          translatedText: koreanTranslation,
          pageNumber: 1,
          imageUrl: sampleImagePath,
          sourceLanguage: SourceLanguage.CHINESE,
          targetLanguage: TargetLanguage.KOREAN,
        ),
      ],
      flashcardCount: 0,
    );
  }
  
  /// 샘플 노트의 ProcessedText 객체 가져오기
  ProcessedText getProcessedTextForPage(String pageId) {
    if (kDebugMode) {
      debugPrint('페이지 ID $pageId에 대한 ProcessedText 요청됨');
    }
    
    // 중국어 샘플 페이지인 경우
    if (pageId == 'sample-page-2') {
      final originalSegments = [
        '小一预备第七课 学校里',
        '开学了，我去学校上课。',
        '看见老师，我对他说："早安！"',
        '看见同学，我对他们说："你好！"',
        '老师说："好学生读书要认真，',
        '写字要专心。"',
        '我们一定要听老师的话，',
        '认真读书，专心写字，',
        '和同学相亲相爱，做个好学生。',
      ];
      
      final translatedSegments = [
        '초등 1학년 준비 제7과 학교에서',
        '개학했어요. 저는 학교에 가서 수업을 들어요.',
        '선생님을 만나면 그분께 말합니다: "안녕하세요!"',
        '학우들을 만나면 그들에게 말합니다: "안녕!"',
        '선생님이 말씀하셨어요: "좋은 학생은 공부할 때 성실하게 하고,',
        '글씨를 쓸 때 집중해야 합니다."',
        '우리는 꼭 선생님의 말씀을 듣고,',
        '성실하게 공부하고, 집중해서 글씨를 쓰고,',
        '학우들과 사이좋게 지내야, 좋은 학생이 될 수 있어요.',
      ];
      
      final pinyinSegments = [
        'Xiǎoyī yùbèi dì qī kè xuéxiào lǐ',
        'Kāixué le, wǒ qù xuéxiào shàng kè.',
        'Kànjiàn lǎoshī, wǒ duì tā shuō: "Zǎo ān!"',
        'Kànjiàn tóngxué, wǒ duì tāmen shuō: "Nǐ hǎo!"',
        'Lǎoshī shuō: "Hào xuéshēng dú shū yào rènzhēn,',
        'xiě zì yào zhuānxīn."',
        'Wǒmen yīdìng yào tīng lǎoshī de huà,',
        'rènzhēn dú shū, zhuānxīn xiě zì,',
        'hé tóngxué xiāng qīn xiāng ài, zuò gè hǎo xuéshēng.',
      ];
      
      List<TextSegment> segments = [];
      for (int i = 0; i < originalSegments.length; i++) {
        segments.add(TextSegment(
          originalText: originalSegments[i],
          translatedText: translatedSegments[i],
          pinyin: pinyinSegments[i],
          sourceLanguage: SourceLanguage.CHINESE,
          targetLanguage: TargetLanguage.KOREAN,
        ));
      }
      
      return ProcessedText(
        fullOriginalText: segments.map((s) => s.originalText).join('\n'),
        fullTranslatedText: segments.map((s) => s.translatedText).join('\n'),
        segments: segments,
        showFullText: false,
        showPinyin: true,
        showTranslation: true,
      );
    }
    
    // 기본 ProcessedText 반환
    return ProcessedText(
      fullOriginalText: '샘플 텍스트입니다.',
      fullTranslatedText: '샘플 텍스트입니다.',
      segments: [
        TextSegment(
          originalText: '샘플 텍스트입니다.',
          translatedText: '샘플 텍스트입니다.',
        )
      ],
      showFullText: true,
    );
  }
  
  // 샘플 노트 페이지의 이미지 파일 경로 가져오기
  String? getImagePathForPageId(String pageId) {
    if (pageId == 'sample-page-2') {
      return sampleImagePath;
    }
    return null;
  }
}
