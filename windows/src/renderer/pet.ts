// 모듈화 (declare global 사용 위해 ES 모듈로 만듦)
export {};

/**
 * Pet renderer — PetWindow.swift PetView.draw() 의 1:1 포팅
 *
 * 좌표계 주의:
 *   macOS Cocoa: y축이 위로 증가 (origin = bottom-left)
 *   HTML Canvas: y축이 아래로 증가 (origin = top-left)
 *
 * 해결: ctx.translate(0, height) + ctx.scale(1, -1) 로 좌표계를 뒤집어서
 *      Swift draw() 코드의 좌표/수식을 그대로 사용 가능하게 만든다.
 *      텍스트만 별도 처리 (그렇지 않으면 거꾸로 출력됨).
 */

// ===== Types =====

type PetState = 'idle' | 'walkingLeft' | 'walkingRight' | 'jumping' | 'happy' | 'excited';
type ClaudeStatus = 'notRunning' | 'idle' | 'working' | 'waitingForPermission';
type PetMode = 'code' | 'desktop';
type PetSkin = 'basic' | 'spring';

interface PetColor {
  body: string;
  bodyDark: string;
  foot: string;
}

interface Petal {
  x: number;
  y: number;
  size: number;
  speed: number;
  swayPhase: number;
  rotation: number;
  alpha: number;
}

// ===== Color Palette (PetWindow.swift PetColor.palette 와 동일) =====

const PALETTE: PetColor[] = [
  // Claude orange
  { body: 'rgb(217, 120, 87)',  bodyDark: 'rgb(184, 97, 66)',  foot: 'rgb(166, 84, 56)' },
  // Blue
  { body: 'rgb(97, 148, 217)',  bodyDark: 'rgb(71, 115, 184)', foot: 'rgb(56, 97, 158)' },
  // Green
  { body: 'rgb(102, 191, 115)', bodyDark: 'rgb(77, 153, 89)',  foot: 'rgb(61, 128, 71)' },
  // Purple
  { body: 'rgb(166, 115, 209)', bodyDark: 'rgb(133, 87, 173)', foot: 'rgb(107, 71, 148)' },
  // Pink
  { body: 'rgb(217, 107, 148)', bodyDark: 'rgb(184, 82, 117)', foot: 'rgb(153, 66, 97)' },
  // Teal
  { body: 'rgb(82, 184, 179)',  bodyDark: 'rgb(61, 148, 143)', foot: 'rgb(46, 122, 117)' },
];

const EYE_WHITE = 'rgb(255, 255, 255)';
const PUPIL_COLOR = 'rgb(38, 38, 38)';

// ===== State =====

const canvas = document.getElementById('pet') as HTMLCanvasElement;
const ctx = canvas.getContext('2d')!;
const W = canvas.width;
const H = canvas.height;

let colorIndex = 0;
let color: PetColor = PALETTE[0];
let state: PetState = 'idle';
let claudeStatus: ClaudeStatus = 'notRunning';
let petMode: PetMode = 'code';
let skin: PetSkin = 'basic';
let workingSeconds = 0;
let showTimer = true;
let animationFrame = 0;

// 봄 에디션 파티클
const petals: Petal[] = [];
const MAX_PETALS = 8;

// 행동 타이머
let behaviorTimeoutId: number | null = null;
let stateTimeoutId: number | null = null;
const SPEED = 1.5;

// ===== IPC bridge (preload 에서 노출) =====

declare global {
  interface Window {
    petBridge: {
      onState: (cb: (data: PetStateUpdate) => void) => void;
      onSetState: (cb: (newState: PetState) => void) => void;
      moveBy: (dx: number) => void;
      dragBy: (dx: number, dy: number) => void;
      dragEnd: () => void;
      onClick: () => void;
      onDoubleClick: () => void;
      onRightClick: (x: number, y: number) => void;
    };
  }
}

interface PetStateUpdate {
  colorIndex?: number;
  claudeStatus?: ClaudeStatus;
  petMode?: PetMode;
  skin?: PetSkin;
  workingSeconds?: number;
  showTimer?: boolean;
}

