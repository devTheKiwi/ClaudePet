/**
 * Electron main 진입점.
 * main.swift 에 해당.
 */

import { app } from 'electron';
import { App } from './app';
import { log, installCrashHandlers } from './logger';

installCrashHandlers();

// 단일 인스턴스 강제 (펫이 두 개 뜨면 안 됨)
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.whenReady().then(async () => {
    try {
      const application = new App();
      await application.start();
    } catch (err) {
      log.error('App.start() failed:', err);
    }

    // macOS 와 달리 Windows 에선 모든 윈도우 닫혀도 종료하지 않음
    app.on('window-all-closed', (e: Event) => {
      e.preventDefault();
    });
  });
}
