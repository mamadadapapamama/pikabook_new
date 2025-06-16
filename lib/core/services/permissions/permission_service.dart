import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// 권한 관리 서비스
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// 카메라 권한 확인 및 요청
  Future<bool> requestCameraPermission(BuildContext context) async {
    final cameraStatus = await Permission.camera.status;
    
    if (kDebugMode) {
      print('📷 카메라 권한 상태: $cameraStatus');
    }
    
    // 이미 허용된 경우
    if (cameraStatus.isGranted) {
      return true;
    }
    
    // 권한이 거부된 적이 있거나 처음 요청하는 경우 설명 다이얼로그 표시
    if (cameraStatus.isDenied || cameraStatus.isRestricted) {
      final shouldRequest = await _showCameraPermissionDialog(context);
      if (!shouldRequest) {
        return false;
      }
      
      // 권한 요청
      final newStatus = await Permission.camera.request();
      if (newStatus.isGranted) {
        return true;
      } else if (newStatus.isDenied || newStatus.isPermanentlyDenied) {
        _showPermissionDeniedDialog(
          context,
          '카메라 권한이 필요합니다',
          '카메라 기능을 사용하려면 설정에서 카메라 권한을 허용해주세요.',
        );
        return false;
      }
    } else if (cameraStatus.isPermanentlyDenied) {
      _showPermissionDeniedDialog(
        context,
        '카메라 권한이 필요합니다',
        '카메라 기능을 사용하려면 설정에서 카메라 권한을 허용해주세요.',
      );
      return false;
    }
    
    return false;
  }

  /// 갤러리 권한 확인 및 요청
  Future<bool> requestGalleryPermission(BuildContext context) async {
    // 플랫폼별로 다른 권한
    Permission galleryPermission = Platform.isIOS 
        ? Permission.photos 
        : Permission.storage;
    
    final galleryStatus = await galleryPermission.status;
    
    if (kDebugMode) {
      print('📱 갤러리 권한 상태: $galleryStatus');
    }
    
    // 이미 허용된 경우
    if (galleryStatus.isGranted) {
      return true;
    }
    
    // 권한이 거부된 적이 있거나 처음 요청하는 경우 설명 다이얼로그 표시
    if (galleryStatus.isDenied || galleryStatus.isRestricted) {
      final shouldRequest = await _showGalleryPermissionDialog(context);
      if (!shouldRequest) {
        return false;
      }
      
      // 권한 요청
      final newStatus = await galleryPermission.request();
      if (newStatus.isGranted) {
        return true;
      } else if (newStatus.isDenied || newStatus.isPermanentlyDenied) {
        _showPermissionDeniedDialog(
          context,
          '갤러리 권한이 필요합니다',
          '갤러리 기능을 사용하려면 설정에서 사진 권한을 허용해주세요.',
        );
        return false;
      }
    } else if (galleryStatus.isPermanentlyDenied) {
      _showPermissionDeniedDialog(
        context,
        '갤러리 권한이 필요합니다',
        '갤러리 기능을 사용하려면 설정에서 사진 권한을 허용해주세요.',
      );
      return false;
    }
    
    return false;
  }

  /// 카메라 권한 설명 다이얼로그
  Future<bool> _showCameraPermissionDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('사진 촬영을 위해 카메라 권한이 필요합니다'),
        content: const Text('[필수] 교재나 노트를 찍어 분석하려면 카메라 접근이 필요합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('거부'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('허용'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  /// 갤러리 권한 설명 다이얼로그
  Future<bool> _showGalleryPermissionDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('갤러리 접근을 위해 사진 권한이 필요합니다'),
        content: const Text('[필수] 저장된 교재나 노트 이미지를 선택하려면 갤러리 접근이 필요합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('거부'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('허용'),
          ),
        ],
      ),
    );
    
    return result ?? false;
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