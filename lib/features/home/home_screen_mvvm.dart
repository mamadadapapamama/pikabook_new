import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../features/home/home_viewmodel.dart';
import '../home/note_list_item.dart';
import '../note/services/note_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../core/services/marketing/marketing_campaign_service.dart';  // 마케팅 캠페인 서비스 추가
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/ui_tokens.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/widgets/image_picker_bottom_sheet.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/widgets/pika_button.dart';
import '../../core/widgets/marketing_campaign_widget.dart';  // 마케팅 캠페인 위젯 추가
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/usage_dialog.dart';
import '../flashcard/flashcard_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../app.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/debug_utils.dart';
import '../../core/models/note.dart';
import '../note/view/note_detail_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart'; // kDebugMode 사용 위해 추가

/// 오버스크롤 색상을 주황색으로 변경하는 커스텀 스크롤 비헤이비어
class OrangeOverscrollBehavior extends ScrollBehavior {
  const OrangeOverscrollBehavior();
  
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return GlowingOverscrollIndicator(
      axisDirection: details.direction,
      color: UITokens.homeOverlayScrollEffect, // 오버스크롤 색상을 primaryverylight로 변경
      child: child,
    );
  }
}

/// 노트 카드 리스트를 보여주는 홈 화면
/// profile setting, note detail, flashcard 화면으로 이동 가능

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  
  @override
  _HomeScreenState createState() {
    try {
      if (kDebugMode) {
        debugPrint('[HomeScreen] createState 호출됨');
      }
      return _HomeScreenState();
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[HomeScreen] createState 중 오류 발생: $e');
        debugPrint('[HomeScreen] 스택 트레이스: $stackTrace');
      }
      rethrow; // 오류 전파 (상위 위젯에서 처리)
    }
  }
}

