import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

/// 이미지 권한 관리 서비스
class PermissionService {
  // 싱글톤 패턴
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// 이미지 관련 권한 요청 (카메라 + 갤러리)
  /// 반환값: {'camera': bool, 'gallery': bool}
  Future<Map<String, bool>> requestImagePermissions(BuildContext context) async {
    try {
      print('🔍 권한 요청 시작...');
      
      // 1. 현재 권한 상태 확인
      final cameraStatus = await Permission.camera.status;
      final photosStatus = await Permission.photos.status;
      
      print('📱 현재 권한 상태:');
      print('   카메라: $cameraStatus');
      print('   갤러리: $photosStatus');
      
      // 2. 권한 요청 결과 저장
      Map<String, bool> results = {};
      
      // 3. 카메라 권한 처리 - 테스트를 위해 항상 요청
      print('📸 카메라 권한 요청 시작...');
      final cameraResult = await Permission.camera.request();
      results['camera'] = cameraResult == PermissionStatus.granted;
      print('📸 카메라 권한 요청 결과: $cameraResult');
      
      if (cameraResult == PermissionStatus.permanentlyDenied) {
        _showSettingsDialog(context, '카메라');
      }
      
      // 4. 갤러리 권한 처리 - 테스트를 위해 항상 요청
      print('🖼️ 갤러리 권한 요청 시작...');
      final photosResult = await Permission.photos.request();
      results['gallery'] = photosResult == PermissionStatus.granted;
      print('🖼️ 갤러리 권한 요청 결과: $photosResult');
      
      if (photosResult == PermissionStatus.permanentlyDenied) {
        _showSettingsDialog(context, '갤러리');
      }
      
      print('🎯 최종 권한 결과: $results');
      return results;
      
    } catch (e) {
      print('❌ 권한 요청 중 오류: $e');
      return {'camera': false, 'gallery': false};
    }
  }

  /// 카메라 권한만 요청
  Future<bool> requestCameraPermission(BuildContext context) async {
    try {
      print('📸 카메라 권한 요청 시작...');
      
      final status = await Permission.camera.status;
      print('📸 현재 카메라 권한 상태: $status');
      
      if (status == PermissionStatus.granted) {
        print('✅ 카메라 권한 이미 허용됨');
        return true;
      }
      
      if (status == PermissionStatus.permanentlyDenied) {
        print('❌ 카메라 권한 영구 거부됨');
        _showSettingsDialog(context, '카메라');
        return false;
      }
      
      final result = await Permission.camera.request();
      print('📸 카메라 권한 요청 결과: $result');
      
      if (result == PermissionStatus.permanentlyDenied) {
        _showSettingsDialog(context, '카메라');
        return false;
      }
      
      return result == PermissionStatus.granted;
      
    } catch (e) {
      print('❌ 카메라 권한 요청 중 오류: $e');
      return false;
    }
  }

  /// 갤러리 권한만 요청
  Future<bool> requestGalleryPermission(BuildContext context) async {
    try {
      print('🖼️ 갤러리 권한 요청 시작...');
      
      final status = await Permission.photos.status;
      print('🖼️ 현재 갤러리 권한 상태: $status');
      
      if (status == PermissionStatus.granted) {
        print('✅ 갤러리 권한 이미 허용됨');
        return true;
      }
      
      if (status == PermissionStatus.permanentlyDenied) {
        print('❌ 갤러리 권한 영구 거부됨');
        _showSettingsDialog(context, '갤러리');
        return false;
      }
      
      final result = await Permission.photos.request();
      print('🖼️ 갤러리 권한 요청 결과: $result');
      
      if (result == PermissionStatus.permanentlyDenied) {
        _showSettingsDialog(context, '갤러리');
        return false;
      }
      
      return result == PermissionStatus.granted;
      
    } catch (e) {
      print('❌ 갤러리 권한 요청 중 오류: $e');
      return false;
    }
  }

  /// 카메라 권한만 확인
  Future<bool> checkCameraPermission() async {
    final status = await Permission.camera.status;
    return status == PermissionStatus.granted;
  }

  /// 갤러리 권한만 확인
  Future<bool> checkGalleryPermission() async {
    final status = await Permission.photos.status;
    return status == PermissionStatus.granted;
  }

  /// 권한 상태 확인 (요청 없이)
  Future<Map<String, PermissionStatus>> checkPermissionStatus() async {
    return {
      'camera': await Permission.camera.status,
      'gallery': await Permission.photos.status,
    };
  }

  /// 설정 화면으로 안내하는 다이얼로그
  void _showSettingsDialog(BuildContext context, String permissionType) {
    if (!context.mounted) return;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('$permissionType 권한 필요'),
          content: Text(
            '$permissionType 권한이 거부되어 있습니다.\n'
            '설정 > 개인정보 보호 및 보안 > $permissionType에서 Pikabook 권한을 허용해주세요.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              child: Text('설정으로 이동'),
            ),
          ],
        );
      },
    );
  }
}