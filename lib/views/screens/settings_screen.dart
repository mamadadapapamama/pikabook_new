import 'package:flutter/material.dart';
import '../../models/text_processing_mode.dart';
import '../../services/user_preferences_service.dart';
import '../../services/chinese_segmenter_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final UserPreferencesService _preferencesService = UserPreferencesService();
  TextProcessingMode _textProcessingMode = TextProcessingMode.languageLearning;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final mode = await _preferencesService.getTextProcessingMode();

      if (mounted) {
        setState(() {
          _textProcessingMode = mode;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('설정을 불러오는 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

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
        title: const Text('설정'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // 텍스트 처리 모드 설정
                _buildSettingSection(
                  title: '텍스트 처리 모드',
                  children: [
                    ListTile(
                      title: const Text('텍스트 처리 모드'),
                      subtitle: Text(
                        _textProcessingMode ==
                                TextProcessingMode.professionalReading
                            ? '전문 서적 모드 (전체 텍스트 번역)'
                            : '언어 학습 모드 (문장별 번역 및 핀인)',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _showTextProcessingModeDialog,
                    ),
                  ],
                ),

                // 중국어 처리 설정
                _buildSettingSection(
                  title: '중국어 처리 설정',
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
                  ],
                ),

                // 앱 정보 섹션
                _buildSettingSection(
                  title: '앱 정보',
                  children: [
                    ListTile(
                      title: const Text('버전'),
                      subtitle: const Text('1.0.0'),
                    ),
                    ListTile(
                      title: const Text('개발자'),
                      subtitle: const Text('Pikabook Team'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildSettingSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  void _showTextProcessingModeDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('텍스트 처리 모드 선택'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<TextProcessingMode>(
                title: const Text('전문 서적 모드'),
                subtitle: const Text('전체 텍스트 번역 제공'),
                value: TextProcessingMode.professionalReading,
                groupValue: _textProcessingMode,
                onChanged: (value) {
                  Navigator.pop(context);
                  if (value != null) {
                    _changeTextProcessingMode(value);
                  }
                },
              ),
              RadioListTile<TextProcessingMode>(
                title: const Text('언어 학습 모드'),
                subtitle: const Text('문장별 번역 및 핀인 제공'),
                value: TextProcessingMode.languageLearning,
                groupValue: _textProcessingMode,
                onChanged: (value) {
                  Navigator.pop(context);
                  if (value != null) {
                    _changeTextProcessingMode(value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _changeTextProcessingMode(TextProcessingMode mode) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _preferencesService.setDefaultTextProcessingMode(mode);

      if (mounted) {
        setState(() {
          _textProcessingMode = mode;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('텍스트 처리 모드가 변경되었습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('설정을 저장하는 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
}
