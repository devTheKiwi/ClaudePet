/**
 * 트레이 아이콘 PNG 동적 생성기.
 * 별도 이미지 파일 없이 코드에서 PNG 바이트를 직접 만든다.
 */

import * as zlib from 'zlib';

function crc32Table(): number[] {
  const table: number[] = [];
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    table[i] = c >>> 0;
  }
  return table;
}

const CRC_TABLE = crc32Table();

function crc32(buf: Buffer): number {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) {
    crc = (crc >>> 8) ^ CRC_TABLE[(crc ^ buf[i]) & 0xFF];
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

function makeChunk(type: string, data: Buffer): Buffer {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const typeBuffer = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 0);
  return Buffer.concat([length, typeBuffer, data, crc]);
}

/**
 * size x size 짜리 RGBA PNG 생성.
 * 픽셀 함수가 [r,g,b,a] 를 반환.
 */
export function generatePng(
  size: number,
  pixelFn: (x: number, y: number) => [number, number, number, number]
): Buffer {
  // 각 행 시작에 filter byte (0) 가 필요
  const stride = size * 4;
  const filteredData = Buffer.alloc(size * (stride + 1));
  for (let y = 0; y < size; y++) {
    filteredData[y * (stride + 1)] = 0;
    for (let x = 0; x < size; x++) {
      const [r, g, b, a] = pixelFn(x, y);
      const off = y * (stride + 1) + 1 + x * 4;
      filteredData[off + 0] = r;
      filteredData[off + 1] = g;
      filteredData[off + 2] = b;
      filteredData[off + 3] = a;
    }
  }

  const idat = zlib.deflateSync(filteredData);

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;  // bit depth
  ihdr[9] = 6;  // color type RGBA
  ihdr[10] = 0; // compression
  ihdr[11] = 0; // filter
  ihdr[12] = 0; // interlace

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    makeChunk('IHDR', ihdr),
    makeChunk('IDAT', idat),
    makeChunk('IEND', Buffer.alloc(0)),
  ]);
}

/**
 * Claude Pet 트레이 아이콘 — 32x32 오렌지 원에 눈알 두 개.
 *
 * 단순한 디자인이 트레이 같은 작은 영역에서 인식성이 좋다.
 * Super-sampling (4x4) 안티앨리어싱으로 부드러운 가장자리 처리.
 */
export function generateTrayIconPng(): Buffer {
  const size = 32;
  const cx = (size - 1) / 2;
  const cy = (size - 1) / 2;
  const bodyR = 14.5;          // 큰 원 반지름

  // 눈 (흰자 + 동공)
  const eyeOffsetX = 5.0;       // 중앙에서 좌우 거리
  const eyeOffsetY = -1.5;      // 약간 위쪽
  const eyeWhiteR = 3.6;
  const pupilR = 1.7;
  const pupilDx = 0.4;          // 동공이 살짝 오른쪽 보는 느낌

  // 색상
  const ORANGE: [number, number, number] = [217, 120, 87];   // Claude orange
  const ORANGE_DARK: [number, number, number] = [184, 97, 66]; // 가장자리 약간 진하게
  const WHITE: [number, number, number] = [255, 255, 255];
  const PUPIL: [number, number, number] = [38, 38, 38];

  // 한 픽셀 안의 색을 결정하는 함수 (sub-pixel float 좌표)
  const pixel = (fx: number, fy: number): [number, number, number, number] => {
    const dx = fx - cx;
    const dy = fy - cy;
    const dist = Math.sqrt(dx * dx + dy * dy);

    // 원 바깥은 transparent
    if (dist > bodyR) return [0, 0, 0, 0];

    // 눈 (왼쪽)
    const lEye = eyeDistance(fx, fy, cx - eyeOffsetX, cy + eyeOffsetY);
    if (lEye < pupilR) {
      // 동공 (살짝 오른쪽)
      const pdx = fx - (cx - eyeOffsetX + pupilDx);
      const pdy = fy - (cy + eyeOffsetY);
      if (Math.sqrt(pdx * pdx + pdy * pdy) < pupilR) return [...PUPIL, 255];
    }
    if (lEye < eyeWhiteR) return [...WHITE, 255];

    // 눈 (오른쪽)
    const rEye = eyeDistance(fx, fy, cx + eyeOffsetX, cy + eyeOffsetY);
    if (rEye < pupilR) {
      const pdx = fx - (cx + eyeOffsetX + pupilDx);
      const pdy = fy - (cy + eyeOffsetY);
      if (Math.sqrt(pdx * pdx + pdy * pdy) < pupilR) return [...PUPIL, 255];
    }
    if (rEye < eyeWhiteR) return [...WHITE, 255];

    // 몸 — 가장자리에 살짝 그라데이션 (입체감)
    const t = dist / bodyR; // 0 (중심) ~ 1 (가장자리)
    const r = ORANGE[0] * (1 - t * 0.15) + ORANGE_DARK[0] * (t * 0.15);
    const g = ORANGE[1] * (1 - t * 0.15) + ORANGE_DARK[1] * (t * 0.15);
    const b = ORANGE[2] * (1 - t * 0.15) + ORANGE_DARK[2] * (t * 0.15);
    return [Math.round(r), Math.round(g), Math.round(b), 255];
  };

  // Super-sampling 4x4 — 픽셀당 16개 샘플 평균
  return generatePng(size, (x, y) => sampleAA(x, y, pixel));
}

