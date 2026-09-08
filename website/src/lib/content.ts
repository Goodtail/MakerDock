export const locales = ["en", "ko", "ja", "zh-CN"] as const;
export type Locale = (typeof locales)[number];
export const localeNames: Record<Locale, string> = { en: "English", ko: "한국어", ja: "日本語", "zh-CN": "简体中文" };
export const localePath = (locale: Locale) => locale === "en" ? "/" : "/" + locale;
export const assetLocale = (locale: Locale) => locale === "zh-CN" ? "zh-Hans" : locale;
export function isLocale(value: string): value is Locale { return locales.includes(value as Locale); }
export const siteUrl = "https://makerdock.goodtail.app";
export const sourceUrl = "https://github.com/Goodtail/MakerDock";
export const downloadUrl = sourceUrl + "/releases/download/v0.1.0/MakerDock-0.1.0-universal.dmg";

export type Copy = {
  title: string; description: string; skip: string;
  nav: { tour: string; faq: string; download: string; source: string; language: string; theme: string; light: string; dark: string; system: string };
  hero: { line1: string; line2: string; body: string; alt: string; caption: string; enlarge: string };
  intro: { title: string; items: { title: string; body: string }[] };
  tour: { title: string; body: string; label: string; enlarge: string; close: string; demo: string; tabs: { id: "plates" | "print-record" | "selection"; label: string; title: string; body: string; detail: string; alt: string }[] };
  local: { label: string; title: string; body: string; items: { title: string; body: string }[] };
  faq: { title: string; items: { question: string; answer: string }[] };
  ending: { title: string; body: string; compatibility: string; release: string };
  footer: { by: string; privacy: string; license: string; disclaimer: string };
};

