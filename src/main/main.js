const { app, BrowserWindow, dialog, ipcMain, screen, shell, Tray, Menu, nativeImage, globalShortcut, powerMonitor, session } = require('electron');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { pathToFileURL } = require('url');
const { spawn } = require('child_process');
const crypto = require('crypto');
const zlib = require('zlib');
const RFACC_KEY = crypto.createHash('sha256').update('riff-account-key-v1').digest();

function encryptAccount(dataObj) {
  const jsonStr = typeof dataObj === 'string' ? dataObj : JSON.stringify(dataObj);
  const compressed = zlib.deflateRawSync(Buffer.from(jsonStr, 'utf8'));
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', RFACC_KEY, iv);
  const encrypted = Buffer.concat([cipher.update(compressed), cipher.final()]);
  const tag = cipher.getAuthTag();
  const header = Buffer.from('RFAC');
  return Buffer.concat([header, iv, tag, encrypted]);
}

function decryptAccount(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 32) throw new Error('Invalid account file');
  if (buffer.subarray(0, 4).toString('utf8') !== 'RFAC') throw new Error('Invalid file header');
  const iv = buffer.subarray(4, 16);
  const tag = buffer.subarray(16, 32);
  const encrypted = buffer.subarray(32);
  const decipher = crypto.createDecipheriv('aes-256-gcm', RFACC_KEY, iv);
  decipher.setAuthTag(tag);
  const decrypted = Buffer.concat([decipher.update(encrypted), decipher.final()]);
  const decompressed = zlib.inflateRawSync(decrypted);
  return JSON.parse(decompressed.toString('utf8'));
}
const { LIBRARY_DIR, DATA_DIR, resolveBinary, tutorialDone, markTutorialDone, readStartupConfig, writeStartupConfig } = require('../shared/platform');
const { getLauncherInfo, installLauncher } = require('./launcher');
const { getSystemAudioOutputInfo } = require('../shared/audio-output');
const { log, tail, LOG_DIR } = require('../shared/logger');
const logger = { log, tail, LOG_DIR, error: (msg, err) => log('ERROR', `${msg}: ${err && err.message ? err.message : err}`) };

process.on('uncaughtException', (err) => {
  try { logger.error('Uncaught exception in main', err); } catch (_) {}
});
process.on('unhandledRejection', (reason) => {
  try {
    const err = reason instanceof Error ? reason : new Error(String(reason));
    logger.error('Unhandled rejection in main', err);
  } catch (_) {}
});

const enabledFeatures = [];
if (process.platform === 'linux') {
  enabledFeatures.push('WaylandWindowDecorations', 'UseOzonePlatform', 'WaylandFractionalScaleV1', 'MediaSessionService', 'HardwareMediaKeyHandling');
  app.commandLine.appendSwitch('ozone-platform-hint', 'auto');
  app.commandLine.appendSwitch('disable-features', 'Vulkan,AudioServiceOutOfProcess');

  if (process.env.RIFF_SKIP_GPU_BUFFER_FLAGS !== '1') {
    app.commandLine.appendSwitch('disable-gpu-memory-buffer-video-frames');
    app.commandLine.appendSwitch('disable-gpu-memory-buffer-compositor-resources');
  }
}

if (process.platform === 'win32') {
  enabledFeatures.push('HardwareMediaKeyHandling');
  app.commandLine.appendSwitch('disable-features', 'CalculateNativeWinOcclusion');
}

if (enabledFeatures.length > 0) {
  app.commandLine.appendSwitch('enable-features', enabledFeatures.join(','));
}

app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');
app.commandLine.appendSwitch('ignore-gpu-blocklist');
app.commandLine.appendSwitch('enable-gpu-rasterization');
app.commandLine.appendSwitch('enable-zero-copy');
app.commandLine.appendSwitch('renderer-process-limit', '1');
app.commandLine.appendSwitch('disable-component-update');
app.commandLine.appendSwitch('disable-background-networking');
app.commandLine.appendSwitch('disable-domain-reliability');
app.commandLine.appendSwitch('disable-sync');
app.commandLine.appendSwitch('disable-speech-api');
app.commandLine.appendSwitch('js-flags', '--expose-gc');

const extraFlags = (process.env.RIFF_FLAGS || '').split(';').map((s) => s.trim()).filter(Boolean);
for (const flag of extraFlags) {
  const eq = flag.indexOf('=');
  if (eq > 0) app.commandLine.appendSwitch(flag.slice(0, eq), flag.slice(eq + 1));
  else app.commandLine.appendSwitch(flag);
}

if (process.env.RIFF_DEBUG === '1') {
  app.whenReady().then(async () => {
    console.log('[gpu] features', JSON.stringify(app.getGPUFeatureStatus()));
    try {
      console.log('[gpu] info', JSON.stringify(await app.getGPUInfo('basic')));
    } catch (e) {}
    setInterval(() => {
      const rows = app.getAppMetrics().map((m) => `${m.type}:${Math.round(m.cpu.percentCPUUsage)}%`);
      console.log('[cpu]', rows.join('  '));
    }, 5000).unref();
  });
}

if (process.argv.includes('lyrics') || process.argv.includes('--lyrics')) {
  const cliPath = path.join(__dirname, 'cli.js');
  const child = spawn(process.execPath, [cliPath, 'lyrics'], { stdio: 'inherit', env: Object.assign({}, process.env, { ELECTRON_RUN_AS_NODE: '1' }) });
  child.on('exit', (code) => process.exit(code || 0));
} else {
  runGUI();
}

