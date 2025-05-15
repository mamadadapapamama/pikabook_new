import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 샘플 모드 상태를 관리하는 서비스
class SampleModeService {
  static const String _sampleModeKey = 'sample_mode_enabled';
  
  /// 싱글톤 패턴 적용
  static final SampleModeService _instance = SampleModeService._internal();
  
  factory SampleModeService() {
    return _instance;
  }
  
  SampleModeService._internal();
  
  /// 샘플 모드 상태를 로드합니다
  Future<bool> isSampleModeEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_sampleModeKey) ?? false;
    } catch (e) {
      debugPrint('샘플 모드 상태 로드 오류: $e');
      return false;
    }
  }
  
  /// 샘플 모드 상태를 저장합니다
  Future<void> setSampleModeEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sampleModeKey, enabled);
    } catch (e) {
      debugPrint('샘플 모드 상태 저장 오류: $e');
    }
  }
  
  /// 샘플 모드를 활성화합니다
  Future<void> enableSampleMode() async {
    await setSampleModeEnabled(true);
  }
  
  /// 샘플 모드를 비활성화합니다 (로그인 성공 시 호출)
  Future<void> disableSampleMode() async {
    await setSampleModeEnabled(false);
  }
} 