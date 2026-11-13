<!--
CurseForge summary (EN): One-click party buffs, debuff cleanse and enemy crowd control, plus spells to learn at each level with costs, rank hints in tooltips and recommended talent builds.
CurseForge summary (KO): 파티 버프 · 디버프 해제 · 적 대상 메즈를 클릭 한 번으로. 레벨별로 배울 주문과 비용, 툴팁 랭크 안내, 직업별 추천 특성까지.
-->

# EzWoW - Spell Control

**English** · [한국어](#한국어)

A small tactical board for WoW Forever: **buff missing members, cleanse debuffs and crowd-control enemies with one click**. It reads only the active spells you have learned and shows just the units that need something. It also keeps track of **the spells you can learn at each level** after you visit your class trainer, and adds **recommended talent builds** to the talent window.

![Tactical board and spells by level](https://raw.githubusercontent.com/qqhrqqhr2/EzWoW-SpellControl/master/docs/images/ui_en.png)

![Settings window](https://raw.githubusercontent.com/qqhrqqhr2/EzWoW-SpellControl/master/docs/images/settings_en.png)

*In-game screenshots (WoW Forever, Korean client). Character and player names and chat text are blurred.*

## Features

### Tactical board
- **Buffs**: party and raid members missing a buff, yourself when solo, and a friendly target outside your group. Left-click the main buff, right-click the secondary buff, Ctrl + mouse wheel to switch the left-click buff.
- **Cleanse**: members with a debuff you can remove appear at once with a sound; the border colour shows the debuff type, and a running Abolish effect shows `Active`.
- **Crowd control**: target an enemy and the board offers the CC that works on its creature type and range (left / right / Ctrl + left-click).
- Smart choices: class-aware buffs, auto-downranking for low-level members, optional group buffs first, buffs about to expire count as missing.
- Buff cells switch to `OK` as soon as the buff is back on, even in combat.
- Raid groups you look after, separate party and raid cell sizes, lock, fold, reorder sections, show only on mouseover.

### Spells by level
- Saved when you open your class trainer: every spell and rank with its level and cost.
- Window with `/ezsc spells`: every level, opening at your level. Spells you can learn now are highlighted, first ranks are marked **(new spell)**, others **(Rank N)**, learned ones are checked, with the total cost of what you can learn now.
- The same list docks next to your spellbook (can be folded or turned off).
- Spell tooltips show **Next rank: Rank N · Lv** or **Learnable at level: N**.
- On level-up, chat tells you how many new spells you can learn.
- Optional: after learning a new rank, lower ranks on your action bars are replaced.

### Recommended talents
- A **Recommended** button on the talent window lists level 1–60 builds for your class, one per spec (e.g. `Shadow (DPS)  16/3/32`).
- Pick one and your free points are spent in the build's order; you are asked once more before they are applied, and Cancel takes them back.
- While leveling, click again after each level to continue.

## Gamepad
- With the gamepad UI on, EzWoW windows work with a gamepad: D-pad to move, A (✕) to press, X (□) for right-click, LB/RB to scroll, B (○) to close. A key guide in your pad's button style shows under the window.
- With no game window open, press **View (Back) / Create** to move to the EzWoW frames on screen. Press it again or B to go back.
- To use another button: Key Bindings > AddOns > EzWoW > "Gamepad: move to / leave the EzWoW frames" (with EzWoW-MapFinder installed).

## Record sharing
- Shared by all EzWoW addons and **on by default**: quest NPCs, rare monster sightings, item drops and gathering spots you have seen yourself are shared with other EzWoW users.
- `/ezshare on` / `off`, `/ezshare channel on` / `off`, `/ezshare status`

## Commands
- `/ezsc` (`/spellcontrol`, `/스펠컨트롤`) — settings
- `/ezsc spells` — spells by level
- `/ezsc toggle` — show or hide the board
- `/ezsc lock` — lock or unlock the board
- `/ezsc reset` — reset the board position, size and section order
- `/eztalent` (`/추천특성`) — recommended talents menu

The board uses secure spell buttons, so its cells do not change during combat; it tidies up when combat ends.

Languages: English, 한국어, Deutsch, Français, Español, Русский, 简体中文, 繁體中文.

---

## 한국어

WoW Forever용 작은 전술 보드입니다. **빠진 버프 걸기 · 디버프 해제 · 적 대상 메즈를 클릭 한 번으로** 합니다. 마법책에서 실제로 배운 액티브 주문만 읽어 필요한 대상만 보여 줍니다. 직업 기술 전문가를 한 번 방문하면 **레벨별로 배울 주문**도 알려 주고, 특성 창에는 **직업별 추천 특성**을 넣어 줍니다.

![전술 보드와 레벨별 배울 스킬](https://raw.githubusercontent.com/qqhrqqhr2/EzWoW-SpellControl/master/docs/images/ui_ko.png)

![설정창](https://raw.githubusercontent.com/qqhrqqhr2/EzWoW-SpellControl/master/docs/images/settings_ko.png)

*실제 게임 화면입니다(WoW Forever, 한국어 클라이언트). 캐릭터 · 다른 플레이어 이름과 채팅 내용은 가렸습니다.*

## 기능

### 전술 보드
- **버프**: 버프가 빠진 파티 · 공격대원, 솔로일 때 나, 파티 밖 우호적 대상. 좌클릭은 주 버프, 우클릭은 보조 버프, Ctrl + 마우스 휠로 좌클릭 버프 변경.
- **해제**: 내가 지울 수 있는 디버프에 걸린 파티원이 알림음과 함께 바로 나타납니다. 테두리 색이 디버프 종류이고, 지속형 해제가 걸려 있으면 `해제중`.
- **메즈**: 적을 대상으로 잡으면 생명체 유형과 사거리에 맞는 군중 제어 주문을 배치합니다(좌 / 우 / Ctrl + 좌클릭).
- 똑똑한 선택: 직업별 맞춤 버프, 저레벨 대상 자동 하향, 단체 버프 우선(선택), 곧 끝나는 버프도 빠진 것으로 표시.
- 버프 칸은 전투 중에도 버프가 다시 걸리면 바로 `완료`로 바뀝니다.
- 담당 공대 파티 선택, 파티 · 공대 칸 크기 따로, 잠금 · 접기 · 섹션 순서 변경, 마우스 올릴 때만 표시.

### 레벨별 배울 스킬
- 직업 기술 전문가를 열 때 모든 주문 · 랭크의 레벨과 비용을 저장합니다.
- `/ezsc spells` 창: 모든 레벨을 보여 주고 현재 레벨에서 열립니다. 지금 배울 수 있는 주문은 강조, 처음 배우는 주문은 **(새 스킬)**, 나머지는 **(랭크 N)**, 배운 주문은 체크, 지금 배울 수 있는 주문의 합계 비용 표시.
- 같은 목록이 주문책 옆에 붙습니다(접거나 끌 수 있음).
- 주문 툴팁에 **다음 랭크: 랭크 N · Lv** 또는 **배울 수 있는 레벨: N** 표시.
- 레벨이 오르면 새로 배울 수 있는 주문 수를 채팅창에 알려 줍니다.
- 선택: 새 랭크를 배우면 단축바의 낮은 랭크를 자동으로 바꿉니다.

### 추천 특성
- 특성 창의 **추천 특성** 단추를 누르면 내 직업의 1~60레벨 빌드가 전문화마다 하나씩 나옵니다(예: `암흑 (딜러)  16/3/32`).
- 하나를 고르면 남은 포인트를 빌드 순서대로 넣고, 적용할지 한 번 더 묻습니다. 취소하면 되돌립니다.
- 레벨이 오를 때마다 다시 누르면 이어서 찍습니다.

## 게임패드
- 게임패드 UI를 켜면 EzWoW 창을 패드로 다룰 수 있습니다. 방향키로 이동, A(✕)로 누르기, X(□)로 오른쪽 클릭, LB/RB로 스크롤, B(○)로 닫기입니다. 창 아래에 연결된 패드 모양으로 키 안내가 나옵니다.
- 블리자드 창이 열려 있지 않을 때 **보기(Back) / Create 버튼**을 누르면 화면의 EzWoW 프레임으로 이동합니다. 다시 누르거나 B를 누르면 돌아갑니다.
- 다른 버튼을 쓰려면: 설정 > 단축키 > 애드온 > EzWoW > "게임패드: EzWoW 창으로 이동/돌아가기" (EzWoW-MapFinder 설치 시)

## 기록 공유
- 모든 EzWoW 애드온이 함께 쓰며 **기본으로 켜져 있습니다**. 직접 확인한 퀘스트 NPC, 희귀 몬스터 목격, 아이템 드롭, 채집 위치를 다른 EzWoW 사용자와 나눕니다.
- `/ezshare on` / `off` (또는 `/공유`), `/ezshare channel on` / `off`, `/ezshare status`

## 명령어
- `/ezsc` (`/spellcontrol`, `/스펠컨트롤`) — 설정창
- `/ezsc spells` (`/ezsc 스킬`) — 레벨별 배울 스킬
- `/ezsc toggle` — 보드 보이기/숨기기
- `/ezsc lock` — 보드 잠금/해제
- `/ezsc reset` — 보드 위치 · 크기 · 섹션 순서 초기화
- `/추천특성` (`/eztalent`) — 추천 특성 메뉴

보안 주문 버튼을 쓰기 때문에 전투 중에는 칸 구성이 바뀌지 않고, 전투가 끝나면 다시 정리됩니다.

지원 언어: English, 한국어, Deutsch, Français, Español, Русский, 简体中文, 繁體中文.

---

**Support:** If you find this addon useful, you can support its development. [Buy Me a Coffee ☕](https://buymeacoffee.com/qqhrqqhr2)

**후원:** 애드온이 도움이 되셨다면 개발 후원으로 응원해 주세요. [Buy Me a Coffee ☕](https://buymeacoffee.com/qqhrqqhr2)