function runGUI() {
  const { startServer, PORT, getServerToken } = require('../server/server');
  const discordRPC = require('./discord');

  let mainWindow = null;
  const allowMulti = !!readStartupConfig().multiInstance;
  const gotLock = app.requestSingleInstanceLock();
  if (!gotLock && !allowMulti) { app.quit(); return; }
  if (!gotLock && allowMulti) app.setPath('userData', `${app.getPath('userData')}-instance-${process.pid}`);
  app.on('second-instance', () => {
    if (allowMulti) return;
    if (mainWindow && !mainWindow.isDestroyed()) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show();
      mainWindow.focus();
    }
  });
  let serverPort = PORT;
  let tray = null;
  let isQuitting = false;
  let trayOnClose = process.platform !== 'linux';
  let isMiniWindow = false;
  let preMiniBounds = null;

  const windowStatePath = path.join(app.getPath('userData'), 'window-state.json');

  const PRIMARY_STORAGE_FILE = path.join(__dirname, '../storage.json');
  const FALLBACK_STORAGE_FILE = path.join(app.getPath('userData'), 'storage.json');

  function getActiveStorageFile() {
    try {
      fs.accessSync(path.dirname(PRIMARY_STORAGE_FILE), fs.constants.W_OK);
      return PRIMARY_STORAGE_FILE;
    } catch (_) {
      return FALLBACK_STORAGE_FILE;
    }
  }

  function readStorageDiskSync() {
    const file = getActiveStorageFile();
    try {
      if (fs.existsSync(file)) {
        const raw = fs.readFileSync(file, 'utf8').trim();
        if (raw) {
          const parsed = JSON.parse(raw);
          if (parsed && typeof parsed === 'object' && Object.keys(parsed).length > 0) return parsed;
        }
      }
    } catch (e) {
      console.warn('[riff] storage.json read warning:', e.message);
    }
    return null;
  }

  function writeStorageDiskSync(data) {
    if (!data || typeof data !== 'object') return;
    const file = getActiveStorageFile();
    const tmpFile = file + '.tmp';
    try {
      fs.writeFileSync(tmpFile, JSON.stringify(data, null, 2), 'utf8');
      fs.renameSync(tmpFile, file);
    } catch (_) {
      try {
        fs.writeFileSync(FALLBACK_STORAGE_FILE, JSON.stringify(data, null, 2), 'utf8');
      } catch (_) {}
    }
  }

  let storageFlushTimer = null;
  let latestStorageSnapshot = null;

  ipcMain.on('storage-get-all-sync', (event) => {
    event.returnValue = latestStorageSnapshot || readStorageDiskSync();
  });

  ipcMain.on('storage-save-batch', (event, data) => {
    if (!data || typeof data !== 'object') return;
    latestStorageSnapshot = data;
    if (storageFlushTimer) clearTimeout(storageFlushTimer);
    storageFlushTimer = setTimeout(() => {
      storageFlushTimer = null;
      writeStorageDiskSync(latestStorageSnapshot);
    }, 250);
  });

  ipcMain.on('storage-save-sync', (event, data) => {
    if (storageFlushTimer) { clearTimeout(storageFlushTimer); storageFlushTimer = null; }
    if (data && typeof data === 'object') {
      latestStorageSnapshot = data;
      writeStorageDiskSync(latestStorageSnapshot);
    }
    event.returnValue = true;
  });

  app.on('before-quit', () => {
    if (storageFlushTimer) {
      clearTimeout(storageFlushTimer);
      storageFlushTimer = null;
      if (latestStorageSnapshot) writeStorageDiskSync(latestStorageSnapshot);
    }
  });

  function readWindowState() {
    try {
      const raw = fs.readFileSync(windowStatePath, 'utf8');
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== 'object') return null;
      return parsed;
    } catch (error) {
      return null;
    }
  }

  function clampBoundsToDisplay(bounds) {
    const primaryDisplay = screen.getPrimaryDisplay();
    const primaryWorkArea = primaryDisplay.workArea;
    const scaleFactor = primaryDisplay.scaleFactor;

    const sourceBounds = bounds && Number.isFinite(bounds.width) && Number.isFinite(bounds.height)
    ? { ...bounds }
    : {};

    const minW = 800;
    const minH = 540;

    const width = Math.max(minW, Math.min(sourceBounds.width || 0, primaryWorkArea.width));
    const height = Math.max(minH, Math.min(sourceBounds.height || 0, primaryWorkArea.height));

    const display = screen.getDisplayMatching({
      x: sourceBounds.x ?? primaryWorkArea.x,
      y: sourceBounds.y ?? primaryWorkArea.y,
      width,
      height
    }) || primaryDisplay;

    const workArea = display.workArea;
    const x = Math.min(
      Math.max(sourceBounds.x ?? workArea.x + Math.round((workArea.width - width) / 2), workArea.x),
                       workArea.x + Math.max(0, workArea.width - width)
    );
    const y = Math.min(
      Math.max(sourceBounds.y ?? workArea.y + Math.round((workArea.height - height) / 2), workArea.y),
                       workArea.y + Math.max(0, workArea.height - height)
    );

    return { x, y, width, height };
  }

  function getResponsiveWindowBounds() {
    const { workArea } = screen.getPrimaryDisplay();
    const persisted = readWindowState();
    const responsiveBounds = {
      width: Math.round(workArea.width * 0.82),
      height: Math.round(workArea.height * 0.86),
      x: workArea.x + Math.round(workArea.width * 0.09),
      y: workArea.y + Math.round(workArea.height * 0.07)
    };
    const merged = {
      ...responsiveBounds,
      ...(persisted && persisted.bounds ? persisted.bounds : {})
    };
    return clampBoundsToDisplay(merged);
  }

  function persistWindowState() {
    if (isMiniWindow) return;
    if (!mainWindow || mainWindow.isDestroyed()) return;
    const isMaximized = mainWindow.isMaximized();
    const isFullScreen = mainWindow.isFullScreen();
    const bounds = isMaximized || isFullScreen ? mainWindow.getNormalBounds() : mainWindow.getBounds();
    try {
      fs.mkdirSync(path.dirname(windowStatePath), { recursive: true });
      fs.writeFileSync(windowStatePath, JSON.stringify({
        bounds,
        isMaximized,
        isFullScreen
      }, null, 2));
    } catch (error) {
      console.warn('Failed to persist window state:', error);
    }
  }

  async function createWindow() {
    serverPort = await startServer(PORT);
    const firstRun = !tutorialDone();
    const initialBounds = getResponsiveWindowBounds();
    const savedState = readWindowState();

    const primaryDisplay = screen.getPrimaryDisplay();
    const scaleFactor = primaryDisplay.scaleFactor;

    app.setAppUserModelId('io.github.rootscripts.riff');
    mainWindow = new BrowserWindow({
      x: initialBounds.x,
      y: initialBounds.y,
      width: initialBounds.width,
      height: initialBounds.height,
      minWidth: 800,
      minHeight: 540,
                                   backgroundColor: firstRun ? '#8d5ef2' : '#000000',
                                   title: 'Riff',
                                   icon: path.join(__dirname, '../../assets', 'icon.png'),
                                   frame: false,
                                   titleBarStyle: 'hidden',
                                   show: false,
                                   useContentSize: true,
                                   webPreferences: {
                                     preload: path.join(__dirname, 'preload.js'),
                                   additionalArguments: [`--riff-token=${getServerToken()}`],
                                   nodeIntegration: false,
                                   contextIsolation: true,
                                   webSecurity: false,
                                   backgroundThrottling: true,
                                   spellcheck: false
                                   }
    });

    if (savedState?.isMaximized) {
      mainWindow.maximize();
    }

    mainWindow.once('ready-to-show', () => {
      if (!mainWindow || mainWindow.isDestroyed()) return;
      mainWindow.show();
    });

    mainWindow.loadFile(path.join(__dirname, '../renderer', firstRun ? 'welcome.html' : 'index.html'));
    if (firstRun) {
      ipcMain.removeAllListeners('welcome-finish');
      ipcMain.once('welcome-finish', (e, detail) => {
        markTutorialDone();
        if (detail && detail.launcher) installLauncher();
        if (!mainWindow || mainWindow.isDestroyed()) return;
        const result = detail && !detail.skipped ? detail : null;
        mainWindow.setBackgroundColor('#000000');
        mainWindow.webContents.once('did-finish-load', () => { if (result) mainWindow.webContents.send('welcome-result', result); });
        mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
        require('./updater').initUpdater(() => mainWindow);
      });
    }

    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
      shell.openExternal(url);
      return { action: 'deny' };
    });

    mainWindow.on('minimize', () => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('window-visibility', false);
        if (global.gc) global.gc();
      }
    });

    mainWindow.on('blur', () => {
      if (global.gc) global.gc();
    });

    mainWindow.on('restore', () => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('window-visibility', true);
      }
    });

    mainWindow.on('hide', () => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('window-visibility', false);
      }
    });

    mainWindow.on('show', () => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send('window-visibility', true);
      }
    });
    mainWindow.on('resize', persistWindowState);
    mainWindow.on('move', persistWindowState);
    mainWindow.on('maximize', persistWindowState);
    mainWindow.on('unmaximize', persistWindowState);
    mainWindow.on('enter-full-screen', persistWindowState);
    mainWindow.on('leave-full-screen', persistWindowState);
    mainWindow.on('close', (e) => {
      persistWindowState();
      if (trayOnClose && tray && !isQuitting) {
        e.preventDefault();
        mainWindow.hide();
      }
    });

    discordRPC.initRPC();
  }

  ipcMain.removeHandler('get-server-port');
  ipcMain.removeHandler('discord-rpc-get-enabled');
  ipcMain.removeHandler('discord-rpc-get-connected');
  ipcMain.removeHandler('discord-rpc-reconnect');
  ipcMain.removeHandler('account-export');
  ipcMain.removeHandler('account-import');
  ipcMain.removeHandler('pick-media');
  ipcMain.removeHandler('import-audio-files');

  ipcMain.on('window-minimize', () => {
    if (mainWindow && !mainWindow.isDestroyed()) mainWindow.minimize();
  });

    ipcMain.on('window-maximize', () => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        if (mainWindow.isMaximized()) mainWindow.unmaximize();
        else mainWindow.maximize();
      }
    });

    ipcMain.on('window-close', () => {
      if (mainWindow && !mainWindow.isDestroyed()) mainWindow.close();
    });

    ipcMain.on('open-external', (e, u) => {
      if (/^https:\/\/(?:accounts\.spotify\.com|(?:www\.)?last\.fm|github\.com)\//i.test(String(u))) {
        shell.openExternal(String(u));
      }
    });

    let mainLogCount = 0;
    let mainLogReset = Date.now();
    ipcMain.on('log-error', (e, data) => {
      const now = Date.now();
      if (now - mainLogReset > 60000) {
        mainLogReset = now;
        mainLogCount = 0;
      }
      if (mainLogCount < 20) {
        mainLogCount++;
        if (data && typeof data === 'object') {
          logger.log(data.level || 'ERROR', data.message || '', data.stack || null);
        }
      }
    });

    ipcMain.handle('get-diagnostics', async () => {
      const lines = [`Riff ${app.getVersion()}`, `OS ${process.platform} ${process.arch} ${os.release()}`, `Electron ${process.versions.electron} Chromium ${process.versions.chrome} Node ${process.versions.node}`, `Locale ${app.getLocale()}`, `Data ${DATA_DIR}`];
      for (const name of ['yt-dlp', 'ffmpeg']) {
        const bin = resolveBinary(name);
        lines.push(`${name}: ${bin || 'NOT FOUND'}`);
      }
      lines.push('--- last log lines ---', ...tail(60));
      return lines.join('\n');
    });
    ipcMain.on('open-logs-folder', () => { shell.openPath(LOG_DIR); });

      ipcMain.handle('get-server-port', () => serverPort);
      ipcMain.handle('get-gpu-compositing', () => { try { return String(app.getGPUFeatureStatus().gpu_compositing || ''); } catch (e) { return ''; } });
      ipcMain.handle('launcher-info', () => getLauncherInfo());
      ipcMain.handle('get-audio-output-info', async () => getSystemAudioOutputInfo());
      require('./themes').register(() => mainWindow);
      require('./plugins').register(() => mainWindow);

      ipcMain.on('discord-rpc-update', (event, trackInfo) => {
        discordRPC.updatePresence(trackInfo);
      });

      ipcMain.on('discord-rpc-clear', () => {
        discordRPC.clearPresence();
      });

      ipcMain.on('discord-rpc-set-enabled', (event, enabled) => {
        discordRPC.setEnabled(enabled);
      });

      ipcMain.handle('discord-rpc-get-enabled', () => discordRPC.getEnabled());
      ipcMain.handle('discord-rpc-get-connected', () => discordRPC.getConnected());
      ipcMain.handle('discord-rpc-reconnect', () => {
        if (discordRPC && discordRPC.reconnectRPC) discordRPC.reconnectRPC();
        return true;
      });
      ipcMain.on('discord-rpc-reconnect', () => {
        if (discordRPC && discordRPC.reconnectRPC) discordRPC.reconnectRPC();
      });

      ipcMain.handle('get-cache-size', async () => {
        const fs = require('fs');
        const path = require('path');
        const os = require('os');
        const { session } = require('electron');

        let webSize = 0;
        try { webSize = await session.defaultSession.getCacheSize(); } catch(e) {}

        let audioSize = 0;
        const tracksDir = require('../shared/platform').CACHE_DIR;
        const thumbnailsDir = require('../shared/platform').THUMBNAILS_DIR;
        const audioExtRegex = /\.(opus|webm|m4a|mp3)$/i;
        try {
          if (fs.existsSync(tracksDir)) {
            for (const file of fs.readdirSync(tracksDir)) {
              if (audioExtRegex.test(file)) {
                try { audioSize += fs.statSync(path.join(tracksDir, file)).size; } catch(e) {}
              }
            }
          }
        } catch(e) {}
        try {
          if (fs.existsSync(thumbnailsDir)) {
            for (const file of fs.readdirSync(thumbnailsDir)) {
              try { audioSize += fs.statSync(path.join(thumbnailsDir, file)).size; } catch(e) {}
            }
          }
        } catch(e) {}

        return { audio: audioSize, web: webSize };
      });

      ipcMain.handle('clear-cache', async () => {
        const fs = require('fs');
        const path = require('path');
        const os = require('os');
        const { session } = require('electron');
        
        try { await session.defaultSession.clearCache(); } catch(e) {}
        try { await session.defaultSession.clearStorageData({ storages: ['serviceworkers', 'cachestorage'] }); } catch(e) {}

        const tracksDir = require('../shared/platform').CACHE_DIR;
        const thumbnailsDir = require('../shared/platform').THUMBNAILS_DIR;
        const audioExtRegex = /\.(opus|webm|m4a|mp3)$/i;
        try {
          if (fs.existsSync(tracksDir)) {
            for (const file of fs.readdirSync(tracksDir)) {
              if (audioExtRegex.test(file)) {
                try { fs.unlinkSync(path.join(tracksDir, file)); } catch(e) {}
              }
            }
          }
        } catch(e) {}
        try {
          if (fs.existsSync(thumbnailsDir)) {
            for (const file of fs.readdirSync(thumbnailsDir)) {
              try { fs.unlinkSync(path.join(thumbnailsDir, file)); } catch(e) {}
            }
          }
        } catch(e) {}

        return true;
      });

      ipcMain.handle('pick-media', async () => {
        const r = await dialog.showOpenDialog(mainWindow, { properties: ['openFile'], filters: [{ name: 'Media', extensions: ['png','jpg','jpeg','webp','gif','mp4','webm'] }] });
        return r.canceled ? null : pathToFileURL(r.filePaths[0]).href;
      });

      ipcMain.handle('import-audio-files', async () => {
        const r = await dialog.showOpenDialog(mainWindow, { properties: ['openFile', 'multiSelections'], filters: [{ name: 'Audio', extensions: ['mp3','wav','flac','opus','ogg','oga','m4a','aac','webm','weba'] }] });
        if (r.canceled) return [];
        fs.mkdirSync(LIBRARY_DIR, { recursive: true });
        const out = [];
        for (const src of r.filePaths) {
          const st = fs.statSync(src), ext = path.extname(src).slice(1).toLowerCase();
          const id = 'local_' + crypto.createHash('sha1').update(path.basename(src) + st.size).digest('hex').slice(0, 12);
          const file = `${id}.${ext}`;
          if (!fs.existsSync(path.join(LIBRARY_DIR, file))) await fs.promises.copyFile(src, path.join(LIBRARY_DIR, file));
          out.push({ id, file, ext, name: path.basename(src, path.extname(src)) });
        }
        return out;
      });

      ipcMain.handle('get-data-dir', () => {
        const platform = require('../shared/platform');
        return {
          dir: platform.DATA_DIR,
          defaultDir: platform.DEFAULT_DATA_DIR,
          isCustom: platform.DATA_DIR !== platform.DEFAULT_DATA_DIR
        };
      });

      ipcMain.handle('pick-data-dir', async () => {
        const platform = require('../shared/platform');
        const r = await dialog.showOpenDialog(mainWindow, {
          title: 'Choose music folder',
          defaultPath: platform.DATA_DIR,
          properties: ['openDirectory', 'createDirectory']
        });
        return r.canceled ? null : r.filePaths[0];
      });

      ipcMain.handle('set-data-dir', async (event, payload) => {
        const platform = require('../shared/platform');
        const target = payload && payload.dir ? path.resolve(String(payload.dir)) : null;
        const move = !!(payload && payload.move);
        if (!target) return { ok: false, error: 'No folder selected' };

        const current = path.resolve(platform.DATA_DIR);
        if (target === current) return { ok: true, dir: target, moved: false };

        const rel = path.relative(current, target);
        const insideCurrent = rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
        const relBack = path.relative(target, current);
        const currentInsideTarget = relBack === '' || (!relBack.startsWith('..') && !path.isAbsolute(relBack));
        if (insideCurrent || currentInsideTarget) {
          return { ok: false, error: 'Choose a folder outside the current music folder' };
        }

        try {
          fs.mkdirSync(target, { recursive: true });
          fs.accessSync(target, fs.constants.W_OK);
        } catch (e) {
          return { ok: false, error: 'That folder is not writable' };
        }

        if (move) {
          try {
            await platform.copyDirContents(current, target);
          } catch (e) {
            return { ok: false, error: 'Could not move files: ' + e.message };
          }
        }

        platform.setDataDir(target);

        if (move) {
          try { await platform.removeDirContents(current); } catch (e) {}
        }

        return { ok: true, dir: target, moved: move };
      });

      const defaultDownloadsDir = () => {
        try { return app.getPath('downloads'); } catch (e) { return null; }
      };

      ipcMain.handle('get-download-dir', () => {
        const platform = require('../shared/platform');
        const def = defaultDownloadsDir();
        const custom = platform.resolveDownloadDir();
        return {
          dir: custom || def,
          defaultDir: def,
          isCustom: !!custom
        };
      });

      ipcMain.handle('pick-download-dir', async () => {
        const platform = require('../shared/platform');
        const r = await dialog.showOpenDialog(mainWindow, {
          title: 'Choose download folder',
          defaultPath: platform.resolveDownloadDir() || defaultDownloadsDir() || undefined,
          properties: ['openDirectory', 'createDirectory']
        });
        return r.canceled ? null : r.filePaths[0];
      });

      ipcMain.handle('set-download-dir', async (event, payload) => {
        const platform = require('../shared/platform');
        const reset = !!(payload && payload.reset);
        if (reset) {
          platform.setDownloadDir(null);
          return { ok: true, dir: defaultDownloadsDir(), reset: true };
        }
        const target = payload && payload.dir ? path.resolve(String(payload.dir)) : null;
        if (!target) return { ok: false, error: 'No folder selected' };
        try {
          fs.mkdirSync(target, { recursive: true });
          fs.accessSync(target, fs.constants.W_OK);
        } catch (e) {
          return { ok: false, error: 'That folder is not writable' };
        }
        platform.setDownloadDir(target);
        return { ok: true, dir: target };
      });

      ipcMain.on('restart-app', () => {
        app.relaunch();
        app.exit(0);
      });

      ipcMain.on('set-tray-on-close', (e, v) => {
        trayOnClose = !!v;
      });

      ipcMain.handle('get-multi-instance', () => !!readStartupConfig().multiInstance);
      ipcMain.on('set-multi-instance', (e, value) => { writeStartupConfig({ multiInstance: !!value }); });

      const MEDIA_KEYS = { MediaPlayPause: 'toggle', MediaNextTrack: 'next', MediaPreviousTrack: 'prev', MediaStop: 'stop' };
      let mediaKeysWanted = true;
      let mediaKeysActive = false;
      const sendMedia = (cmd) => {
        if (process.env.RIFF_DEBUG === '1') console.log('[media] globalShortcut', cmd);
        if (mainWindow && !mainWindow.isDestroyed()) mainWindow.webContents.send('media-command', cmd);
      };
      function unregisterMediaKeys() {
        for (const k of Object.keys(MEDIA_KEYS)) {
          try { globalShortcut.unregister(k); } catch (e) {}
        }
      }
      function registerMediaKeys() {
        if (process.platform !== 'win32') return;
        unregisterMediaKeys();
        if (!mediaKeysWanted || !mediaKeysActive) return;
        for (const [k, cmd] of Object.entries(MEDIA_KEYS)) {
          try {
            if (!globalShortcut.register(k, () => sendMedia(cmd))) {
              console.warn('[media] could not register', k);
            }
          } catch (e) {}
        }
      }
      ipcMain.on('set-media-keys', (e, enabled) => { mediaKeysWanted = !!enabled; registerMediaKeys(); });
      ipcMain.on('media-keys-active', () => { if (!mediaKeysActive) { mediaKeysActive = true; registerMediaKeys(); } });
      powerMonitor.on('resume', registerMediaKeys);
      powerMonitor.on('unlock-screen', registerMediaKeys);
      app.on('will-quit', () => globalShortcut.unregisterAll());

      let preMiniLyricsH = null;
      ipcMain.removeHandler('toggle-mini-window');
      ipcMain.handle('toggle-mini-window', () => {
        if (!mainWindow || mainWindow.isDestroyed()) return false;
        if (!isMiniWindow) {
          isMiniWindow = true;
          preMiniBounds = mainWindow.isMaximized() ? mainWindow.getNormalBounds() : mainWindow.getBounds();
          if (mainWindow.isMaximized()) mainWindow.unmaximize();
          mainWindow.setMinimumSize(280, 115);
          mainWindow.setSize(380, 160);
          mainWindow.setAlwaysOnTop(true);
          return true;
        } else {
          isMiniWindow = false;
          preMiniLyricsH = null;
          mainWindow.setAlwaysOnTop(false);
          mainWindow.setMinimumSize(800, 540);
          if (preMiniBounds) {
            mainWindow.setBounds(clampBoundsToDisplay(preMiniBounds));
          } else {
            mainWindow.setSize(1000, 700);
          }
          return false;
        }
      });

      ipcMain.removeHandler('set-mini-lyrics');
      ipcMain.handle('set-mini-lyrics', (e, enabled) => {
        if (!mainWindow || mainWindow.isDestroyed() || !isMiniWindow) return false;
        const bounds = mainWindow.getBounds();
        const display = screen.getDisplayMatching(bounds);
        const maxH = Math.floor(display.workArea.height * 0.9);
        if (enabled) {
          if (!preMiniLyricsH) preMiniLyricsH = bounds.height;
          mainWindow.setMinimumSize(320, 240);
          const targetH = Math.min(Math.max(bounds.height, 360), maxH);
          if (bounds.y + targetH > display.workArea.y + display.workArea.height) {
            const newY = Math.max(display.workArea.y, display.workArea.y + display.workArea.height - targetH);
            mainWindow.setBounds({ x: bounds.x, y: newY, width: bounds.width, height: targetH });
          } else {
            mainWindow.setSize(bounds.width, targetH);
          }
        } else {
          mainWindow.setMinimumSize(320, 140);
          const targetH = preMiniLyricsH || 160;
          mainWindow.setSize(bounds.width, targetH);
          preMiniLyricsH = null;
        }
        return true;
      });

      ipcMain.handle('get-app-version', () => app.getVersion());

      ipcMain.handle('save-playlists-json', async (event, payload) => {
        const win = BrowserWindow.fromWebContents(event.sender) || mainWindow;
        const defaultName = payload && payload.defaultName ? payload.defaultName : 'playlists.json';
        const content = payload && payload.content ? payload.content : '';
        const r = await dialog.showSaveDialog(win, {
          title: 'Export playlists as JSON',
          defaultPath: defaultName,
          filters: [{ name: 'JSON', extensions: ['json'] }]
        });
        if (r.canceled || !r.filePath) return { canceled: true };
        await fs.promises.writeFile(r.filePath, content, 'utf8');
        return { success: true, filePath: r.filePath };
      });

      ipcMain.handle('account-export', async (event, payload) => {
        try {
          const win = BrowserWindow.fromWebContents(event.sender) || mainWindow;
          const r = await dialog.showSaveDialog(win, {
            title: 'Export Riff account',
            defaultPath: 'riff-account.rfacc',
            filters: [{ name: 'Riff Account (.rfacc)', extensions: ['rfacc'] }]
          });
          if (r.canceled || !r.filePath) return { canceled: true };
          const buffer = encryptAccount(payload || {});
          await fs.promises.writeFile(r.filePath, buffer);
          return { success: true, filePath: r.filePath };
        } catch (err) {
          return { success: false, error: err.message };
        }
      });

      ipcMain.handle('account-import', async (event) => {
        try {
          const win = BrowserWindow.fromWebContents(event.sender) || mainWindow;
          const r = await dialog.showOpenDialog(win, {
            title: 'Import Riff account',
            properties: ['openFile'],
            filters: [{ name: 'Riff Account (.rfacc)', extensions: ['rfacc'] }]
          });
          if (r.canceled || !r.filePaths || !r.filePaths.length) return { canceled: true };
          const buffer = await fs.promises.readFile(r.filePaths[0]);
          const data = decryptAccount(buffer);
          return { success: true, data, filePath: r.filePaths[0] };
        } catch (err) {
          return { success: false, error: err.message };
        }
      });

      ipcMain.handle('show-playlist-context-menu', async (event) => {
        const win = BrowserWindow.fromWebContents(event.sender) || mainWindow;
        return new Promise((resolve) => {
          const menu = Menu.buildFromTemplate([
            {
              label: 'Export as JSON',
              click: () => resolve('export')
            }
          ]);
          menu.popup({
            window: win,
            callback: () => resolve(null)
          });
        });
      });

      ipcMain.handle('google-auth-status', async () => {
        try {
          const s = session.fromPartition('persist:riff-google');
          const cookies = await s.cookies.get({ name: 'SAPISID' });
          const loggedIn = Array.isArray(cookies) && cookies.some(c => c && c.value);
          return { loggedIn };
        } catch (e) {
          return { loggedIn: false };
        }
      });

      ipcMain.handle('google-logout', async () => {
        try {
          const s = session.fromPartition('persist:riff-google');
          await s.clearStorageData();
          return { success: true };
        } catch (e) {
          return { success: false, error: e && e.message ? e.message : 'Logout failed' };
        }
      });

      ipcMain.handle('google-login', async (event) => {
        const win = BrowserWindow.fromWebContents(event.sender) || mainWindow;
        const s = session.fromPartition('persist:riff-google');
        const chromeUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
        try { s.setUserAgent(chromeUA); } catch (e) {}

        return new Promise((resolve) => {
          let finished = false;
          let pollTimer = null;
          const authWin = new BrowserWindow({
            width: 480,
            height: 680,
            parent: win || undefined,
            modal: true,
            title: 'Google Login',
            webPreferences: {
              session: s,
              contextIsolation: true,
              nodeIntegration: false
            }
          });
          try { authWin.webContents.setUserAgent(chromeUA); } catch (e) {}

          const checkCookies = async () => {
            if (finished) return;
            try {
              const url = authWin.webContents.getURL() || '';
              if (url.includes('music.youtube.com') || url.includes('youtube.com')) {
                const cookies = await s.cookies.get({ name: 'SAPISID' });
                if (Array.isArray(cookies) && cookies.some(c => c && c.value)) {
                  finished = true;
                  if (pollTimer) clearInterval(pollTimer);
                  if (!authWin.isDestroyed()) authWin.close();
                  resolve({ success: true, loggedIn: true });
                }
              }
            } catch (e) {}
          };

          authWin.webContents.on('did-navigate', checkCookies);
          authWin.webContents.on('did-navigate-in-page', checkCookies);
          authWin.webContents.on('did-finish-load', checkCookies);
          pollTimer = setInterval(checkCookies, 1000);

          authWin.on('closed', () => {
            if (pollTimer) clearInterval(pollTimer);
            if (!finished) {
              finished = true;
              s.cookies.get({ name: 'SAPISID' }).then(cookies => {
                const loggedIn = Array.isArray(cookies) && cookies.some(c => c && c.value);
                resolve({ success: loggedIn, loggedIn });
              }).catch(() => {
                resolve({ success: false, loggedIn: false });
              });
            }
          });

          authWin.loadURL('https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F', {
            userAgent: chromeUA
          }).catch(() => {});
        });
      });

      ipcMain.handle('google-import-library', async (event, opts) => {
        const platform = (opts && opts.platform === 'ytmusic') ? 'ytmusic' : 'youtube';
        const doLikes = !opts || opts.doLikes !== false;
        const doPlaylists = !opts || opts.doPlaylists !== false;

        const s = session.fromPartition('persist:riff-google');
        const cookies = await s.cookies.get({ name: 'SAPISID' });
        const sapisidCookie = Array.isArray(cookies) ? cookies.find(c => c && c.value) : null;
        if (!sapisidCookie) {
          return { success: false, error: 'Not logged in to Google' };
        }
        const sapisid = sapisidCookie.value;

        const isYtm = platform === 'ytmusic';
        const browseUrl = isYtm
          ? 'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false'
          : 'https://www.youtube.com/youtubei/v1/browse?prettyPrint=false';
        const origin = isYtm ? 'https://music.youtube.com' : 'https://www.youtube.com';
        const clientName = isYtm ? 'WEB_REMIX' : 'WEB';
        const clientVersion = isYtm ? '1.20240401.01.00' : '2.20240401.01.00';
        const likedBrowseId = isYtm ? 'VLLM' : 'VLLL';
        const playlistsBrowseId = isYtm ? 'FEmusic_liked_playlists' : 'FEplaylist_aggregation';

        function extractText(node) {
          if (!node) return '';
          if (typeof node === 'string') return node;
          if (typeof node.simpleText === 'string') return node.simpleText;
          if (Array.isArray(node.runs)) return node.runs.map(r => (r && r.text) || '').join('');
          return '';
        }

        function parseDurationSec(val) {
          if (!val) return 0;
          if (typeof val === 'number') return val;
          const str = String(val).trim();
          const m = str.match(/(?:(\d+):)?(\d+):(\d+)/);
          if (m) {
            const h = m[1] ? parseInt(m[1], 10) : 0;
            const min = parseInt(m[2], 10);
            const sec = parseInt(m[3], 10);
            return h * 3600 + min * 60 + sec;
          }
          const num = parseInt(str, 10);
          return Number.isFinite(num) ? num : 0;
        }

        function findContinuationToken(node, visited = new Set()) {
          if (!node || typeof node !== 'object') return null;
          if (visited.has(node)) return null;
          visited.add(node);
          if (typeof node.continuation === 'string' && node.continuation) return node.continuation;
          if (typeof node.token === 'string' && node.token) return node.token;
          if (node.continuationCommand && typeof node.continuationCommand.token === 'string') {
            return node.continuationCommand.token;
          }
          if (node.nextContinuationData && typeof node.nextContinuationData.continuation === 'string') {
            return node.nextContinuationData.continuation;
          }
          for (const k of Object.keys(node)) {
            const res = findContinuationToken(node[k], visited);
            if (res) return res;
          }
          return null;
        }

        function extractTracksGeneric(root) {
          const tracks = [];
          const seenIds = new Set();
          function walk(node, visited = new Set()) {
            if (!node || typeof node !== 'object') return;
            if (visited.has(node)) return;
            visited.add(node);
            if (node.musicResponsiveListItemRenderer) {
              const r = node.musicResponsiveListItemRenderer;
              let videoId = (r.playlistItemData && r.playlistItemData.videoId) ? r.playlistItemData.videoId : null;
              if (!videoId) {
                const findVid = (obj) => {
                  if (!obj || typeof obj !== 'object') return null;
                  if (obj.watchEndpoint && typeof obj.watchEndpoint.videoId === 'string') return obj.watchEndpoint.videoId;
                  for (const k of Object.keys(obj)) {
                    const v = findVid(obj[k]);
                    if (v) return v;
                  }
                  return null;
                };
                videoId = findVid(r);
              }
              if (videoId && !seenIds.has(videoId)) {
                seenIds.add(videoId);
                const title = extractText(r.flexColumns && r.flexColumns[0] && r.flexColumns[0].musicResponsiveListItemFlexColumnRenderer && r.flexColumns[0].musicResponsiveListItemFlexColumnRenderer.text) || 'untitled';
                let artist = '';
                if (r.flexColumns && r.flexColumns[1]) {
                  const runs = r.flexColumns[1].musicResponsiveListItemFlexColumnRenderer && r.flexColumns[1].musicResponsiveListItemFlexColumnRenderer.text && r.flexColumns[1].musicResponsiveListItemFlexColumnRenderer.text.runs;
                  if (Array.isArray(runs) && runs.length > 0) {
                    artist = runs[0].text || '';
                  } else {
                    artist = extractText(r.flexColumns[1].musicResponsiveListItemFlexColumnRenderer && r.flexColumns[1].musicResponsiveListItemFlexColumnRenderer.text);
                  }
                }
                let duration = 0;
                const findDur = (obj) => {
                  if (!obj || typeof obj !== 'object') return;
                  if (Array.isArray(obj.runs)) {
                    for (const ru of obj.runs) {
                      if (ru && ru.text && /^\d+:\d+(:\d+)?$/.test(ru.text.trim())) {
                        duration = parseDurationSec(ru.text.trim());
                        return;
                      }
                    }
                  }
                  for (const k of Object.keys(obj)) {
                    if (!duration) findDur(obj[k]);
                  }
                };
                findDur(r);
                const thumbs = r.thumbnail && r.thumbnail.musicThumbnailRenderer && r.thumbnail.musicThumbnailRenderer.thumbnail && r.thumbnail.musicThumbnailRenderer.thumbnail.thumbnails;
                const cover = (Array.isArray(thumbs) && thumbs.length > 0) ? thumbs[thumbs.length - 1].url : '';
                tracks.push({ videoId, title, artist, duration, cover });
              }
            } else if (node.playlistVideoRenderer || node.videoRenderer || node.compactVideoRenderer) {
              const r = node.playlistVideoRenderer || node.videoRenderer || node.compactVideoRenderer;
              const videoId = r.videoId;
              if (videoId && !seenIds.has(videoId)) {
                seenIds.add(videoId);
                const title = extractText(r.title) || 'untitled';
                const artist = extractText(r.shortBylineText) || extractText(r.ownerText) || '';
                const duration = r.lengthSeconds ? parseInt(r.lengthSeconds, 10) : parseDurationSec(extractText(r.lengthText));
                const thumbs = (r.thumbnail && r.thumbnail.thumbnails) || (r.thumbnails && r.thumbnails[0] && r.thumbnails[0].thumbnails);
                const cover = (Array.isArray(thumbs) && thumbs.length > 0) ? thumbs[thumbs.length - 1].url : '';
                tracks.push({ videoId, title, artist, duration, cover });
              }
            }
            if (Array.isArray(node)) {
              for (const item of node) walk(item, visited);
            } else {
              for (const k of Object.keys(node)) walk(node[k], visited);
            }
          }
          walk(root);
          return tracks;
        }

        function extractPlaylistsGeneric(root) {
          const playlists = [];
          const seenIds = new Set();
          function walk(node, visited = new Set()) {
            if (!node || typeof node !== 'object') return;
            if (visited.has(node)) return;
            visited.add(node);
            if (node.musicTwoRowItemRenderer) {
              const r = node.musicTwoRowItemRenderer;
              const title = extractText(r.title);
              let browseId = r.navigationEndpoint && r.navigationEndpoint.browseEndpoint && r.navigationEndpoint.browseEndpoint.browseId;
              if (!browseId) {
                const findBrowse = (obj) => {
                  if (!obj || typeof obj !== 'object') return null;
                  if (obj.browseEndpoint && typeof obj.browseEndpoint.browseId === 'string') return obj.browseEndpoint.browseId;
                  for (const k of Object.keys(obj)) {
                    const b = findBrowse(obj[k]);
                    if (b) return b;
                  }
                  return null;
                };
                browseId = findBrowse(r);
              }
              if (browseId && !seenIds.has(browseId) && (browseId.startsWith('VL') || browseId.startsWith('PL') || browseId.startsWith('MPREb_') || browseId.includes('playlist') || browseId.startsWith('RD'))) {
                seenIds.add(browseId);
                const thumbs = r.thumbnailRenderer && r.thumbnailRenderer.musicThumbnailRenderer && r.thumbnailRenderer.musicThumbnailRenderer.thumbnail && r.thumbnailRenderer.musicThumbnailRenderer.thumbnail.thumbnails;
                const cover = (Array.isArray(thumbs) && thumbs.length > 0) ? thumbs[thumbs.length - 1].url : '';
                playlists.push({ id: browseId, name: title || 'Playlist', cover });
              }
            } else if (node.gridPlaylistRenderer || node.playlistRenderer || node.compactPlaylistRenderer) {
              const r = node.gridPlaylistRenderer || node.playlistRenderer || node.compactPlaylistRenderer;
              const id = r.playlistId || (r.navigationEndpoint && r.navigationEndpoint.browseEndpoint && r.navigationEndpoint.browseEndpoint.browseId);
              const title = extractText(r.title);
              if (id && !seenIds.has(id)) {
                seenIds.add(id);
                const thumbs = (r.thumbnail && r.thumbnail.thumbnails) || (r.thumbnails && r.thumbnails[0] && r.thumbnails[0].thumbnails);
                const cover = (Array.isArray(thumbs) && thumbs.length > 0) ? thumbs[thumbs.length - 1].url : '';
                playlists.push({ id, name: title || 'Playlist', cover });
              }
            }
            if (Array.isArray(node)) {
              for (const item of node) walk(item, visited);
            } else {
              for (const k of Object.keys(node)) walk(node[k], visited);
            }
          }
          walk(root);
          return playlists;
        }

        async function fetchInnertube(browseId, continuationToken = null) {
          const ts = Math.floor(Date.now() / 1000);
          const hash = crypto.createHash('sha1').update(`${ts} ${sapisid} ${origin}`).digest('hex');
          const headers = {
            'Authorization': `SAPISIDHASH ${ts}_${hash}`,
            'Content-Type': 'application/json',
            'Origin': origin,
            'Referer': `${origin}/`,
            'X-Origin': origin,
            'X-Goog-AuthUser': '0'
          };
          const body = {
            context: {
              client: {
                clientName,
                clientVersion,
                hl: 'en'
              }
            }
          };
          let targetUrl = browseUrl;
          if (continuationToken) {
            body.continuation = continuationToken;
            targetUrl = `${browseUrl}&continuation=${encodeURIComponent(continuationToken)}`;
          } else if (browseId) {
            body.browseId = browseId;
          }
          const res = await s.fetch(targetUrl, {
            method: 'POST',
            headers,
            body: JSON.stringify(body)
          });
          if (!res.ok) {
            throw new Error(`Innertube request failed: ${res.status}`);
          }
          return await res.json();
        }

        async function fetchAllTracks(browseId) {
          let initial = await fetchInnertube(browseId);
          let tracks = extractTracksGeneric(initial);
          let token = findContinuationToken(initial);
          let safety = 0;
          while (token && safety < 30) {
            safety++;
            const contData = await fetchInnertube(null, token);
            const newTracks = extractTracksGeneric(contData);
            if (!newTracks.length) break;
            tracks = tracks.concat(newTracks);
            const nextToken = findContinuationToken(contData);
            if (!nextToken || nextToken === token) break;
            token = nextToken;
          }
          return tracks;
        }

        async function fetchAllPlaylists(browseId) {
          let initial = await fetchInnertube(browseId);
          let playlists = extractPlaylistsGeneric(initial);
          let token = findContinuationToken(initial);
          let safety = 0;
          while (token && safety < 20) {
            safety++;
            const contData = await fetchInnertube(null, token);
            const newPlaylists = extractPlaylistsGeneric(contData);
            if (!newPlaylists.length) break;
            playlists = playlists.concat(newPlaylists);
            const nextToken = findContinuationToken(contData);
            if (!nextToken || nextToken === token) break;
            token = nextToken;
          }
          return playlists;
        }

        try {
          let likes = [];
          if (doLikes) {
            const rawLikes = await fetchAllTracks(likedBrowseId);
            likes = rawLikes.map(t => ({
              title: t.title,
              artist: t.artist,
              duration: t.duration,
              id: t.videoId,
              url: `https://www.youtube.com/watch?v=${t.videoId}`,
              platform,
              thumbnail: t.cover,
              cover: t.cover
            }));
          }

          let playlists = [];
          if (doPlaylists) {
            const rawPlaylists = await fetchAllPlaylists(playlistsBrowseId);
            for (const pl of rawPlaylists) {
              try {
                const plBrowseId = pl.id.startsWith('VL') ? pl.id : `VL${pl.id}`;
                const plTracks = await fetchAllTracks(plBrowseId);
                playlists.push({
                  id: pl.id,
                  name: pl.name,
                  cover: pl.cover,
                  tracks: plTracks.map(t => ({
                    title: t.title,
                    artist: t.artist,
                    duration: t.duration,
                    id: t.videoId,
                    url: `https://www.youtube.com/watch?v=${t.videoId}`,
                    platform,
                    thumbnail: t.cover,
                    cover: t.cover
                  }))
                });
              } catch (e) {
                playlists.push({
                  id: pl.id,
                  name: pl.name,
                  cover: pl.cover,
                  tracks: []
                });
              }
            }
          }

          return { success: true, likes, playlists };
        } catch (err) {
          return { success: false, error: (err && err.message) ? err.message : 'Failed to fetch library' };
        }
      });

      function setupTray() {
        try {
          const iconPath = path.join(__dirname, '../../assets', 'icon.png');
          let trayIcon = nativeImage.createFromPath(iconPath);
          trayIcon = trayIcon.resize({ width: 22, height: 22 });
          tray = new Tray(trayIcon);
          tray.setToolTip('Riff');
          const contextMenu = Menu.buildFromTemplate([
            {
              label: 'Show/Hide',
              click: () => {
                if (!mainWindow || mainWindow.isDestroyed()) return;
                if (mainWindow.isVisible()) mainWindow.hide();
                else { mainWindow.show(); mainWindow.focus(); }
              }
            },
            {
              label: 'Play/Pause',
              click: () => {
                if (mainWindow && !mainWindow.isDestroyed()) {
                  mainWindow.webContents.send('media-command', 'toggle');
                }
              }
            },
            { type: 'separator' },
            {
              label: 'Quit',
              click: () => {
                isQuitting = true;
                app.quit();
              }
            }
          ]);
          tray.setContextMenu(contextMenu);
          tray.on('click', () => {
            if (!mainWindow || mainWindow.isDestroyed()) return;
            if (mainWindow.isVisible()) mainWindow.hide();
            else { mainWindow.show(); mainWindow.focus(); }
          });
        } catch (err) {
          console.warn('Tray creation failed:', err);
          tray = null;
        }
      }

      app.on('before-quit', () => {
        isQuitting = true;
      });

      app.whenReady().then(() => {
        if (process.platform === 'darwin' && app.dock) {
          try {
            const dockIcon = nativeImage.createFromPath(path.join(__dirname, '../../assets', 'icon.png'));
            if (!dockIcon.isEmpty()) app.dock.setIcon(dockIcon);
          } catch (_) {}
        }
        setupTray();
        createWindow();
        if (tutorialDone()) require('./updater').initUpdater(() => mainWindow);
        app.on('activate', () => {
          if (BrowserWindow.getAllWindows().length === 0) createWindow();
        });
      });

      app.on('window-all-closed', () => {
        discordRPC.destroyRPC();
        if (process.platform !== 'darwin') app.quit();
      });
}