/** 4x4 super-sampling 안티앨리어싱 */
function sampleAA(
  x: number,
  y: number,
  fn: (fx: number, fy: number) => [number, number, number, number]
): [number, number, number, number] {
  const N = 4;
  let r = 0, g = 0, b = 0, a = 0;
  for (let sy = 0; sy < N; sy++) {
    for (let sx = 0; sx < N; sx++) {
      const fx = x + (sx + 0.5) / N;
      const fy = y + (sy + 0.5) / N;
      const [pr, pg, pb, pa] = fn(fx, fy);
      // premultiplied alpha 로 합산
      const af = pa / 255;
      r += pr * af;
      g += pg * af;
      b += pb * af;
      a += pa;
    }
  }
  const total = N * N;
  const finalA = a / total;
  if (finalA < 1) return [0, 0, 0, 0];
  // un-premultiply
  const af = finalA / 255;
  return [
    Math.round(r / total / af),
    Math.round(g / total / af),
    Math.round(b / total / af),
    Math.round(finalA),
  ];
}

function eyeDistance(fx: number, fy: number, ex: number, ey: number): number {
  const dx = fx - ex;
  const dy = fy - ey;
  return Math.sqrt(dx * dx + dy * dy);
}

/**
 * 앱 인스톨러 / 시작메뉴 / 작업표시줄용 큰 아이콘 (256x256).
 * 트레이 아이콘과 동일한 디자인을 비례 확대.
 */
export function generateAppIconPng(): Buffer {
  const size = 256;
  const cx = (size - 1) / 2;
  const cy = (size - 1) / 2;
  const bodyR = size * 0.45;

  const eyeOffsetX = size * 0.156;
  const eyeOffsetY = -size * 0.047;
  const eyeWhiteR = size * 0.1125;
  const pupilR = size * 0.053;
  const pupilDx = size * 0.0125;

  const ORANGE: [number, number, number] = [217, 120, 87];
  const ORANGE_DARK: [number, number, number] = [184, 97, 66];
  const WHITE: [number, number, number] = [255, 255, 255];
  const PUPIL: [number, number, number] = [38, 38, 38];

  const pixel = (fx: number, fy: number): [number, number, number, number] => {
    const dx = fx - cx;
    const dy = fy - cy;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > bodyR) return [0, 0, 0, 0];

    const lEye = eyeDistance(fx, fy, cx - eyeOffsetX, cy + eyeOffsetY);
    if (lEye < pupilR) {
      const pdx = fx - (cx - eyeOffsetX + pupilDx);
      const pdy = fy - (cy + eyeOffsetY);
      if (Math.sqrt(pdx * pdx + pdy * pdy) < pupilR) return [...PUPIL, 255];
    }
    if (lEye < eyeWhiteR) return [...WHITE, 255];

    const rEye = eyeDistance(fx, fy, cx + eyeOffsetX, cy + eyeOffsetY);
    if (rEye < pupilR) {
      const pdx = fx - (cx + eyeOffsetX + pupilDx);
      const pdy = fy - (cy + eyeOffsetY);
      if (Math.sqrt(pdx * pdx + pdy * pdy) < pupilR) return [...PUPIL, 255];
    }
    if (rEye < eyeWhiteR) return [...WHITE, 255];

    const t = dist / bodyR;
    const r = ORANGE[0] * (1 - t * 0.15) + ORANGE_DARK[0] * (t * 0.15);
    const g = ORANGE[1] * (1 - t * 0.15) + ORANGE_DARK[1] * (t * 0.15);
    const b = ORANGE[2] * (1 - t * 0.15) + ORANGE_DARK[2] * (t * 0.15);
    return [Math.round(r), Math.round(g), Math.round(b), 255];
  };

  return generatePng(size, (x, y) => sampleAA(x, y, pixel));
}