if (window.petBridge) {
  window.petBridge.onState((data) => {
    if (data.colorIndex !== undefined) {
      colorIndex = data.colorIndex;
      color = PALETTE[colorIndex] || PALETTE[0];
    }
    if (data.claudeStatus !== undefined) claudeStatus = data.claudeStatus;
    if (data.petMode !== undefined) petMode = data.petMode;
    if (data.skin !== undefined) skin = data.skin;
    if (data.workingSeconds !== undefined) workingSeconds = data.workingSeconds;
    if (data.showTimer !== undefined) showTimer = data.showTimer;
  });

  window.petBridge.onSetState((newState) => {
    setPetState(newState);
  });
}

// ===== Mouse Events =====
//
// 클릭과 드래그를 임계값으로 구분:
//   - mousedown 시 시작점 기록
//   - mousemove 누적 거리 > DRAG_THRESHOLD 이면 드래그 모드로 전환
//   - mouseup 시 드래그 모드면 클릭 무시, 아니면 single/double 클릭 처리

let lastClickTime = 0;
let mouseDownAt = 0;
let isDragging = false;
let dragAccumDx = 0;
let dragAccumDy = 0;
const DRAG_THRESHOLD = 4;

canvas.addEventListener('mousedown', (e) => {
  if (e.button === 2) {
    // 우클릭
    window.petBridge?.onRightClick(e.screenX, e.screenY);
    return;
  }
  if (e.button === 0) {
    mouseDownAt = Date.now();
    isDragging = false;
    dragAccumDx = 0;
    dragAccumDy = 0;
  }
});

canvas.addEventListener('mousemove', (e) => {
  if (mouseDownAt === 0) return;
  // movementX/Y 는 마지막 mousemove 이후 이동량
  dragAccumDx += e.movementX;
  dragAccumDy += e.movementY;
  if (!isDragging && Math.abs(dragAccumDx) + Math.abs(dragAccumDy) > DRAG_THRESHOLD) {
    isDragging = true;
  }
  if (isDragging) {
    window.petBridge?.dragBy(e.movementX, e.movementY);
  }
});

window.addEventListener('mouseup', (e) => {
  if (mouseDownAt === 0) return;
  if (e.button !== 0) {
    mouseDownAt = 0;
    return;
  }

  if (isDragging) {
    // 드래그 종료 — 클릭 처리 안 함
    window.petBridge?.dragEnd();
  } else {
    // 클릭/더블클릭 처리
    const now = Date.now();
    if (now - lastClickTime < 300) {
      window.petBridge?.onDoubleClick();
      lastClickTime = 0;
    } else {
      window.petBridge?.onClick();
      lastClickTime = now;
    }
  }

  mouseDownAt = 0;
  isDragging = false;
});

canvas.addEventListener('contextmenu', (e) => e.preventDefault());

// ===== Behavior Logic (PetView 행동 로직 포팅) =====

function setPetState(newState: PetState): void {
  state = newState;
  if (stateTimeoutId !== null) {
    clearTimeout(stateTimeoutId);
    stateTimeoutId = null;
  }

  if (newState === 'jumping' || newState === 'happy' || newState === 'excited') {
    stateTimeoutId = window.setTimeout(() => {
      scheduleBehavior();
    }, 3000);
  }
}

function scheduleBehavior(): void {
  if (behaviorTimeoutId !== null) clearTimeout(behaviorTimeoutId);
  const delay = 2000 + Math.random() * 3000; // 2~5초
  behaviorTimeoutId = window.setTimeout(pickRandomBehavior, delay);
}

function pickRandomBehavior(): void {
  const roll = Math.floor(Math.random() * 11);
  if (roll < 4) {
    state = 'idle';
  } else if (roll < 7) {
    state = 'walkingRight';
  } else {
    state = 'walkingLeft';
  }

  const duration = 3000 + Math.random() * 5000; // 3~8초
  if (behaviorTimeoutId !== null) clearTimeout(behaviorTimeoutId);
  behaviorTimeoutId = window.setTimeout(pickRandomBehavior, duration);
}

// ===== Animation Loop (15 FPS, Swift 와 동일) =====

setInterval(tick, 1000 / 15);
scheduleBehavior();

