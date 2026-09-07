# MakerDock — Mac App Store 배포 검토

2026-09-08 확인 · 대상: MakerDock 1.4.1 (8), 현재 설치된 운영 앱과 소스

**현재 빌드는 그대로 제출할 수 없다. 로컬 3MF 관리 기능을 중심으로 샌드박스 버전을 만들면 앱스토어 배포를 추진할 수 있다. MakerWorld 연동은 서비스 허용 범위 확인이 별도로 필요하다.** 이 문서는 구현·정책 대조 결과이며 심사 승인이나 서비스 이용허가를 받은 결과가 아니다. Apple 포털 등록·업로드·공증·공개 배포는 수행하지 않았다.

## 1. 확정된 기술적 장애물: 샌드박스

프로젝트의 `ENABLE_APP_SANDBOX = NO`이며 운영 앱에도 App Sandbox entitlement가 없다. Mac App Store 제출에는 App Sandbox가 필수다. [Apple 샌드박스 설정](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)

| 현재 기능 | 앱스토어 버전에서의 처리 제안 |
| --- | --- |
| 로컬 3MF 가져오기·미리보기·태그·분류·메모·출력 기록 | 유지. 앱 컨테이너 안에 라이브러리 저장 |
| 감시 폴더·출력 완료 폴더 이동 | 사용자가 고른 폴더의 읽기/쓰기 권한과 지속 북마크로 구현. 재실행·권한 철회·이동 경로별 시험 필요 |
| 기존 PlateShelf 데이터·웹 세션 이전 | 자동으로 다른 저장 경로를 읽는 현재 방식을 검토하고, 사용자 선택 기반 가져오기와 새 웹 로그인으로 변경 |
| Studio 설정 자동 탐색 | 다른 앱의 설정 파일을 직접 읽는 현재 방식은 재검증. 앱 안 프린터 선택 또는 사용자가 선택한 설정 파일로 대체 |

