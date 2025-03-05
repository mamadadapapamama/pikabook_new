import 'package:flutter/material.dart';
import '../../services/dictionary_service.dart';
import '../../services/tts_service.dart';

class DictionaryPopup extends StatelessWidget {
  final String word;
  final VoidCallback? onClose;
  final bool showAddToFlashcardButton;
  final Function(String, String, String)? onAddToFlashcard;

  const DictionaryPopup({
    Key? key,
    required this.word,
    this.onClose,
    this.showAddToFlashcardButton = true,
    this.onAddToFlashcard,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dictionaryService = DictionaryService();
    final entry = dictionaryService.lookupWord(word);
    final ttsService = TTSService();

    if (entry == null) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    word,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('사전에서 찾을 수 없는 단어입니다.'),
              if (showAddToFlashcardButton && onAddToFlashcard != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ElevatedButton(
                    onPressed: () => onAddToFlashcard!(word, '', '직접 의미 입력 필요'),
                    child: const Text('플래시카드에 추가'),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  entry.word,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  entry.pinyin,
                  style: const TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: Colors.blue,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up, size: 20),
                  onPressed: () => ttsService.speak(entry.word),
                ),
              ],
            ),
            const Divider(),
            const Text(
              '의미:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                entry.meaning,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            if (entry.examples.isNotEmpty) ...[
              const Text(
                '예문:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              ...entry.examples.map((example) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(example),
                  )),
            ],
            if (showAddToFlashcardButton && onAddToFlashcard != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: ElevatedButton(
                    onPressed: () => onAddToFlashcard!(
                      entry.word,
                      entry.pinyin,
                      entry.meaning,
                    ),
                    child: const Text('플래시카드에 추가'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
