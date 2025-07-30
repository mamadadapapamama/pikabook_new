# 📖 Pikabook - Chinese Language Learning App
A smart learning app for book based Chinese learners!

## 🔮 Main features
- **Image Translation**: OCR + Translation for text in Chinese books.
- **Study View**: Display text in sentence-by-sentence format for easier learning.
- **TTS**: Audio pronunciation with pinyin support for Chinese.
- **Flashcards**: Highlight frequently missed words for focused repetition.
- **Dictionary**: Word meanings, pinyin, and TTS for selected words.
- **Save & Manage Notes**: Save translated content as notes and review at any time.

## 🤹🏼 Managing github branch
We are following simplified Git Flow.

```bash
main (production)
├── dev (development)
│   ├── features/new_feature_1
│   └── features/new_feature_2
├── backup/test_subscription
└── backup/main_beforeLLM
```

- main: Production-ready code
- dev: Development branch
- backup: Backup branch
- Feature branches: dev/feature/feature-name

## 📐 Commit convention
Use the following format for commit messages:
type: brief description

```bash
Examples:
- feat: add login functionality
- fix: resolve button click bug
- docs: update README file
- refactor: clean up authentication code
```

**Commit Types**
- `feat`: New feature
- `fix` : Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring

## 👑 Essential Rules

**1. Branch Protection**
No direct push to main branch.
All changes must go through Pull Requests

**2. Pull Request Rules**
PR title must follow commit convention
Requires approval from team member before merge
Merge only after code review

**3. Code Formatting**
Use consistent code formatting (Prettier/ESLint)
Maintain unified code style across the project




