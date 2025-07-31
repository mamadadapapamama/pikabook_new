# pikabook requirements (Updated)

### Pikabook will make book-based language learning smarter through image recognition and AI technology.

## **Target users**

1. 제 2 언어 공부를 도와줘야 하는 학부모 (e.g. 중국어를 모르는 엄마가 아이의 중국어 학습을 봐줘야 함)
2. 제 2언어 공부를 원서 교재로 독학하는 사람

(not for MVP) 원서 교재로 독학하는 사람 (e.g. 경제학 학생이 원서로 책을 읽는 사람)

## **Main features**

- Image translation: Google lens 와 같이 사진별 번역을 제공해 유저가 교재 내용 이해할수 있게
- Study view: Extracted 된 텍스트를 학습하기 좋게 문장별 제공
- TTS: TTS (audio)(중국어의 경우, 병음도 제공) 제공을 통해 학습 도움
- Flashcard: 자주 틀리는 단어는 따로 highlight 해서 반복학습을 따로 하기 편하게 하는 경험 제공
- Dictionary: 선택된 원문 단어의 뜻, pin yin, TTS 제공
- Toggle : 목적에 따라 뷰를 전환 (원문만, 원문+번역, 번역만)
- Save and manage note: Translated 된 이미지들은 노트와 페이지로 저장, 유저는 언제든 돌아와 학습 가능.
- Note: MVP는 중국어-한국어/영어 번역으로 시작. 향후 다양한 언어 support

## **Subscription & Usage System**

### **Current Plan Structure**
- **Free Plan**: OCR 30페이지/월, TTS 50회/월
- **Premium Plan**: OCR 300페이지/월, TTS 1000회/월
- **Upgrade System**: 수동 업그레이드 요청 (Firestore 기반)

### **Usage Tracking**
- OCR 페이지 업로드 횟수
- TTS 요청 횟수
- 번역된 문자 수
- 저장소 사용량

### **Upgrade Process**
1. 사용량 한도 도달 시 자동 알림
2. "사용량 추가 요청하기" 버튼 클릭
3. 인앱 폼에서 요청 사항 작성
4. Firestore에 요청 저장
5. 관리자가 수동으로 플랜 업그레이드

## **Onboarding System**

### **3-Step Onboarding Process**
1. **Step 1**: 제품 소개 및 스플래시 이미지
2. **Step 2**: 사용자 이름 입력
3. **Step 3**: 학습 목적 선택
   - 직접 원서를 공부하는데 사용
   - 아이의 중국어 학습 보조
   - 기타

### **Welcome Modal**
- 온보딩 완료 후 신규 사용자 대상
- 무료 사용량 안내 (30페이지, 50회 TTS)
- Feature Flag로 제어 가능

## **Enhanced Flashcard System**

### **Advanced Features**
- **Dictionary Integration**: 내부 사전 및 CC-CEDICT 연동
- **TTS Support**: 플래시카드 단어 발음 제공
- **Review Statistics**: 복습 횟수 및 마지막 복습 시간 추적
- **Cache System**: 성능 최적화를 위한 캐시 관리
- **Smart Creation**: 단어 선택 시 자동으로 사전 정보 추가

### **Flashcard Management**
- 노트별 플래시카드 그룹화
- 카드 삭제 및 수정 기능
- 복습 통계 추적
- 사전 연동으로 정확한 병음 및 뜻 제공

## **Tutorial System**

### **First Note Tutorial**
- 첫 번째 노트 생성 후 자동 표시
- 3단계 튜토리얼:
  1. 단어 검색 방법 (길게 눌러 선택)
  2. 플래시카드 생성 방법
  3. TTS 사용법 (느린 속도 포함)

### **Tutorial Features**
- 사용자별 튜토리얼 완료 상태 저장
- 첫 번째 노트 생성 시점 감지
- 한 번만 표시되는 원타임 튜토리얼

## Techstack

- Flutter - 우선 ios 개발 먼저
- For OCR, Translation, TTS, dictionary
    - 정확한 번역과 text detection 이 중요
    - for MVP : google clound apis (Google vision api, cloud translation api, Text-to-Speech api)
    - 내부 사전 시스템: DictionaryService, CcCedictService
    - Auth method: Service Account