// HomeScreen을 ChangeNotifierProvider로 감싸는 래퍼 위젯
class HomeScreenWrapper extends StatelessWidget {
  const HomeScreenWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        if (kDebugMode) {
          debugPrint('[HomeScreen] HomeViewModel 인스턴스 생성');
        }
        return HomeViewModel();
      },
      child: const HomeScreen(),
    );
  }
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final UsageLimitService _usageLimitService = UsageLimitService();
  final MarketingCampaignService _marketingService = MarketingCampaignService();
  
  // 사용량 관련 상태 변수
  bool _hasCheckedUsage = false;
  Map<String, dynamic> _limitStatus = {};
  Map<String, double> _usagePercentages = {};
  bool _noteExceed = false; // 노트 생성 관련 제한 플래그 추가
  
  // 이미지 피커 상태 변수 추가
  bool _isImagePickerShowing = false;
  
  // 사용량 확인 중인지 추적하는 변수 추가
  bool _isCheckingUsage = false;
  DateTime? _lastUsageCheckTime;
  
  // 화면 초기화 실패를 추적하는 변수
  bool _initializationFailed = false;
  String? _initFailReason;

  @override
  void initState() {
    if (kDebugMode) {
      debugPrint('[HomeScreen] initState 호출됨');
    }
    
    try {
      super.initState();
      
      // WidgetsBinding 옵저버 등록
      WidgetsBinding.instance.addObserver(this);
      
      // 비동기 작업들을 병렬로 실행하여 성능 최적화
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeAsyncTasks();
      });
      
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[HomeScreen] initState 초기화 중 오류 발생: $e');
        debugPrint('[HomeScreen] 스택 트레이스: $stackTrace');
      }
      
      // 초기화 실패 상태 저장
      _initializationFailed = true;
      _initFailReason = e.toString();
      
      // 중요: 에러가 발생해도 WidgetsBinding 옵저버는 등록해야 함
      WidgetsBinding.instance.addObserver(this);
    }
  }

  /// 비동기 초기화 작업들을 병렬로 실행
  Future<void> _initializeAsyncTasks() async {
    try {
      // 병렬로 실행할 작업들
      await Future.wait([
        _checkUsageAndButtonStatus(),
        _initializeMarketingService(),
      ]);
      
      // Route 변경 감지를 위한 리스너 추가
      if (ModalRoute.of(context) != null) {
        ModalRoute.of(context)!.addScopedWillPopCallback(() async {
          // 화면으로 돌아올 때마다 노트스페이스 이름을 다시 로드
          await _checkUsageAndButtonStatus();
          return false; // false를 반환하여 pop을 방해하지 않음
        });
      }
      
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[HomeScreen] 비동기 초기화 중 오류 발생: $e');
        debugPrint('[HomeScreen] 스택 트레이스: $stackTrace');
      }
      // 비동기 초기화 실패는 앱 진행에 영향을 주지 않음
    }
  }
  
  // 마케팅 캠페인 서비스 초기화
  Future<void> _initializeMarketingService() async {
    try {
    await _marketingService.initialize();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HomeScreen] 마케팅 서비스 초기화 중 오류: $e');
      }
      // 마케팅 서비스 초기화 실패는 무시하고 계속 진행
    }
  }
  
  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint('[HomeScreen] dispose 호출됨');
    }
    
    try {
    // 리스너 제거
    WidgetsBinding.instance.removeObserver(this);
    
    super.dispose();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HomeScreen] dispose 중 오류 발생: $e');
      }
      super.dispose(); // 오류가 발생해도 부모 dispose는 호출해야 함
    }
  }

  @override
  Widget build(BuildContext context) {
    // 디버그 로그 추가
    if (kDebugMode) {
      debugPrint('[HomeScreen] build 메서드 시작');
    }
    
    // 초기화 실패 시 복구 UI 표시
    if (_initializationFailed) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Pikabook'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {
                  _initializationFailed = false;
                });
              },
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('화면을 초기화하는 중 문제가 발생했습니다'),
              if (_initFailReason != null) ...[
                const SizedBox(height: 16),
                Text(_initFailReason!),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _initializationFailed = false;
                  });
                },
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }
    
    try {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF9F1), // Figma 디자인의 #FFF9F1 배경색 적용
        appBar: PikaAppBar.home(),
        body: Consumer<HomeViewModel>(
          builder: (context, viewModel, _) {
            if (kDebugMode) {
              debugPrint('[HomeScreen] Consumer<HomeViewModel> 빌드');
            }
            
            try {
              if (viewModel.isLoading) {
                return const Center(
                  child: DotLoadingIndicator(),
                );
              } else if (viewModel.notes.isEmpty) {
                return _buildZeroState(context);
              }
              
              // 리스트가 실제로 보일 때만 빌드
              return _buildNotesList(context, viewModel);
            } catch (e, stackTrace) {
              if (kDebugMode) {
                debugPrint('[HomeScreen] Consumer 내부에서 오류 발생: $e');
                debugPrint('[HomeScreen] 스택 트레이스: $stackTrace');
              }
              
              // 간단한 에러 복구 UI
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('화면 로딩 중 문제가 발생했습니다.'),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        viewModel.refreshNotes();
                      },
                      child: const Text('새로고침'),
                    ),
                  ],
                ),
              );
            }
          },
        ),
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[HomeScreen] 전체 빌드 과정에서 오류 발생: $e');
        debugPrint('[HomeScreen] 스택 트레이스: $stackTrace');
      }
      
      // 빌드 실패 시 표시할 위젯
      return Scaffold(
        appBar: AppBar(
          title: const Text('Pikabook'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() {});
              },
            ),
          ],
        ),
        body: Center(
          child: Text('화면을 표시할 수 없습니다: $e'),
        ),
      );
    }
  }

  /// 노트 리스트 빌드 (실제로 보일 때만)
  Widget _buildNotesList(BuildContext context, HomeViewModel viewModel) {
    if (kDebugMode) {
      debugPrint('[HomeScreen] 노트 리스트 빌드: ${viewModel.notes.length}개');
    }
    
    return SafeArea(
      child: Column(
        children: [
          // 노트 목록
          Expanded(
            child: RefreshIndicator(
              color: ColorTokens.primary,
              backgroundColor: Colors.white,
              onRefresh: () async {
                await viewModel.refreshNotes();
              },
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 4, bottom: 16),
                itemCount: viewModel.notes.length,
                itemExtent: 104.0, // 고정 높이 설정 (성능 최적화)
                cacheExtent: 500.0, // 캐시 범위 설정
                addAutomaticKeepAlives: false, // 자동 KeepAlive 비활성화 (메모리 최적화)
                addRepaintBoundaries: false, // 불필요한 RepaintBoundary 제거
                itemBuilder: (context, index) {
                  final note = viewModel.notes[index];
                  
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    child: NoteListItem(
                      note: note,
                      onNoteTapped: (note) => _navigateToNoteDetail(context, note),
                      onDismissed: () {
                        if (note.id != null) {
                          viewModel.deleteNote(note.id!);
                          // 노트 삭제 후 사용량 재확인
                          _onNoteEvent();
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ),
          // 하단 버튼 영역
          if (viewModel.hasNotes)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: _isButtonDisabled()
                ? Tooltip(
                    message: '사용량 한도 초과로 비활성화되었습니다',
                    child: PikaButton(
                      text: '스마트 노트 만들기',
                      variant: PikaButtonVariant.primary,
                      isFullWidth: false,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      onPressed: () => _showUsageLimitInfo(context),
                    ),
                  )
                : PikaButton(
                    text: '스마트 노트 만들기',
                    variant: PikaButtonVariant.primary,
                    isFullWidth: false,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    onPressed: () => _showImagePickerBottomSheet(context),
                  ),
            ),
        ],
      ),
    );
  }

  // 사용량 확인 - 이벤트 기반으로 변경 (노트 삭제/생성 시에만)
  Future<void> _checkUsageAndButtonStatus({bool forceCheck = false}) async {
    // 이미 확인 중이면 중복 호출 방지
    if (_isCheckingUsage) {
      if (kDebugMode) {
        debugPrint('사용량 확인이 이미 진행 중입니다. 중복 호출 건너뜀');
      }
      return;
    }
    
    // 강제 체크가 아니고 이미 확인했다면 스킵
    if (!forceCheck && _hasCheckedUsage) {
      if (kDebugMode) {
        debugPrint('사용량 이미 확인됨 - 스킵');
      }
      return;
    }
    
    if (kDebugMode) {
      debugPrint('사용량 확인 시작... (forceCheck: $forceCheck)');
    }
    
    _isCheckingUsage = true;
    
    try {
      // 사용량 제한 체크 (모든 확인을 한 번에 처리)
      final usageInfo = await _usageLimitService.getUsageInfo(withBuffer: false);
      final limitStatus = usageInfo['limitStatus'] as Map<String, dynamic>;
      final usagePercentages = usageInfo['percentages'] as Map<String, double>;
      
      // 노트 제한 확인 (반복 호출하지 않도록 로컬 변수에 저장)
      final ocrLimitReached = limitStatus['ocrLimitReached'] == true;
      final ttsLimitReached = limitStatus['ttsLimitReached'] == true;
      final translationLimitReached = limitStatus['translationLimitReached'] == true;
      final storageLimitReached = limitStatus['storageLimitReached'] == true;
      final noteExceed = ocrLimitReached || translationLimitReached || storageLimitReached;
      
      if (kDebugMode) {
        debugPrint('Home 화면: OCR 제한 도달=${limitStatus['ocrLimitReached']}, 노트 제한=$noteExceed');
        debugPrint('Home 화면: 번역 제한=${limitStatus['translationLimitReached']}, 저장소 제한=${limitStatus['storageLimitReached']}');
      }
      
      // 상태가 실제로 변경되었을 때만 setState 호출
      final bool shouldDisableButton = ocrLimitReached || translationLimitReached || storageLimitReached || noteExceed;
      
      if (mounted && (_noteExceed != shouldDisableButton || !_hasCheckedUsage)) {
        setState(() {
          _limitStatus = limitStatus;
          _usagePercentages = usagePercentages;
          _noteExceed = shouldDisableButton;
          _hasCheckedUsage = true;
          _lastUsageCheckTime = DateTime.now();
        });
        
        if (kDebugMode) {
          debugPrint('사용량 상태 업데이트: 노트 생성 제한=$_noteExceed, 버튼 비활성화=$shouldDisableButton');
        }
      } else {
        // 상태는 변경되지 않았지만 시간은 업데이트
        _lastUsageCheckTime = DateTime.now();
        
        if (kDebugMode) {
          debugPrint('사용량 확인 완료 (상태 변경 없음): 노트 생성 제한=$_noteExceed');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('사용량 확인 중 오류 발생: $e');
      }
    } finally {
      // 확인 중 상태 해제
      _isCheckingUsage = false;
    }
  }
  
  /// 노트 관련 이벤트 발생 시 사용량 재확인
  void _onNoteEvent() {
    _checkUsageAndButtonStatus(forceCheck: true);
  }
  
  // 지원팀 문의하기 처리
  void _handleContactSupport() async {
    // 프리미엄 문의 구글 폼 URL
    const String formUrl = 'https://forms.gle/9EBEV1vaLpNbkhxD9';
    final Uri url = Uri.parse(formUrl);
    
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        // URL을 열 수 없는 경우 스낵바로 알림
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('문의 폼을 열 수 없습니다. 직접 브라우저에서 다음 주소를 입력해 주세요: $formUrl'),
              duration: const Duration(seconds: 10),
            ),
          );
        }
      }
    } catch (e) {
      // 오류 발생 시 스낵바로 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('문의 폼을 여는 중 오류가 발생했습니다. 이메일로 문의해 주세요: hello.pikabook@gmail.com'),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  void _showImagePickerBottomSheet(BuildContext context) async {
    // 이미 표시 중이면 중복 호출 방지
    if (_isImagePickerShowing) {
      if (kDebugMode) {
        debugPrint('이미지 피커가 이미 표시 중입니다. 중복 호출 방지');
      }
      return;
    }
    
    try {
      // 최근에 확인한 경우 다시 확인하지 않음 (10초 이내)
      final now = DateTime.now();
      final skipCheck = _hasCheckedUsage && _lastUsageCheckTime != null && 
          now.difference(_lastUsageCheckTime!).inSeconds < 10;
          
      if (!skipCheck) {
        if (kDebugMode) {
          debugPrint('사용량 확인 필요 - 확인 중...');
        }
        await _checkUsageAndButtonStatus();
      } else {
        if (kDebugMode) {
          debugPrint('최근에 사용량 이미 확인함 (캐시 사용)');
        }
      }
      
      // 제한에 도달했으면 다이얼로그 표시하고 종료
      if (_noteExceed) {
        UsageDialog.show(
          context,
          title: '사용량 한도에 도달했습니다',
          message: '다음 달 1일부터 다시 이용하실수 있습니다. 더 많은 기능이 필요하시다면 문의하기를 통해 요청해 주세요.',
          limitStatus: _limitStatus,
          usagePercentages: _usagePercentages,
          onContactSupport: _handleContactSupport,
        );
        return;
      }
      
      // 표시 중 상태로 설정
      setState(() {
        _isImagePickerShowing = true;
      });
      
      // 제한이 없으면 이미지 피커 바텀시트 표시
      if (mounted) {
        await showModalBottomSheet(
      context: context,
          isScrollControlled: true,
          isDismissible: true,
          enableDrag: true,
          backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
            return const ImagePickerBottomSheet();
      },
    );
        
        // 바텀 시트가 닫힌 후 상태 업데이트
        if (mounted) {
          setState(() {
            _isImagePickerShowing = false;
          });
          // 노트 생성 가능성이 있으므로 사용량 재확인
          _onNoteEvent();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('이미지 피커 표시 중 오류: $e');
      }
      if (mounted) {
        setState(() {
          _isImagePickerShowing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 선택 화면을 열 수 없습니다')),
        );
      }
    }
  }

  void _navigateToNoteDetail(BuildContext context, Note note) async {
    try {
      if (note.id == null || note.id!.isEmpty) {
        print("[HOME] 노트 ID가 유효하지 않습니다: ${note.id}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 정보가 유효하지 않습니다.')),
        );
        return;
      }

      print("[HOME] 노트 상세화면으로 이동합니다. ID: ${note.id!}");
      print("[HOME] 노트 제목: ${note.title}");
      print("[HOME] 노트 생성 시간: ${note.createdAt}");
      
      // 네비게이션 직전 로그 추가
      print("🚀 [HOME] Navigator.push 호출 직전. Note ID: ${note.id}");

      Navigator.of(context).push(
        NoteDetailScreenMVVM.route(note: note), // MVVM 패턴 적용한 화면으로 변경
      ).then((_) {
        print("[HOME] 노트 상세화면에서 돌아왔습니다.");
        Provider.of<HomeViewModel>(context, listen: false).refreshNotes();
      });
    } catch (e, stackTrace) {
      print("[HOME] 노트 상세화면 이동 중 오류 발생: $e");
      print("[HOME] 스택 트레이스: $stackTrace");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('노트 상세화면으로 이동할 수 없습니다: $e')),
      );
    }
  }
