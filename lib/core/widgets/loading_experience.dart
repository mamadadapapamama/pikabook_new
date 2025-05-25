import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../../core/theme/tokens/typography_tokens.dart';
import 'dot_loading_indicator.dart';

/// 로딩 경험을 중앙 관리하는 클래스와 위젯들
/// 애플리케이션 전체에서 일관된 로딩 UI 경험을 제공합니다.
/// 
/// 1. 인라인 로딩 - LoadingExperience 위젯
/// 2. 전체 화면 로딩 - LoadingPage 위젯

// ----------------- 1. 인라인 로딩 경험 위젯 -----------------

/// 로딩 경험을 중앙 관리하는 위젯
/// 로딩 상태, 오류 상태, 콘텐츠 표시를 일관되게 처리합니다.
class LoadingExperience extends StatefulWidget {
  /// 로딩 중일 때 표시할 위젯 (기본 DotLoadingIndicator 사용)
  final Widget? loadingWidget;
  
  /// 오류 발생 시 표시할 위젯
  final Widget Function(dynamic error, VoidCallback retry)? errorWidgetBuilder;
  
  /// 콘텐츠 위젯 빌더
  final Widget Function(BuildContext context) contentBuilder;
  
  /// 데이터를 로드하는 비동기 함수
  final Future<void> Function() loadData;
  
  /// 로딩 표시 지연 시간 (밀리초)
  /// 이 시간보다 짧게 로딩되면 로딩 위젯을 표시하지 않음
  final int loadingDelayMs;
  
  /// 초기 로드 여부
  final bool initialLoad;
  
  /// 빈 상태 표시 위젯
  final Widget? emptyStateWidget;
  
  /// 빈 상태 체크 함수
  final bool Function()? isEmptyState;
  
  /// 로딩 메시지
  final String? loadingMessage;

  /// 로딩 경험 관리 위젯 생성자
  const LoadingExperience({
    Key? key,
    this.loadingWidget,
    this.errorWidgetBuilder,
    required this.contentBuilder,
    required this.loadData,
    this.loadingDelayMs = 300,
    this.initialLoad = true,
    this.emptyStateWidget,
    this.isEmptyState,
    this.loadingMessage,
  }) : super(key: key);

  @override
  State<LoadingExperience> createState() => _LoadingExperienceState();
}

class _LoadingExperienceState extends State<LoadingExperience> {
  bool _isLoading = false;
  bool _isFirstLoad = true;
  dynamic _error;
  Timer? _loadingTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialLoad) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_isLoading) return;
    
    // 로딩 타이머 시작
    _loadingTimer?.cancel();
    _loadingTimer = Timer(Duration(milliseconds: widget.loadingDelayMs), () {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
    });
    
    try {
      await widget.loadData();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFirstLoad = false;
          _error = null;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('LoadingExperience: 로드 중 오류 발생 - $e');
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e;
        });
      }
    } finally {
      _loadingTimer?.cancel();
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildDefaultLoadingWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DotLoadingIndicator(),
          if (widget.loadingMessage != null && !kReleaseMode) ...[
            const SizedBox(height: 16),
            Text(
              widget.loadingMessage!,
              style: TypographyTokens.body2,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDefaultErrorWidget(dynamic error, VoidCallback retry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            '오류가 발생했습니다.\n${error.toString()}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: retry,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 로딩 중인 경우
    if (_isLoading && _isFirstLoad ) {
      return widget.loadingWidget ?? _buildDefaultLoadingWidget();
    }
    
    // 오류가 발생한 경우
    if (_error != null) {
      return widget.errorWidgetBuilder != null
          ? widget.errorWidgetBuilder!(_error, _loadData)
          : _buildDefaultErrorWidget(_error, _loadData);
    }
    
    // 빈 상태 체크
    if (widget.isEmptyState != null && 
        widget.isEmptyState!() && 
        widget.emptyStateWidget != null) {
      return widget.emptyStateWidget!;
    }
    
    // 콘텐츠 표시 (로딩 중이더라도 콘텐츠가 있다면 표시)
    return widget.contentBuilder(context);
  }
}

/// 로딩 경험을 페이지 단위로 제공하는 위젯
/// 전체 화면을 로딩/오류/콘텐츠 상태로 관리합니다.
class LoadingPage extends StatelessWidget {
  /// 로딩 중일 때 표시할 위젯
  final Widget? loadingWidget;
  
  /// 오류 발생 시 표시할 위젯
  final Widget Function(dynamic error, VoidCallback retry)? errorWidgetBuilder;
  
  /// 페이지 제목
  final String title;
  
  /// 콘텐츠 위젯 빌더
  final Widget Function(BuildContext context) contentBuilder;
  
  /// 데이터를 로드하는 비동기 함수
  final Future<void> Function() loadData;
  
  /// 앱바에 표시할 액션 버튼들
  final List<Widget>? actions;
  
  /// 스캐폴드의 floatingActionButton
  final Widget? floatingActionButton;
  
  /// 스캐폴드의 bottomNavigationBar
  final Widget? bottomNavigationBar;
  
  /// 로딩 메시지
  final String? loadingMessage;
  
  /// 로딩 페이지 생성자
  const LoadingPage({
    Key? key,
    this.loadingWidget,
    this.errorWidgetBuilder,
    required this.title,
    required this.contentBuilder,
    required this.loadData,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.loadingMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: actions,
      ),
      body: LoadingExperience(
        loadingWidget: loadingWidget,
        errorWidgetBuilder: errorWidgetBuilder,
        contentBuilder: contentBuilder,
        loadData: loadData,
        loadingMessage: loadingMessage,
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
} 