/**
 * folia-bridge.js — Folia 原生版 WebEffect 插值协议（M2）
 *
 * 协议（native-arch.md §9，前后端统一，枚举扩展只增不删、未知值忽略）：
 *   原生 -> 网页 onNativeEvent(type, payload)：
 *     state       { playing, rate, t, trackId }      离散状态（播放/暂停/切歌）
 *     progress    { t, rate }                        200ms 周期基准
 *     seek        { t, rate }                        锚点重置（乐观 seek / 恢复补发）
 *     queue       { currentIndex, items: [{id,title,artist}] }
 *     artwork     { trackId, ref }
 *     lyrics      { trackId, lrc }
 *     theme       { backgroundMode: web | native-scene, palette }
 *     snapshot    全量状态快照（didFinish / reload 恢复唯一入口）
 *     renderState { active }                         渲染启停
 *     buffering   { buffering }                      缓冲态
 *     spectrum    预留，POC 前原生不发，只定型
 *   网页 -> 原生 sendAction(action, data)：togglePlay / next / prev / seek /
 *     like / minimize / log（只发 warn/error，fire-and-forget，不要求回执）。
 *
 * 时间模型：原生下发 anchor + rate，前端用 rAF + performance.now() 本地插值，
 * 禁止 60Hz evaluateJavaScript。rate 定义域 [0, 2]，时间基准 = 听众感知时间，
 * 只保留 anchor + elapsed * rate 乘法，不留其他速率假设。
 * 初始态：renderState inactive（播放页未打开时不跑 rAF），收到 renderState(true)
 * 或 renderActive 的 snapshot 后才起循环。
 *
 * 日志纪律：内置 gated Logger；release 只放行 warn/error，info 仅 Debug 构建
 * 输出（原生以 WKUserScript 注入 window.__FOLIA_BRIDGE_DEBUG__）；200ms 同步
 * 与 rAF 路径内禁任何逐帧/逐次 console 输出；面板缓冲环形滚动上限 200 条。
 * 过桥日志禁 cookie/token/带签名参数的完整音频 URL（只许平台＋歌曲 id＋错误码）。
 */
