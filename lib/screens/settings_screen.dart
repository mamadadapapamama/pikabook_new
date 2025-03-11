import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/chinese_segmenter_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 설정 저장 함수
  Future<void> _saveSettings(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      print('설정 저장 중 오류 발생: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('설정'),
      ),
      body: ListView(
        children: [
          // 세그멘테이션 기능 활성화/비활성화 옵션
          SwitchListTile(
            title: Text('중국어 단어 구분 기능'),
            subtitle: Text('중국어 텍스트를 단어 단위로 구분합니다 (MVP에서는 비활성화 권장)'),
            value: ChineseSegmenterService.isSegmentationEnabled,
            onChanged: (bool value) {
              setState(() {
                ChineseSegmenterService.isSegmentationEnabled = value;
                _saveSettings('segmentation_enabled', value);
              });
            },
          ),

          Divider(),

          // 기타 설정 옵션들...
        ],
      ),
    );
  }
}