export const content: Record<Locale, Copy> = {
  en: {
    title: "MakerDock | A home for your 3D prints",
    description: "Find your 3MF files, preview every plate, and remember what you printed. A free, open-source 3D printing library for Mac.",
    skip: "Skip to content",
    nav: { tour: "Take a look", faq: "Questions", download: "Download for Mac", source: "View source", language: "Language", theme: "Appearance", light: "Light", dark: "Dark", system: "System" },
    hero: { line1: "Less file hunting.", line2: "More making.", body: "Your 3D files, plate previews, and print history. Together in one Mac app.", alt: "MakerDock library with six 3D models, print estimates, categories, and completed print indicators", caption: "A proper home for your 3MF files.", enlarge: "Enlarge the library screenshot" },
    intro: { title: "Downloaded it. Printed it.\nNow, where was it?", items: [
      { title: "Find the file you already have.", body: "Keep a visual library of your 3MF files. Identical imports are merged, while different print profiles stay separate." },
      { title: "See more than a filename.", body: "Browse model previews, plates, materials, and saved print estimates before opening your slicer." },
      { title: "Remember the finished print.", body: "Save the time, filament, and notes with the model. Pick up where you left off next time." },
    ] },
    tour: { title: "From saved file\nto finished print.", body: "The details you need, right beside your models.", label: "Explore MakerDock features", enlarge: "Enlarge screenshot", close: "Close screenshot", demo: "Real app screens with original demo models.", tabs: [
      { id: "plates", label: "See every plate", title: "The whole project, at a glance.", body: "Three plates or thirteen, see them together. Open a preview for a closer look, with saved time and material estimates beside it.", detail: "Saved MakerWorld estimates are shown first when available. Stored 3MF estimates fill in the gaps.", alt: "MakerDock displaying multiple plates and a large preview of a modular desk tray" },
      { id: "print-record", label: "Keep a print record", title: "A little note goes a long way.", body: "Mark a print complete and keep its duration, filament, and notes. The saved estimate is filled in, ready to accept or adjust.", detail: "Choose to move the file to your completed folder when you save the record.", alt: "Print record form with duration, filament weight, notes, and an option to move the completed file" },
      { id: "selection", label: "Tidy up in batches", title: "A growing collection. Still in order.", body: "Select several models to categorize, mark complete, or move to Trash together. Use favorites and tags to find them again.", detail: "Changed your mind? Restore models and their records from the in-app Trash.", alt: "Multiple 3D models selected in MakerDock with batch organization actions" },
    ] },
    local: { label: "Your files, on your Mac", title: "A library you can keep.", body: "No MakerDock account to set up. No library to upload. Just your files and the history you add to them.", items: [
      { title: "Made for your existing workflow", body: "Open an archived model as a working copy in the official Bambu Studio. Your saved original stays in your library." },
      { title: "Free, with the source included", body: "An independent Goodtail project, shared under the MIT license. Read the code, report an issue, or help make it better." },
    ] },
    faq: { title: "A few things to know.", items: [
      { question: "How does it work with MakerWorld?", answer: "Browse MakerWorld and open My Collections inside the app. Linked model and print-profile pages open there too. The public build uses normal website downloads; automatic download capture is disabled while we check permissions. You can import your downloaded 3MF files into the library." },
      { question: "Does it detect when my printer finishes?", answer: "You mark prints complete yourself. MakerDock saves the time, filament, and notes you confirm. It does not monitor live printer jobs or read actual AMS consumption." },
      { question: "Where do print estimates come from?", answer: "Saved MakerWorld profile information takes priority when linked to a file. MakerDock can also read estimates stored in a 3MF, or ask a compatible, separately installed Bambu Studio to slice for your printer. Unsliced files may have no estimate. Estimates are not measured print results." },
      { question: "Is a Chrome extension available?", answer: "A companion Chrome extension is planned to make the handoff from browser to library easier. It is not released yet. The Mac app is available now." },
      { question: "What stays on my Mac?", answer: "Your library files, categories, and print records are stored locally. MakerDock does not upload your library to its own server. If you browse MakerWorld, that website handles your visit under its own privacy policy." },
    ] },
    ending: { title: "Make room for your next print.", body: "Start with the files already on your Mac.", compatibility: "macOS 13 or later. Apple silicon and Intel.", release: "Release notes" },
    footer: { by: "Made by Goodtail", privacy: "Privacy", license: "MIT license", disclaimer: "An independent app. Not affiliated with or endorsed by Bambu Lab or MakerWorld." },
  },
  ko: {
    title: "MakerDock | 3D 출력 파일과 기록을 한곳에",
    description: "3MF 파일을 찾고, 모든 플레이트를 미리 보고, 출력한 모델을 기록하세요. Mac을 위한 무료 오픈소스 3D 프린팅 보관함.",
    skip: "본문으로 건너뛰기",
    nav: { tour: "기능 둘러보기", faq: "궁금한 점", download: "Mac용 다운로드", source: "소스 코드 보기", language: "언어", theme: "화면 모드", light: "라이트", dark: "다크", system: "시스템" },
    hero: { line1: "파일 찾는 시간은 줄이고.", line2: "만드는 즐거움은 더하고.", body: "3D 파일부터 플레이트 미리보기, 출력 기록까지. Mac 앱 하나에 모아두세요.", alt: "모델 6개와 예상 출력시간, 분류, 출력 완료 상태가 보이는 MakerDock 보관함", caption: "3MF 파일을 위한 나만의 보관함.", enlarge: "보관함 스크린샷 크게 보기" },
    intro: { title: "받아뒀는데. 출력도 했는데.\n그 파일, 어디 있더라?", items: [
      { title: "이미 받은 파일을 다시 찾아요.", body: "3MF 파일을 미리보기로 쉽게 찾아보세요. 같은 파일은 하나로 모으고, 다른 출력 프로필은 따로 보관합니다." },
      { title: "파일 이름만으로 짐작하지 마세요.", body: "슬라이서를 열기 전에 모델과 플레이트, 재료, 저장된 예상 출력시간을 확인할 수 있어요." },
      { title: "출력한 다음도 기억해요.", body: "걸린 시간과 사용한 필라멘트, 메모를 모델에 남겨두세요. 다음에 다시 만들 때 도움이 됩니다." },
    ] },
    tour: { title: "파일을 보관하는 순간부터\n출력을 마친 다음까지.", body: "필요한 정보를 모델 바로 옆에 모았습니다.", label: "MakerDock 기능 살펴보기", enlarge: "스크린샷 크게 보기", close: "스크린샷 닫기", demo: "직접 만든 데모 모델을 담은 실제 앱 화면입니다.", tabs: [
      { id: "plates", label: "플레이트 한눈에 보기", title: "여러 판이어도, 한눈에.", body: "세 판이든 열세 판이든 함께 확인하세요. 미리보기를 누르면 크게 볼 수 있고, 저장된 시간과 재료 예상치도 살펴볼 수 있어요.", detail: "저장된 MakerWorld 예상치가 있으면 먼저 보여주고, 없으면 3MF에 담긴 정보를 사용합니다.", alt: "여러 플레이트와 확대 미리보기를 보여주는 MakerDock" },
      { id: "print-record", label: "출력 기록 남기기", title: "다음 출력을 돕는 짧은 메모.", body: "출력 완료를 표시하면서 시간과 필라멘트, 메모를 남기세요. 예상 시간은 미리 채워두니 그대로 저장하거나 수정하면 됩니다.", detail: "기록을 저장할 때 파일을 출력 완료 폴더로 옮길 수도 있어요.", alt: "출력시간, 필라멘트 사용량, 메모와 완료 폴더 이동 옵션이 있는 기록 화면" },
      { id: "selection", label: "여러 모델 함께 정리", title: "파일이 늘어도, 정리는 가볍게.", body: "그리드에서 여러 모델을 골라 한 번에 분류하고, 완료 처리하거나 휴지통으로 옮기세요. 즐겨찾기와 태그로 다시 찾기도 쉬워져요.", detail: "잘못 지웠다면 앱 안의 휴지통에서 모델과 기록을 함께 복원하세요.", alt: "모델 여러 개를 선택해 일괄 정리하는 MakerDock 화면" },
    ] },
    local: { label: "내 파일은 내 Mac에", title: "오래 곁에 둘 보관함.", body: "MakerDock 계정을 만들거나 보관함을 업로드할 필요 없어요. 내 파일과 직접 남긴 기록을 Mac에 보관합니다.", items: [
      { title: "쓰던 방식 그대로 이어서", body: "보관한 모델을 공식 Bambu Studio에서 작업용 사본으로 열 수 있어요. 원본은 보관함에 그대로 남습니다." },
      { title: "무료로 쓰고, 코드도 열어보고", body: "Goodtail이 만드는 독립 앱입니다. MIT 라이선스로 공개한 코드를 살펴보고, 문제를 알려주거나 함께 개선할 수 있어요." },
    ] },
    faq: { title: "궁금할 만한 이야기.", items: [
      { question: "MakerWorld와 어떻게 연결되나요?", answer: "앱 안에서 MakerWorld를 둘러보고 내 컬렉션으로 이동할 수 있어요. 연결된 원본 모델과 출력 프로필 페이지도 앱 안에서 열립니다. 공개 버전은 웹사이트의 일반 다운로드를 사용하며, 자동 다운로드 수집은 허용 범위를 확인하는 동안 비활성화되어 있어요. 내려받은 3MF 파일은 보관함에 가져올 수 있습니다." },
      { question: "출력 완료를 자동으로 감지하나요?", answer: "출력 완료는 직접 표시합니다. 확인한 출력시간과 필라멘트, 메모를 기록하며, 프린터의 실시간 작업이나 실제 AMS 사용량을 자동으로 읽지는 않아요." },
      { question: "예상 출력시간은 어디서 가져오나요?", answer: "파일에 연결된 MakerWorld 프로필 정보가 저장되어 있으면 먼저 사용합니다. 3MF 안의 예상치를 읽거나, 별도로 설치한 호환 Bambu Studio로 내 프린터에 맞게 슬라이싱해 계산할 수도 있어요. 아직 슬라이싱하지 않은 파일에는 예상치가 없을 수 있고, 예상치는 실제 출력 결과와 다를 수 있습니다." },
      { question: "크롬 확장 프로그램도 있나요?", answer: "브라우저에서 보관함으로 파일을 더 쉽게 가져오기 위한 보조 크롬 확장 프로그램을 준비할 예정입니다. 아직 출시되지 않았으며, Mac 앱은 지금 사용할 수 있어요." },
      { question: "어떤 정보가 Mac에 저장되나요?", answer: "보관한 파일과 분류, 출력 기록은 Mac에 저장됩니다. MakerDock 자체 서버에 보관함을 업로드하지 않아요. 앱에서 MakerWorld를 방문하면 해당 웹사이트의 개인정보 처리방침이 적용됩니다." },
    ] },
    ending: { title: "다음 출력을 위한 자리.", body: "Mac에 받아둔 파일부터 모아보세요.", compatibility: "macOS 13 이상. Apple Silicon 및 Intel 지원.", release: "릴리스 노트" },
    footer: { by: "Goodtail이 만듭니다", privacy: "개인정보 처리방침", license: "MIT 라이선스", disclaimer: "독립적으로 개발한 앱이며 Bambu Lab 또는 MakerWorld의 공식·제휴 앱이 아닙니다." },
  },
  ja: {
    title: "MakerDock | 3Dプリントのファイルと記録をひとつに",
    description: "3MFファイルを探し、すべてのプレートを確認し、プリントの記録を残す。Mac向けの無料オープンソースアプリ。",
    skip: "本文へスキップ",
    nav: { tour: "機能を見る", faq: "よくある質問", download: "Mac版をダウンロード", source: "ソースコード", language: "言語", theme: "外観", light: "ライト", dark: "ダーク", system: "システム" },
    hero: { line1: "探す時間を減らして。", line2: "つくる時間を増やそう。", body: "3Dファイル、プレートのプレビュー、プリント履歴。Macのアプリひとつに、まとめて。", alt: "6つの3Dモデル、予想時間、カテゴリ、完了状態が並ぶMakerDockのライブラリ", caption: "3MFファイルに、いつもの置き場所を。", enlarge: "ライブラリの画像を拡大" },
    intro: { title: "保存した。プリントもした。\nあのファイル、どこだっけ？", items: [
      { title: "手元のファイルを、すぐ見つける。", body: "3MFファイルをプレビューで探せます。同じファイルはひとつにまとめ、異なるプリントプロファイルは別々に保存します。" },
      { title: "名前だけでは分からないことも。", body: "スライサーを開く前に、モデル、プレート、素材、保存済みの予想時間を確認できます。" },
      { title: "プリントした後も、忘れずに。", body: "かかった時間、使ったフィラメント、メモをモデルと一緒に保存。次に作るときの手がかりになります。" },
    ] },
    tour: { title: "ファイルの保存から、\nプリントの記録まで。", body: "必要な情報を、モデルのすぐそばに。", label: "MakerDockの機能を選択", enlarge: "画像を拡大", close: "画像を閉じる", demo: "オリジナルのデモモデルを使った実際のアプリ画面です。", tabs: [
      { id: "plates", label: "プレートを一覧で", title: "プロジェクト全体を、ひと目で。", body: "3枚でも13枚でも、プレートをまとめて確認。プレビューを拡大して、保存済みの時間や素材の見積もりも確認できます。", detail: "保存済みのMakerWorld予想値があれば優先し、なければ3MF内の情報を使います。", alt: "複数のプレートと拡大プレビューを表示したMakerDock" },
      { id: "print-record", label: "プリントを記録", title: "小さなメモが、次のヒントに。", body: "プリントを完了にして、時間、フィラメント、メモを保存。予想時間は入力済みなので、そのまま保存することも修正することもできます。", detail: "記録の保存時に、ファイルをプリント済みフォルダへ移動することもできます。", alt: "時間、フィラメント、メモ、フォルダへの移動を設定するプリント記録画面" },
      { id: "selection", label: "まとめて整理", title: "コレクションが増えても、すっきり。", body: "複数のモデルを選び、分類、完了の記録、ゴミ箱への移動をまとめて。お気に入りやタグで、後から探すのも簡単です。", detail: "間違えて消しても、アプリ内のゴミ箱からモデルと記録を一緒に戻せます。", alt: "複数のモデルを選択してまとめて整理するMakerDock" },
    ] },
    local: { label: "ファイルは、自分のMacに", title: "手元に残るライブラリ。", body: "MakerDockのアカウント作成も、ライブラリのアップロードも不要。ファイルと記録をMacに保存します。", items: [
      { title: "いつもの作業を、そのまま", body: "保存したモデルを作業用コピーとして公式Bambu Studioで開けます。元のファイルはライブラリに残ります。" },
      { title: "無料で使えて、コードも公開", body: "Goodtailが開発する独立したアプリです。MITライセンスで公開しているので、コードの確認、不具合の報告、開発への参加もできます。" },
    ] },
    faq: { title: "使い始める前に。", items: [
      { question: "MakerWorldとはどう連携しますか？", answer: "アプリ内でMakerWorldや自分のコレクションを閲覧できます。関連付けたモデルやプリントプロファイルのページもアプリ内で開きます。公開版では通常のダウンロードを使い、自動取り込みは許可範囲を確認する間、無効にしています。ダウンロードした3MFはライブラリに追加できます。" },
      { question: "プリントの完了を自動検出しますか？", answer: "完了は自分で記録します。確認した時間、フィラメント、メモを保存する仕組みです。プリンターの稼働状況や実際のAMS消費量は自動取得しません。" },
      { question: "予想時間はどこから取得しますか？", answer: "ファイルに保存されたMakerWorldプロファイル情報があれば優先します。3MF内の予想値を読み取るほか、別途インストールした対応版のBambu Studioで、自分のプリンターに合わせてスライス計算もできます。未スライスのファイルには予想値がない場合があり、実際の結果とは異なることがあります。" },
      { question: "Chrome拡張機能はありますか？", answer: "ブラウザーからライブラリへの取り込みを手助けするChrome拡張機能を予定しています。まだ公開されていません。Macアプリは今すぐ使えます。" },
      { question: "どの情報がMacに保存されますか？", answer: "ファイル、カテゴリ、プリント記録はMacに保存されます。MakerDockのサーバーにライブラリをアップロードすることはありません。MakerWorldを閲覧する場合は、そのサイトのプライバシーポリシーが適用されます。" },
    ] },
    ending: { title: "次のプリントに、備えよう。", body: "Macに保存したファイルから始めてみませんか。", compatibility: "macOS 13以降。Appleシリコン・Intel対応。", release: "リリースノート" },
    footer: { by: "Goodtailが開発", privacy: "プライバシー", license: "MITライセンス", disclaimer: "独立したアプリです。Bambu LabおよびMakerWorldの公式・提携アプリではありません。" },
  },
  "zh-CN": {
    title: "MakerDock | 收好3D打印文件，记下每次打印",
    description: "查找3MF文件，预览所有打印板，记录打印结果。适用于Mac的免费开源3D打印管理应用。",
    skip: "跳转到正文",
    nav: { tour: "看看功能", faq: "常见问题", download: "下载Mac版", source: "查看源码", language: "语言", theme: "外观", light: "浅色", dark: "深色", system: "跟随系统" },
    hero: { line1: "少一点翻找。", line2: "多一点创造。", body: "3D文件、打印板预览、打印记录。一个Mac应用，全都放好。", alt: "MakerDock模型库展示六个3D模型、预计时间、分类和完成状态", caption: "给3MF文件一个固定的家。", enlarge: "放大模型库截图" },
    intro: { title: "下载过，也打印过。\n那个文件放哪了？", items: [
      { title: "找回已经下载的文件。", body: "通过预览图查找3MF文件。完全相同的文件合并保存，不同的打印配置仍然单独保留。" },
      { title: "不用再靠文件名猜。", body: "打开切片软件之前，就能查看模型、打印板、材料和已保存的预计时间。" },
      { title: "打印完，也留个记录。", body: "把用时、耗材和备注随模型一起保存。下次再打印时，随时翻看。" },
    ] },
    tour: { title: "从保存文件，\n到记下打印结果。", body: "需要的信息，就在模型旁边。", label: "探索MakerDock功能", enlarge: "放大截图", close: "关闭截图", demo: "使用原创演示模型的真实应用截图。", tabs: [
      { id: "plates", label: "看清每块打印板", title: "整个项目，一眼看清。", body: "三板也好，十三板也好，都能一起查看。点击预览即可放大，还能查看已保存的时间和材料估算。", detail: "优先显示已保存的MakerWorld预计值，没有时则读取3MF内的信息。", alt: "展示多块打印板和放大预览的MakerDock" },
      { id: "print-record", label: "记下打印结果", title: "一条备注，下次就用得上。", body: "标记打印完成，记录用时、耗材和备注。预计时间已经填好，可以直接保存，也可以修改。", detail: "保存记录时，还可以将文件移至已完成文件夹。", alt: "包含打印用时、耗材重量、备注及文件移动选项的记录界面" },
      { id: "selection", label: "多个模型一起整理", title: "收藏多了，也能井井有条。", body: "多选模型，批量分类、标记完成或移至废纸篓。收藏和标签让下次查找更方便。", detail: "误删了？可以从应用内的废纸篓恢复模型和相关记录。", alt: "在MakerDock网格中多选模型并批量整理" },
    ] },
    local: { label: "你的文件，留在你的Mac", title: "一直留在手边的模型库。", body: "不用注册MakerDock账号，也不用上传模型库。文件和你添加的记录，都保存在Mac上。", items: [
      { title: "接着用你熟悉的工具", body: "在官方Bambu Studio中打开已归档模型的工作副本。原始文件仍保留在模型库中。" },
      { title: "免费使用，源码公开", body: "MakerDock是Goodtail独立开发的应用，采用MIT许可。你可以阅读代码、反馈问题，也可以参与改进。" },
    ] },
    faq: { title: "你可能想了解。", items: [
      { question: "如何与MakerWorld配合使用？", answer: "你可以在应用内浏览MakerWorld，进入我的收藏，也能打开已关联的原始模型和打印配置页面。公开版本使用网站的常规下载功能；在确认许可范围期间，自动捕获下载功能保持关闭。下载后的3MF文件可以导入模型库。" },
      { question: "能自动检测打印完成吗？", answer: "需要你手动标记完成。MakerDock保存你确认的打印时间、耗材和备注，不会自动监控实时打印任务或读取AMS的实际消耗量。" },
      { question: "预计时间从哪里来？", answer: "文件关联了已保存的MakerWorld配置时，会优先使用该信息。也能读取3MF中的预计值，或通过单独安装的兼容Bambu Studio，按你的打印机配置进行切片计算。未切片的文件可能没有预计值，估算也可能与实际打印结果不同。" },
      { question: "有Chrome扩展程序吗？", answer: "计划推出配套的Chrome扩展，让文件从浏览器进入模型库更方便。目前尚未发布，Mac应用已经可以使用。" },
      { question: "哪些信息保存在Mac上？", answer: "模型库文件、分类和打印记录都保存在本机。MakerDock不会将模型库上传到自己的服务器。如果在应用内访问MakerWorld，则适用该网站的隐私政策。" },
    ] },
    ending: { title: "为下一次打印，留好位置。", body: "从Mac上已经下载的文件开始。", compatibility: "支持macOS 13及以上、Apple芯片和Intel。", release: "发行说明" },
    footer: { by: "由Goodtail开发", privacy: "隐私政策", license: "MIT许可", disclaimer: "本应用独立开发，与Bambu Lab或MakerWorld无隶属或官方合作关系。" },
  },
};
