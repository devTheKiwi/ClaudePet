import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('bubbleBridge', {
  onShow: (cb: (data: { text: string; skin: 'basic' | 'spring' }) => void) => {
    ipcRenderer.on('bubble:show', (_e, data) => cb(data));
  },
});
