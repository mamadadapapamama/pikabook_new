#!/usr/bin/env python3
import os
import re
import glob

def fix_imports():
    """Flutter 프로젝트의 import 경로를 자동으로 수정합니다."""
    
    # 수정할 import 매핑 (잘못된 경로 -> 올바른 경로)
    import_mappings = {
        # Core models
        "../core/models/note.dart": "../../../core/models/note.dart",
        "../../models/note.dart": "../../../core/models/note.dart", 
        "../models/note.dart": "../../core/models/note.dart",
        
        "../core/models/page.dart": "../../../core/models/page.dart",
        "../../models/page.dart": "../../../core/models/page.dart",
        "../models/page.dart": "../../core/models/page.dart",
        
        "../core/models/flash_card.dart": "../../../core/models/flash_card.dart",
        "../../models/flash_card.dart": "../../../core/models/flash_card.dart",
        "../models/flash_card.dart": "../../core/models/flash_card.dart",
        
        "../core/models/dictionary.dart": "../../../core/models/dictionary.dart",
        "../../models/dictionary.dart": "../../../core/models/dictionary.dart",
        "../models/dictionary.dart": "../../core/models/dictionary.dart",
        
        "../core/models/processed_text.dart": "../../../core/models/processed_text.dart",
        "../../models/processed_text.dart": "../../../core/models/processed_text.dart",
        "../models/processed_text.dart": "../../core/models/processed_text.dart",
        
        "../core/models/processing_status.dart": "../../../core/models/processing_status.dart",
        "../../models/processing_status.dart": "../../../core/models/processing_status.dart",
        "../models/processing_status.dart": "../../core/models/processing_status.dart",
        
        "../core/models/text_unit.dart": "../../../core/models/text_unit.dart",
        "../../models/text_unit.dart": "../../../core/models/text_unit.dart",
        "../models/text_unit.dart": "../../core/models/text_unit.dart",
        
        # Theme tokens
        "../core/theme/tokens/color_tokens.dart": "../../../core/theme/tokens/color_tokens.dart",
        "../../core/theme/tokens/color_tokens.dart": "../../../core/theme/tokens/color_tokens.dart",
        "../theme/tokens/color_tokens.dart": "../../core/theme/tokens/color_tokens.dart",
        
        "../core/theme/tokens/typography_tokens.dart": "../../../core/theme/tokens/typography_tokens.dart",
        "../../core/theme/tokens/typography_tokens.dart": "../../../core/theme/tokens/typography_tokens.dart",
        "../theme/tokens/typography_tokens.dart": "../../core/theme/tokens/typography_tokens.dart",
        
        "../core/theme/tokens/spacing_tokens.dart": "../../../core/theme/tokens/spacing_tokens.dart",
        "../../core/theme/tokens/spacing_tokens.dart": "../../../core/theme/tokens/spacing_tokens.dart",
        "../theme/tokens/spacing_tokens.dart": "../../core/theme/tokens/spacing_tokens.dart",
        
        "../core/theme/tokens/ui_tokens.dart": "../../../core/theme/tokens/ui_tokens.dart",
        "../../core/theme/tokens/ui_tokens.dart": "../../../core/theme/tokens/ui_tokens.dart",
        "../theme/tokens/ui_tokens.dart": "../../core/theme/tokens/ui_tokens.dart",
        
        # Services - 더 정확한 매핑
        "../../core/services/media/image_service.dart": "../media/image_service.dart",
        "../../core/services/common/usage_limit_service.dart": "../common/usage_limit_service.dart",
        "../../core/services/text_processing/llm_text_processing.dart": "../text_processing/llm_text_processing.dart",
        
        "../core/services/content/note_service.dart": "../../../core/services/content/note_service.dart",
        "../../core/services/content/note_service.dart": "../../../core/services/content/note_service.dart",
        "../services/content/note_service.dart": "../../core/services/content/note_service.dart",
        
        "../core/services/content/page_service.dart": "../../../core/services/content/page_service.dart",
        "../../core/services/content/page_service.dart": "../../../core/services/content/page_service.dart",
        "../services/content/page_service.dart": "../../core/services/content/page_service.dart",
        
        "../core/services/media/image_service.dart": "../../../core/services/media/image_service.dart",
        "../../core/services/media/image_service.dart": "../../../core/services/media/image_service.dart",
        "../services/media/image_service.dart": "../../core/services/media/image_service.dart",
        "../media/image_service.dart": "../../core/services/media/image_service.dart",
        
        "../core/services/media/image_cache_service.dart": "../../../core/services/media/image_cache_service.dart",
        "../../core/services/media/image_cache_service.dart": "../../../core/services/media/image_cache_service.dart",
        "../services/media/image_cache_service.dart": "../../core/services/media/image_cache_service.dart",
        
        "../core/services/tts/tts_service.dart": "../../../core/services/tts/tts_service.dart",
        "../../core/services/tts/tts_service.dart": "../../../core/services/tts/tts_service.dart",
        "../services/tts/tts_service.dart": "../../core/services/tts/tts_service.dart",
        
        "../core/services/tts/tts_playback_service.dart": "../../../core/services/tts/tts_playback_service.dart",
        "../../core/services/tts/tts_playback_service.dart": "../../../core/services/tts/tts_playback_service.dart",
        "../services/tts/tts_playback_service.dart": "../../core/services/tts/tts_playback_service.dart",
        
        "../core/services/tts/tts_api_service.dart": "../../../core/services/tts/tts_api_service.dart",
        "../../core/services/tts/tts_api_service.dart": "../../../core/services/tts/tts_api_service.dart",
        "../services/tts/tts_api_service.dart": "../../core/services/tts/tts_api_service.dart",
        "../tts/tts_api_service.dart": "../../core/services/tts/tts_api_service.dart",
        
        "../core/services/dictionary/dictionary_service.dart": "../../../core/services/dictionary/dictionary_service.dart",
        "../../core/services/dictionary/dictionary_service.dart": "../../../core/services/dictionary/dictionary_service.dart",
        "../services/dictionary/dictionary_service.dart": "../../core/services/dictionary/dictionary_service.dart",
        
        "../core/services/dictionary/cc_cedict_service.dart": "../../../core/services/dictionary/cc_cedict_service.dart",
        "../../core/services/dictionary/cc_cedict_service.dart": "../../../core/services/dictionary/cc_cedict_service.dart",
        "../services/dictionary/cc_cedict_service.dart": "../../core/services/dictionary/cc_cedict_service.dart",
        
        "../core/services/text_processing/llm_text_processing.dart": "../../../core/services/text_processing/llm_text_processing.dart",
        "../../core/services/text_processing/llm_text_processing.dart": "../../../core/services/text_processing/llm_text_processing.dart",
        "../services/text_processing/llm_text_processing.dart": "../../core/services/text_processing/llm_text_processing.dart",
        "../text_processing/llm_text_processing.dart": "../../core/services/text_processing/llm_text_processing.dart",
        
        "../core/services/text_processing/ocr_service.dart": "../../../core/services/text_processing/ocr_service.dart",
        "../../core/services/text_processing/ocr_service.dart": "../../../core/services/text_processing/ocr_service.dart",
        "../services/text_processing/ocr_service.dart": "../../core/services/text_processing/ocr_service.dart",
        "../text_processing/ocr_service.dart": "../../core/services/text_processing/ocr_service.dart",
        
        "../core/services/common/usage_limit_service.dart": "../../../core/services/common/usage_limit_service.dart",
        "../../core/services/common/usage_limit_service.dart": "../../../core/services/common/usage_limit_service.dart",
        "../services/common/usage_limit_service.dart": "../../core/services/common/usage_limit_service.dart",
        "../common/usage_limit_service.dart": "../../core/services/common/usage_limit_service.dart",
        
        "../core/services/cache/note_cache_service.dart": "../../../core/services/cache/note_cache_service.dart",
        "../../core/services/cache/note_cache_service.dart": "../../../core/services/cache/note_cache_service.dart",
        "../services/cache/note_cache_service.dart": "../../core/services/cache/note_cache_service.dart",
        "../cache/note_cache_service.dart": "../../core/services/cache/note_cache_service.dart",
        
        # Widgets
        "../core/widgets/pika_button.dart": "../../../core/widgets/pika_button.dart",
        "../../core/widgets/pika_button.dart": "../../../core/widgets/pika_button.dart",
        "../widgets/pika_button.dart": "../../core/widgets/pika_button.dart",
        
        "../core/widgets/tts_button.dart": "../../../core/widgets/tts_button.dart",
        "../../core/widgets/tts_button.dart": "../../../core/widgets/tts_button.dart",
        "../widgets/tts_button.dart": "../../core/widgets/tts_button.dart",
        
        "../core/widgets/dot_loading_indicator.dart": "../../../core/widgets/dot_loading_indicator.dart",
        "../../core/widgets/dot_loading_indicator.dart": "../../../core/widgets/dot_loading_indicator.dart",
        "../widgets/dot_loading_indicator.dart": "../../core/widgets/dot_loading_indicator.dart",
        
        "../core/widgets/loading_dialog_experience.dart": "../../../core/widgets/loading_dialog_experience.dart",
        "../../core/widgets/loading_dialog_experience.dart": "../../../core/widgets/loading_dialog_experience.dart",
        "../widgets/loading_dialog_experience.dart": "../../core/widgets/loading_dialog_experience.dart",
        
        # Utils
        "../core/utils/date_formatter.dart": "../../../core/utils/date_formatter.dart",
        "../../core/utils/date_formatter.dart": "../../../core/utils/date_formatter.dart",
        "../utils/date_formatter.dart": "../../core/utils/date_formatter.dart",
        
        "../core/utils/context_menu_manager.dart": "../../../core/utils/context_menu_manager.dart",
        "../../core/utils/context_menu_manager.dart": "../../../core/utils/context_menu_manager.dart",
        "../utils/context_menu_manager.dart": "../../core/utils/context_menu_manager.dart",
        
        "../core/utils/segment_utils.dart": "../../../core/utils/segment_utils.dart",
        "../../core/utils/segment_utils.dart": "../../../core/utils/segment_utils.dart",
        "../utils/segment_utils.dart": "../../core/utils/segment_utils.dart",
        
        # Managers
        "../core/managers/note_creation_ui_manager.dart": "../../../core/managers/note_creation_ui_manager.dart",
        "../../core/managers/note_creation_ui_manager.dart": "../../../core/managers/note_creation_ui_manager.dart",
        "../managers/note_creation_ui_manager.dart": "../../core/managers/note_creation_ui_manager.dart",
        
        # Feature specific paths
        "../../widgets/flashcard_counter_badge.dart": "../flashcard/flashcard_counter_badge.dart",
        "../widgets/flashcard_counter_badge.dart": "../flashcard/flashcard_counter_badge.dart",
        "flashcard_counter_badge.dart": "../flashcard/flashcard_counter_badge.dart",
        
        "../../widgets/note_list_item.dart": "../home/note_list_item.dart",
        "../widgets/note_list_item.dart": "../home/note_list_item.dart",
        "note_list_item.dart": "../home/note_list_item.dart",
        
        "../../../widgets/edit_title_dialog.dart": "../../../core/widgets/edit_title_dialog.dart",
        "../../widgets/edit_title_dialog.dart": "../../core/widgets/edit_title_dialog.dart",
        "../widgets/edit_title_dialog.dart": "../../core/widgets/edit_title_dialog.dart",
        
        "../../../widgets/delete_note_dialog.dart": "../../../core/widgets/delete_note_dialog.dart",
        "../../widgets/delete_note_dialog.dart": "../../core/widgets/delete_note_dialog.dart",
        "../widgets/delete_note_dialog.dart": "../../core/widgets/delete_note_dialog.dart",
        
        "../../../widgets/note_action_bottom_sheet.dart": "../view/note_action_bottom_sheet.dart",
        "../../widgets/note_action_bottom_sheet.dart": "../view/note_action_bottom_sheet.dart",
        "../widgets/note_action_bottom_sheet.dart": "../view/note_action_bottom_sheet.dart",
        
        "../../widgets/note_progress_bar.dart": "../view/note_progress_bar.dart",
        "../widgets/note_progress_bar.dart": "../view/note_progress_bar.dart",
        
        "../../widgets/page_indicator.dart": "../view/page_indicator.dart",
        "../widgets/page_indicator.dart": "../view/page_indicator.dart",
        
        "../../widgets/page_navigation_button.dart": "../view/page_navigation_button.dart",
        "../widgets/page_navigation_button.dart": "../view/page_navigation_button.dart",
        
        "../../widgets/tts_play_all_button.dart": "../tts/tts_play_all_button.dart",
        "../widgets/tts_play_all_button.dart": "../tts/tts_play_all_button.dart",
        
        # Screen paths
        "../features/flashcard/flashcard_screen.dart": "../flashcard/flashcard_screen.dart",
        "../../features/flashcard/flashcard_screen.dart": "../flashcard/flashcard_screen.dart",
        
        "../features/sample/sample_flashcard_screen.dart": "../sample/sample_flashcard_screen.dart",
        "../../features/sample/sample_flashcard_screen.dart": "../sample/sample_flashcard_screen.dart",
        
        "../../views/screens/full_image_screen.dart": "../../../views/screens/full_image_screen.dart",
        "../views/screens/full_image_screen.dart": "../../views/screens/full_image_screen.dart",
        
        # ViewModel paths
        "../features/flashcard/flashcard_view_model.dart": "../flashcard/flashcard_view_model.dart",
        "../../features/flashcard/flashcard_view_model.dart": "../flashcard/flashcard_view_model.dart",
        
        "../../features/flashcard/flashcard_view_model.dart": "../flashcard/flashcard_view_model.dart",
        "../../../features/flashcard/flashcard_view_model.dart": "../flashcard/flashcard_view_model.dart",
        
        # App specific paths
        "widgets/loading_screen.dart": "views/screens/loading_screen.dart",
    }
    
    # lib 폴더의 모든 .dart 파일 찾기
    dart_files = glob.glob("lib/**/*.dart", recursive=True)
    
    total_files = len(dart_files)
    modified_files = 0
    
    print(f"총 {total_files}개의 Dart 파일을 검사합니다...")
    
    for file_path in dart_files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            original_content = content
            
            # import 문 수정
            for old_path, new_path in import_mappings.items():
                # import 'old_path' 패턴 찾기
                pattern = f"import\\s+['\"]({re.escape(old_path)})['\"]"
                replacement = f"import '{new_path}'"
                content = re.sub(pattern, replacement, content)
                
                # export 'old_path' 패턴도 찾기
                pattern = f"export\\s+['\"]({re.escape(old_path)})['\"]"
                replacement = f"export '{new_path}'"
                content = re.sub(pattern, replacement, content)
            
            # 내용이 변경되었으면 파일 저장
            if content != original_content:
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                modified_files += 1
                print(f"✅ 수정됨: {file_path}")
        
        except Exception as e:
            print(f"❌ 오류 ({file_path}): {e}")
    
    print(f"\n완료! {modified_files}/{total_files} 파일이 수정되었습니다.")

if __name__ == "__main__":
    fix_imports() 