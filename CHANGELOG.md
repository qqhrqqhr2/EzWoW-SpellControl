# Changelog - EzWoW - Spell Control

## v2.0.0

### English

- Fixed icon and window dragging offsets at different UI scales.
- Separated Buffs, Cleanse and Crowd Control into reorderable sections.
- Added direct left/right-click buff casting and Ctrl+mouse-wheel buff selection.
- Added crowd-control suggestions based on the enemy creature type.
- Reduced unnecessary aura and slot redraws.

### 한국어

- UI 배율에 따라 아이콘·창을 끌 때 위치가 어긋나는 문제를 수정했습니다.
- 버프·해제·메즈를 독립 섹션으로 나누고 순서 변경을 지원합니다.
- 좌·우클릭 버프 시전과 Ctrl+마우스 휠 버프 선택을 추가했습니다.
- 적의 생명체 유형에 맞는 군중 제어 주문 표시를 추가했습니다.
- 오라와 슬롯의 불필요한 화면 갱신을 줄였습니다.

## v1.1.0
- 드래그 시 마우스 포인터와 아이콘/프레임 좌표가 어긋나거나 벌어지는 스케일 오차(`EffectiveScale`) 및 초기 점프 현상 수정
- **모듈 아키텍처 재구성 (`Core/`, `Data/`, `Modules/`, `UI/`) 및 전술 기능 통합**:
  - `Core/Init.lua`, `Core/Locales.lua`(8개 언어), `Core/UIKit.lua`, `Data/Spells.lua`
  - `Modules/SpellScanner.lua`(액티브 주문·등급 스캐너), `Modules/SecureAttributes.lua`(보안 시전 속성 바인더)
  - `UI/MicroBoard.lua`(3섹션 전술 보드), `UI/OptionsWindow.lua`(설정창 및 섹션 순서 제어)
- **주요 기능 개선**:
  - `버프` / `해제` / `메즈(적 대상 군중 제어)` 3개 독립 섹션 구성 및 섹션 순서 변경 기능 적용
  - 버프 슬롯 좌/우클릭 직접 시전 및 `Ctrl + 마우스 휠` 주력 버프 실시간 변경 지원
  - 적 대상 생명체 유형(야수·언데드·악마·정령·용족·인간형 등) 자동 판별 기반 메즈 슬롯 추가
  - 슬롯 시각 시그니처(`_ezscVisualSig`, `_ezscFilterSig`) 비교를 통한 불필요한 오라 재렌더링 방지 최적화

## v1.0.0
- 초기 릴리즈: 파티·공격대 스마트 버프, 저레벨 자동 등급 하향(Auto-Downranking), 디버프 해제, 8개 언어 실시간 전환 지원