function tick(): void {
  animationFrame++;

  if (state === 'walkingLeft') {
    window.petBridge?.moveBy(-SPEED);
  } else if (state === 'walkingRight') {
    window.petBridge?.moveBy(SPEED);
  }

  draw();
}

// ===== Drawing (PetView.draw 1:1 포팅) =====

function draw(): void {
  // Clear
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, W, H);
  ctx.restore();

  // Cocoa 좌표계로 뒤집기 (origin = bottom-left, y축 위로)
  ctx.save();
  ctx.translate(0, H);
  ctx.scale(1, -1);

  const centerX = W / 2;
  const baseY = 4;

  let bounceY: number;
  let footOffset: number;

  switch (state) {
    case 'idle':
      bounceY = Math.sin(animationFrame * 0.2) * 2;
      footOffset = 0;
      break;
    case 'walkingLeft':
    case 'walkingRight':
      bounceY = Math.abs(Math.sin(animationFrame * 0.3)) * 3;
      footOffset = Math.sin(animationFrame * 0.6) * 3;
      break;
    case 'jumping': {
      const jumpPhase = (animationFrame % 30) / 30.0;
      bounceY = Math.sin(jumpPhase * Math.PI) * 15;
      footOffset = 0;
      break;
    }
    case 'happy':
      bounceY = Math.abs(Math.sin(animationFrame * 0.4)) * 5;
      footOffset = Math.sin(animationFrame * 0.8) * 2;
      break;
    case 'excited':
      bounceY = Math.sin(animationFrame * 0.5) * 3;
      footOffset = Math.cos(animationFrame * 0.5) * 2;
      break;
  }

  const bodyY = baseY + 10 + bounceY;

  // === 발 ===
  ctx.fillStyle = color.foot;
  const leftFootX = centerX - 14 + footOffset;
  const rightFootX = centerX + 6 - footOffset;
  const footY = baseY + bounceY;

  fillRoundRect(leftFootX, footY, 8, 10, 3);
  fillRoundRect(rightFootX, footY, 8, 10, 3);

  // === 몸통 ===
  ctx.fillStyle = color.body;
  const bodyWidth = 40;
  const bodyHeight = 30;
  const bodyX = centerX - bodyWidth / 2;
  fillRoundRect(bodyX, bodyY, bodyWidth, bodyHeight, 13); // 14x12 평균

  // === 머리 ===
  const headWidth = 32;
  const headHeight = 18;
  const headX = centerX - headWidth / 2;
  const headY = bodyY + bodyHeight - 14;
  fillRoundRect(headX, headY, headWidth, headHeight, 11);

  // === 눈 ===
  const eyeY = bodyY + bodyHeight - 6;
  const leftEyeX = centerX - 9;
  const rightEyeX = centerX + 3;

  ctx.fillStyle = EYE_WHITE;
  fillEllipse(leftEyeX, eyeY, 7, 8);
  fillEllipse(rightEyeX, eyeY, 7, 8);

  // 동공
  ctx.fillStyle = PUPIL_COLOR;
  let pupilDx = 0;
  if (state === 'walkingLeft') pupilDx = -1.5;
  else if (state === 'walkingRight') pupilDx = 1.5;
  else pupilDx = Math.sin(animationFrame * 0.1) * 1;

  fillEllipse(leftEyeX + 2 + pupilDx, eyeY + 2.5, 3.5, 3.5);
  fillEllipse(rightEyeX + 2 + pupilDx, eyeY + 2.5, 3.5, 3.5);

  // === 작업 중 이펙트 ===
  if (claudeStatus === 'working') {
    drawWorkingEffect(centerX, bodyY + bodyHeight + headHeight - 10);
  }

  // === Desktop 모드: 커피잔 ===
  if (petMode === 'desktop') {
    drawCoffee(centerX, bodyY, bounceY);
  }

  // === 봄 스킨 악세서리 ===
  if (skin === 'spring') {
    drawSpringAccessory(centerX, headY + headHeight, bounceY);
    updateAndDrawPetals();
  }

  ctx.restore();

  // === 시간 뱃지 (텍스트라 변환 안 한 상태에서 그림) ===
  if (showTimer && workingSeconds > 0) {
    drawTimeBadge(bodyX, headY + headHeight, bounceY);
  }
}

