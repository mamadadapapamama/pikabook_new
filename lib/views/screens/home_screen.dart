import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../viewmodels/home_viewmodel.dart';
import '../../widgets/note_list_item.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/loading_dialog.dart';
import '../../services/note_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
import '../../services/user_preferences_service.dart';
import '../../models/note.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';
import '../../theme/tokens/ui_tokens.dart';
import 'note_detail_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// 노트 카드 리스트를 보여주는 홈 화면
/// profile setting, note detail, flashcard 화면으로 이동 가능

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final UserPreferencesService _userPreferences = UserPreferencesService();
  String _noteSpaceName = '';
  
  @override
  void initState() {
    super.initState();
    _loadNoteSpaceName();
  }
  
  Future<void> _loadNoteSpaceName() async {
    final noteSpaceName = await _userPreferences.getDefaultNoteSpace();
    if (mounted) {
      setState(() {
        _noteSpaceName = noteSpaceName;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeViewModel(),
      child: Scaffold(
        backgroundColor: UITokens.homeBackground,
        appBar: AppBar(
          backgroundColor: UITokens.homeBackground,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 앱 로고
                Container(
                  alignment: Alignment.centerLeft,
                  child: Image.asset(
                    'assets/images/logo_pika_small.svg',
                    width: SpacingTokens.appLogoWidth,
                    height: SpacingTokens.appLogoHeight,
                    errorBuilder: (context, error, stackTrace) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.menu_book,
                            color: ColorTokens.primary,
                            size: SpacingTokens.iconSizeSmall,
                          ),
                          SizedBox(width: SpacingTokens.xs),
                          Text(
                            'Pikabook',
                            style: TypographyTokens.poppins.copyWith(
                              fontSize: SpacingTokens.md,
                              fontWeight: FontWeight.bold,
                              color: ColorTokens.primary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                SizedBox(height: SpacingTokens.xs),
                // 노트 스페이스 이름
                Text(
                  _noteSpaceName,
                  style: TypographyTokens.headline3.copyWith(
                    color: ColorTokens.textPrimary,
                  ),
                  textAlign: TextAlign.left,
                ),
              ],
            ),
          ),
          actions: [
            // 설정 버튼
            Padding(
              padding: EdgeInsets.only(right: SpacingTokens.md),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    Navigator.pushNamed(context, '/settings').then((_) {
                      // 설정 화면에서 돌아올 때 노트 스페이스 이름 다시 로드
                      _loadNoteSpaceName();
                    });
                  },
                  splashColor: ColorTokens.primary.withOpacity(0.1),
                  highlightColor: ColorTokens.primary.withOpacity(0.05),
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: SpacingTokens.iconSizeMedium,
                      height: SpacingTokens.iconSizeMedium,
                      child: Image.asset(
                        'assets/images/btn_profile.svg',
                        width: SpacingTokens.iconSizeMedium,
                        height: SpacingTokens.iconSizeMedium,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.person,
                            color: ColorTokens.secondary,
                            size: SpacingTokens.iconSizeMedium,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
          child: Consumer<HomeViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isLoading) {
                return const LoadingIndicator(message: '노트 불러오는 중...');
              }

              if (viewModel.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: SpacingTokens.iconSizeXLarge,
                        color: ColorTokens.error,
                      ),
                      SizedBox(height: SpacingTokens.md),
                      Text(
                        viewModel.error!,
                        textAlign: TextAlign.center,
                        style: TypographyTokens.body1,
                      ),
                      SizedBox(height: SpacingTokens.md),
                      ElevatedButton(
                        onPressed: () => viewModel.refreshNotes(),
                        child: const Text('다시 시도'),
                        style: UITokens.primaryButtonStyle,
                      ),
                    ],
                  ),
                );
              }

              if (!viewModel.hasNotes) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.note_alt_outlined,
                        size: SpacingTokens.iconSizeXLarge + 16,
                        color: Colors.grey,
                      ),
                      SizedBox(height: SpacingTokens.md),
                      Text(
                        '저장된 노트가 없습니다.\n새 노트를 만들어보세요!',
                        textAlign: TextAlign.center,
                        style: TypographyTokens.body1,
                      ),
                      SizedBox(height: SpacingTokens.lg),
                      ElevatedButton.icon(
                        onPressed: () => _showImagePickerBottomSheet(context),
                        icon: const Icon(Icons.add),
                        label: const Text('새 노트 만들기'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: ColorTokens.primary,
                          padding: EdgeInsets.symmetric(
                            horizontal: SpacingTokens.md,
                            vertical: SpacingTokens.sm + 4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              // RefreshIndicator로 감싸서 pull to refresh 기능 추가
              return RefreshIndicator(
                onRefresh: () => viewModel.refreshNotes(),
                color: ColorTokens.primary,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: SpacingTokens.md,
                    vertical: SpacingTokens.sm,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: viewModel.notes.length,
                    itemBuilder: (context, index) {
                      // 일반 노트 아이템
                      final note = viewModel.notes[index];
                      return NoteListItem(
                        note: note,
                        onTap: () => _navigateToNoteDetail(context, note.id!),
                        onFavoriteToggle: (isFavorite) {
                          if (note.id != null) {
                            viewModel.toggleFavorite(note.id!, isFavorite);
                          }
                        },
                        onDelete: () {
                          if (note.id != null) {
                            viewModel.deleteNote(note.id!);
                          }
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        floatingActionButton: Container(
          width: SpacingTokens.fabSizeSmall,
          height: SpacingTokens.fabSizeSmall,
          margin: EdgeInsets.only(
            right: SpacingTokens.sm,
            bottom: SpacingTokens.lg,
          ),
          child: FloatingActionButton(
            onPressed: () => _showImagePickerBottomSheet(context),
            tooltip: '새 노트 만들기',
            backgroundColor: ColorTokens.primary,
            child: Icon(
              Icons.add,
              color: Colors.white,
              size: SpacingTokens.iconSizeMedium,
            ),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
            ),
          ),
        ),
      ),
    );
  }

  void _showImagePickerBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SpacingTokens.radiusLarge),
        ),
      ),
      backgroundColor: UITokens.cardBackground,
      builder: (context) => _ImagePickerBottomSheet(),
    );
  }

  void _navigateToNoteDetail(BuildContext context, String noteId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NoteDetailScreen(noteId: noteId),
      ),
    );
  }
}