샌드박스가 파일 관리를 금지하는 것은 아니다. 사용자 선택 파일·폴더와 보안 북마크로 필요한 접근을 확장할 수 있다. 기존 코드에도 북마크 처리는 있지만, 샌드박스를 켠 상태의 전체 동작은 아직 시험하지 않았다. [Apple 파일 접근 문서](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

## 2. 가장 큰 서비스 위험: MakerWorld 연동

공식 사이트의 Terms 링크를 브라우저에서 직접 열어 확인했다. 페이지 상단에는 **Updated June 11, 2024 / Effective June 18, 2024**라고 표시된다. 이는 2026-09-08에 제공된 페이지의 표시 날짜이며 2026년 개정본이라고 주장하지 않는다.

- **4조:** 서비스 이용은 제한된 라이선스이며, 서면 동의 없는 상업적 활용·유사/경쟁 서비스 구축 등에 제한이 있다.
- **9조:** 자동화 도구, 페이지 수집 등으로 사이트나 콘텐츠에 접근·취득·복제·모니터링하거나 제공 방식을 우회하는 행위를 폭넓게 제한한다.
- **5조:** 모델의 이용권한은 제작자가 선택한 라이선스에 따른다. 다운로드 가능하다는 사실만으로 모델 재배포권을 얻지는 않는다.

출처: [MakerWorld 이용약관 4·5·9조](https://makerworld.com/en/user-agreement)

현재 앱은 사용자 요청에 따라 다운로드를 처리하고 로컬 파일을 재사용한다. 대량 크롤링 기능은 없다. 다만 페이지에 넣은 JavaScript가 다운로드 응답과 표시된 프로필 정보를 관찰하므로 **현재 구현을 약관상 허용된다고 확정할 근거는 확보하지 못했다.** 소량·개인 사용이라는 사실만으로 예외를 단정해서도 안 된다.

공개 배포 전 확인할 범위는 ① WKWebView 내 사이트 표시·로그인 ② 다운로드 응답 감지 ③ 모델/프로필 URL·시간·썸네일 로컬 보관 ④ 기존 파일 재사용 ⑤ 유료 앱일 경우 그 수익화 방식이다. MakerWorld에 이 기능과 데이터 흐름을 제시해 명시적 허용 여부를 확인하는 것이 적절하다. 문의 메시지는 발송하지 않았다.

Bambu도 오픈소스 코드 라이선스와 클라우드 접근 권한은 별개라고 설명한다. **DMG 직접 배포나 Chrome 확장으로 바꿔도 이 서비스 약관 문제는 남는다.** [Bambu 공식 설명, 2026-05-07](https://blog.bambulab.com/setting-the-record-straight-on-cloud-access-and-community/)

## 3. Apple 심사에서 추가로 설명할 부분

| 규정 | 현재 구현에 대한 판단 |
| --- | --- |
| 5.2.2 제3자 서비스 | MakerWorld 사용 권한을 입증할 준비가 필요 |
| 4.2 최소 기능 | 독립적인 파일 관리·분류·미리보기·기록 기능이 있어 단순 웹 포장보다 설명하기 유리. 최종 판단은 심사 대상 |
| 4.2.3(i), 2.4.5(ii) 독립 실행 | 외부 Studio CLI 계산은 별도 검토 대상. 초기 앱스토어 버전에서는 제외하고 저장된 예상 표시를 유지하는 방안을 권장 |
| 1.2 사용자 콘텐츠 | 웹의 신고·차단·유해 콘텐츠 처리 동작과 문의 경로 확인 필요 |
| 3.1 결제 | 현재 자체 결제 없음. 웹의 유료 콘텐츠·멤버십 구매 흐름은 출시 국가와 함께 재검토 |
| 5.1.1 개인정보 | 앱 내부와 스토어에 개인정보처리방침 링크 필요 |
| 4.1, 5.2.1 식별·권리 | 독립 앱임을 명확히 표시하고 제작자 모델을 동의 없이 홍보 자료나 설치본에 넣지 않기 |

출처: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

외부 앱으로 파일을 여는 동작 자체를 일괄 금지로 판정한 것은 아니다. MakerDock은 Studio 없이도 파일 관리가 가능하다. 다만 **설치된 Studio 실행 파일·리소스에 의존하는 현재 시간 계산은 샌드박스 호환성이 검증되지 않았다.** 첫 앱스토어 제출에서는 “Studio에서 열기”를 선택적 내보내기로 두고, 외부 프로그램 실행 의존도를 줄이는 편이 단순하다. 기존 Bambu URL 기본 처리 앱 등록도 자동 등록보다 사용자가 선택하는 연결 방식으로 정리할 것을 권장한다.

## 4. 개인정보: 로컬 앱이라고 모두 ‘수집 안 함’은 아님

코드 확인 결과 자체 서버·분석 SDK는 없으며, 모델·노트·기록·계산 결과는 로컬에 저장된다. 다운로드 전송부는 브라우저 쿠키를 공유하지 않는다. 그러나 내장 MakerWorld 웹뷰에는 로그인과 웹 트래픽이 있다. Apple은 일반 웹 탐색 기능의 예외를 제외하고 웹뷰에서 발생하는 수집도 신고 대상으로 설명한다. 현재는 MakerWorld 전용 브라우저이므로 **‘수집 안 함’을 바로 선택하면 안 된다.** 웹에서 실제 전송·보관되는 정보, 로그인 제공자, 추적 여부를 확인해야 한다. [Apple App Privacy Details — Web views](https://developer.apple.com/app-store/app-privacy-details/)

현재 앱 자체 `PrivacyInfo.xcprivacy`는 없고, ZIPFoundation 의존성의 manifest는 번들에 포함된다. 앱 코드의 UserDefaults·파일 날짜 사용과 SDK를 개인정보 보고서에서 확인해야 한다. 다만 현재 required-reason API 문서의 적용 플랫폼 열거에는 macOS가 없으므로, 이것만으로 **네이티브 macOS 앱의 확정 반려 사유라고 단정하지 않는다.** 개인정보처리방침·App Privacy 답변과 manifest는 서로 다른 항목이다. [Apple manifest 안내](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk), [Required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

## 5. 현실적인 배포 경로

**앱스토어 우선:** 로컬 3MF 보관함을 중심으로 샌드박스 지원 → 원본 사이트는 일반 브라우저로 열기 → 웹 감지·자동 수집과 외부 CLI 계산은 첫 제출에서 제외 → 사용자 선택 파일의 저장된 시간·분류·메모·완료 기록 유지. MakerWorld 허용을 확보하면 연동 범위를 다시 검토한다.

**현재 기능을 유지한 직접 배포:** MakerWorld 허용 범위 확인 → Developer ID 서명·공증 → 다른 Mac에서 설치/계산/다운로드 시험 → 공개 배포. 공증은 악성 코드·서명 검사이며 앱스토어 심사나 제3자 서비스 이용허가를 대신하지 않는다. [Apple 공증 문서](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

현재 DMG는 개인 `CHANWOO KOO (D523TSBMWR)` Developer ID로 서명했고 공증은 미완료다. 운영 ID는 `com.ninepiece.app.mac.makerdock`, 개발 ID는 `.dev`다. 회사 팀은 사용하지 않았다. 앱스토어용 서명/프로비저닝 및 앱 등록은 별도 단계다.

## 6. 이번 기능 검증

- MakerWorld 시간이 있으면 카드·목록·상세·매핑 가능한 플레이트에 우선 표시. 여러 판의 합계 시간을 임의로 나누지 않음.
- 3MF의 `slice_info.config` 예상을 읽고, 없으면 대응 G-code 헤더의 저장된 시간을 추가로 확인. 슬라이싱 결과가 없는 편집용 3MF는 읽기만으로 시간을 만들 수 없음.
- 프린터/노즐·출력 품질을 저장하고 설치된 공식 Studio로 로컬 복사본 계산. 재료·배치·오브젝트별 설정은 파일 기준. 계산은 출력 명령이 아님.
- 결과는 원본 3MF와 분리 저장. 프린터·품질·Studio 버전·프리셋 내용이 달라지면 이전 계산을 현재 결과로 사용하지 않음. 취소 및 5분 제한 제공.
- 실제 클립: 파일 설정 계산 **26분54초**, 저장된 MakerWorld **27분**, X2D 0.4 / 0.20mm Standard 계산 **20분27초**. 품질 설정이 다르므로 MakerWorld와 수치가 같아야 하는 것은 아님.
- 앱 테스트 41개 통과. Core 21개 통과·외부 데이터 폴더가 필요한 1개 생략. 운영 원본 63개 해시와 모델/분류/메모/출력 기록 유지 확인. Universal 빌드·서명·DMG 검증 완료. Intel에서의 실제 실행 및 모든 프린터/재료 조합은 검증하지 않음.

기술 근거: [공식 Studio CLI 문서](https://github.com/bambulab/BambuStudio/wiki/Command-Line-Usage), [3MF 저장 포맷 구현](https://github.com/bambulab/BambuStudio/blob/master/src/libslic3r/Format/bbs_3mf.cpp), [G-code 시간 기록 구현](https://github.com/bambulab/BambuStudio/blob/master/src/libslic3r/GCode/GCodeProcessor.cpp)
