# v2.0.15

### 한국어
- 데이터 공유 현황 창을 추가했습니다. `/공유` 또는 `/ezshare`로 열면 받은 기록, 보낸 사람, 보낸 기록, 종류별 현황과 새로 받은 기록만 따로 볼 수 있습니다.
- 공유 데이터를 채널로도 보내 더 빨리 퍼지게 했습니다.
- 데이터 채널의 사용자 명단이 새로 갱신되지 않아 일부 사용자와 귓속말로 공유 기록을 주고받지 못하던 문제를 고쳤습니다.
- 퀘스트 보상, 트레이너가 가르치는 주문, 오브젝트 이름도 다른 사용자와 공유합니다.
- 게임패드: 전투가 끝나면 EzWoW 창이 패드 조작을 가져가던 문제를 고쳤습니다. 전투 전에 EzWoW 창을 조작하던 경우에만 되돌립니다.
- 특성 창이 닫혀 있을 때 1초마다 모든 화면 요소를 훑어 끊김이 생기던 문제를 고쳤습니다.
- 공격대와 전장에서 자신에게만 거는 버프(내면의 열정, 갑옷 주문, 전투의 외침 등)가 표시되지 않던 문제를 고쳤습니다.
- 주문을 쓸 때마다, 그리고 추적하지 않는 공격대원의 거리가 바뀔 때마다 전체를 다시 계산하던 부담을 줄였습니다.
- 확인 창이 떠 있을 때 특성 조합을 다시 고르면 적용되지 않던 문제를 고쳤습니다.
- 같은 직업의 다른 캐릭터로 접속하면 버프 선택이 "자동"으로 바뀌던 문제를 고쳤습니다.
- 해제 가능한 디버프 알림음이 전투 밖에서만 울린다는 것을 설정 문구에 적었습니다.
- 전투 중 아군 대상의 거리를 잴 때 "애드온 동작 차단"이 날 수 있던 호출을 막았습니다.
- 전투 중에도 버프 칸 왼쪽 클릭이 다음 버프로 넘어갑니다(예: 야생의 징표 다음 가시). 칸 표시와 툴팁도 다음 버프로 바뀝니다.
- 전투 중에도 버프 칸에서 Ctrl+휠로 쓸 버프를 바꿀 수 있습니다.
- 공유 기록을 설치된 EzWoW 애드온 중 최대 2개에만 저장해 접속·다시 불러오기가 빨라지고 저장 파일이 작아집니다. 업데이트 후 게임을 한 번 완전히 다시 시작하면 적용됩니다.

### English
- Added a data sharing window. Open it with `/ezshare` to see received records, players, sent records, totals by kind, and only the newly received records.
- Shared data is now also sent through the channel, so it spreads faster.
- Fixed shared records not being exchanged by whisper with some players because the data channel's player list was not refreshed.
- Quest rewards, trainer spells and object names are now shared with other players too.
- Gamepad: EzWoW windows no longer take over the pad after combat; it returns only if you were using an EzWoW window before the fight.
- Fixed a stutter every second from scanning every interface frame while the talent window was closed.
- Fixed self-only buffs (Inner Fire, armor spells, Battle Shout and so on) not showing in raids and battlegrounds.
- Reduced full rescans on every cast and on range changes of raid members that are not tracked.
- Fixed picking a talent build again while the confirm window was open applying nothing.
- Fixed logging into another character of the same class resetting your buff choice to Auto.
- The dispellable debuff sound option now says it works out of combat only.
- Avoided a range check on friendly targets in combat that could cause an "action blocked" error.
- In combat too, a buff cell's left click moves on to the next buff (for example Mark of the Wild, then Thorns), and the cell and tooltip show the next buff.
- Ctrl+wheel on a buff cell now changes the buff in combat too.
- Shared records are now saved by at most 2 of your installed EzWoW addons, so logins and reloads are faster and save files smaller. Takes effect after one full game restart following the update.
