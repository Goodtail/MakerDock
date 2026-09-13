import type { Locale } from './content';

type Guide = {
  label: string; title: string; description: string; back: string; eyebrow: string; free: string;
  browser: { label: string; title: string; body: string; items: string[]; shortcut: string };
  sections: { id: string; title: string; body: string[] }[];
};
export const guides: Record<Locale, Guide> = {
  en: {
    label: 'Getting started', title: 'From a downloaded 3MF to a finished print',
    description: 'How to organize 3MF files, save MakerWorld links, calculate print estimates, and record real print time with MakerDock for Mac.',
    back: 'Back to MakerDock', eyebrow: '3MF library & print planner for Mac', free: 'Free · Open source · No account',
    browser: { label: 'MakerWorld, inside MakerDock', title: 'Keep browsing.\nKeep what you find.', body: 'Your collection is a starting point. Open a few models in tabs, save the ones you want, and come back to the page you were reading.', items: ['Keep your place when switching between the library and the web.', 'Save the observed model link with downloads started in the app.', 'Open an archived copy in Studio, or request a fresh download.'], shortcut: 'Open a link in a new tab' },
    sections: [
      { id: 'library', title: '1. Bring your 3MF files together', body: ['Download the DMG, drag MakerDock into Applications, and open it on macOS 13 or later. Import 3MF files, drop them into the window, or choose folders to watch. The app keeps archived copies in its local library.', 'Byte-identical files are merged. Different print profiles remain separate. Categories, tags, favorites, and batch selection help organize the library; the in-app Trash lets you restore a model and its records.'] },
      { id: 'makerworld', title: '2. Save a model with its original page', body: ['Open MakerWorld from the sidebar, or sign in on the website to use My Collections. Command-click a link or use its right-click menu to open a new tab. Switching to the library and back keeps the current page; selecting the active sidebar destination again returns to its starting page.', 'A download or Studio handoff you start inside this browser retains the observed public model URL. Open the source button in model details to revisit it. If a page cannot be identified, attach its link manually. To bypass a saved download, use the fresh-download option. External browser handoffs are not part of the public release; the Chrome companion is planned.'] },
      { id: 'estimates', title: '3. Check plates and estimated time', body: ['Every saved plate preview is listed together. Click one to enlarge it. Saved MakerWorld estimates are used when present; 3MF metadata can provide stored estimates too. A 3MF without slicing results may not contain a duration.', 'Choose your printer profile and a compatible, separately installed official Bambu Studio in Settings. Adding a model with no estimate to the queue can then run a local slicing calculation and save the result across the library. Keep estimates distinct from measured results; printer, material, and quality settings affect them.'] },
      { id: 'queue', title: '4. Plan around the time you have', body: ['Add models to Print Queue, order them, and set a start time, available hours, and time between prints. MakerDock shows what fits. Mark a model as printing when you start it and correct its start time if needed.', 'The queue helps you plan; it does not send print commands. An optional local printer connection can read status and remaining time from a compatible device. Set its IP, serial number, and LAN access code, then explicitly link the live job to the queued model. Hardware and firmware support varies.'] },
      { id: 'records', title: '5. Record the result, not just the estimate', body: ['For a started print, the completion form calculates duration from its editable start and end times, including pauses. Without a recorded start, the saved estimate can prefill the duration. Check the result before saving.', 'Add the filament, grams, and notes you want to remember. Connected printer reports can suggest observed filament type and color, but cannot measure grams consumed. You can also move the archived file to the completed folder when recording the print.'] },
      { id: 'fusion', title: '6. Continue in Studio or Fusion', body: ['Open an archived model as a working copy in the official Bambu Studio; the original remains in your library. You can reset that working copy when you want to start over.', 'Open in Fusion uses a compatible installed Studio to export an STL mesh, then opens your installed Autodesk Fusion app. The mesh does not contain the original parametric CAD history. When a creator provides a STEP or native CAD file, that is usually a better starting point for this kind of editing.'] },
    ],
  },
  ko: {
    label: '사용 가이드', title: '내려받은 3MF부터 출력 기록까지',
    description: 'MakerDock에서 3MF 파일과 MakerWorld 원본 링크를 보관하고, 예상 시간을 계산해 출력 계획과 실제 소요시간을 기록하는 방법을 알아보세요.',
    back: 'MakerDock으로 돌아가기', eyebrow: 'Mac을 위한 3MF 보관함과 출력 계획', free: '무료 · 오픈소스 · 계정 없이',
    browser: { label: 'MakerDock 안의 MakerWorld', title: '둘러보던 페이지도,\n마음에 든 모델도 그대로.', body: '내 컬렉션에서 찾은 모델을 여러 탭으로 비교하세요. 필요한 파일을 저장하고, 보던 페이지로 돌아와 이어서 살펴볼 수 있어요.', items: ['보관함에 다녀와도 웹에서 보던 위치를 유지합니다.', '앱에서 시작한 다운로드에 확인된 원본 링크를 함께 저장합니다.', '보관한 파일을 Studio로 열거나, 필요할 때 새로 다운로드합니다.'], shortcut: '링크를 새 탭으로 열기' },
    sections: [
      { id: 'library', title: '1. 받아둔 3MF 파일 모으기', body: ['DMG를 내려받아 MakerDock을 응용 프로그램 폴더로 옮기세요. macOS 13 이상에서 사용할 수 있습니다. 3MF 파일을 가져오거나 창에 끌어 놓고, 자동 확인할 폴더를 선택할 수도 있어요. 보관함에는 원본의 사본을 저장합니다.', '내용이 완전히 같은 파일은 하나로 모으고, 다른 출력 프로필은 따로 보관합니다. 분류·태그·즐겨찾기와 다중 선택으로 정리하세요. 잘못 지운 모델은 앱 안의 휴지통에서 기록과 함께 복원할 수 있어요.'] },
      { id: 'makerworld', title: '2. 모델과 원본 페이지 함께 저장하기', body: ['사이드바에서 MakerWorld를 열고, 내 컬렉션을 보려면 웹사이트에 로그인하세요. 링크를 Command-클릭하거나 우클릭 메뉴로 새 탭에서 열 수 있습니다. 보관함에 다녀와도 보던 페이지가 유지되며, 현재 탐색 메뉴를 한 번 더 누르면 시작 페이지로 이동합니다.', '앱 안에서 시작한 다운로드나 Studio 열기에는 확인된 원본 모델 URL을 함께 보관합니다. 모델 상세의 원본 버튼으로 다시 방문하세요. 원본을 찾지 못했다면 직접 연결할 수 있어요. 새로 받기 옵션을 쓰면 보관한 다운로드를 재사용하지 않습니다. 외부 브라우저 연동은 공개 버전에 포함되지 않았고, 크롬 보조 확장은 출시 예정입니다.'] },
      { id: 'estimates', title: '3. 플레이트와 예상 시간 확인하기', body: ['저장된 플레이트 미리보기를 목록으로 확인하고, 누르면 확대해서 볼 수 있어요. 저장된 MakerWorld 예상치가 있으면 먼저 사용하고 3MF 안의 예상치도 읽습니다. 슬라이싱 결과가 없는 3MF에는 시간이 저장되어 있지 않을 수 있어요.', '설정에서 내 프린터 프로필과 별도로 설치한 호환 공식 Bambu Studio를 지정하세요. 시간이 없는 모델을 대기열에 넣으면 로컬 슬라이싱으로 계산하고, 보관함 전체의 같은 모델에도 반영합니다. 예상 시간은 프린터·재료·품질 설정에 따라 달라지며 실제 출력 결과와는 구분됩니다.'] },
      { id: 'queue', title: '4. 남는 시간에 맞춰 출력 계획하기', body: ['모델을 출력 대기열에 추가하고 순서를 정하세요. 시작 시각, 사용 가능한 시간, 출력 사이 준비 시간을 넣으면 어디까지 가능한지 보여줍니다. 실제 출력을 시작할 때 출력 중으로 표시하고, 필요하면 시작 시각을 고치세요.', '대기열은 계획을 도우며 출력 명령을 보내지는 않습니다. 선택형 로컬 연결로 호환 프린터의 상태와 남은 시간을 읽을 수 있어요. IP·시리얼 번호·LAN 접근 코드를 설정한 뒤 현재 작업을 대기열 모델과 직접 연결합니다. 기종과 펌웨어에 따라 지원 여부가 달라집니다.'] },
      { id: 'records', title: '5. 예상치 대신 실제 결과 남기기', body: ['출력 시작이 기록되어 있다면 완료 창에서 시작·종료 시각으로 소요시간을 계산합니다. 일시정지 시간도 포함되며 두 시각은 수정할 수 있어요. 시작 기록이 없을 때는 저장된 예상 시간으로 미리 채웁니다. 확인한 뒤 저장하세요.', '사용한 필라멘트와 무게, 메모를 함께 남기세요. 연결된 프린터에서 확인한 재료 종류와 색상을 제안할 수 있지만, 실제 소모한 무게를 측정하지는 않습니다. 기록과 함께 파일을 출력 완료 폴더로 옮길 수도 있어요.'] },
      { id: 'fusion', title: '6. Studio나 Fusion에서 이어서 작업하기', body: ['공식 Bambu Studio로 열면 작업용 사본을 사용하므로 보관함 원본이 유지됩니다. 처음부터 다시 작업하고 싶을 때는 작업용 사본을 초기화할 수 있어요.', 'Fusion으로 열기는 설치된 호환 Studio로 STL 메시를 만든 뒤, 별도로 설치된 Autodesk Fusion에서 여는 기능입니다. 원래 CAD의 파라미터와 설계 이력은 들어 있지 않아요. 제작자가 STEP이나 원본 CAD 파일을 제공한다면 그런 파일로 편집하는 편이 수월합니다.'] },
    ],
  },
  ja: {
    label: '使い方', title: 'ダウンロードした3MFからプリント記録まで',
    description: 'MakerDockで3MFとMakerWorldのリンクを整理し、予想時間を計算して、プリント計画と実際の所要時間を記録する方法。',
    back: 'MakerDockに戻る', eyebrow: 'Mac向け3MFライブラリ・プリント計画', free: '無料・オープンソース・アカウント不要',
    browser: { label: 'MakerDockの中でMakerWorldを', title: '見ていたページも、\n気になったモデルも。', body: 'コレクションで見つけたモデルを複数のタブで比較。必要なファイルを保存して、元のページで続きを探せます。', items: ['ライブラリへ切り替えても、閲覧中のページを保持。', 'アプリ内のダウンロードに、確認できた元リンクを保存。', '保存済みファイルをStudioで開くか、新しくダウンロード。'], shortcut: 'リンクを新しいタブで開く' },
    sections: [
      { id: 'library', title: '1. 保存した3MFをまとめる', body: ['DMGをダウンロードし、MakerDockをアプリケーションフォルダに移動します。macOS 13以降に対応。3MFの読み込み、ウィンドウへのドラッグ、確認対象フォルダの指定ができます。ライブラリにはファイルのコピーを保存します。', '内容が完全に同じファイルは統合し、異なるプリントプロファイルは別々に残します。カテゴリ、タグ、お気に入り、複数選択で整理できます。削除したモデルはアプリ内のゴミ箱から記録と一緒に復元できます。'] },
      { id: 'makerworld', title: '2. モデルと元ページを保存する', body: ['サイドバーからMakerWorldを開き、マイコレクションを使う場合はサイトにログインします。Commandクリックか右クリックのメニューでリンクを新しいタブに開けます。ライブラリへ移動して戻ってもページを保持し、選択中のサイドバーメニューをもう一度押すと開始ページに戻ります。', 'アプリ内で開始したダウンロードやStudioへの受け渡しでは、確認できた公開モデルURLも保存します。詳細画面の元ページボタンで再訪でき、特定できない場合は手動で追加できます。再ダウンロードのオプションで保存済みファイルを使わずに取得できます。外部ブラウザー連携は公開版に含まれず、Chrome拡張は予定段階です。'] },
      { id: 'estimates', title: '3. プレートと予想時間を確認する', body: ['保存済みプレートを一覧し、クリックで拡大できます。保存されたMakerWorldの予想値があれば優先し、3MF内の予想値も読み取ります。スライス結果がない3MFには時間が含まれない場合があります。', '設定でプリンタープロファイルと、別途インストールした対応版の公式Bambu Studioを指定します。予想時間のないモデルをキューに入れると、ローカルでスライス計算し、ライブラリの同じモデルにも保存できます。予想値はプリンター、素材、品質設定によって変わり、実際の結果とは区別されます。'] },
      { id: 'queue', title: '4. 使える時間に合わせて計画する', body: ['モデルをキューに追加して順序を決め、開始時刻、使える時間、プリント間の準備時間を入力します。時間内に収まるモデルを確認でき、開始時にはプリント中として記録できます。開始時刻は修正可能です。', 'キューからプリント命令は送りません。任意のローカル接続で対応プリンターの状態と残り時間を読み取れます。IP、シリアル番号、LANアクセスコードを設定し、現在のジョブをキューのモデルに手動で関連付けます。対応状況は機種とファームウェアによります。'] },
      { id: 'records', title: '5. 予想値ではなく結果を記録する', body: ['開始が記録されていれば、完了画面で開始・終了時刻から所要時間を計算します。一時停止も含む経過時間で、両方の時刻を編集できます。開始記録がなければ予想時間が初期値になります。確認してから保存してください。', '使用したフィラメント、重さ、メモを残せます。接続中に確認できた素材や色は候補として使えますが、実際の消費重量は測定しません。記録と同時にファイルをプリント済みフォルダへ移動することもできます。'] },
      { id: 'fusion', title: '6. StudioやFusionで作業を続ける', body: ['公式Bambu Studioでは作業用コピーを開くため、ライブラリの元ファイルは残ります。やり直すときは作業用コピーをリセットできます。', 'Fusionで開く機能は、対応版StudioでSTLメッシュを書き出し、別途インストールしたAutodesk Fusionに渡します。元のCADのパラメーターや設計履歴は含まれません。作者がSTEPや元のCADファイルを公開している場合、そちらのほうが編集に向いています。'] },
    ],
  },
  'zh-CN': {
    label: '使用指南', title: '从下载3MF到记录打印结果',
    description: '了解如何用MakerDock整理3MF和MakerWorld链接、计算预估时间、安排打印队列并记录实际用时。',
    back: '返回MakerDock', eyebrow: 'Mac上的3MF模型库与打印计划工具', free: '免费 · 开源 · 无需账号',
    browser: { label: '在MakerDock里浏览MakerWorld', title: '接着看刚才的页面，\n留住喜欢的模型。', body: '从收藏中找到模型，用多个标签页比较。保存需要的文件，再回到刚才的页面继续浏览。', items: ['切换到模型库后，仍能回到正在浏览的页面。', '应用内发起的下载会保存已识别的原始链接。', '用Studio打开已归档文件，也可以按需重新下载。'], shortcut: '在新标签页中打开链接' },
    sections: [
      { id: 'library', title: '1. 把下载的3MF放在一起', body: ['下载DMG，将MakerDock拖入应用程序文件夹。支持macOS 13及以上。可以导入3MF、将文件拖入窗口，或选择自动检查的文件夹。模型库保存的是原文件的副本。', '内容完全相同的文件会合并，不同打印配置则单独保留。通过分类、标签、收藏和多选整理模型。误删后，可从应用内的废纸篓恢复模型及其记录。'] },
      { id: 'makerworld', title: '2. 保存模型及其原始页面', body: ['从侧栏打开MakerWorld，登录网站后即可访问我的收藏。按住Command点击链接，或用右键菜单在新标签页打开。切换到模型库再回来时保留当前页面，再次点击已选中的探索菜单才返回起始页面。', '从应用内发起下载或用Studio打开时，会保存已识别的公开模型URL。可通过详情中的原始页面按钮回访，无法识别时也能手动关联。使用重新下载选项即可跳过已保存的文件。公开版暂不支持外部浏览器传入下载，Chrome辅助扩展仍在计划中。'] },
      { id: 'estimates', title: '3. 查看打印板和预估时间', body: ['保存的打印板预览会一起列出，点击可放大。如果已有MakerWorld预计值，会优先显示，也能读取3MF中的预计值。没有切片结果的3MF可能不包含时长。', '在设置中指定打印机配置，以及单独安装的兼容官方Bambu Studio。将缺少预计时间的模型加入队列后，可进行本地切片计算，并同步保存到模型库中的同一模型。预计值受打印机、材料和质量设置影响，与实际结果不同。'] },
      { id: 'queue', title: '4. 按可用时间安排打印', body: ['把模型加入队列并排序，设置开始时间、可用时长和每次打印之间的准备时间，即可查看哪些模型能按时完成。实际开始时标记为正在打印，开始时间可修改。', '队列不会发送打印命令。可选的局域网连接能够读取兼容打印机的状态和剩余时间。设置IP、序列号及LAN访问码后，手动将当前任务关联到队列模型。支持情况取决于机型和固件。'] },
      { id: 'records', title: '5. 记录结果，而不只是预计值', body: ['已有开始记录时，完成表单会根据开始与结束时间计算经过的时长，包含暂停时间。两个时间都能修改。没有开始记录时，可以用预计时间预填。确认结果后再保存。', '记录使用的耗材、克数和备注。连接中观察到的材料类型和颜色可用于预填，但不会测量实际消耗的克数。保存记录时，也可以将文件移到已完成文件夹。'] },
      { id: 'fusion', title: '6. 在Studio或Fusion里继续编辑', body: ['用官方Bambu Studio打开时使用工作副本，模型库中的原始文件保持不变。想从头开始时，可以重置工作副本。', '在Fusion中打开会用兼容的Studio导出STL网格，再交给单独安装的Autodesk Fusion。网格不包含原始CAD参数和设计历史。如果作者提供STEP或原生CAD文件，它们通常更适合这类编辑。'] },
    ],
  },
};
