/**
 * i18n strings — Korean/English auto-detection.
 * Mirrors Sources/ClaudePet/Strings.swift.
 *
 * Language is detected once at startup via app.getLocale().
 * If the locale starts with "ko", Korean strings are used; otherwise English.
 */

import { app } from 'electron';

const isKorean: boolean = app.getLocale().startsWith('ko');

// MARK: - Greeting

export const greeting = isKorean ? '안녕! 나는 Claude Pet이야!' : "Hi! I'm Claude Pet!";

// MARK: - Status changes

export const workStarted = isKorean ? '작업 시작!' : 'Work started!';
export const workDone = isKorean ? '작업 완료!' : 'Work done!';
export const permissionNeeded = isKorean
  ? '⚠️ 권한이 필요해! 확인해줘!'
  : '⚠️ Permission needed! Check terminal!';
export const sessionConnected = isKorean ? '연결됨!' : 'Connected!';
export const newSession = isKorean ? '새 세션' : 'new session';
export const sessionStart = isKorean ? '시작!' : 'start!';
export const desktopHello = isKorean ? 'Claude Desktop 왔다! 반가워!' : 'Claude Desktop is here! Hi!';
export const desktopBye = (time: string): string =>
  isKorean ? `${time} 사용했어! 수고했어~` : `Used ${time}! Good work~`;
export const formatDuration = (mins: number, secs: number): string =>
  isKorean
    ? `${String(mins).padStart(2, '0')}분${String(secs).padStart(2, '0')}초`
    : `${String(mins).padStart(2, '0')}m${String(secs).padStart(2, '0')}s`;

export const formatMinutes = (totalMins: number): string => {
  if (isKorean) {
    if (totalMins < 60) return `${totalMins}분`;
    const h = Math.floor(totalMins / 60);
    const m = totalMins % 60;
    return m > 0 ? `${h}시간 ${m}분` : `${h}시간`;
  } else {
    if (totalMins < 60) return `${totalMins}m`;
    const h = Math.floor(totalMins / 60);
    const m = totalMins % 60;
    return m > 0 ? `${h}h ${m}m` : `${h}h`;
  }
};
export const bye = isKorean ? '바이바이~' : 'Bye bye~';

// MARK: - Tool messages

export function toolMessage(tool: string): string {
  const t = tool.toLowerCase();
  if (t === 'bash')         return isKorean ? '명령어 실행 중...' : 'Running command...';
  if (t === 'read')         return isKorean ? '파일 읽는 중...' : 'Reading file...';
  if (t === 'edit')         return isKorean ? '코드 수정 중...' : 'Editing code...';
  if (t === 'write')        return isKorean ? '파일 작성 중...' : 'Writing file...';
  if (t === 'grep')         return isKorean ? '코드 검색 중...' : 'Searching code...';
  if (t === 'glob')         return isKorean ? '파일 찾는 중...' : 'Finding files...';
  if (t === 'agent')        return isKorean ? '에이전트 작업 중...' : 'Agent working...';
  if (t.includes('webcrawl') || t.includes('webfetch') || t.includes('websearch'))
                            return isKorean ? '웹 검색 중...' : 'Searching web...';
  if (t.includes('notebookedit')) return isKorean ? '노트북 수정 중...' : 'Editing notebook...';
  if (t.includes('task'))   return isKorean ? '작업 관리 중...' : 'Managing tasks...';
  if (t.includes('mcp'))    return isKorean ? '플러그인 실행 중...' : 'Running plugin...';
  return isKorean ? '작업 중...' : 'Working...';
}

// MARK: - Click messages

export const clickWorkingDir = (dir: string): string =>
  isKorean ? `지금 ${dir}에서 열심히 일하는 중!` : `Working hard in ${dir} right now!`;

export const clickWorking = isKorean
  ? ['지금 열심히 일하는 중!', '잠깐만, 거의 다 됐어!', 'Claude가 코드 작성 중~']
  : ['Working hard right now!', 'Almost done, wait!', 'Claude is coding~'];

export const clickPermission = isKorean
  ? ['권한 승인이 필요해! 터미널 확인해줘!', '나 좀 도와줘~ 권한이 필요해!']
  : ['Permission needed! Check terminal!', 'Help me~ I need permission!'];

export const clickIdleDir = (dir: string): string =>
  isKorean ? `${dir} 대기 중~ 뭐 시킬 거야?` : `${dir} idling~ what do you need?`;

export const clickIdle = isKorean
  ? ['나 건드리지 마~ 간지러워!', '놀아줄 거야?', '왜왜왜~ 뭐 필요해?']
  : ["Don't poke me~ ticklish!", 'Wanna play?', 'What do you need?'];

export const clickNotRunning = isKorean
  ? ['Claude Code가 꺼져있어~', '나 혼자 심심해...']
  : ['Claude Code is off~', "I'm lonely..."];

export const doubleClick = isKorean ? '우왕! 신난다~!' : 'Woah! So fun~!';

// MARK: - Random speech

