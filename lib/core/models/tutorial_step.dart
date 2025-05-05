/// 튜토리얼의 각 단계를 나타내는 모델 클래스
class TutorialStep {
  /// 제목
  final String title;
  
  /// 설명
  final String description;
  
  /// 이미지 경로 (없을 수 있음)
  final String? imagePath;
  
  const TutorialStep({
    required this.title,
    required this.description,
    this.imagePath,
  });
}
