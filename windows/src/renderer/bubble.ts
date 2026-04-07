// 모듈화
export {};

/**
 * Speech bubble renderer — SpeechBubble.swift SpeechBubbleView.draw() 포팅
 */

type PetSkin = 'basic' | 'spring';

declare global {
  interface Window {
    bubbleBridge: {
      onShow: (cb: (data: { text: string; skin: PetSkin }) => void) => void;
    };
  }
}

const canvas = document.getElementById('bg') as HTMLCanvasElement;
const textEl = document.getElementById('text') as HTMLDivElement;
const ctx = canvas.getContext('2d')!;

let currentSkin: PetSkin = 'basic';

function resize(): void {
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
  draw();
}

window.addEventListener('resize', resize);

if (window.bubbleBridge) {
  window.bubbleBridge.onShow(({ text, skin }) => {
    currentSkin = skin;
    textEl.textContent = text;
    resize();
  });
}

function draw(): void {
  const w = canvas.width;
  const h = canvas.height;
  ctx.clearRect(0, 0, w, h);

  const tailHeight = 8;
  const bubbleRect = {
    x: 2,
    y: 2,
    w: w - 4,
    h: h - tailHeight - 4,
  };

  // 색상
  let bgColor: string;
  let borderColor: string;
  let tailColor: string;

  if (currentSkin === 'spring') {
    bgColor = 'rgb(255, 242, 245)';
    borderColor = 'rgb(242, 191, 204)';
    tailColor = bgColor;
  } else {
    bgColor = 'rgb(255, 255, 255)';
    borderColor = 'rgb(217, 217, 217)';
    tailColor = 'rgb(255, 255, 255)';
  }

  // 그림자
  ctx.fillStyle = 'rgba(0, 0, 0, 0.12)';
  roundedRectPath(bubbleRect.x, bubbleRect.y + 1, bubbleRect.w, bubbleRect.h, 12);
  ctx.fill();

  // 배경
  ctx.fillStyle = bgColor;
  roundedRectPath(bubbleRect.x, bubbleRect.y, bubbleRect.w, bubbleRect.h, 12);
  ctx.fill();

  // 테두리
  ctx.strokeStyle = borderColor;
  ctx.lineWidth = 1;
  ctx.stroke();

  // 꼬리 (삼각형) — 말풍선 아래쪽 중앙
  const tailCenterX = w / 2;
  const tailY = bubbleRect.y + bubbleRect.h;
  ctx.fillStyle = tailColor;
  ctx.beginPath();
  ctx.moveTo(tailCenterX - 6, tailY - 1);
  ctx.lineTo(tailCenterX, tailY + tailHeight);
  ctx.lineTo(tailCenterX + 6, tailY - 1);
  ctx.closePath();
  ctx.fill();

  // 꼬리 테두리 (양쪽 선만)
  ctx.strokeStyle = borderColor;
  ctx.beginPath();
  ctx.moveTo(tailCenterX - 6, tailY - 1);
  ctx.lineTo(tailCenterX, tailY + tailHeight);
  ctx.lineTo(tailCenterX + 6, tailY - 1);
  ctx.lineWidth = 1;
  ctx.stroke();
}

function roundedRectPath(x: number, y: number, w: number, h: number, r: number): void {
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
}

resize();
