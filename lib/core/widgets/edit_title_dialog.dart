import 'package:flutter/material.dart';
import 'edit_dialog.dart';

/// @deprecated 이 파일은 더 이상 사용되지 않습니다. 
/// 대신 edit_dialog.dart의 EditDialog를 사용하세요.
/// 
/// 기존 코드 호환성을 위해 유지되고 있습니다.

@deprecated
class EditTextDialog extends StatelessWidget {
  final String title;
  final String currentValue;
  final String labelText;
  final String hintText;
  final String? helperText;
  final int maxLength;
  final Function(String) onValueUpdated;

  const EditTextDialog({
    Key? key,
    required this.title,
    required this.currentValue,
    required this.labelText,
    required this.hintText,
    this.helperText,
    this.maxLength = 50,
    required this.onValueUpdated,
  }) : super(key: key);

  /// 노트 제목 편집용 팩토리 생성자
  factory EditTextDialog.forNoteTitle({
    required String currentTitle,
    required Function(String) onTitleUpdated,
  }) {
    return EditTextDialog(
      title: '노트 제목 변경',
      currentValue: currentTitle,
      labelText: '제목',
      hintText: '노트 내용을 잘 나타내는 제목을 입력하세요',
      maxLength: 50,
      onValueUpdated: onTitleUpdated,
    );
  }

  /// 노트스페이스 이름 편집용 팩토리 생성자
  factory EditTextDialog.forNoteSpace({
    required String currentName,
    required Function(String) onNameUpdated,
  }) {
    return EditTextDialog(
      title: '노트스페이스 이름 변경',
      currentValue: currentName,
      labelText: '이름',
      hintText: '새로운 노트스페이스 이름을 입력하세요',
      maxLength: 30,
      onValueUpdated: onNameUpdated,
    );
  }

  @override
  Widget build(BuildContext context) {
    return EditDialog(
      title: title,
      currentValue: currentValue,
      labelText: labelText,
      hintText: hintText,
      helperText: helperText,
      maxLength: maxLength,
      onValueUpdated: onValueUpdated,
    );
  }
}

/// 기존 코드 호환성을 위한 deprecated 클래스
@deprecated
class EditTitleDialog extends StatelessWidget {
  final String currentTitle;
  final Function(String) onTitleUpdated;

  const EditTitleDialog({
    Key? key,
    required this.currentTitle,
    required this.onTitleUpdated,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return EditDialog.forNoteTitle(
      currentTitle: currentTitle,
      onTitleUpdated: onTitleUpdated,
    );
  }
}