- For pin yin
    - [https://pub.dev/packages/pinyin](https://pub.dev/packages/pinyin)
- Data storage
    - image: save in local storage
    - image optimization: to reduce the file size
    - other data (user, note space, note, page, flashcard) : firebase
    - use cache to save api cost
    - usage tracking: Firestore 기반 실시간 사용량 추적

## [Data structrure](https://www.figma.com/design/YNjYqD2qc9e5pRcKHLM5DB/Lingowith-UI?node-id=48-3370&t=K3pEfsuiaeyRCxXj-1)

![image.png](pikabook%20requirements%201aa1a8f8717f801bbf60f56ea576a220/image.png)

| type | description |
| --- | --- |
| User | Individual user. We need to collect name, language they are learning, language to translate, usage statistics, subscription state |
| Note space | A user can create multiple note space. A note space can be used per language, or per books they are studying. |
| Note | Storage for one or multiple images(pages). Usecase: if the user is studying a book, one chapter could be a note. |
| Page | One image. 유저가 저장하는 이미지 단위. 이 이미지 단위로 텍스트 추출. 보통 교재의 한 페이지를 찍을 것이라 예상 |
| Note card | 노트의 리스트. homescreen 에서 note 로 이동할수 있게 하는 카드. |
| Flashcard | page 에서 추출한 원문 text 단어를 highlight 하면 flashcard 로 저장됨. 사전 연동으로 정확한 병음 및 뜻 제공. |
| Flashcard counter | Flashcard의 전체 count는 "Note" 단위. Note_card에서 Flashcard_counter 가 보여짐 |
| Usage | 사용량 추적 데이터 (OCR 페이지, TTS 요청, 번역 문자 수, 저장소 사용량) |
| Subscription State | 구독 상태 관리 (free/premium, 사용량 한도, 만료일 등) |

## [User flow](https://www.figma.com/board/EcgaRkLLWKGKRtFGjZvnF2/Lingowith?node-id=39-1481&t=j3ypUD7Pn2ExmC6n-4)

![image.png](pikabook%20requirements%201aa1a8f8717f801bbf60f56ea576a220/image%201.png)

## User stories

Stories sorted by the priority order

**Top priority**

- **As a user, I can complete onboarding**
    - 3단계 온보딩 프로세스 완료
    - 사용자 이름, 학습 목적 설정
    - 온보딩 완료 후 환영 모달 표시
    - 기본 사용량 안내 (30페이지, 50회 TTS)

- **As a user, I can create my note**
    
    ![image.png](pikabook%20requirements%201aa1a8f8717f801bbf60f56ea576a220/image%202.png)
    
    - On home screen, users can create their note
    - 노트가 생성되면, 해당 노트 스페이스에 저장됨. MVP 에는 한개의 노트 스페이스만 제공
    - **Flow**
        - user taps on create new note button on home screen
        - 2 options given: select image(s) from gallery or take photo
        - 이미지를 새로 찍거나 선택하면, 노트가 바로 생성됨
        - User will be nativated to the note_detail page
    - 개별 이미지는 extracted text, translated text, tts 의 데이터를 갖는 'page'로 저장됨
    - 유저가 여러개의 이미지를 선택하면 한개의 노트 안엔 여러 개의 이미지 (page)가 만들어질 수 있음.
    - 첫 번째 노트 생성 시 튜토리얼 자동 표시

- **As a user, I can access my note**
    
    
    ![image.png](pikabook%20requirements%201aa1a8f8717f801bbf60f56ea576a220/image%203.png)
    
    - On homescreen, users can view the list of note card
    - note card is the summary of note
    - note card contains:
        - image thumbnail: if user adds multiple images, it will be the first image
        - no of pages
        - date created
        - name of the note: upon note creation, automatically assigned (format: #[1] note)
        - flashcard counter: if there are flashcards made in the note
    - by tapping on note card, users can access to their note (note_detail)

- **As a user, I can view the note (note_detail)**
    - 
    
    ![image.png](pikabook%20requirements%201aa1a8f8717f801bbf60f56ea576a220/image%204.png)
    
    - if the user taps on note card on home screen, they would access to note (note_detail)
    - because note could contain multiple pages, we have a screen template (note_detail)
    - note detail contains app bar, body, bottom bar
        - app bar
            - back button
            - name of the note
            - page locator (x / xx pages)
            - flashcard counter (will navigate to flashcard page)
            - pagination bar
        - body (page)
            - the main part of this app
            - 1 image in the note
            - extracted text ( per sentence)
            - translated text ( per sentence)
            - TTS ( per sentence)
            - [context menu](https://www.notion.so/pikabook-requirements-1aa1a8f8717f801bbf60f56ea576a220?pvs=21) (refer to "create flash card" story)
        - bottom bar
            - page navigator (back and forward)
            - toggle button set : change view of the page
                - show translation only
                - show extracted text only
                - show both
                
- **As a user, I can create flash card for repetitive studying**
    - When user selects some of the extracted text, context menu will appear
        - highlight (this is flash card creator)
            - save to the flash card, update flashcard counter
            - once saved to the flashcard, it will be marked highlighted in the page
            - 자동으로 사전 정보 (병음, 뜻) 추가
    - When user creates new flash card, the flash card counter will be reflected
    - 사전 연동으로 정확한 병음 및 뜻 제공

- **As a user, I can view the flash card**
    
    ![image.png](pikabook%20requirements%201aa1a8f8717f801bbf60f56ea576a220/image%205.png)
    
    - app bar
        - back button: navigate back to where they were
        - pagination: #/xx cards
    - body
        - flash card
            - front
                - highlighted text (chinese)
                - TTS
                - pin yin
            - back
                - translation
        - navigating between cards
            - arrow buttons
        - 복습 통계 표시 (복습 횟수, 마지막 복습 시간)

- **As a user, I can manage my notes (edit, delete)**
    - from the note card 'more' button on home screen, user can edit or delete note
    - edit: user can change the name of the note.
        - Users can save or cancel
    - delete: user can delete the note
        - once selected, confirmation dialog will pop up
        - if user agrees to delete, it will be permenantly deleted
        
- **As a user, I can track my usage and upgrade when needed**
    - 실시간 사용량 표시 (OCR 페이지, TTS 요청)
    - 사용량 한도 도달 시 자동 알림
    - "사용량 추가 요청하기" 버튼으로 업그레이드 요청
    - 인앱 폼에서 요청 사항 작성 및 제출

**2nd priority**

- As a user, I can use gesture to navigate between flash cards
    - swipe left: move to the previous card
    - swipe right: move to the next card
    - tap: flip to other side (front to back: flip right, back to front: flip left)
- As a user, I can manage the flash cards
    - if the user doesn't need to study the word on card any more, they can remove from the flash card
    - on the front of the card, there is a delete button
    - gesture: swipe up
    - update the flash card counter
- As a user, I can view full size image
    - on note detail screen, on each image, user has 'expand' option
    - it will navigate to full page image view
    - user should be able to navigate back to the page view

**3rd priority**

- As a user, I can edit the wrongly extracted text
    - on note detail screen, on each image, user has 'edit' option
    - on modal dialog, the entire extracted text will be appear
    - user can delete, edit the text
    - user can save or cancel
    - once edited, translation needs to be updated
    - if that includes flashcard, it will be also updated
- as a user, I can check the dictionary for selected words
    - offered in context menu in the page
    - show
        - pin yin
        - TTS
        - translation
        - option to save to flashcard
- As a user, I could onboard to pikabook app
    
    Pikabook user can start their journey, set up the app for their purpose.
    after step 2, they can go back to previous step and edit their answer.
    
    - Step 1
        - One liner of the product explanation and product splash image.
        - Include Next button
    - Step 2
        - Ask user's name.
        - Next button
    - Step 3
        - Ask user's learning purpose (options: own language learning, helping child, or learning other subject in different language)
        - Next/ back button
    - Welcome Modal
        - Show welcome message and usage limits
        - Include Start button

- As a user, I am aided to create my first note
    - This is about the first time experience of the homescreen
    - When there are no note card(note) available, show 'Create new note' icon
    - story tell the feature
    - aid users to tap on create new note button
    - 첫 번째 노트 생성 후 튜토리얼 자동 표시

**Beyond MVP**

- As a user, I can change the setting of flash card
    - front/ back 을 korean front/ chinse back 으로…
- As a user, I can view my usage statistics
    - 월별 사용량 통계
    - 사용량 한도 대비 진행률
    - 사용 패턴 분석
- As a user, I can manage my subscription
    - 현재 플랜 상태 확인
    - 사용량 추가 요청 히스토리
    - 플랜 변경 요청