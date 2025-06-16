import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/color_tokens.dart';

/// 권한 관리 서비스
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// 권한 상태 확인 및 요청
  Future<Map<String, bool>> requestImagePermissions(BuildContext context) async {
    print('🔐 권한 요청 시작');

    // 1. 현재 권한 상태 확인
    final cameraStatus = await Permission.camera.status;
    final photosStatus = await Permission.photos.status;
    
    print('📷 현재 카메라 권한 상태: $cameraStatus');
    print('📱 현재 갤러리 권한 상태: $photosStatus');

    // 2. 권한이 이미 허용된 경우
    if (cameraStatus.isGranted && photosStatus.isGranted) {
      print('✅ 모든 권한이 이미 허용됨');
      return {'camera': true, 'gallery': true};
    }

    // 3. 권한 요청 가능 여부 확인
    print('🔍 권한 요청 가능 여부 확인:');
    print('📷 카메라 - isDenied: ${cameraStatus.isDenied}, isLimited: ${cameraStatus.isLimited}');
    print('📱 갤러리 - isDenied: ${photosStatus.isDenied}, isLimited: ${photosStatus.isLimited}');
    print('📷 카메라 - isPermanentlyDenied: ${cameraStatus.isPermanentlyDenied}');
    print('📱 갤러리 - isPermanentlyDenied: ${photosStatus.isPermanentlyDenied}');

    // 4. 권한 요청 시도
    PermissionStatus cameraResult = cameraStatus;
    PermissionStatus galleryResult = photosStatus;

    // 카메라 권한 요청
    if (!cameraStatus.isGranted && !cameraStatus.isPermanentlyDenied) {
      print('📷 카메라 권한 요청 중...');
      cameraResult = await Permission.camera.request();
      print('📷 카메라 권한 요청 결과: $cameraResult');
    } else if (cameraStatus.isPermanentlyDenied) {
      print('📷 카메라 권한이 영구적으로 거부됨 - 요청 스킵');
    }

    // 갤러리 권한 요청
    if (!photosStatus.isGranted && !photosStatus.isPermanentlyDenied) {
      print('📱 갤러리 권한 요청 중...');
      galleryResult = await Permission.photos.request();
      print('📱 갤러리 권한 요청 결과: $galleryResult');
    } else if (photosStatus.isPermanentlyDenied) {
      print('📱 갤러리 권한이 영구적으로 거부됨 - 요청 스킵');
    }

    final results = {
      'camera': cameraResult.isGranted,
      'gallery': galleryResult.isGranted,
    };

    print('🔐 최종 결과: $results');
    return results;
  }

  /// 공통 권한 요청 메서드
  Future<bool> _requestPermission({
    required BuildContext context,
    required Permission permission,
    required String permissionName,
    required String debugIcon,
    required String deniedMessage,
  }) async {
    final status = await permission.status;
    
    if (kDebugMode) {
      print('$debugIcon $permissionName 권한 상태: $status');
    }
    
    // 이미 허용된 경우
    if (status.isGranted) {
      return true;
    }
    
    // 영구적으로 거부된 경우 설정 안내
    if (status.isPermanentlyDenied) {
      _showPermissionDeniedDialog(
        context,
        '$permissionName 권한이 필요합니다',
        deniedMessage,
      );
      return false;
    }
    
    // 바로 시스템 권한 요청 (커스텀 다이얼로그 없이)
    final newStatus = await permission.request();
    
    // 권한이 허용되면 성공
    if (newStatus.isGranted) {
      return true;
    }
    
    // 영구적으로 거부된 경우에만 설정 안내 다이얼로그 표시
    if (newStatus.isPermanentlyDenied) {
      _showPermissionDeniedDialog(
        context,
        '$permissionName 권한이 필요합니다',
        deniedMessage,
      );
    }
    
    // 일반 거부의 경우 조용히 실패 (추가 다이얼로그 없음)
    return false;
  }

  /// 권한 거부 시 설정 안내 다이얼로그
  void _showPermissionDeniedDialog(
    BuildContext context,
    String title,
    String content,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('설정으로 이동'),
          ),
        ],
      ),
    );
  }
} 