(function () {
    'use strict';

    var DEBUG = window.__FOLIA_BRIDGE_DEBUG__ === true;

    /* ------------------------------------------------------------------ */
    /* Logger：gated + 环形缓冲（上限 200 条）+ 过桥只发 warn/error          */
    /* ------------------------------------------------------------------ */

    var LOG_BUFFER_LIMIT = 200;
    var logBuffer = [];

    function sanitizeLogMessage(message) {
        var text = String(message == null ? '' : message);
        // 剥 URL 查询串（禁带签名参数的完整音频 URL）。
        text = text.replace(/https?:\/\/[^\s"'<>`]+/g, function (url) {
            var q = url.indexOf('?');
            return q >= 0 ? url.slice(0, q) : url;
        });
        // mask token / cookie / auth / password / secret 类键值。
        text = text.replace(
            /(token|auth|cookie|password|secret|signature|sig|access_key)\s*=\s*[^&\s"',;]+/gi,
            '$1=***'
        );
        return text;
    }

    function pushToBuffer(level, module, message) {
        logBuffer.push({ t: Date.now(), level: level, module: module, message: message });
        if (logBuffer.length > LOG_BUFFER_LIMIT) {
            logBuffer.splice(0, logBuffer.length - LOG_BUFFER_LIMIT);
        }
    }

    function forwardToNative(level, module, message) {
        // fire-and-forget：只转发 warn/error，info 不过桥；不要求回执。
        if (level !== 'warn' && level !== 'error') return;
        sendAction('log', { level: level, module: module, message: sanitizeLogMessage(message) });
    }

    var Logger = {
        debug: function (module, message) {
            if (!DEBUG) return;
            var text = sanitizeLogMessage(message);
            pushToBuffer('debug', module, text);
            if (typeof console !== 'undefined' && console.debug) console.debug('[Folia][' + module + '] ' + text);
        },
        info: function (module, message) {
            if (!DEBUG) return;
            var text = sanitizeLogMessage(message);
            pushToBuffer('info', module, text);
            if (typeof console !== 'undefined' && console.info) console.info('[Folia][' + module + '] ' + text);
        },
        warn: function (module, message) {
            var text = sanitizeLogMessage(message);
            pushToBuffer('warn', module, text);
            if (typeof console !== 'undefined' && console.warn) console.warn('[Folia][' + module + '] ' + text);
            forwardToNative('warn', module, text);
        },
        error: function (module, message) {
            var text = sanitizeLogMessage(message);
            pushToBuffer('error', module, text);
            if (typeof console !== 'undefined' && console.error) console.error('[Folia][' + module + '] ' + text);
            forwardToNative('error', module, text);
        },
        // 诊断面板读缓冲（不经过桥）。
        snapshot: function () {
            return logBuffer.slice();
        }
    };

    /* ------------------------------------------------------------------ */
    /* 状态                                                                */
    /* ------------------------------------------------------------------ */

    var anchorAudioTime = 0; // 原生下发的基准音频时间（秒）
    var anchorPerfTime = 0; // 收到校准时的本地 performance.now()
    var playbackRate = 0; // 0 暂停，(0, 2] 播放（含变速预留）
    var isPlaying = false;
    var isRenderActive = false; // 初始休眠：播放页未打开时不跑 rAF
    var rafRunning = false;
    var rafId = 0;

    var currentTrack = null; // { id, title, artist, album, duration, isLiked, artworkRef }
    var currentLrc = '';
    var lyricsLines = []; // [{ time, text }]
    var currentQueue = []; // [{ id, title, artist }]
    var currentQueueIndex = -1;
    var currentTheme = { backgroundMode: 'web', palette: {} };
    var isBuffering = false;

    function clampRate(rate) {
        var r = Number(rate);
        if (!isFinite(r) || r < 0) return 0;
        if (r > 2) return 2;
        return r;
    }

    function setAnchor(t, rate) {
        anchorAudioTime = Math.max(0, Number(t) || 0);
        anchorPerfTime = performance.now();
        playbackRate = clampRate(rate);
    }

    /** 前端 60/120fps 插值获取当前精准时间：只保留 anchor + elapsed * rate。 */
    function getInterpolatedTime() {
        if (playbackRate === 0) return anchorAudioTime;
        var elapsedSec = (performance.now() - anchorPerfTime) / 1000;
        return anchorAudioTime + elapsedSec * playbackRate;
    }

    /* ------------------------------------------------------------------ */
    /* 网页 -> 原生                                                         */
    /* ------------------------------------------------------------------ */

    function sendAction(action, data) {
        var handler = window.webkit &&
            window.webkit.messageHandlers &&
            window.webkit.messageHandlers.foliaAction;
        if (!handler || typeof handler.postMessage !== 'function') return;
        var payload = { action: action };
        if (data) {
            for (var key in data) {
                if (Object.prototype.hasOwnProperty.call(data, key)) payload[key] = data[key];
            }
        }
        try {
            handler.postMessage(payload);
        } catch (e) {
            // 桥不可用时静默丢弃，不抛到页面逻辑里。
        }
    }

    /* ------------------------------------------------------------------ */
    /* rAF 插值循环                                                         */
    /* ------------------------------------------------------------------ */

    function tick() {
        if (!isRenderActive) {
            rafRunning = false;
            return;
        }
        rafRunning = true;
        // 热路径：禁任何 console 输出。
        var smoothTime = getInterpolatedTime();
        window.dispatchEvent(new CustomEvent('folia:tick', { detail: { time: smoothTime } }));
        rafId = requestAnimationFrame(tick);
    }

    function startLoop() {
        if (rafRunning || !isRenderActive) return;
        rafId = requestAnimationFrame(tick);
    }

    function stopLoop() {
        isRenderActive = false;
        if (rafId) cancelAnimationFrame(rafId);
        rafId = 0;
        rafRunning = false;
    }

    /** renderState(false) 的等价入口：停 rAF（页面退后台 / 播放页收起时原生调用）。 */
    function pauseRender() {
        applyRenderActive(false);
    }

    function resumeRender() {
        applyRenderActive(true);
    }

    function applyRenderActive(active) {
        var next = !!active;
        if (next === isRenderActive && next) {
            startLoop();
            return;
        }
        isRenderActive = next;
        if (typeof document !== 'undefined' && document.documentElement) {
            // 休眠连 CSS 一起冻结：folia-frozen 停 animation、藏 heavy-canvas。
            document.documentElement.classList.toggle('folia-frozen', !next);
        }
        if (next) {
            startLoop();
        } else if (rafId) {
            cancelAnimationFrame(rafId);
            rafId = 0;
            rafRunning = false;
        }
    }

    /* ------------------------------------------------------------------ */
    /* 歌词解析                                                             */
    /* ------------------------------------------------------------------ */

    function parseLrc(text) {
        var lines = [];
        if (!text) return lines;
        var re = /\[(\d+):(\d+(?:\.\d+)?)\](.*)/;
        String(text).split(/\r?\n/).forEach(function (raw) {
            var m = re.exec(raw);
            if (!m) return;
            var t = parseInt(m[1], 10) * 60 + parseFloat(m[2]);
            if (!isFinite(t)) return;
            lines.push({ time: t, text: m[3].trim() });
        });
        lines.sort(function (a, b) { return a.time - b.time; });
        return lines;
    }

    /** 给定插值时间，返回当前歌词行下标（无歌词返回 -1）。 */
    function lyricLineAt(time) {
        var idx = -1;
        for (var i = 0; i < lyricsLines.length; i++) {
            if (lyricsLines[i].time <= time) idx = i;
            else break;
        }
        return idx;
    }

    function setLyrics(trackId, lrc) {
        currentLrc = lrc || '';
        lyricsLines = parseLrc(currentLrc);
        window.dispatchEvent(new CustomEvent('folia:lyrics', {
            detail: { trackId: trackId, lrc: currentLrc, lines: lyricsLines }
        }));
    }

    /* ------------------------------------------------------------------ */
    /* 主题                                                                 */
    /* ------------------------------------------------------------------ */

    function applyTheme(theme) {
        if (!theme) return;
        currentTheme = {
            backgroundMode: theme.backgroundMode || 'web',
            palette: theme.palette || {}
        };
        if (typeof document !== 'undefined' && document.documentElement) {
            var root = document.documentElement;
            root.setAttribute('data-background-mode', currentTheme.backgroundMode);
            var palette = currentTheme.palette;
            Object.keys(palette).forEach(function (key) {
                root.style.setProperty('--folia-' + key, String(palette[key]));
            });
        }
        window.dispatchEvent(new CustomEvent('folia:theme', { detail: currentTheme }));
    }

    /* ------------------------------------------------------------------ */
    /* 原生 -> 网页：事件总入口（未知 type 直接忽略，不报错、不刷日志）        */
    /* ------------------------------------------------------------------ */

    function onNativeEvent(type, payload) {
        payload = payload || {};
        switch (type) {
            case 'state': {
                // 热路径：不打日志。
                isPlaying = !!payload.playing;
                setAnchor(payload.t, payload.rate);
                window.dispatchEvent(new CustomEvent('folia:state', {
                    detail: { playing: isPlaying, rate: playbackRate, time: anchorAudioTime, trackId: payload.trackId || '' }
                }));
                break;
            }
            case 'progress': {
                // 200ms 周期基准：只更新锚点，不发事件、不打日志。
                setAnchor(payload.t, payload.rate);
                break;
            }
            case 'seek': {
                // 锚点重置（乐观 seek / 中断恢复 / scenePhase 回前台补发）。
                setAnchor(payload.t, payload.rate);
                window.dispatchEvent(new CustomEvent('folia:seek', {
                    detail: { time: anchorAudioTime, rate: playbackRate }
                }));
                break;
            }
            case 'queue': {
                currentQueue = Array.isArray(payload.items) ? payload.items : [];
                currentQueueIndex = typeof payload.currentIndex === 'number' ? payload.currentIndex : -1;
                window.dispatchEvent(new CustomEvent('folia:queue', {
                    detail: { currentIndex: currentQueueIndex, items: currentQueue }
                }));
                break;
            }
            case 'artwork': {
                if (currentTrack) currentTrack.artworkRef = payload.ref || '';
                window.dispatchEvent(new CustomEvent('folia:artwork', {
                    detail: { trackId: payload.trackId || '', ref: payload.ref || '' }
                }));
                break;
            }
            case 'lyrics': {
                setLyrics(payload.trackId || '', payload.lrc || '');
                break;
            }
            case 'theme': {
                applyTheme(payload);
                break;
            }
            case 'snapshot': {
                // 全量恢复：track / lrc / queue / theme / renderActive / time / rate 一次推齐。
                if (payload.track) {
                    currentTrack = {
                        id: payload.track.id || '',
                        title: payload.track.title || '',
                        artist: payload.track.artist || '',
                        album: payload.track.album || '',
                        duration: Number(payload.track.duration) || 0,
                        isLiked: !!payload.track.isLiked,
                        artworkRef: payload.track.artworkRef || ''
                    };
                    window.dispatchEvent(new CustomEvent('folia:track', { detail: currentTrack }));
                }
                if (typeof payload.lrc === 'string') setLyrics(currentTrack ? currentTrack.id : '', payload.lrc);
                if (Array.isArray(payload.queue)) {
                    currentQueue = payload.queue;
                    currentQueueIndex = typeof payload.currentIndex === 'number' ? payload.currentIndex : -1;
                    window.dispatchEvent(new CustomEvent('folia:queue', {
                        detail: { currentIndex: currentQueueIndex, items: currentQueue }
                    }));
                }
                if (payload.theme) applyTheme(payload.theme);
                if (payload.track && payload.track.artworkRef !== undefined) {
                    window.dispatchEvent(new CustomEvent('folia:artwork', {
                        detail: { trackId: currentTrack ? currentTrack.id : '', ref: payload.track.artworkRef || '' }
                    }));
                }
                setAnchor(payload.initialTime, payload.rate);
                if (typeof payload.renderActive === 'boolean') applyRenderActive(payload.renderActive);
                break;
            }
            case 'renderState': {
                applyRenderActive(payload.active);
                break;
            }
            case 'buffering': {
                isBuffering = !!payload.buffering;
                window.dispatchEvent(new CustomEvent('folia:buffering', { detail: { buffering: isBuffering } }));
                break;
            }
            case 'spectrum': {
                // 预留：POC 通过前原生不发；收到也只忽略。
                break;
            }
            default:
                // 未知值忽略（枚举扩展只增不删的另一侧约定）。
                break;
        }
    }

    /* ------------------------------------------------------------------ */
    /* 网页侧进度手势：拖动只预览，松手才发 seek                              */
    /* ------------------------------------------------------------------ */

    /** 拖动中预览：只改本地锚点，不发桥。 */
    function previewSeek(time) {
        setAnchor(time, playbackRate);
        window.dispatchEvent(new CustomEvent('folia:seek-preview', { detail: { time: anchorAudioTime } }));
    }

    /** 松手提交：发 seek 动作，原生回推乐观锚点并执行 seek。 */
    function commitSeek(time) {
        sendAction('seek', { time: Math.max(0, Number(time) || 0) });
    }

    /* ------------------------------------------------------------------ */
    /* 无障碍 / 误触加固                                                      */
    /* ------------------------------------------------------------------ */

    function hardenLyricsContainer(el) {
        if (!el) return;
        // 歌词区 role=text 合并朗读；禁长按菜单与文本选择。
        el.setAttribute('role', 'text');
        el.style.webkitTouchCallout = 'none';
        el.style.webkitUserSelect = 'none';
        el.style.userSelect = 'none';
    }

    function initA11y() {
        if (typeof document === 'undefined') return;
        // 装饰层 aria-hidden，不进朗读。
        document.querySelectorAll('[data-folia-decor]').forEach(function (el) {
            el.setAttribute('aria-hidden', 'true');
        });
        // 歌词容器：role=text + 禁长按菜单/文本选择。
        document.querySelectorAll('[data-folia-lyrics]').forEach(hardenLyricsContainer);
    }

    if (typeof document !== 'undefined') {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initA11y);
        } else {
            initA11y();
        }
        // 初始即冻结：播放页未打开时不跑 rAF（原生 renderState(true) 后才起）。
        document.documentElement.classList.add('folia-frozen');
        // 页面隐藏时本地停 rAF（原生仍以 renderState 为准；回前台且激活时重起）。
        document.addEventListener('visibilitychange', function () {
            if (document.hidden) {
                if (rafId) cancelAnimationFrame(rafId);
                rafId = 0;
                rafRunning = false;
            } else if (isRenderActive) {
                startLoop();
            }
        });
    }

    // 不在加载时自启 rAF：等原生 renderState(true) / snapshot(renderActive=true)。
    window.__FOLIA_BRIDGE__ = {
        onNativeEvent: onNativeEvent,
        getInterpolatedTime: getInterpolatedTime,
        sendAction: sendAction,
        previewSeek: previewSeek,
        commitSeek: commitSeek,
        pauseRender: pauseRender,
        resumeRender: resumeRender,
        lyricLineAt: lyricLineAt,
        hardenLyricsContainer: hardenLyricsContainer,
        Logger: Logger
    };
})();