// zero state 디자인 위젯

  Widget _buildZeroState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/zeronote.png',
              width: 214,
              height: 160,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 30),
            
            Text(
              '먼저, 번역이 필요한\n이미지를 올려주세요.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF0E2823), // #0E2823
              ),
            ),
            const SizedBox(height: 16),
            
            Text(
              '이미지를 기반으로 학습 노트를 만들어드립니다. \n카메라 촬영도 가능합니다.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: const Color(0xFF969696), // #969696
              ),
            ),
            const SizedBox(height: 24),
            // CTA 버튼 - 이미지 업로드하기 (사용량 초과시 비활성화)
            _isButtonDisabled()
              ? Tooltip(
                  message: '사용량 한도 초과로 비활성화되었습니다',
                  child: PikaButton(
                    text: '이미지 올리기',
                    variant: PikaButtonVariant.primary,
                    isFullWidth: true,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    onPressed: () => _showUsageLimitInfo(context),
                  ),
                )
              : PikaButton(
                  text: '이미지 올리기',
                  variant: PikaButtonVariant.primary,
                  isFullWidth: true,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  onPressed: () => _showImagePickerBottomSheet(context),
                ),
          ],
        ),
      ),
    );
  }

  // Zero state에서 '새 노트 만들기' 버튼 클릭 핸들러
  void _handleAddImage(BuildContext context) async {
    // 바로 이미지 피커 바텀 시트 표시
    if (!mounted) return;
    _showImagePickerBottomSheet(context);
  }

  /// 모든 플래시카드 보기 화면으로 이동
  Future<void> _navigateToAllFlashcards() async {
    try {
      // 플래시카드 화면으로 이동
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const FlashCardScreen(),
        ),
      );

      /// 플래시카드 카운터 업데이트가 필요한 경우
      if (result != null && result is Map && result.containsKey('flashcardCount')) {
        final HomeViewModel viewModel = Provider.of<HomeViewModel>(context, listen: false);
        
        // 특정 노트의 플래시카드 카운터만 업데이트
        if (result.containsKey('noteId') && result['noteId'] != null) {
          String noteId = result['noteId'] as String;
          
          // 해당 노트의 플래시카드 수만 업데이트 (NoteService를 통해 직접 업데이트)
          final int flashcardCount = result['flashcardCount'] as int;
          final int index = viewModel.notes.indexWhere((note) => note.id == noteId);
          if (index >= 0) {
            final note = viewModel.notes[index].copyWith(flashcardCount: flashcardCount);
            final noteService = NoteService();
            await noteService.updateNote(noteId, note);
          }
        }
        
        // 최신 데이터로 새로고침
        viewModel.refreshNotes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('플래시카드 화면 이동 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  // 버튼 비활성화 여부 확인
  bool _isButtonDisabled() {
    // OCR, 번역, 저장 공간 중 하나라도 한도 도달 시 버튼 비활성화
    // _noteExceed 플래그는 이미 이러한 조건들을 종합적으로 체크함
    if (kDebugMode) {
      debugPrint('버튼 비활성화 확인: _noteExceed=$_noteExceed, limitStatus=$_limitStatus');
    }
    
    if (_noteExceed) {
      return true;
    }
    
    // 플래그에 의존하지 않고 직접 확인 (안전장치)
    if (_limitStatus.isNotEmpty) {
      final bool ocrLimitReached = _limitStatus['ocrLimitReached'] == true;
      final bool translationLimitReached = _limitStatus['translationLimitReached'] == true;
      final bool storageLimitReached = _limitStatus['storageLimitReached'] == true;
      
      return ocrLimitReached || translationLimitReached || storageLimitReached;
    }
    
    return false;
  }

  // HomeViewModel 변경 시 호출될 메서드
  void _onViewModelChanged() {
    // 필요시 상태 업데이트
    if (!mounted) return;
  }

  // 노트스페이스 옵션 표시
  void _showNoteSpaceOptions() {
    // 현재는 기능 구현 없이 로그만 출력
    if (kDebugMode) {
    print('노트스페이스 옵션 메뉴 표시 예정');
    }
    // TODO: 노트스페이스 선택 또는 관리 메뉴 표시 구현
  }

  // 사용량 제한 정보 다이얼로그 표시 메서드 추가
  void _showUsageLimitInfo(BuildContext context) {
    // 다이얼로그 표시 (다이얼로그 방식)
    UsageDialog.show(
      context,
      title: '사용량 제한에 도달했습니다',
      message: '노트 생성 관련 기능이 제한되었습니다. 더 많은 기능이 필요하시다면 문의하기를 통해 요청해 주세요.',
      limitStatus: _limitStatus,
      usagePercentages: _usagePercentages,
      onContactSupport: _handleContactSupport,
    );
  
  }
} 