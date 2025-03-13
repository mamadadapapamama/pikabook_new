import 'package:flutter/material.dart';
import '../models/text_processing_mode.dart';

class NoteActionBottomSheet extends StatelessWidget {
  final VoidCallback onEditTitle;
  final VoidCallback onDeleteNote;
  final VoidCallback onShowTextProcessingModeDialog;
  final TextProcessingMode textProcessingMode;

  const NoteActionBottomSheet({
    Key? key,
    required this.onEditTitle,
    required this.onDeleteNote,
    required this.onShowTextProcessingModeDialog,
    required this.textProcessingMode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('노트 제목 변경'),
            onTap: () {
              Navigator.pop(context);
              onEditTitle();
            },
          ),
          // 텍스트 처리 모드 선택 옵션
          ListTile(
            leading: Icon(
              textProcessingMode == TextProcessingMode.professionalReading
                  ? Icons.menu_book
                  : Icons.school,
            ),
            title: const Text('텍스트 처리 모드'),
            subtitle: Text(
              textProcessingMode == TextProcessingMode.professionalReading
                  ? '전문 서적 모드 (전체 텍스트 번역)'
                  : '언어 학습 모드 (문장별 번역 및 핀인)',
            ),
            onTap: () {
              Navigator.pop(context);
              onShowTextProcessingModeDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete),
            title: const Text('노트 삭제'),
            onTap: () {
              Navigator.pop(context);
              onDeleteNote();
            },
          ),
        ],
      ),
    );
  }
}

class TextProcessingModeDialog extends StatelessWidget {
  final TextProcessingMode currentMode;
  final Function(TextProcessingMode) onModeChanged;

  const TextProcessingModeDialog({
    Key? key,
    required this.currentMode,
    required this.onModeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('텍스트 처리 모드 선택'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<TextProcessingMode>(
            title: const Text('전문 서적 모드'),
            subtitle: const Text('전체 텍스트 번역 제공'),
            value: TextProcessingMode.professionalReading,
            groupValue: currentMode,
            onChanged: (value) {
              Navigator.pop(context);
              if (value != null) {
                onModeChanged(value);
              }
            },
          ),
          RadioListTile<TextProcessingMode>(
            title: const Text('언어 학습 모드'),
            subtitle: const Text('문장별 번역 및 핀인 제공'),
            value: TextProcessingMode.languageLearning,
            groupValue: currentMode,
            onChanged: (value) {
              Navigator.pop(context);
              if (value != null) {
                onModeChanged(value);
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
  }
}