export const idleMessages = isKorean
  ? [
      '오늘 코딩 많이 했어?',
      '잠깐 스트레칭 하는 건 어때?',
      '커피 한잔 어때요~',
      '버그 없는 하루 되길!',
      'git commit 했어?',
      '오늘도 화이팅!',
      '난 여기서 지켜보고 있을게~',
      '세미콜론 빼먹지 않았지?',
      '물 한 잔 마시고 와~ 💧',
      '눈도 잠깐 쉬어주자 👀',
      '오늘 목표 절반은 했어?',
      '막히면 잠깐 산책 어때?',
      '넌 충분히 잘하고 있어 :)',
      '테스트 돌려보는 거 잊지 마!',
      '어깨 쫙 펴고 자세 바르게~',
      '가끔은 쉬어도 괜찮아~',
    ]
  : [
      'Done much coding today?',
      'How about a stretch?',
      'Coffee break?',
      'Bug-free day!',
      'Did you git commit?',
      'You got this!',
      "I'm watching over you~",
      "Didn't forget a semicolon?",
      'Go grab some water~ 💧',
      'Rest your eyes for a sec 👀',
      "Halfway to today's goal?",
      'Stuck? Take a short walk!',
      "You're doing great :)",
      "Don't forget to run tests!",
      'Sit up straight~ shoulders back!',
      "It's okay to take a break~",
    ];

export const workingMessages = isKorean
  ? ['열심히 작업 중이야!', '잘 되고 있어!', '곧 끝날 거야!',
     '집중 모드 ON! 🔥', '타닥타닥... 코드 나간다~', '이번엔 한 번에 돼라~ 🙏',
     '버그야 비켜! 🐛', '조금만 더, 거의 다 왔어!']
  : ['Working hard!', 'Going well!', 'Almost done!',
     'Focus mode ON! 🔥', 'Tap tap... code incoming~', 'Please work first try~ 🙏',
     'Move over, bugs! 🐛', 'Just a bit more, almost there!'];

// MARK: - 에디션 멘트 (스킨별)

export const summerMessages = isKorean
  ? ['물놀이 가고 싶다~ 🏖️', '오늘 완전 여름 날씨야! ☀️', '튜브 타고 둥둥~ 🛟',
     '아이스크림 먹고 싶어 🍦', '수박 한 입 어때? 🍉', '선크림 꼭 발라~ 🧴',
     '바다 보러 가고 싶다 🌊', '더우니까 물 많이 마셔! 💧']
  : ['I wanna go swimming~ 🏖️', 'Total summer weather! ☀️', 'Floating on my tube~ 🛟',
     'I want ice cream 🍦', 'Watermelon, anyone? 🍉', "Don't forget sunscreen~ 🧴",
     'I miss the beach 🌊', "Stay hydrated, it's hot! 💧"];

export const springMessages = isKorean
  ? ['벚꽃이 예쁘다~ 🌸', '봄바람 살랑살랑~ 🍃', '꽃놀이 가고 싶다!',
     '새싹이 쏙 돋았어 🌱', '봄이라 그런가 나른해~', '꽃가루 조심해! 🤧']
  : ['Cherry blossoms are pretty~ 🌸', 'Spring breeze~ 🍃', "Let's go see the flowers!",
     'A little sprout popped up 🌱', 'Spring makes me sleepy~', 'Watch out for pollen! 🤧'];

// MARK: - Model reactions

export function modelReactions(name: string): string[] {
  return isKorean
    ? [
        `난 ${name}이야, 최고지!`,
        `난 ${name}! 멋지지?`,
        `난 ${name}, 잘 부탁해!`,
        `${name} 등장! 반가워~`,
        `난 ${name}이야, 믿고 맡겨!`,
      ]
    : [
        `I'm ${name}, the best!`,
        `I'm ${name}! Cool right?`,
        `I'm ${name}, nice to meet you!`,
        `${name} is here!`,
        `I'm ${name}, trust me!`,
      ];
}

// MARK: - Token milestones

export const tokenMilestones: [number, string][] = isKorean
  ? [
      [10,   '오늘 10K 토큰 사용!'],
      [50,   '오늘 50K 돌파!'],
      [100,  '오늘 100K! 열심히 일하는 중!'],
      [200,  '오늘 200K...많이 썼다!'],
      [500,  '오늘 500K!! 대작업이었구나!'],
      [1000, '오늘 1M!!! 역대급이야!'],
    ]
  : [
      [10,   '10K tokens today!'],
      [50,   '50K reached!'],
      [100,  '100K! Working hard!'],
      [200,  "200K... that's a lot!"],
      [500,  '500K!! Big project!'],
      [1000, "1M!!! That's legendary!"],
    ];

// MARK: - Desktop time alerts

export function desktopTimeAlert(mins: number): string[] {
  return isKorean
    ? [`${mins}분 지났어!`, `${mins}분이야! 스트레칭 어때?`, `벌써 ${mins}분! 물 한잔 마셔!`]
    : [`${mins} min passed!`, `${mins} min! How about a stretch?`, `${mins} min already! Drink some water!`];
}

// MARK: - Skin names

