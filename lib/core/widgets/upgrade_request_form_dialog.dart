import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../models/upgrade_request_form.dart';
import '../services/common/upgrade_request_service.dart';
import 'pika_button.dart';

/// 프리미엄 업그레이드 요청 폼 다이얼로그
class UpgradeRequestFormDialog extends StatefulWidget {
  const UpgradeRequestFormDialog({Key? key}) : super(key: key);

  @override
  State<UpgradeRequestFormDialog> createState() => _UpgradeRequestFormDialogState();
}

class _UpgradeRequestFormDialogState extends State<UpgradeRequestFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _upgradeRequestService = UpgradeRequestService();
  
  // 폼 데이터
  bool _needAdditionalNoteFeature = false;
  bool _needListeningFeature = false;
  bool _needOtherFeatures = false;
  final _otherFeatureController = TextEditingController();
  final _featureSuggestionController = TextEditingController();
  bool? _interviewParticipation;
  final _contactInfoController = TextEditingController();
  
  // 사용자 정보
  String? _userEmail;
  String? _userName;
  
  // 상태
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _otherFeatureController.dispose();
    _featureSuggestionController.dispose();
    _contactInfoController.dispose();
    super.dispose();
  }

  /// 사용자 정보 로드
  void _loadUserInfo() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userEmail = user.email;
      _userName = user.displayName;
    }
  }



  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: isTablet ? 600 : 400,
          maxHeight: isTablet ? screenSize.height * 0.8 : 600,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            _buildHeader(),
            
            // 폼 내용
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isTablet ? SpacingTokens.lg : SpacingTokens.md),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. 추가로 필요한 기능
                      _buildFeatureSection(),
                      SizedBox(height: isTablet ? SpacingTokens.xl : SpacingTokens.lg),
                      
                      // 2. 기능 제안
                      _buildFeatureSuggestionSection(),
                      SizedBox(height: isTablet ? SpacingTokens.xl : SpacingTokens.lg),
                      
                      // 3. 인터뷰 참여 의향
                      _buildInterviewSection(),
                    ],
                  ),
                ),
              ),
            ),
            
            // 버튼
            _buildButtons(),
          ],
        ),
      ),
    );
  }

  /// 헤더 위젯
  Widget _buildHeader() {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? SpacingTokens.xl : SpacingTokens.lg, 
        vertical: isTablet ? SpacingTokens.md : SpacingTokens.sm
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '🚀 사용량 추가 요청하기',
              style: (isTablet ? TypographyTokens.subtitle1 : TypographyTokens.subtitle2).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close, 
              color: ColorTokens.textSecondary,
              size: isTablet ? 28 : 24,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// 기능 요청 섹션
  Widget _buildFeatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1. 사용량이 더 필요한 기능을 표시해주세요',
          style: TypographyTokens.body1.copyWith(
            fontWeight: FontWeight.w600,
            color: ColorTokens.textPrimary,
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        
        // 체크박스들
        CheckboxListTile(
          title: Text(
            '추가 노트 생성기능',
            style: TypographyTokens.body2,
          ),
          value: _needAdditionalNoteFeature,
          onChanged: (value) {
            setState(() {
              _needAdditionalNoteFeature = value ?? false;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
        ),
        
        CheckboxListTile(
          title: Text(
            '듣기 기능',
            style: TypographyTokens.body2,
          ),
          value: _needListeningFeature,
          onChanged: (value) {
            setState(() {
              _needListeningFeature = value ?? false;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
        ),
        
        CheckboxListTile(
          title: Text(
            '기타',
            style: TypographyTokens.body2,
          ),
          value: _needOtherFeatures,
          onChanged: (value) {
            setState(() {
              _needOtherFeatures = value ?? false;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
        ),
        
        // 기타 기능 입력 필드
        if (_needOtherFeatures) ...[
          const SizedBox(height: SpacingTokens.sm),
          TextFormField(
            controller: _otherFeatureController,
            decoration: InputDecoration(
              hintText: '어떤 기능이 더 필요하신가요?',
              hintStyle: TypographyTokens.body2.copyWith(
                color: ColorTokens.textGrey,
              ),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: ColorTokens.secondaryLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: ColorTokens.secondaryLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: ColorTokens.secondary),
              ),
              contentPadding: EdgeInsets.all(MediaQuery.of(context).size.width > 600 ? SpacingTokens.md : SpacingTokens.sm),
            ),
            style: TypographyTokens.body2,
            maxLines: 3,
          ),
        ],
      ],
    );
  }

  /// 기능 제안 섹션
  Widget _buildFeatureSuggestionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2. 피카북에 어떤 기능이 있으면 좋을까요?\n원하는 기능이나 개선사항을 자유롭게 작성해주세요.',
          style: TypographyTokens.body1.copyWith(
            fontWeight: FontWeight.w600,
            color: ColorTokens.textPrimary,

          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        TextFormField(
          controller: _featureSuggestionController,
          decoration: InputDecoration(
            hintText: '자유롭게 작성해주세요',
            hintStyle: TypographyTokens.body2.copyWith(
              color: ColorTokens.textGrey,
            ),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: ColorTokens.secondaryLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: ColorTokens.secondaryLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: ColorTokens.secondary),
            ),
            contentPadding: EdgeInsets.all(MediaQuery.of(context).size.width > 600 ? SpacingTokens.md : SpacingTokens.sm),
          ),
          style: TypographyTokens.body2,
          maxLines: 4,
        ),
      ],
    );
  }

  /// 인터뷰 섹션
  Widget _buildInterviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '3. 사용자 경험 개선을 위해 30분-1시간 정도의 인터뷰를 진행하고 있어요.\n혹시 참여의향이 있으신가요?',
          style: TypographyTokens.body1.copyWith(
            fontWeight: FontWeight.w600,
            color: ColorTokens.textPrimary,
          ),
        ),
        const SizedBox(height: SpacingTokens.sm),
        
        // 라디오 버튼들
        RadioListTile<bool>(
          title: Text(
            '예',
            style: TypographyTokens.body2,
          ),
          value: true,
          groupValue: _interviewParticipation,
          onChanged: (value) {
            setState(() {
              _interviewParticipation = value;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
        ),
        
        RadioListTile<bool>(
          title: Text(
            '아니오',
            style: TypographyTokens.body2,
          ),
          value: false,
          groupValue: _interviewParticipation,
          onChanged: (value) {
            setState(() {
              _interviewParticipation = value;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          visualDensity: VisualDensity.compact,
        ),
        
        // 연락처 입력 필드 (예를 선택한 경우)
        if (_interviewParticipation == true) ...[
          const SizedBox(height: SpacingTokens.sm),
          TextFormField(
            controller: _contactInfoController,
            decoration: InputDecoration(
              hintText: '연락처를 입력해주세요 (이메일 또는 전화번호)',
              hintStyle: TypographyTokens.body2.copyWith(
                color: ColorTokens.textGrey,
              ),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: ColorTokens.secondaryLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: ColorTokens.secondaryLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: ColorTokens.secondary),
              ),
              contentPadding: EdgeInsets.all(MediaQuery.of(context).size.width > 600 ? SpacingTokens.md : SpacingTokens.sm),
            ),
            style: TypographyTokens.body2,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '연락처를 입력해주세요';
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  /// 버튼 섹션
  Widget _buildButtons() {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    
    return Container(
      padding: EdgeInsets.all(isTablet ? SpacingTokens.xl : SpacingTokens.lg),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: ColorTokens.greyLight),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: PikaButton(
              text: '취소',
              variant: PikaButtonVariant.outline,
              size: isTablet ? PikaButtonSize.large : PikaButtonSize.medium,
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            ),
          ),
          SizedBox(width: isTablet ? SpacingTokens.md : SpacingTokens.sm),
          Expanded(
            child: PikaButton(
              text: _isLoading ? '전송 중...' : '요청 전송',
              variant: PikaButtonVariant.primary,
              size: isTablet ? PikaButtonSize.large : PikaButtonSize.medium,
              onPressed: _isLoading ? null : _submitForm,
            ),
          ),
        ],
      ),
    );
  }

  /// 폼 제출
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 폼 데이터 생성
    final form = UpgradeRequestForm(
      needAdditionalNoteFeature: _needAdditionalNoteFeature,
      needListeningFeature: _needListeningFeature,
      needOtherFeatures: _needOtherFeatures,
      otherFeatureRequest: _otherFeatureController.text.isNotEmpty 
          ? _otherFeatureController.text 
          : null,
      featureSuggestion: _featureSuggestionController.text.isNotEmpty 
          ? _featureSuggestionController.text 
          : null,
      interviewParticipation: _interviewParticipation,
      contactInfo: _contactInfoController.text.isNotEmpty 
          ? _contactInfoController.text 
          : null,
      userEmail: _userEmail,
      userName: _userName,
    );

    // 유효성 검사
    if (!form.isValid()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('최소한 하나의 기능 요청이나 제안을 입력해주세요.'),
          backgroundColor: ColorTokens.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Firestore에 저장
      final success = await _upgradeRequestService.submitUpgradeRequest(form);
      
      if (success) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('사용량 추가 요청이 성공적으로 전송되었습니다!'),
              backgroundColor: ColorTokens.secondary,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('요청 전송에 실패했습니다. 잠시 후 다시 시도해주세요.'),
              backgroundColor: ColorTokens.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 정적 메서드로 다이얼로그 표시
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const UpgradeRequestFormDialog(),
    );
  }
} 