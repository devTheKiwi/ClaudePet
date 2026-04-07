import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('petBridge', {
  onState: (cb: (data: any) => void) => {
    ipcRenderer.on('pet:state', (_e, data) => cb(data));
  },
  onSetState: (cb: (state: any) => void) => {
    ipcRenderer.on('pet:set-state', (_e, state) => cb(state));
  },
  moveBy: (dx: number) => {
    ipcRenderer.send('pet:move-by', dx);
  },
  dragBy: (dx: number, dy: number) => {
    ipcRenderer.send('pet:drag-by', { dx, dy });
  },
  dragEnd: () => {
    ipcRenderer.send('pet:drag-end');
  },
  onClick: () => ipcRenderer.send('pet:click'),
  onDoubleClick: () => ipcRenderer.send('pet:double-click'),
  onRightClick: (x: number, y: number) => ipcRenderer.send('pet:right-click', { x, y }),
});