class _ImagePickerBottomSheet extends StatefulWidget {
  _ImagePickerBottomSheet({Key? key}) : super(key: key);

  @override
  State<_ImagePickerBottomSheet> createState() =>
      _ImagePickerBottomSheetState();
}

class _ImagePickerBottomSheetState extends State<_ImagePickerBottomSheet> {
  final ImageService _imageService = ImageService();
  final NoteService _noteService = NoteService();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '새 노트 만들기',
            style: TypographyTokens.subtitle1,
          ),
          SizedBox(height: SpacingTokens.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildOptionButton(
                context,
                icon: Icons.photo_library,
                label: '갤러리에서 선택',
                onTap: () => _pickImagesAndCreateNote(context),
              ),
              _buildOptionButton(
                context,
                icon: Icons.camera_alt,
                label: '카메라로 촬영',
                onTap: () => _takePhotoAndCreateNote(context),
              ),
            ],
          ),
          SizedBox(height: SpacingTokens.md),
        ],
      ),
    );
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      child: Container(
        width: 120,
        padding: EdgeInsets.symmetric(vertical: SpacingTokens.md),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: SpacingTokens.iconSizeXLarge, 
              color: Theme.of(context).primaryColor,
            ),
            SizedBox(height: SpacingTokens.sm),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TypographyTokens.button,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImagesAndCreateNote(BuildContext context) async {
    // 바텀 시트를 닫기 전에 전역 키를 사용하여 컨텍스트 저장
    final navigatorContext = Navigator.of(context).context;

    Navigator.pop(context); // 바텀 시트 닫기

    try {
      final images = await _imageService.pickMultipleImages();

      if (images.isNotEmpty) {
        // 저장된 컨텍스트를 사용하여 로딩 다이얼로그 표시
        if (navigatorContext.mounted) {
          LoadingDialog.show(navigatorContext, message: '노트 생성 중...');
          await _createNoteWithImages(navigatorContext, images);
        }
      }
    } catch (e) {
      if (navigatorContext.mounted) {
        // 오류 발생 시 로딩 다이얼로그 닫기
        LoadingDialog.hide(navigatorContext);
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          SnackBar(
            content: Text('이미지 선택 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
            behavior: UITokens.snackBarTheme.behavior,
            shape: UITokens.snackBarTheme.shape,
          ),
        );
      }
    }
  }

  Future<void> _takePhotoAndCreateNote(BuildContext context) async {
    // 바텀 시트를 닫기 전에 전역 키를 사용하여 컨텍스트 저장
    final navigatorContext = Navigator.of(context).context;

    Navigator.pop(context); // 바텀 시트 닫기

    try {
      final image = await _imageService.takePhoto();

      if (image != null) {
        // 저장된 컨텍스트를 사용하여 로딩 다이얼로그 표시
        if (navigatorContext.mounted) {
          LoadingDialog.show(navigatorContext, message: '노트 생성 중...');
          await _createNoteWithImages(navigatorContext, [image]);
        }
      } else {
        // 사용자가 사진 촬영을 취소한 경우
        if (navigatorContext.mounted) {
          ScaffoldMessenger.of(navigatorContext).showSnackBar(
            SnackBar(
              content: const Text('사진 촬영이 취소되었습니다.'),
              backgroundColor: ColorTokens.secondary,
              behavior: UITokens.snackBarTheme.behavior,
              shape: UITokens.snackBarTheme.shape,
            ),
          );
        }
      }
    } catch (e) {
      if (navigatorContext.mounted) {
        // 오류 발생 시 로딩 다이얼로그 닫기
        LoadingDialog.hide(navigatorContext);
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          SnackBar(
            content: Text('사진 촬영 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
            behavior: UITokens.snackBarTheme.behavior,
            shape: UITokens.snackBarTheme.shape,
          ),
        );
      }
    }
  }

  Future<void> _createNoteWithImages(
      BuildContext context, List<File> images) async {
    if (images.isEmpty) return;

    // 로딩 다이얼로그 표시 여부를 추적하는 변수
    bool isLoadingDialogShowing = false;

    try {
      print("노트 생성 시작: ${images.length}개 이미지");

      // 로딩 다이얼로그 표시 - 첫 페이지 로딩까지만 표시
      if (context.mounted) {
        LoadingDialog.show(context, message: '노트 생성 중...');
        isLoadingDialogShowing = true;
      }

      // 여러 이미지로 노트 생성 (첫 번째 페이지만 처리하고 결과 반환)
      final result = await _noteService.createNoteWithMultipleImages(
        imageFiles: images,
        title: null, // 자동 타이틀 생성을 위해 null 전달
        silentProgress: true, // 진행 상황 업데이트 무시
      );

      // 로딩 다이얼로그 닫기 (화면 전환 전)
      if (context.mounted && isLoadingDialogShowing) {
        LoadingDialog.hide(context);
        isLoadingDialogShowing = false;
        // 약간의 지연을 주어 다이얼로그가 확실히 닫히도록 함
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (result['success'] == true && result['noteId'] != null) {
        final String noteId = result['noteId'] as String;

        // 노트 상세 화면으로 이동
        if (context.mounted) {
          print("노트 상세 화면으로 이동 시도");

          // 화면 전환
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => NoteDetailScreen(
                noteId: noteId,
                isProcessingBackground: false, // 백그라운드 처리 알림 제거
              ),
            ),
          );

          print("노트 상세 화면으로 이동 완료");
        }
      } else {
        // 오류 메시지 표시
        final message = result['message'] ?? '노트 생성에 실패했습니다.';
        print("노트 생성 실패: $message");

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message.toString()),
              backgroundColor: ColorTokens.error,
              behavior: UITokens.snackBarTheme.behavior,
              shape: UITokens.snackBarTheme.shape,
            ),
          );
        }
      }
    } catch (e) {
      print("노트 생성 중 오류 발생: $e");

      // 오류 발생 시 로딩 다이얼로그 닫고 오류 메시지 표시
      if (context.mounted && isLoadingDialogShowing) {
        LoadingDialog.hide(context);
        isLoadingDialogShowing = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('노트 생성 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
            behavior: UITokens.snackBarTheme.behavior,
            shape: UITokens.snackBarTheme.shape,
          ),
        );
      }
    }
  }
}