export const skinBasic  = isKorean ? '기본' : 'Basic';
export const skinSpring = isKorean ? '봄 에디션 🌸' : 'Spring 🌸';
export const skinSummer = isKorean ? '여름 에디션 🍉' : 'Summer 🍉';
export const skinChanged = (skin: 'basic' | 'spring' | 'summer'): string => {
  switch (skin) {
    case 'spring': return isKorean ? '봄이 왔어! 🌸' : 'Spring is here! 🌸';
    case 'summer': return isKorean ? '여름이다! 물놀이 가자~ 🍉' : "Summer time! Let's splash~ 🍉";
    default:       return isKorean ? '기본 스킨으로 돌아왔어!' : 'Back to default skin!';
  }
};

// MARK: - Menu labels

export const menuWorking    = isKorean ? '🔵 작업 중'   : '🔵 Working';
export const menuPermission = isKorean ? '🟡 권한 대기' : '🟡 Permission';
export const menuIdle       = isKorean ? '🟢 대기 중'   : '🟢 Idle';
export const menuOff        = isKorean ? '⚫ 꺼짐'      : '⚫ Off';
export const menuWorkTime   = isKorean ? '작업시간 표시' : 'Show work time';
export const menuSkin       = isKorean ? '스킨'         : 'Skins';
export const menuUpdate     = isKorean ? '업데이트!'    : 'Update!';
export const menuQuit       = isKorean ? '종료'         : 'Quit';
export const menuTodayWork  = (time: string): string =>
  isKorean ? `📊 오늘 총 작업: ${time}` : `📊 Today: ${time}`;
export const menuSessionWork = (sessionTime: string, workTime: string): string =>
  isKorean
    ? `📊 세션 ${sessionTime} (작업 ${workTime})`
    : `📊 Session ${sessionTime} (work ${workTime})`;
export const menuTokenSession = (total: string, inp: string, out: string): string =>
  isKorean
    ? `🪙 세션: ${total} (입력 ${inp} / 출력 ${out})`
    : `🪙 Session: ${total} (in ${inp} / out ${out})`;
export const menuTokenToday = (total: string, cacheRate: number): string =>
  isKorean
    ? `🪙 오늘 총: ${total} (캐시 ${cacheRate}%)`
    : `🪙 Today total: ${total} (cache ${cacheRate}%)`;
export const menuNoSessions = isKorean ? '세션 없음' : 'No sessions';
export const menuAutoLaunch = isKorean ? 'PC 시작 시 자동 실행' : 'Launch at startup';
export const autoLaunchOn   = isKorean ? '이제 PC 켤 때마다 나타날게! 🚀' : "I'll appear every time you boot! 🚀";
export const autoLaunchOff  = isKorean ? '자동 실행 꺼졌어~ 다음엔 직접 켜줘!' : 'Auto-launch off~ Start me manually next time!';

// MARK: - Update messages

export const updateAvailable = (ver: string): string =>
  isKorean ? `새 버전 v${ver} 나왔어! 우클릭→업데이트!` : `New v${ver} available! Right-click→Update!`;
export const updateLatest = (ver: string): string =>
  isKorean ? `최신 버전이에요! (v${ver})` : `You're up to date! (v${ver})`;
export const updateStarted  = isKorean ? '업데이트 시작! 터미널을 확인해줘!' : 'Updating! Check terminal!';
export const updateChecking = isKorean ? '업데이트 확인 중...' : 'Checking updates...';
export const updateFailed   = isKorean ? '업데이트 확인 실패' : 'Update check failed';

// MARK: - Hook setup dialog strings

export const hookDialogTitle   = isKorean ? 'Claude Code 연동'  : 'Claude Code Integration';
export const hookDialogMessage = isKorean ? 'Claude Code 연동'  : 'Claude Code Integration';
export const hookDialogDetail  = isKorean
  ? 'Claude Code와 연동하면 작업 상태를 실시간으로 알려줘요!\n\n- 작업 시작/완료 알림\n- 권한 요청 알림\n- 세션별 상태 표시\n\n연동하시겠습니까?'
  : 'Link with Claude Code to get real-time status updates!\n\n- Work start/done notifications\n- Permission request alerts\n- Per-session status display\n\nWould you like to integrate?';
export const hookDialogConfirm = isKorean ? '연동하기' : 'Integrate';
export const hookDialogLater   = isKorean ? '나중에'   : 'Later';
export const hookSuccessTitle  = isKorean ? '연동 완료' : 'Integration complete';
export const hookSuccessMsg    = isKorean ? '연동 완료!' : 'Integration complete!';
export const hookSuccessDetail = isKorean
  ? 'Claude Code와 연동되었습니다.\nClaude Code를 새로 시작하면 적용됩니다.'
  : 'Claude Code has been integrated.\nRestart Claude Code to apply.';
export const hookFailTitle  = isKorean ? '연동 실패' : 'Integration failed';
export const hookFailMsg    = isKorean ? '연동 실패' : 'Integration failed';
export const hookFailDetail = isKorean
  ? 'Hook 설정 중 문제가 발생했습니다.'
  : 'A problem occurred while setting up hooks.';
export const hookDialogOk = isKorean ? '확인' : 'OK';
