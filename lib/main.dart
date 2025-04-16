import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'firebase_options.dart';
import 'services/image_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'views/screens/home_screen.dart';
import 'views/screens/note_detail_screen.dart';

/// 앱의 진입점
/// 
/// 앱 실행 준비 및 스플래시 화면 관리만 담당하고
/// 모든 로직은 App 클래스에 위임합니다.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 릴리즈 모드에서 디버그 출력 억제 (타이머 등 출력 방지)
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  
  // 시작 시 캐시 정리
  await _cleanupOnStart();
  
  // Firebase 초기화
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // 디버그 모드에서 타임스탬프 사용 설정
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
    debugPrint('Firebase 초기화 완료');
  } catch (e) {
    debugPrint('Firebase 초기화 실패: $e');
    // 초기화 실패해도 앱은 계속 실행 (일부 기능 제한)
  }
  
  // 이미지 캐시 초기화
  final imageService = ImageService();
  await imageService.cleanupTempFiles();
  
  // 보류 중인 노트 ID 확인
  String? pendingNoteId;
  bool isProcessing = false;
  
  try {
    final prefs = await SharedPreferences.getInstance();
    pendingNoteId = prefs.getString('pending_note_id');
    isProcessing = prefs.getBool('pending_note_is_processing') ?? false;
    
    if (pendingNoteId != null && pendingNoteId.isNotEmpty) {
      debugPrint('앱 시작 시 보류 중인 노트 발견: $pendingNoteId (메인 함수에서)');
      
      // SharedPreferences에서 값 제거
      await prefs.remove('pending_note_id');
      await prefs.remove('pending_note_is_processing');
    }
  } catch (e) {
    debugPrint('SharedPreferences 접근 중 오류: $e');
  }
  
  // 바로 노트 상세 페이지로 이동하도록 설정
  if (pendingNoteId != null && pendingNoteId.isNotEmpty) {
    // 노트 상세 페이지로 이동하기 위해 App 대신 직접 MaterialApp 실행
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          fontFamily: 'Pretendard',
        ),
        home: NoteDetailScreen(
          noteId: pendingNoteId,
          isProcessingBackground: isProcessing,
        ),
      ),
    );
  } else {
    // 일반적인 앱 시작
    runApp(const App());
  }
}

/// 앱 시작 시 캐시 및 임시 데이터 정리
Future<void> _cleanupOnStart() async {
  try {
    // 이미지 캐시 정리
    ImageCache imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    
    // 타이머 로그 출력 억제
    FlutterError.onError = (FlutterErrorDetails details) {
      if (!details.toString().contains('timer')) {
        FlutterError.presentError(details);
      }
    };
    
    // 이미지 서비스 임시 파일 정리
    await ImageService().cleanupTempFiles();
    
    debugPrint('앱 시작 시 캐시 정리 완료');
  } catch (e) {
    debugPrint('앱 시작 시 캐시 정리 중 오류: $e');
  }
}

Future<Widget> _determineStartScreen() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final pendingNoteId = prefs.getString('pending_note_id');
    
    if (pendingNoteId != null && pendingNoteId.isNotEmpty) {
      final isProcessing = prefs.getBool('pending_note_is_processing') ?? false;
      debugPrint('앱 시작 시 보류 중인 노트 발견: $pendingNoteId');
      
      // SharedPreferences에서 값 제거
      await prefs.remove('pending_note_id');
      await prefs.remove('pending_note_is_processing');
      
      // 노트 상세 화면으로 이동
      return NoteDetailScreen(
        noteId: pendingNoteId,
        isProcessingBackground: isProcessing,
      );
    }
    
    // 기본 시작 화면 (홈 화면)
    return const HomeScreen();
  } catch (e) {
    debugPrint('시작 화면 결정 중 오류: $e');
    return const HomeScreen();
  }
}