// ===== Helper: rounded rect / ellipse =====

function fillRoundRect(x: number, y: number, w: number, h: number, r: number): void {
  ctx.beginPath();
  // Canvas roundRect 는 좌표 변환 후에도 동작
  if (typeof (ctx as any).roundRect === 'function') {
    (ctx as any).roundRect(x, y, w, h, r);
  } else {
    // Fallback (구형 브라우저)
    const rr = Math.min(r, w / 2, h / 2);
    ctx.moveTo(x + rr, y);
    ctx.lineTo(x + w - rr, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
    ctx.lineTo(x + w, y + h - rr);
    ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
    ctx.lineTo(x + rr, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - rr);
    ctx.lineTo(x, y + rr);
    ctx.quadraticCurveTo(x, y, x + rr, y);
    ctx.closePath();
  }
  ctx.fill();
}

function strokeRoundRect(x: number, y: number, w: number, h: number, r: number, lineWidth: number): void {
  ctx.beginPath();
  if (typeof (ctx as any).roundRect === 'function') {
    (ctx as any).roundRect(x, y, w, h, r);
  } else {
    const rr = Math.min(r, w / 2, h / 2);
    ctx.moveTo(x + rr, y);
    ctx.lineTo(x + w - rr, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
    ctx.lineTo(x + w, y + h - rr);
    ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
    ctx.lineTo(x + rr, y + h);
    ctx.quadraticCurveTo(x, y + h, x, y + h - rr);
    ctx.lineTo(x, y + rr);
    ctx.quadraticCurveTo(x, y, x + rr, y);
    ctx.closePath();
  }
  ctx.lineWidth = lineWidth;
  ctx.stroke();
}

function fillEllipse(x: number, y: number, w: number, h: number): void {
  ctx.beginPath();
  ctx.ellipse(x + w / 2, y + h / 2, w / 2, h / 2, 0, 0, Math.PI * 2);
  ctx.fill();
}

// ===== Effects =====

function drawWorkingEffect(centerX: number, topY: number): void {
  ctx.fillStyle = 'rgba(255, 217, 77, 0.8)';
  const phase = animationFrame * 0.15;
  for (let i = 0; i < 3; i++) {
    const angle = phase + i * (2 * Math.PI / 3);
    const radius = 6;
    const x = centerX + Math.cos(angle) * radius - 1.5;
    const y = topY + 8 + Math.sin(angle) * radius - 1.5;
    fillEllipse(x, y, 3, 3);
  }
}

// ===== Coffee (Desktop 모드) =====

function drawCoffee(centerX: number, bodyY: number, _bounceY: number): void {
  const cupX = centerX + 16;
  const cupY = bodyY + 6;

  // 컵 몸통
  ctx.fillStyle = 'rgb(140, 89, 51)';
  fillRoundRect(cupX, cupY, 9, 10, 2);

  // 컵 안쪽 커피
  ctx.fillStyle = 'rgb(89, 51, 26)';
  fillRoundRect(cupX + 1.5, cupY + 6, 6, 3, 1);

  // 컵 손잡이 (베지어)
  ctx.strokeStyle = 'rgb(140, 89, 51)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(cupX + 9, cupY + 7);
  ctx.bezierCurveTo(cupX + 13, cupY + 7, cupX + 13, cupY + 3, cupX + 9, cupY + 3);
  ctx.stroke();

  // 김 (애니메이션)
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.6)';
  for (let i = 0; i < 2; i++) {
    const sx = cupX + 3 + i * 4;
    const sy = cupY + 11;
    const phase = animationFrame * 0.12 + i * 1.5;
    ctx.beginPath();
    ctx.moveTo(sx, sy);
    ctx.bezierCurveTo(
      sx + Math.sin(phase) * 3, sy + 2,
      sx - Math.sin(phase) * 3, sy + 5,
      sx + Math.sin(phase) * 2, sy + 7
    );
    ctx.lineWidth = 1.0;
    ctx.stroke();
  }
}

// ===== Spring Skin =====

function drawSpringAccessory(centerX: number, headTopY: number, _bounceY: number): void {
  const flowerX = centerX + 8;
  const flowerY = headTopY + 6;

  // 꽃잎 5장
  ctx.fillStyle = 'rgba(255, 179, 199, 0.95)';
  const petalSize = 4.5;
  for (let i = 0; i < 5; i++) {
    const angle = (i * 72.0 + animationFrame * 0.5) * Math.PI / 180.0;
    const px = flowerX + Math.cos(angle) * 3.5 - petalSize / 2;
    const py = flowerY + Math.sin(angle) * 3.5 - petalSize / 2;
    fillEllipse(px, py, petalSize, petalSize);
  }

  // 꽃 중심 (노랑)
  ctx.fillStyle = 'rgb(255, 230, 102)';
  fillEllipse(flowerX - 2.5, flowerY - 2.5, 5, 5);

  // 줄기 (초록)
  ctx.strokeStyle = 'rgb(102, 179, 89)';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(flowerX, flowerY - 3);
  ctx.lineTo(flowerX + 1, flowerY - 8);
  ctx.stroke();
}

function updateAndDrawPetals(): void {
  // 새 꽃잎 추가
  if (petals.length < MAX_PETALS && animationFrame % 12 === 0) {
    petals.push({
      x: -10 + Math.random() * (W + 20),
      y: H + 5,
      size: 2.5 + Math.random() * 2,
      speed: 0.3 + Math.random() * 0.5,
      swayPhase: Math.random() * 2 * Math.PI,
      rotation: Math.random() * 2 * Math.PI,
      alpha: 0.5 + Math.random() * 0.4,
    });
  }

  // 업데이트 + 그리기
  for (let i = petals.length - 1; i >= 0; i--) {
    const p = petals[i];
    p.y -= p.speed;
    p.x += Math.sin(p.swayPhase + p.y * 0.05) * 0.5;
    p.rotation += 0.03;

    if (p.y > -10) {
      ctx.fillStyle = `rgba(255, 191, 209, ${p.alpha})`;
      const px = p.x + Math.sin(p.rotation) * 1.5;
      fillEllipse(px, p.y, p.size, p.size * 0.7);
    } else {
      petals.splice(i, 1);
    }
  }
}

// ===== Time Badge (텍스트, 일반 좌표계로 그림) =====

function drawTimeBadge(bodyX: number, headTopY: number, bounceY: number): void {
  const totalMins = Math.floor(workingSeconds / 60);
  const secs = workingSeconds % 60;
  const timeText = `${String(totalMins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;

  ctx.font = '600 8px -apple-system, "Segoe UI", system-ui, sans-serif';
  const textMetrics = ctx.measureText(timeText);
  const textWidth = textMetrics.width;
  const textHeight = 10;

  const badgeWidth = textWidth + 8;
  const badgeHeight = textHeight + 4;
  // Cocoa coords → canvas coords flip
  const badgeXLogical = bodyX - badgeWidth + 10;
  const badgeYLogical = headTopY + bounceY - 2;
  const badgeXCanvas = badgeXLogical;
  const badgeYCanvas = H - badgeYLogical - badgeHeight;

  // 뱃지 배경
  ctx.fillStyle = skin === 'spring'
    ? 'rgba(255, 237, 242, 0.9)'
    : 'rgba(242, 242, 242, 0.9)';
  ctx.beginPath();
  if (typeof (ctx as any).roundRect === 'function') {
    (ctx as any).roundRect(badgeXCanvas, badgeYCanvas, badgeWidth, badgeHeight, 5);
  } else {
    ctx.rect(badgeXCanvas, badgeYCanvas, badgeWidth, badgeHeight);
  }
  ctx.fill();

  // 테두리
  ctx.strokeStyle = skin === 'spring'
    ? 'rgba(229, 191, 204, 0.7)'
    : 'rgba(204, 204, 204, 0.7)';
  ctx.lineWidth = 0.5;
  ctx.stroke();

  // 텍스트
  ctx.fillStyle = 'rgb(89, 89, 89)';
  ctx.textBaseline = 'top';
  ctx.fillText(timeText, badgeXCanvas + 4, badgeYCanvas + 2);
}
