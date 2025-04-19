import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart' show timeDilation;

import '../../../models/note.dart';
import '../../../models/page.dart' as page_model;
import '../../../services/note/note_service.dart';
import '../../../services/image/image_service.dart';
import '../../../services/user/user_preferences_service.dart';
import '../../../widgets/dot_loading_indicator.dart';
import '../../../theme/tokens/color_tokens.dart';
import '../../../theme/tokens/typography_tokens.dart';
import '../../../theme/tokens/spacing_tokens.dart';

import 'widgets/note_detail_app_bar.dart';
import 'widgets/note_detail_body.dart';
import 'widgets/note_detail_bottom_bar.dart';
import 'managers/note_page_manager_wrapper.dart';
import 'managers/text_processing_manager.dart';
import 'managers/background_processing_manager.dart';
import 'managers/image_loading_manager.dart';

/// 노트 상세 화면 - 메인 코드
/// 
/// 이 파일은 노트 상세 화면의 기본 구조를 정의합니다.
/// 세부 기능은 다음과 같이 분리되었습니다:
/// - note_page_manager_wrapper.dart: 페이지 관리 로직
/// - text_processing_manager.dart: 텍스트 처리 로직
/// - background_processing_manager.dart: 백그라운드 처리 로직
/// - image_loading_manager.dart: 이미지 로딩 로직
/// - widgets/: UI 컴포넌트들

class NoteDetailScreen extends StatefulWidget {
  final String noteId;
  final bool isProcessingBackground;
  final int? totalImageCount;

  const NoteDetailScreen({
    super.key,
    required this.noteId,
    this.isProcessingBackground = false,
    this.totalImageCount,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> with WidgetsBindingObserver {
  // 서비스 인스턴스들
  final NoteService _noteService = NoteService();
  final ImageService _imageService = ImageService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  
  // 관리자 인스턴스들 (분리된 코드에서 관리)
  late NotePageManagerWrapper _pageManagerWrapper;
  late TextProcessingManager _textProcessingManager;
  late BackgroundProcessingManager _backgroundManager;
  late ImageLoadingManager _imageLoadingManager;
  
  // 상태 변수
  Note? _note;
  bool _isLoading = true;
  String? _error;
  bool _useSegmentMode = true;
  
  @override
  void initState() {
    super.initState();
    // Force disable debug timer
    timeDilation = 1.0;
    
    WidgetsBinding.instance.addObserver(this);
    
    // 관리자 클래스 초기화
    _pageManagerWrapper = NotePageManagerWrapper(
      noteId: widget.noteId,
      onPageChanged: _handlePageChanged,
    );
    
    _textProcessingManager = TextProcessingManager(
      onProcessingStateChanged: _handleProcessingStateChanged,
    );
    
    _backgroundManager = BackgroundProcessingManager(
      noteId: widget.noteId,
      onProcessingCompleted: _handleBackgroundProcessingCompleted,
    );
    
    _imageLoadingManager = ImageLoadingManager(
      imageService: _imageService,
      onImageLoaded: _handleImageLoaded,
    );
    
    // 초기 설정
    if (widget.totalImageCount != null && widget.totalImageCount! > 0) {
      _pageManagerWrapper.setExpectedTotalPages(widget.totalImageCount!);
    }
    
    // 시스템 UI 설정 및 데이터 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupSystemUI();
      _loadNote();
    });
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    
    // 리소스 정리
    _cleanupResources();
    
    super.dispose();
  }
  
  // 시스템 UI 설정
  void _setupSystemUI() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }
  
  // 노트 로드
  Future<void> _loadNote() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });
      
      // 노트 로드
      final note = await _noteService.getNote(widget.noteId);
      
      if (note == null) {
        throw Exception('노트를 찾을 수 없습니다.');
      }
      
      // 페이지 로드
      await _pageManagerWrapper.loadPages();
      
      // 백그라운드 처리 상태 확인
      _backgroundManager.checkProcessingStatus();
      
      if (mounted) {
        setState(() {
          _note = note;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '노트를 로드하는 중 오류가 발생했습니다: $e';
          _isLoading = false;
        });
      }
    }
  }
  
  // 리소스 정리
  Future<void> _cleanupResources() async {
    await _pageManagerWrapper.dispose();
    await _textProcessingManager.dispose();
    await _backgroundManager.dispose();
    await _imageLoadingManager.dispose();
  }
  
  // 페이지 변경 핸들러
  void _handlePageChanged(int pageIndex) {
    // 페이지가 변경되면 관련 텍스트 및 이미지 로드
    if (_note != null) {
      _textProcessingManager.processTextForPage(
        _pageManagerWrapper.getCurrentPage(),
      );
      
      _imageLoadingManager.loadImageForPage(
        _pageManagerWrapper.getCurrentPage(),
      );
    }
    
    setState(() {});
  }
  
  // 처리 상태 변경 핸들러
  void _handleProcessingStateChanged(bool isProcessing) {
    setState(() {});
  }
  
  // 백그라운드 처리 완료 핸들러
  void _handleBackgroundProcessingCompleted() {
    _pageManagerWrapper.reloadPages();
  }
  
  // 이미지 로드 완료 핸들러
  void _handleImageLoaded(File? imageFile) {
    setState(() {});
  }
  
  // 전체 텍스트/세그먼트 모드 전환
  void _toggleTextMode() {
    setState(() {
      _useSegmentMode = !_useSegmentMode;
      
      // 현재 페이지의 텍스트 모드 업데이트
      if (_pageManagerWrapper.getCurrentPage()?.id != null) {
        _textProcessingManager.toggleTextMode(
          _pageManagerWrapper.getCurrentPage()!.id!,
          useSegmentMode: _useSegmentMode,
        );
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingScreen();
    }
    
    if (_error != null) {
      return _buildErrorScreen();
    }
    
    return Scaffold(
      appBar: NoteDetailAppBar(
        note: _note,
        onBack: () => Navigator.of(context).pop(),
        onUpdateTitle: _handleTitleUpdate,
      ),
      body: NoteDetailBody(
        note: _note,
        pageManagerWrapper: _pageManagerWrapper,
        useSegmentMode: _useSegmentMode,
        imageLoadingManager: _imageLoadingManager,
      ),
      bottomNavigationBar: NoteDetailBottomBar(
        pageManagerWrapper: _pageManagerWrapper,
        useSegmentMode: _useSegmentMode,
        onToggleTextMode: _toggleTextMode,
      ),
    );
  }
  
  // 타이틀 업데이트 핸들러
  Future<void> _handleTitleUpdate(String newTitle) async {
    if (_note != null) {
      try {
        await _noteService.updateNoteTitle(_note!.id!, newTitle);
        
        if (mounted) {
          setState(() {
            _note = _note!.copyWith(title: newTitle);
          });
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('제목 업데이트 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
  
  // 로딩 화면
  Widget _buildLoadingScreen() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DotLoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              '노트를 로드하고 있습니다...',
              style: TypographyTokens.body1,
            ),
          ],
        ),
      ),
    );
  }
  
  // 오류 화면
  Widget _buildErrorScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('오류'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: ColorTokens.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                '문제가 발생했습니다',
                style: TypographyTokens.h6,
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? '알 수 없는 오류가 발생했습니다.',
                textAlign: TextAlign.center,
                style: TypographyTokens.body2,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadNote,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 