=== reasoning ===
我们需要回答中文。任务：对抗评审，找漏洞，逐条回应草案1-4和Q1-Q6，标注同意/反对/替代，最后排序修复清单必做/可选，并指出看似对不解决根因的条目。需要具体机制、反例、更稳替代。不能泛泛。需要理解现状。要严格对抗。需要设计看门狗独立线程/队列并跨线程动UIKit姿势。需要讨论证据不足点。

We need formulate thorough critique.

Let's parse facts.

App: effects overlays. FxOverlayHost91 hitTest whitelist only UIControl itself, rest pass through. Fx root isUserInteractionEnabled false. ConsolePanel82 in main window. Dim outside closes console. Bug after any effect on cannot turn off effect nor console, any taps no response, kill app. Video sample lantern, after ~6.5s every frame console & lantern present, no close. Big lantern visually over console button area. User says all four effects cannot close, only lantern video.

(95) design:
1 normal: console effect button -> toggleX -> start/stop -> setX(on,src) -> log p94 fx sw fx=<code> on=... src=...; close cleanup logs p95 fx clear fx=<code>. Tap dim close console via handler, both increment ConsolePanel82.handlerTrace95.
2 double fallback:
- passive probe UITapGestureRecognizer tapProbe92 on main window, cancelsTouchesInView=false, delegate always allow. shouldReceive -> probeRawShould95(touch): raw point log (same-second throttle) + first point after arm logs p95 probe first.
- watchdog probeGuardCheck95 only call at end of probeRawShould95 (:818). Logic: while effect on, if tap hits console registered effect button frame or dim frame -> schedule 350ms -> if handlerTrace95 no new value within period (handler chain broken) -> probe directly performs close (via existing setX path toggle, or notification asking console dismiss), logs p95 probe guard fired=1.
- arm edge any effect false->true logs three strings: p93 probe arm, p94 fx arm, p95 probe arm view=…; setX logs p94 fx sw. Synchronous breadcrumbs, other breadcrumbs work.

Evidence:
- Two logs didn't capture stuck session. Mechanism: two rotating files; new session startup preserves previous session last 200 lines as prevtail (one-time non-rolling); export = prevtail + current file.
- First log after video ~0.5h export: recording session zero lines, pushed by later use; retained window no effect ever on. Web canvas resize ~30 lines/sec.
- Second log per process: turn effect stuck -> kill app -> reopen -> immediately export: retained contains four adjacent sessions total ~83s, no segment ever effect on—fx switch/arm/raw/dismiss/clear all zero, deck breadcrumb normal. Stuck session not in window; prevtail only at next startup; if startup chain abnormal after kill, tail may break. Four sessions total 83s means stuck session either outside retention or no breadcrumbs.
- Wall high frequency: fast scroll ~70.5 lines/sec, 200-line tail covers 2.8 sec.
- Therefore tap dead layer unresolved; criteria ready.

Draft:
1 forensics three fixes:
a fx event lines pinned: not evicted by ring, separate small file or marked retain, ensure stuck session fx events saved regardless of flood.
b prevtail 200 -> >=2000 or throttle high freq wall lines (one or both).
c prevtail rolling save: not only next startup, periodic/key event sync tail file, avoid kill break.
2 watchdog decouple from taps: effect on arm edge timer arm independent watchdog, no tap needed; responsibility periodically self-check "close path alive" (what check, interval undecided—ask design/attack). Original 350ms post-tap watchdog retain second layer.
3 independent exit: beyond above, another exit path not through console handler chain nor effect overlay (candidates system gesture/volume key/shake/dynamic island/lock screen/force gesture area undecided), ensure effect on user always can retreat; maintain hard req overlay only intercept own interactive elements rest pass; console can open, tap effect button closes same frame.
4 triage criteria after sample: arm yes raw no -> dead window/overlay interception; arm+raw yes, dismiss try & fx clear no -> dead dispatch/execution; raw yes, guard fired=1 & fx clear no -> watchdog execution path broken.

Questions Q1-Q6 as above.

Need answer as adversarial reviewer. Need maybe identify contradictions:
- FxOverlayHost91 hitTest whitelist only UIControl itself; but visual lanterns big over console buttons should not intercept because isUserInteractionEnabled false? Wait "特效绘制根视图 isUserInteractionEnabled=false 整窗不接点按; 自有浮层卡挂 FxOverlayHost91 hitTest white list only UIControl itself..." Big lantern visual over console button: if noninteractive drawing, shouldn't block. But if host hitTest returns nil except controls, should pass. Yet bug all taps no response perhaps because some overlay/window swallowing touches. Need inspect possible gestures on main window? tapProbe cancelsTouches false but gesture recognizer delegate always allow? A UITapGestureRecognizer on main window with delegate always allow, cancelsTouches false generally doesn't prevent controls. But it can delay touches? recognizes simultaneously? It might still set delaysTouchesBegan? Default false for UITap? Actually UIGestureRecognizer has delaysTouchesBegan default NO except? UIScrollView? UIGestureRecognizer delaysTouchesBegan defaults NO? cancels false. shouldReceive called only if hit-test view attached? UIKit delivers touch to window; gesture recognizers on window? Gesture recognizer attached to view receives touches before hit-test? Need precise: A gesture recognizer attached to a view receives touches hit-tested to that view or subviews? For gesture recognizer on window, all touches in window are hit test to descendants; window's recognizers can observe touches? Yes if hitTest view is descendant. If touch is swallowed by another window, main window's recognizer not called. If hitTest returns nil due to overlay? Actually touch at a point: window hitTest returns deepest view. Gesture recognizers attached to that view and superviews receive. If some overlay view returns itself and doesn't forward, main window recognizer won't receive because different window? Main window may still? Event delivered to window under point by window server; only one window receives. If overlay window level 0 same coordinate maybe top window receives. If its root disabled? isUserInteractionEnabled false -> hitTest returns nil, window itself might receive? UIWindow hitTest? If subviews disabled and no interactive, hitTest may return window? Then main window? Window ordering: hitTest on each window? UIApplication sends event to window that hitTest returns non-nil. If top window hitTest returns nil, maybe next window? Need not overstate. We can say raw probe on main window cannot see touches consumed by another UIWindow/UIAlertController/presented modal, nor touches whose hitTest view is not in main window hierarchy; thus raw absent doesn't prove overlay intercept within main window, and raw present doesn't prove hitTest/view chain normal. Need criteria refine with hitTest instrumentation at UIWindow/UIApplication sendEvent or swizzle, not just gesture.

- HandlerTrace only incremented by console handler and dim handler. Watchdog checks no new value. But if handler executes and fails to toggle, handlerTrace increments, no guard fired; bug could be execution/state. Also handlerTrace could be incremented by unrelated console handlers (if any) causing false alive. Need per-effect tokens/generation, not global trace. Need ack at final state, not handler entry.

- Watchdog tied to probeRawShould: if touches not delivered, no check. Draft 2 independent timer solves delivery but if main runloop blocked no timer. Need independent thread/queue, but cannot mutate UIKit off main. Need design: independent watchdog on DispatchQueue/Thread timer checks heartbeats, then dispatch async to main; if main not responsive, cannot clean overlay via UIKit. To guarantee escape, need system-level/independent UIWindow? But any UIKit mutation still main thread. If main thread deadlock, nothing inside process can draw or dismiss; only terminate? You can't safely force close UIKit from background. Could use UIApplication.requestSceneSessionDestruction? Must be main? Most UIKit main. Could set non-UIKit flag and watchdog?? If main thread dead, app dead; external system gestures (volume? accessibility?) maybe not. Need avoid main-thread blockage as root. Need prove via hang detection not just closure.

- "独立退出路" candidates: volume key via KVO requires app audio session active? outputVolume KVO only after audio session active, won't receive if app inactive; not App Store issue? Private API? Monitoring volume via KVO is common but unreliable; volume HUD changes, not fresh after iOS? It may be observed but `AVAudioSession.sharedInstance().outputVolume` KVO, but system volume changes only if app's audio session active; no granular reliable in background; no guarantee. Shake `motionEnded` requires device motion? UIResponder motion events; not if view/controller in responder chain? With overlay root disabled? Main window? Needs first responder? Actually shake motion events delivered to responder chain if app active, but can be disabled by `applicationSupportsShakeToEdit`? Not reliable, can be disabled by system/accessibility, user may not know, false triggers. System-level gesture (edge swipe) conflicts with OS app switcher/home? Cannot intercept system edge gestures reliably; home indicator swipe is OS. Dynamic Island/lock screen controls require ActivityKit Live Activity and user interaction, not immediate, App Store okay but heavy and not guaranteed; also main app killed? Lock screen controls can't close in-app overlay if app not active? It can via App Intents maybe launch/NSUserActivity? Not immediate. Best: a dedicated UIWindow at higher level with a small always-visible panic close control (or handle touches) that sits above overlays, but must not block all touches: window hitTest returns only panic button frame, nil elsewhere; root view background clear, isUserInteractionEnabled true? A separate `UIWindow` with `windowLevel = .alert + 1` and hitTest override that returns button for frame, nil otherwise. But if it returns nil for outside, does it pass through to lower window? For UIWindow hitTest nil, system may send to lower window? Need verify. On iOS, if top window's hitTest returns nil, event may go to next window? I think hit-testing across windows: UIApplication finds window containing point with highest level? It calls hitTest on each window? Need precise. UIWindow hitTest override can return nil to pass through? Apple's event routing: hitTest:withEvent: on window returns view; if nil maybe window itself? UIWindow inherits UIView hitTest; if subviews return nil and point inside window, super hitTest returns self if userInteractionEnabled. To pass through window, override hitTest to return nil outside button, and set window isUserInteractionEnabled true? Does system then try lower windows? There is `UIWindow` hitTest called for all windows in order? I believe event routing to window uses `hitTest` on all windows, if nil maybe not. There is known "passthrough window" pattern: override hitTest return nil for points outside desired view; lower window receives touches. Yes common for floating button overlays. Need ensure not open to jailbreak? App Store okay with extra UIWindow? Yes but may affect accessibility, rotation, scenes; use UIWindowScene. Also if overlays are separate same-level window above? Need set panic window above all app windows (level > fx window) but lower than system windows. On iOS 13 scene windows: can create additional UIWindow in scene, level `.alert + 1`. But if system keyboard/alerts? Fine.

But if main thread blocked, panic window also can't respond. Need not if root is touch routing not block. But for "always exit", additional window solves touch interception but not main thread dead. Need watchdog with main thread hang detection and maybe crash (abort) not user-friendly. But can't guarantee if main dead. Need mention.

- Draft forensic pinned区: if same process/file writes on main/serial queue, if main stuck or kill no flush. Need independent fsync. But if main thread stuck, event generation stops; can't log. Pin fx events generated on main; if main blocked after fx on, no further. Need log at arm synchronously before leaving arm; and periodic heartbeat from independent queue writing to file with O_APPEND/O_DSYNC. UserDefaults not suitable for high-frequency, synchronous? `UserDefaults.synchronize` deprecated, not guaranteed immediate; default writes async cfprefsd, kill may lose. Better `os_log`? Logs captured by Console, not in app file; survives process termination? Unified logging can be streamed/exported by device, but accessibility in field? Could use `os_log` plus file. For app file: open with O_APPEND, write complete framed records via `write`, `fsync`/`fcntl(F_FULLFSYNC)` for critical events, not from main? Critical event write on main may block but okay at arm before freeze; must not depend on next startup. Use dedicated serial IO queue; but if main stuck, critical arm event already enqueued? For guaranteed pre-crash, synchronous `F_FULLFSYNC` on main for rare fx events. But if the very event causing hang before write, hmm. Need record before toggling? At arm edge after state changed; if toggle itself hangs, no arm. Better log before and after state transitions both in toggle/setX. Also sequence numbers/generation per effect. Use `OSLog` and store into ring buffer in memory? Memory lost on kill. Pinned separate file with no eviction; rotate small segments and retain session IDs. But if all logs in same binary file and app sandbox remains, okay. Need set no high-frequency writes in same file? Separate file.

- prevtail 200 -> 2000: at 70.5 lines/s covers 28s, but sessions total 83s and one 2-min recording, maybe not enough. Need dynamic bounded-by-time vs lines. The video session 2min at 30 lines/s resizing = 3600 lines plus wall, 2000 insufficient; need time-based retention e.g. last 10 minutes or capped size. But if high frequency 70.5 lines/sec, 10 min = 42k lines. Feasible small MB. Yet prevtail one-time at startup cannot capture current session until next launch. If user kills and reopens, previous session tail should save at new startup but if kill right after? Actually previous session file exists; prevtail copy at startup. But second log supposedly no effect due to four sessions window; if app killed after effect then reopen, that session should be previous? Maybe because startup overwrote prevtail with current (empty) before exporting? Need understand. They export prevtail + current file. On new session startup, preserve previous session last 200 lines to prevtail. If user kills stuck and reopens, prevtail should contain stuck session last 200 lines. But they found no effect. Maybe because after kill, did not immediately export; app created sessions and prevtail overwritten multiple times? They say four adjacent sessions total 83s, no effect, stuck not in window; prevtail only at next startup. If multiple launches after stuck, prevtail overwritten by later session tails. Need save per-session tails with unique IDs, not single prevtail. Also preserve current session on crash? The current file before kill may be flushed? Could export after relaunch before data overwritten. Need snapshot all log files by session id, never overwrite; on startup move previous active file to archive rather than just tail. Use append-only session logs with metadata. That is safer than increasing tail. Also if kill after effect, current session file may not be synced to disk; repeated writes flush? Need sync.

- They mention "four sessions total 83s no effect" maybe because app relaunch loops due to crash? If stuck session not captured maybe because session was not logged? Need instrument at launch/session with unique boot ID, effect state persisted? Store current fx state in persistent store at arm/clear with generation; on next launch detect prior uncleared state (like "crash while fx on") and write diagnostic. This is key: even if logs lost, persist `fxActive` + timestamps + generation to UserDefaults/file synchronously when state changes. On next startup, if active from previous session, log `previous session ended with active fx` and write to crash marker. That can prove stuck session and capture sequence. Even if no raw logs, marker has effect code and on/off transitions. Use not UserDefaults? File with fsync. This should be in forensics.

- Potential source: FxOverlayHost91 hitTest whitelist only UIControl, but if console panel itself is behind FxOverlayHost? Wait "自有浮层卡挂在主窗的 FxOverlayHost91 上, hitTest whitelist only UIControl..." Console in main window. Big lantern visual over console. If FxOverlayHost is above console and hitTest returns nil for non-UIControl, pass through. But if a big lantern is a UIControl? Maybe not. It only passes UIControl itself; if it returns a UIControl, system sends. But other touches pass to next. Could bug be because `hitTest` returns nil from overlay host, causing main window hitTest to stop? Need understand UIView hitTest: If a subview returns nil, superview continues checking other subviews and itself. If FxOverlayHost is subview of main window, returning nil only makes superview check other subviews. If top overlay is separate window, returns nil might block lower window if window hitTest. Need establish window stack. The description says FxOverlayHost91 on main window? "自有浮层卡（祝福卡/写灯钮/推荐卡）挂在主窗的 FxOverlayHost91 上" so host main window. Fx drawing root maybe another window? "特效绘制根视图 isUserInteractionEnabled=false 整窗不接点按" likely a separate window. FxOverlayHost main window. If drawing window is same level, because isUserInteractionEnabled false, should not intercept. But if a window is above main and its root disabled: UIWindow itself default userInteractionEnabled true. `isUserInteractionEnabled=false` on root view (window's root) not necessarily window? A `UIWindow` is a UIView. If only root view controller view disabled, window hitTest may still return window? Let's recall: UIWindow's rootViewController.view is subview of window. If root view userInteractionEnabled false, hitTest might return window itself? Window is userInteractionEnabled true, point inside bounds, no subview hit, so hitTest returns self. Thus the disabled root view might still allow the UIWindow to swallow touches! This is important. If effect drawing window is a separate UIWindow, setting root view interactive false is insufficient; must override `hitTest` on UIWindow to return nil (or outside interactive subviews), set window.isUserInteractionEnabled=false? If `UIWindow.isUserInteractionEnabled=false`, maybe hitTest returns nil? But can you set? UIView property yes. Or use `UIWindow` subclass passthrough. The fact "特效绘制根视图 isUserInteractionEnabled=false 整窗不接点按" may be false assumption. A top-level UIWindow can swallow even if its root view disabled because window itself hit tests. This could explain every tap dead: top effect window receives and swallows all touches; tapProbe on main window never sees raw; console cannot be tapped; dim cannot. The large lantern over console is red herring. This is a strong alternative root cause. Need highlight. Also FxOverlayHost whitelist for cards works only if touches reach main window, but effect drawing window above blocks. If effect drawing window level 0 same as main? UIWindow ordering among same level based on last made key/visible, maybe effect window above; even if not, if it is key? `windowLevel=0`; system may route to topmost window whose hitTest non-nil. If drawing window returns itself for entire screen because root disabled, all taps swallowed. This fits: effects on => effect drawing window becomes visible and hitTest returns window => no controls/dim/tapProbe. Closing via console impossible. It also explains all four effects: any on shows noninteractive window but actually swallows. It explains video: console remains visually, no taps. It may also explain probe logs absent? If tapProbe on main window never receives touches, raw absent. But arm logs? Should have arm. But logs didn't capture. Need still fix.

Need see (95) bug originally from previous reviews maybe caused by overlay. The task likely expects adversarial review to identify. Need not assume? We can present as hypothesis demanding test, not conclusion. It fits Q5 raw probe blind spot. Need attack "isUserInteractionEnabled=false 整窗不接点按": A UIWindow with disabled root view can still hit-test to window itself if window remains userInteractionEnabled; must implement passthrough UIWindow subclass, or set window.isUserInteractionEnabled=false? Actually can a window be userInteractionEnabled false? It inherits. But if set on window, hitTest returns nil? Apple's UIView hitTest: if userInteractionEnabled false -> returns nil. Then sender might look at next window? Need verify across windows. Better override `hitTest` and `point(inside:)` to return nil outside interactive elements. Also if window's root view disabled but window enabled, hitTest returns self when point inside window (window is a UIView, userInteractionEnabled true) if no subview. This is very plausible. Need mention `isUserInteractionEnabled=false` on root view does not set window; UIWindow is hit-test root and itself receives if no subview. This is line-level mechanism not line number.

Also FxOverlayHost hitTest whitelist only UIControl itself: If returns nil for non-UIControl, it may still block? If host is in main window above console, returning nil should allow sibling below if host's superview continues. But if host is itself in a separate window, returning nil from view may still window self. If host view returns nil for point, window hitTest then may return window? If host is subview, superview checks other subviews. But if host is window's root, nil -> window returns itself. Need differentiate.

Need discuss `UIControl` whitelist too narrow: Some interactive elements are not UIControl (SwiftUI, UITextField? UITextField is UIControl; UIButton is UIControl; UITapGestureRecognizer on UILabel; cells; dim maybe UIView with gesture not UIControl). If dim close is a UIControl? Console dim likely a UIView/button? They mention dim frame registered. If dim is a bare UIView with tap gesture, whitelist only UIControl excludes it. If console panel itself maybe UIControl? If dim is overlay control? They say point dim close console via handler; if dim is UIControl? Not sure. Need note: hitTest whitelist by `UIControl` only will drop touches for gesture-based dim/cards unless they are UIControl; but bug after effect on? Console effect buttons are UIControl likely.

Need watch for gesture recognizer on main window: `cancelsTouchesInView=false`, delegate always allow, but `shouldReceive` can be called even if another window? no. Also even on main window, if a tap lands on `UIControl`, window gesture recognizer and control's own touch handling can coexist. But gesture's `shouldReceive` may not be called if touch is not in main window. The guard only at probeRawShould, so if any overlay above main intercepts, no check. Draft 2 independent timer.

Need discuss `handlerTrace95` and `probe guard`: 350ms timing race. If handler executes but takes >350ms (e.g., animation/stop video), guard might fire and toggle again, causing state flip on then off? If handler later completes, close may be undone or reentrant. If start/stop expensive; the watchdog uses no new handlerTrace within 350ms; but handlerTrace increment at entry or end? "两处落痕递增 handlerTrace95" unclear. If at handler entry, immediately no new? It could still race. If at end, maybe slow. Need use transaction/generation and cancel on state changed. Also guard "directly performs close via existing setX pathway toggle" could double-toggle: if handler actually processes after 350ms, guard toggles off then handler toggles off? If toggle not idempotent (toggle uses current state), two toggles might turn back on. setX(false) idempotent with guard? They say via existing setX pathway toggle, or notify dismiss. Need avoid double action with generation. Use only idempotent `setX(false)` not toggle. Need mention.

Need discuss setX `guard isX != on`. If already true and request true returns; for closing false, okay. But if state already false, no log. If call not reaching setX, no log. Mechanisms:
- `toggleX` might read `isX` incorrectly? If toggle from true to false? It may invoke stopX which has mutex; maybe if another startX in progress? 
- `startX` inside `onStateChanged` callback re-enter and reset state. Need inspect? Not given. We can hypothesize event callbacks from asynchronous renderer/presentation call `setX(true)` after close; timer/particle completion? 
- UI event not delivered as suspected.
- Gesture recognizer state/failure prevents control action. 
- `isUserInteractionEnabled` on ancestor false? Console disabled? 
- Animations with `isUserInteractionEnabled=false` set during start and never restored. It would block console even after effect? If startX sets main window/console `isUserInteractionEnabled=false` to prevent taps and fails to restore on some path? But console should be able to close effect; if main window disabled, all taps dead. The bug after effect on exactly. Maybe overlay host intercept. Need identify from source: setX guard doesn't prevent closing if on=0 and state true, because guard isX != on passes. Unless isX already false due to inconsistent state, but effect still visible. Then close request `setX(false)` hits guard and returns without `fx clear`, leaving visible overlay. Console could still close? But user says console can't close too, all taps no response. If state false but visual on, console taps should work; unless console close handler also affected by effect? The dim/console issue may be separate: maybe effect window blocks all. 
- If state flips back to true by completion callbacks after close; logs would show fx sw on=0 and perhaps on=1. No sample.
- If `toggleX` uses `!isX` and effect visual on but state false, pressing button would "open" not close, maybe arm again; not no response. 
- If `handlerTrace95` increments but no effect? Need log acks.
- Synchronous call can fail to reach setX if control action not called: hit test, gesture, control disabled, window swallowed, responder chain. If action called, synchronous call should reach unless exception/crash? But app doesn't crash, main loop continues? If main blocked, watch UI frozen? Video shows frames continue (animations? actual video frames). If UI thread blocked, visual effects might stop animating. They only know frames show console/lantern present; if main runloop blocked, recording continues but UI static. They might not test animations. Need use instrumentation heartbeat.

Need discuss log no fx events in retained sessions. If effect was on, arm should log. If no fx arm in logs, either logs lost or arm not logged. But arm edge logs are synchronous. However if the effect is started before app launch? Or effect state persisted and restored on launch? They say "开启特效后". Could button action calls `startX` but arm logs only when `false->true` in setX? If setX has guard `isX != on`, if state already true due to persisted state, pressing doesn't log. If effect visual starts from restored state without arm? Then no arm. Need test fresh state. Also if toggling on from console starts `startX` but arm logs in `setX` after `isX` set? should. Need capture exact launch and effect actions in session, not rely on prevtail.

Need propose replacing `prevtail` with append-only per-launch session files, unique boot ID, automatically mark active/unclosed. On every app start, never delete; rotate by size; retain at least e.g. 20 sessions/50MB. At effect on/off, append a compact JSON event to a dedicated `fx-events.log` with `O_APPEND|O_DSYNC`; on next launch scan for unmatched arm and mark previous session. This addresses Q1. Also write heartbeat from main runloop and from separate queue. Include `sendEvent`/window hitTest instrumentation. Instead of high-frequency logs, use counters per second.

Need propose instrumentation for hit-test/window stack:
- At effect arm, log window list: `UIApplication.shared.connectedScenes` windows, window.windowLevel, isKeyWindow, isHidden, alpha, rootVC, `isUserInteractionEnabled`, class names, frame, hitTest at console button center, dim center, effect overlay center. This directly tests window swallow.
- Add a `sendEvent` swizzle/UISceneDelegate instrumentation? In app, subclass UIWindow or install event tap: override `sendEvent` in main window and effect window to log touch phase, window id. Compare which window receives.
- On effect on, call `window.hitTest(point, with: nil)` for console button center on each window and log returned view class/pointer; but `hitTest` with nil event maybe not accurate? Use actual event? Still.
- Add a transparent diagnostic overlay? no.

Need design independent watchdog:
- Use dedicated `DispatchQueue(label: "fx.watchdog")` with `DispatchSourceTimer` or a `Thread` runloop. It must not touch UIKit. It monitors:
  1. `mainRunloopHeartbeat` incremented by a `CADisplayLink`/`DispatchQueue.main.async` recurring probe; if heartbeat stale > e.g. 1s, record hang marker and perhaps not attempt UIKit until main recovers.
  2. `fxStateGeneration` and close request transaction: on effect on, store `FxSession(activeCode, armedAt, generation, lastHandlerTrace, closeRequested?)`. Watchdog timeout e.g. 2s after on? No, user may not request close. It should check invariants: if effect is visually active? Can't inspect UIKit off-main. It can check that main heartbeat alive and that close path responds to injected close? It could periodically dispatch a "canary" block to main; if main runloop responsive, canary executes and verifies state; if not, write log. But periodic self-check "close path alive" can be a canary close? Need not close while user wants effect on. Could run a no-op close-path transaction: on main, call `setX(current, src:"watchdog")`? That logs but no visual change due guard; but if guard swallows, not useful. Better implement a dedicated `FxCloseabilityProbe` that traverses from console button to effect state without changing UI: verify console button is userInteractionEnabled, its window is key, `hitTest(button center)` returns button or descendant, `FxOverlayHost.hitTest` at same point returns expected pass-through, effect window hitTest returns nil/passthrough, handler registered. But doing on main can detect if console is blocked by hitTest. However cannot from background. If main responsive, run every e.g. 1s. If main unresponsive, independent queue logs hang but cannot fix UI. This satisfies "check close path alive" and catches window swallow. If check fails, watchdog can dispatch async to main to set a "panic close all effects" via idempotent `setX(false)` and dismiss console; but should not auto-close while effect intentionally on if a probe falsely fails. Could present a UI panic button instead.
- Original 350ms post-tap guard retained but rewrite: event from tap must carry effect code and generation; on tap at registered frame, schedule 350ms on main? If dispatch to background, verify handler ACK generation; if no ack, cancel via `forceStopFx(code, reason)`. Use idempotent `setX(false, src:"guard")` not toggle. The guard should not rely on raw probe alone: add handler "will handle" and "did close" tokens. Also if tap never reaches main window, independent timer/panic button handles.

Need "cross-thread UIKit risk": UIKit state must only mutate on main thread. Background watchdog can:
- Maintain atomic generation/flags; write logs; if main responsive, dispatch to main to perform `forceStop`; use `DispatchQueue.main.async` with timeout? If main blocked, cannot.
- Use `UIApplication.shared.beginIgnoringInteractionEvents`? deprecated and main only.
- Cannot call setX/UIView from background; no locking will make it safe.
- If main thread hangs due deadlock, only safe in-process recovery is not possible; you need not deadlock main, or use watchdog to `exit(0)`? Crash/terminate is not acceptable maybe, but better than kill by user? App Store discourages exit. Or use system scene session destruction via main (also blocked). 
- Could use `os_unfair_lock`? no.

Need discuss "独立退出路" with window:
- Recommended: dedicated `FxPanicWindow`/`EmergencyCloseWindow` in same `UIWindowScene`, level above Fx windows but below system alerts, with tiny button in safe area (e.g., "关闭特效" persistent while effect on). Its root view controller's view background clear, `hitTest`/`point(inside:)` return only button frame; outside returns nil so pass-through. Crucially implement passthrough on `UIWindow` subclass, not just root view. On effect arm show; on clear hide. The button calls idempotent `forceStopAllFx(reason:"panic")`, then `dismiss console` maybe. Accessibility label. Does not rely on console handler. This is App Store compliant (auxiliary UIWindow) if not obscuring, uses public API. But if main thread blocked, button won't work; pair with main heartbeat detection and deadlock prevention. 
- Need ensure panic window doesn't itself cause original bug: if its hitTest returns nil outside, lower windows receive? Use known pattern. But test on device. Set `windowLevel = .alert - 1`? Actually above all app windows. If console? It only returns button. When no effect, remove from hierarchy/hide.
- Alternatively put a close button inside `FxOverlayHost` above effects and UIControl whitelist; but bug might be overlay window swallowing; a separate window is more robust. Yet another window could worsen touch routing; must instrument.

Volume key: oppose as primary. KVO on `AVAudioSession.outputVolume` observes hardware volume changes but requires audio session active, may not fire if system volume at max/min (no change), does not distinguish press direction reliably, volume HUD, user may change volume expecting audio. App Store no private API but fragile. Could use MPVolumeView hidden? Not reliable. Shake: oppose primary; requires motion availability and user knowledge, conflicts with accessibility, mis-triggers, not guaranteed. Dynamic Island/lock screen: too heavy, requires Live Activity user permission? ActivityKit not for this; lock screen controls via App Intents could launch app, not immediate if foreground? Not robust. System-level gesture/edge: cannot guarantee; OS home/app switcher may background, but returning should be able to close; however user can leave app (they did). The requirement "within App any effect on always exit" maybe app switcher kill is not acceptable. A panic button window is best.

Need Q5: raw probe blind spots:
- `UITapGestureRecognizer.shouldReceive` is called when recognizer receives touch after hit-testing has selected a view in its associated view's hierarchy. If touch is delivered to another UIWindow above (effect window), main window's recognizer never receives; raw absent. That just means another window got event, not necessarily "overlay interception layer" among windows? Actually that is window layer. But if a modal presented VC or system window takes touch, raw absent but not Fx overlay. If touch is on a UIControl whose `isExclusiveTouch`? Gesture recognizers on superview still receive? Unless `cancelsTouches` no. If point outside main window? all screen. If window's root view has `isUserInteractionEnabled=false`, but window returns self -> main recognizer absent. If a child view overrides hitTest and returns a view not in main window? no.
- Also `shouldReceive` can be called even if later another gesture/control cancels? For UIEvent, yes.
- If touch has no gesture because `tapProbe92` delegate? It should. But if `tapProbe92.isEnabled=false` or view not in hierarchy? not.
- If touch begins outside main window due keyboard/system alert, raw absent.
- Therefore "arm有 raw无 → 死在窗口/覆层拦截层" too coarse. Need instrument both main and effect windows' `sendEvent`, plus scene `sendEvent`? `UIWindow.sendEvent` logs window receiving. Also log `UIApplication.shared.sendAction`? For controls. Add hitTest snapshots. Criteria:
  - arm on, `FxWindow.sendEvent` gets touch while MainWindow doesn't -> effect window swallow.
  - MainWindow sendEvent gets, tapProbe.shouldReceive no -> gesture disabled/hitTest? Wait if MainWindow sendEvent gets but no shouldReceive maybe window hitTest returns no? sendEvent called on window for all touches? UIWindow sendEvent receives before hitTest? Actually `sendEvent` is called for event delivered to window; it then dispatches to hitTest view. If main window `sendEvent` gets, raw should get if recognizer. If effect window sendEvent gets, main no.
  - Main sendEvent + raw + no control action -> hitTest returned non-control/gesture conflict.
  - Control action enters handler but no setX -> exception/guard.
  - setX false logs but overlay remains -> visual/state desync.
Need add effect window `sendEvent` instrumentation and main window subclass. Since cannot subclass existing UIWindow easily, can add `UIWindow` subclass? Or use `sendEvent` swizzle in debug only. They can add category method exchange for UIWindow in app? Not ideal. Or use `UIGestureRecognizer` on effect window? If root disabled, gesture won't? Use `UIWindow` subclass for both windows.

Need discuss "log raw no" may be caused by effect window swallowing; this is likely root cause. We should explicitly say draft 2 watchdog independent timer may not help if tapping is dead because effect window swallows all touches; watchdog must detect/repair window hitTest, not just closure. If watchdog auto closes after timer? It needs know user wants close; independent periodic "close path alive" can check hitTest and if effect window blocks, force its `isUserInteractionEnabled=false` or override hitTest; but if main thread alive, can fix. At arm edge, can proactively ensure effect window's hitTest passthrough. The minimal fix might be set effect UIWindow.isUserInteractionEnabled=false or subclass hitTest return nil. Also FxOverlayHost hitTest should not return window self. Need test.

Need attack draft 1 a:
- "pin fx events not evicted" if same file/queue may not solve. Need separate append-only dedicated file and synchronously commit critical events. Also pin by ring only doesn't help if no events generated (arm missing due state already on, or bug before log) or if process killed before flush. Need event schema with monotonic seq, boot/session id, state snapshot, hitTest snapshots. A small file can be overwritten if not careful; use append and never truncate until export. File protection? If device locked? Not relevant.
- High frequency: use level/event sampler, not logging every raw tap? Raw point logs same-second throttle but can still flood. Need maintain ring in memory plus write critical events. At export, include counters. But if killed, memory lost. Critical only.

Draft 1 b:
- 2000 may be insufficient; choose time/size retention and per-session files. Throttle high freq but don't drop fx. Use aggregated counters for wall rows. Also the real issue is single prevtail overwritten by later launches. Need archive per session. Increasing lines is band-aid. Mark "反对 as sufficient; agree with throttle".
- 30 lines/sec resize: 2000 = 66s but with multiple? Video 2 min => ~3600. 70.5/s => 28s. Stuck session plus subsequent 83s, could still push. Need retain at least several minutes * peak + all fx events. Use bounded size e.g. 5-10 MB per session, rotation by day/session. Do not rely on 2000.

Draft 1 c:
- Rolling prevtail: agree, but need not write every line fsync; write append-only session log continuously; on key events fsync. If main thread hangs, rolling writes on main stop. Use dedicated I/O queue and write from logging API. But if logging called from main after hang, no. The arm/clear events synchronously before potential hang. Also maintain a "last known good state" file updated at arm/clear with atomic replace. On next launch detect orphan active. 
- Danger: periodic sync high frequency can cause I/O stalls. Use batched writes on background for raw; critical sync for fx.

Draft 2:
- Agree decouple from tap, but need design. "periodic self-check close path alive" can be:
  - main-thread canary every 1s; update `mainTick`.
  - background watchdog checks canary. If missed >2s, write hang log with stacks? Can use `Thread.callStackSymbols`? Background can capture its own, not main. Use `os_signpost`? Maybe `dispatch_async` cannot get main stack. For app, use `SIGABRT`? No.
  - If main responsive, run `hitTestAudit`: for current effect and console effect button/dim center, call `window.hitTest` on each window with a synthetic event? Need actual UITouch impossible. But can call `window.hitTest(CGPoint, with: nil)`; many views ignore event. Log which view. It can detect top effect window returning itself. Also check `window.isUserInteractionEnabled`, root, host hitTest.
  - Verify close path by an idempotent "dry-run": call a new `canCloseFx(code)` that validates state and logs `p96 fx closeable code=... ok=... blockers=...` without changing. If blockers, force fix (e.g., correct effect window hitTest) or show panic button.
  - Watchdog should only act on a real close request or invariant violation, not auto-close every few seconds while user intentionally on. It can arm a timeout only after a tap or user close command; independent timer detects if close request not ACKed within e.g. 500ms and force stop. For "tap never delivered", the timer won't know close requested. Need panic button or "close path alive" monitoring. If it proactively detects console hitTest not possible while effect on, it can log and maybe auto-fix overlay hitTest; not close effect.
  - If root cause is window swallow, at arm edge the watchdog can schedule audit immediately after showing effect and if effect window hitTest returns itself for console button center, set pass-through or hide window. But automatic repair of hitTest perhaps safe: ensure effect window never intercepts outside whitelist always.
- If main thread blocked, background timer cannot mutate UIKit. Need explicitly state no in-process UIKit watchdog can guarantee. To mitigate, prevent main-thread block; use background watchdog to log hang and optionally crash/terminate? App Store? `abort()` not allowed? Better not. For user escape, if main hung, app switcher/kill is only path; no overlay can respond. Thus "独立看门狗保证退出" is false if root is main thread hang. Need measure main heartbeat. If no main hang, watchdog can fix.
- Cross-thread UIKit: never call UIView/UIViewController/UIWindow off main. Use `DispatchQueue.main.async`; if main blocked, don't try. Use atomics/locks for state. For forced close, dispatch to main with generation and check still active. If cannot acquire main within timeout, log only. Could use `CFRunLoopPerformBlock`? Still main. There is no sanctioned cross-thread UIKit.

Draft 3:
- Agree with independent exit but candidates: choose panic window. Oppose volume/shake. Need maintain hard requirement: overlay only intercept own UIControl, rest pass; but whitelist by UIControl too broad? Actually only return UIControl itself. Need include gesture-based controls? For overlay own controls, if using gesture, whitelist must include them or wrap in UIControl. For effect window, override hitTest to return nil for all (since no interactive drawing) not just root disabled. For FxOverlayHost, implement `hitTest`:
  ```
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
      guard let v = super.hitTest(point, with:event) else { return nil }
      return isAllowed(v) ? v : nil
  }
  ```
  But beware `super.hitTest` returns host itself if no subview; then return nil. Also if `super.hitTest` returns a descendant UIControl inside noninteractive? Need allow. If overlay host returns nil, superview continues.
- Need ensure console opens while effect on: If effect window is passthrough, console controls reachable. If a full-screen FX root is a separate window above, it must not intercept. Use `UIWindow` subclass `PassthroughWindow` with `hitTest` returning nil except allowed? For effect drawing, return nil always. But if window returns nil, will main window get? Need verify with scene. If not, lower window? On iOS multiple windows, yes if top returns nil maybe. But test. Alternative place effect drawing as subview under FxOverlayHost in main window with `isUserInteractionEnabled=false`; no separate window. But rendering performance? Could.
- Panic button should be inside an always-on-top window. It itself is a UIControl (UIButton). HitTest returns button only; outside returns nil. It must not be covered by effect drawing window. Level > effect. If effect window is `.normal`, set panic `.alert+1`? Need not interfere with system. Use `windowLevel = UIWindow.Level.alert - 1`? System alert higher. Or `.statusBar + 1`. App Store okay. Need set `isHidden = true` when no effect.
- App Store: additional window allowed, but ensure accessibility and no obscuring. Volume KVO no private API but unreliable. Shake public but unreliable. Dynamic Island requires Live Activity and user permission? Not suitable.

Draft 4:
- Criteria too coarse and can misattribute. Need add:
  - `fx sw on=1` and arm view; `mainWindow.sendEvent`, `fxWindow.sendEvent`; `hitTest snapshot` per window; `tapProbe.shouldReceive`; control action (`UIControl .touchUpInside` or `sendAction`); handler entry; setX entry; setX guard/return; clear; overlay hidden; console dismiss.
  - Raw absent can be because effect window swallowed, modal/system window, probe disabled, main window not hit at point, touch cancelled, or event on different scene. It doesn't prove "overlay interception" alone.
  - Raw present, handler absent: could be hitTest returned non-control, gesture recognizer failure, control disabled, another gesture cancels, or action target nil.
  - handlerTrace increments but no setX: handler code path branch, guard, state already false, early return.
  - setX logs on=0 but clear no: setX guard? Actually if on=0 logs then clear should. If state already false, guard returns before log. Need log entry and guard reason.
  - guard fired but no clear: if guard uses toggle and state flipped? or notification not delivered, or setX guard. Need log guard decision inputs.
  - "arm有 raw无→窗口/覆层拦截层" must separate `fxWindow.sendEvent` vs `mainWindow.sendEvent`; if neither, maybe system/other scene; if main sendEvent but no raw, hitTest/gesture not window. If fx sendEvent, top window swallowing. If main sendEvent+raw but control not receive, dispatch.
  - If `arm` absent in stuck session, then state never transitioned false->true or log lost; cannot classify. Need persistent active marker.

Q6:
- If only three changes, what cut/replace and minimal fix order. Need decide.
- Minimal (96) repair set sorted:
  Mandatory:
  1. Fix UIWindow/hit-test passthrough: effect drawing window subclass override hitTest/pointInside to return nil for all touches; never rely on root view `isUserInteractionEnabled=false`; set window.isUserInteractionEnabled=false? Implement and test. Also audit FxOverlayHost hitTest whitelist returns nil for host/window, include gesture-based owned controls; ensure console/effect button hitTest returns actual control. This likely root cause and restores closure. This is a code fix not just instrumentation.
  2. Panic independent close button window while any fx active, at level above effects; button calls idempotent `forceStopAllFx` and dismiss console; passthrough outside. This guarantees user escape if any future touch routing issue (assuming main alive).
  3. Targeted forensic: per-session append-only log with critical fx events synchronously fsync, persistent orphan-active marker, window sendEvent/hitTest snapshots; archive previous session not single 200-line prevtail. This lets verify/fix. Maybe include watchdog independent timer as instrumentation, but not rely as root fix.
  Maybe order: 1 root cause fix, 2 panic exit, 3 forensics. If can't confirm root cause, maybe forensics first? The task is current bug; could choose fix hitTest first because strong hypothesis. But adversarial: evidence not enough to declare; however if only three, implement pass-through fix with test because low risk and directly addresses likely. Keep panic. Keep forensic.
  Optional: independent watchdog timer, rolling logs, 2000 prevtail, volume/shake, 350ms guard. 
- Cut: Draft 2 independent watchdog as "periodic self-check" without defined check is not a fix; cut from mandatory unless it does hitTest audit and main heartbeat. Draft 1 b 2000 lines is low value; replace with archive/per-session + throttle. Draft 3 volume/shake/dynamic island cut.
- "Looks right but doesn't solve root": increasing prevtail/rolling logs only diagnosis; watchdog tied to tap; global handlerTrace; volume/shake; UIWindow root view disabled assumption; guard fired auto-close using toggle can double flip.

Need respond逐条草案 1-4. Let's structure answer:

Intro: adversarial summary: I do not accept premise "effects close chain broken" as root; strongest unrefuted hypothesis is effect drawing UIWindow itself swallows touches. Need state clearly.

Then Section 草案 1:
a: 部分同意. But if same process/queue, pinning ring not guarantee. fsync/file. Need event design. Replace. Mention on arm and before/after toggles; persistent orphan active; unique session.
b: 反对作为充分修复. 2000 insufficient; single prevtail overwritten. Use per-session append-only and size/time retention, throttle. Also 30 lines/s. 
c: 同意 rolling but correct mechanics: dedicated serial I/O queue; append; `F_FULLFSYNC` critical; avoid UserDefaults; main hang caveat. Add previous-session marker.
Need mention Q1 integrated.

Section 草案 2:
- 同意 decouple but opposition to undefined periodic check; design with main heartbeat + hitTest audit + transaction ACK + forceStop idempotent; independent queue. If main runloop blocked, cannot act. Must not call UIKit off-main; dispatch main. No cross-thread UIKit. Need maybe "watchdog can detect but not cure main hang; independent exit window also dead; only bug prevention/log/terminate." Use main canary. Original 350ms guard: fix to per-effect generation and idempotent close, avoid double-toggle. Mention `handlerTrace95` global insufficient.

Section 草案 3:
- Agree independent exit. Oppose volume/shake/notification as primary. Recommend panic window. Also effect overlay hitTest fix. App Store compliance. Mention if main blocked no in-process path. Hard requirement maintain. Need test passthrough window across windows.

Section 草案 4:
- 反对 current criteria. Blind spots. Need instrument window sendEvent and state returns. Refined decision tree. Mention raw absent reasons. Need maybe give exact logs:
  - `p96 win recv win=fx|main touch=...`
  - `p96 hit win=... point=... view=...`
  - `p96 action ctrl=...`
  - `p96 handler enter/exit token=...`
  - `p96 setx enter code on src gen stateBefore`
  - `p96 setx guard-skip`
  - `p96 clear`
  - `p96 overlay hidden`
  - `p96 console dismiss`
  - `p96 main tick seq`
  - `p96 fx active persisted`
 Then criteria.

Q1-Q6 individual:
Q1:
- Most likely still fail: pinning on same process/queue and prevtail expansion. If process killed/main blocked no flush; UserDefaults/CFPrefs not synchronous reliable. Use dedicated append-only file with O_APPEND/O_DSYNC/F_FULLFSYNC for critical events; write before state change and after; independent serial queue plus sync for critical. Keep per-session archive, orphan marker. Raw aggregated. If only fsync every event high freq bad; critical only. Use `os_log` as secondary? Not rely. Mention if main thread hangs, no event generated at hang instant; but marker before.
- Also "fx events zero" may be true because no state transition/logged, so pinned file would be empty. Need persist state and arm at the action before toggle? Log `p96 fx request` at control action and before setX; if action never called no logs. Need main window sendEvent/hitTest snapshot at effect on.

Q2:
- If root is main runloop hang, main timer won't fire; your independent timer works but cannot mutate UIKit. Need independent thread to detect, log, maybe set non-UI state. To force close, dispatch to main; if main not responding, impossible. UIKit pass-through/hitTest fix should prevent. Cross-thread risk: cannot call UIView/UIViewController/UIWindow; use main. Use locks/atomics, no locks around UIKit. If watchdog sees main hang, do not try UI. Could use `exit` not recommended. 
- Design: independent DispatchQueue timer (not main), atomic `mainHeartbeat`; main CADisplayLink or `DispatchQueue.main.asyncAfter` updates; hitTest audit on main every 1s while fx active; close transaction with generation ACK; forceStop idempotent on main; auto-fix if `hitTest` returns effect window. 350ms second layer only after actual tap/close request and should call idempotent `forceStopFx`, not toggle. No guarantee if main hung.

Q3:
- Yes possible. Need not assume touch. Mechanisms: toggle/stop mutex loses close; start completion/onStateChanged reenters setX(true) after close; `guard isX != on` returns if state already false while visual still on; control action not invoked; animation completion resets overlay; notification dismiss not delivered; main thread blocked. Synchronous call can fail to reach setX only before action (hit-test/gesture/disabled) or if it throws/crashes; once in toggle->setX synchronous, absent exception/reentrancy, should reach. So if no `fx sw on=0`, first suspect action/hit-test not delivered, not "setX guard swallowed" because guard for false would pass if state true; if state false, guard skip and visual stale implies inconsistent state. Need log entry of toggle and guard reason. Add `p96 setx enter stateBefore` and `guard skip reason`. Also atomic state; prevent async callbacks from reasserting on after close: generation token, ignore stale start completions; centralize state with serial main state machine. Check `startX` mutex stop: if `stopX` contends, ensure close completion not swallowed. Reentrancy onStateChanged: add reentrancy guard and queue.
- Also `p94 fx sw` is logged inside setX after guard; absence doesn't tell whether not called or guard skip. Need log at setX entry before guard. That's a key critique: current breadcrumbs cannot distinguish guard skip vs not called. Add entry log.

Q4:
- As above. Volume KVO: not reliable, requires active audio session, max/min, HUD, not app-specific; public but bad. Shake: not reliable, not discoverable, accessibility, false triggers. Dynamic Island/lock screen: heavy, permissions, not immediate; not for in-app stuck. System gestures: OS-controlled, cannot rely. Best: separate panic UIWindow with passthrough hitTest and UIButton at high level, shown on arm; idempotent forceStopAllFx. App Store compliant if accessible, unobtrusive, no private API; test scene multiwindow, rotation, safe area, accessibility. Also maybe App Intent/Control Center for future optional, not primary. Mention if effect window itself swallows, a higher panic window works only if main thread responsive. 
- Also can make effect root window never hit-testable; then console path restored; panic is belt-and-suspenders.

Q5:
- Current criteria not rigorous. Raw probe attached to main window: shouldReceive only if main window receives and touch is in its view hierarchy? If effect window above with non-nil hitTest, no raw. If top window hitTest nil, next? Need test. If presented VC in same window, raw may or may not because probe on window superview? If modal presented covers window with its view, window recognizer still attached to window and sees all touches in window? Gesture recognizers on window receive touches hit-tested to descendants, including presented VC's view? The presented VC view is subview of window? For full screen presentation, presentation container in window, so window recognizer may receive? Actually gesture recognizer on window may see. But system modal/alert in separate window no. Keyboard? separate window. So raw absent cannot definitively mean Fx overlay. Need add `sendEvent` per window and scene. Decision tree refine. Also raw present and no handler could be control not hit because overlay host returns nil? Actually if raw sees via window recognizer, hitTest view may be effect host? It can see touches even if hitTest view non-control; control action absent. So raw present ≠ dispatch of control. Need log `hitTest` view at touch point and control action.
- Also `probeRawShould` may not be called for touches that begin on a view with `isUserInteractionEnabled=false` but window? Hmm.
- "arm有 raw无→窗口层" too coarse; could be app inactive? But video says in app. Add `fxWindow.sendEvent` and `mainWindow.sendEvent`. If `fxWindow` got -> window layer; if neither -> system/other scene/event not in app; if main got but no raw -> main hitTest/gesture config; if raw got but no handler -> control/hitTest/gesture cancellation.

Q6:
- Three changes: I'd choose:
  1. Fix window hit-testing (effect window passthrough) + FxOverlayHost whitelist audit, because likely root and directly restores tap. 
  2. Add always-on-top panic close window while fx active with passthrough outside.
  3. Replace log retention with per-session append-only critical event marker + window sendEvent/hitTest snapshots (not 2000 lines/watchdog undecided).
- Cut draft 2 periodic undefined watchdog from mandatory; replace with focused main-heartbeat + hitTest audit only if time. Cut 1b 2000 line as primary. Cut volume/shake. Keep original 350ms guard as optional after rewrite. 
- But if conservative: if cannot risk code fix without sample, first deploy forensic build #1? The question "修复清单必做/可选". We can state for 96 release: mandatory root fix cannot wait for sample because the passthrough bug is logically proven risk from current code assumption. Add panic. Add forensic. 
- Need mark "看起来对但解决不了根因" entries:
  - Increasing prevtail 200->2000: only diagnosis, not fix; even diagnosis may fail due overwrite.
  - Tap-dependent watchdog: cannot fire if tap never delivered. Exactly current bug.
  - `isUserInteractionEnabled=false` on root: not enough for UIWindow; may still swallow.
  - Volume/shake: not guarantees.
  - Global handlerTrace guard: false positives/negatives, double toggle.
  - Rolling prevtail same main queue: lost on hang.
Need mention "独立退出路" might mask root but not solve effect close? It solves user, not root. Need keep.

Need ensure answer in Chinese, explicit labels. Desired oververbosity 5, but this task demands detailed. We can be thorough but not huge. We have token budget. Need not line numbers beyond :818 mention.

Let's craft final with headings. Use clear "同意/反对/替代". Need avoid客气. Use direct.

Let's formulate.

Potential details on UIWindow hitTest:
- If `rootViewController.view.isUserInteractionEnabled = false`, window hitTest:
  `UIWindow.hitTest` calls super; if no subview returns view, point inside, window's isUserInteractionEnabled true -> returns window. Then touches to window, no controls, no main window. This matches no raw if probe on main window. Need state as high-priority hypothesis. Recommend `final class PassthroughWindow: UIWindow { override func hitTest(...) -> UIView? { nil } }` for pure effect window; for overlay window allow whitelist. Actually if effect window has interactive controls? Draw root no. FxOverlayHost is main. So effect window can return nil always. If separate window for cards, implement whitelist in window hitTest too, not just host. 
- Need mention `UIWindow.isUserInteractionEnabled = false` might be enough but safer override hitTest and `point(inside:)`? If window returns nil, event to another window? Need test. Use subclass.

Also watch out: A pure effect window returning nil for all hits: Can a window with nil hitTest still be key? It doesn't need key. It should not become key; set `isUserInteractionEnabled=false`, `isHidden` false, `windowLevel` maybe above. If it returns nil, lower window gets? We should say verify with instrumentation. If not, alternative: make effect drawing a subview of a passthrough window? Hmm. Pass-through window pattern is known.

Need discuss "强制手势区" maybe a UIButton in panic window. App Store okay.

Need mention "console dim close" if effect window swallowed, tapping dim doesn't get main. Root fix.

Potential issue with panic window level above effect can be covered by console? It is above, but only button; hitTest nil outside. If console dim wants tap outside, panic outside nil passes to console. Good.

Need include refined triage decision tree maybe:
- P0 if `p96 fx arm` exists.
- For a touch at console fx button/dim:
  1. `fxWindow.sendEvent` receives and main not -> top effect window swallow (likely).
  2. neither window sendEvent -> system/other scene/app inactive.
  3. main sendEvent, no tapProbe -> main window hitTest/gesture not reached; inspect `hitTest` view and `isUserInteractionEnabled` chain.
  4. tapProbe raw yes, no control action -> hitTest view not UIControl/allowed, control disabled, gesture conflict.
  5. control action yes, no handler enter -> target/action break.
  6. handler enter, no setX enter -> branch/early return.
  7. setX enter, guard skip -> state inconsistency/log `stateBefore`.
  8. setX on=0 logged, no clear/overlay hidden -> cleanup/visual desync.
  9. guard fired, no forceStop -> notification/setX guard.
Need include.

Need discuss Q3 more: "同步调用链中途不达 setX" possibilities:
- `toggleX` may be called on background? UI action main. If `toggleX` does `DispatchQueue.main.async`? Not given. If asynchronous? They say normal path toggle -> start/stop -> setX synchronous. If actually part async (e.g., animations), then can be lost. Need log tokens.
- `guard isX != on`: if state already false but overlay visible, closing request is skipped. This is not "state changes back"; it's desync. Need make state source of truth from visual? Add invariant check activeFxCode vs overlay window visibility.
- `startX` inner mutex stop: If start is still pending and stop called, perhaps `isX` set true after stop due async. Use generation.
- `onStateChanged` callback reentrant sets on: if notification from start after stop, ignore if generation stale.
- `handlerTrace` increments but only at handler; if handler hits another branch not effect, false alive.

Need mention "same-second throttle raw" can drop first tap after arm if same second as other raw? They say arm后首点落 p95 probe first; but raw same-second throttled could suppress? If critical, not. Need keep first point unthrottled. Not central.

Need mention "prevtail export = prevtail + current file", if current file is active and not flushed, kill loses. Need `fcntl F_FULLFSYNC` on critical.

Need mention "wall.cache/pf83/cvr.stat/wall.dec78/web resize" throttling: use per-second counters and flush one aggregate, but preserve fx lines and maybe event order. Use structured binary? Not necessary.

Need answer Q1 "哪条最可能仍然抓不到": (a) pinned same process/queue; (c) rolling if same queue; (b) expansion obviously. Also if arm logs never happen because state already on/action not delivered. Need "独立即时落盘" yes for critical fx events. UserDefaults no; it's not immediate, cfprefsd. Use file with fsync. But fsync each raw not; critical only.

Need address "two logs rotation" maybe use archive all sessions. Also current session file on kill should persist due OS? But without sync not guaranteed. 

Need answer Q4 "音量键监听合规性": KVO outputVolume public API; no App Store rejection generally, but not reliable and may break with no audio session; using it as hidden close could be confusing. Shake: public motion events, App Store okay, but not reliable. Panic window: public, allowed, but extra UIWindow must support scenes and accessibility; avoid covering system UI. 

Need mention "Dynamic Island/lock screen" require Live Activity and user outside app, not for stuck in app. Control Center/App Intent could launch app or send intent, but not immediate in foreground; cannot be primary.

Need maybe mention "system-level window above alerts" cannot be above system windows without special entitlements; don't try. Use app-level window.

Need final minimal repair sorted:
Mandatory:
1. `PassthroughWindow` for effect drawing + hitTest at UIWindow level; pure effect window returns nil for all touches. Audit FxOverlayHost whitelist; ensure no `super.hitTest` returns host/window; allow UIControl owners + gesture dim if needed. Add immediate device test: effect on, tap console fx button, dim, card.
2. Panic `forceStopAllFx` path + always-on-top panic close button window while fx active. Idempotent setX(false) for all codes, dismiss console via notification; no toggle. Button accessible. 
3. Diagnostics: per-session append-only log with fx critical events fsync, orphan active marker; window sendEvent/hitTest snapshots; main heartbeat. Keep 2000/throttle optional.
Maybe if only three, omit independent watchdog. Or include main-heartbeat in diagnostics. Then optional:
- rewritten 350ms tap guard as second layer with generation and idempotent close.
- independent background watchdog with main heartbeat and hitTest audit; no UIKit off-main.
- rolling logs/time retention/throttle.
- volume/shake no.
Need "必做/可选分开".

Need mention if we choose only three and bug root is main thread block, panic etc may not solve; but we assert hypothesis. If after fix sample shows main hang, then 96 should not ship watchdog as cure; need find hang. We can say emergency fallback: if main heartbeat missed while fx active, record full stack via `PLCrashReporter`? Not available. Use `os_log`? Hmm.

Could mention "watchdog to terminate app on main hang" not acceptable. If user can only kill app, that's current. The only robust fix is prevent hang/interception.

Need be careful not to overstate "logical proven" because no sample. Say "当前事实足以把 UIWindow 自身命中作为一级未排除根因；草案把它当已排除，这是错误." This is adversarial. The background says root view isUserInteractionEnabled=false "整窗不接点按" as fact? It says "特效绘制根视图 isUserInteractionEnabled=false 整窗不接点按" maybe they believe. We can challenge: That statement is not equivalent; root view disabled does not guarantee window hitTest nil. Need definitive device test. This is key.

Need mention "FxOverlayHost91 hitTest白名单制只把命中 UIControl 本体的点交回系统"—if it returns nil for non-UIControl, touch may still be swallowed by its window? If host is subview main, no. But if its superview returns itself? Hmm.

Need maybe mention "hitTest whitelist should be based on target view being allowed, not UIControl.class" because UIControl subclass can include large clear button covering screen? Not likely. But if a UIControl with large frame from overlay (e.g., card) covers console, it will intercept. Video big lanterns visual over console but not necessarily controls. If any overlay card/control has frame over console, whitelist will intentionally deliver to that control, blocking console. User described "多只大灯笼视觉上压在控制台按钮区上"; if lanterns are not controls, pass. But if card container is UIControl large, maybe. Need audit frames: own interactive elements should not have full-screen or oversized hit areas; use `point(inside:)`/hitTest shrink. Could be root cause too: overlay card UIControl covering console despite not visually obvious. But all taps dead including dim? If full-screen host returns an oversized UIControl (maybe tap-anywhere card) above all, then all taps to that control, no console. But description says host only returns UIControl itself; if one big UIControl covers screen, yes. The big lanterns may be inside a UIControl? Need not ignore. Add test: log hitTest returned view and frame at tap. If it returns a UIControl in FxOverlayHost, that's "overlay card too large", not window. But user says any point no response; if big lantern control covers console, outside maybe dim? Multiple large lanterns could cover large areas but not entire. The console dim maybe also under overlay host? The dim is in main window; overlay host above? If host returns nil outside controls, dim tap reaches. But if a full-screen card control? 
Need mention as second hypothesis: OverlayHost whitelist returning an oversized UIControl. Need instrument hitTest.

Need maybe challenge "all four effects all cannot close" from user oral only; only lantern recorded. Use not definitive. Adversarial: Don't overfit four; only lantern sample. But root window per effect likely shared. Need say Q evidence: only one sample, user oral for other three; cannot conclude same mechanism. Need include? The prompt says all facts confirmed? "用户口头补充：四个特效全都关不掉（录屏只取样孔明灯，其余三个无录屏样本）". It may be fact but less evidence. We can note for root cause need samples or instrument all effect codes. Maybe include in 草案4: need per-effect `code` in logs; don't assume same. But shared code likely.

Need address "handlerTrace95 new value" increments by dim close too. If user taps console effect button but dim handler fires somehow? Hmm. Global trace not per effect. Watchdog may think handler alive if some other handler increments. Also if dim tap increments but console doesn't dismiss, guard won't fire. Need per-effect ACK. Good.

Need mention "350ms after tap if handlerTrace no new -> probe directly close via toggle" If no tap delivered, not fired; if touch swallowed by effect window, main probe not called; this watchdog can never fix current bug. Draft 2 solves by timer but "what check" is critical.

Need "same second throttle" raw may hide repeated taps; for diagnosis need first few unthrottled and counts. But not central.

Need "shouldReceive → probeRawShould95(touch)" maybe `shouldReceive` not guaranteed to be called if another gesture's delegate returns false? It is called before recognition for taps. If tapProbe's delegate "恒放行", okay. But if another gesture fails? If shouldReceive returns true but gesture later fails, raw still logged. Good.

Need "UITapGestureRecognizer on UIWindow" if window `isUserInteractionEnabled`? main window enabled. But if main window not key/hidden due scene? no.

Need mention "UIScene/window restoration": After killing app, re-entry may create new windows; if effect window remains visible? On launch, effect state maybe persisted and restored without arm logs. If effects are on after restart? User kills and re-enters; if effect state persisted, app could show effect on with no arm, and still blocked. They say logs no effect opened. Maybe app auto-restores effect on from state, causing bug even before user opens? But they said logs no fx events. Need instrument app launch snapshot: enumerate windows on launch and any active fx flag. If app restores active effect, must log `restored active` and clear or arm. Add to forensic. Important: If previous session had active effect, on next launch restore system may set on without `fx arm` log. The second log sessions no effect on maybe because effect was auto-closed on launch? Hmm. But if persisted active state with no log, could explain. Need include Q1: persist and on launch detect orphan. Good.

Need maybe propose "state machine and audit invariants":
- `FxStateStore` with generation, desiredOn, presenting, overlayHidden, closeRequested.
- All transitions on main serial; stale callbacks ignored by generation.
- `setX` logs entry before guard, guard skip reason, transition, completion.
- `forceStopAllFx` bypasses toggle, idempotent, always hides overlay and dismiss console, logs `p96 forceStop`.
This addresses Q3.

Need mention "setX guard `guard isX != on` if request false and state true passes. If state already false, skip is okay only if visual also false; if visual true, invariant broken. Add check visual overlay hidden state and force cleanup even if isX false." Good.

Need maybe answer "which mechanism can make synchronous call chain not reach setX?" Exact: control action not invoked (hit testing/gesture), target deallocated (target-action with `addTarget(nil`?), control disabled/ancestor disabled, `UIControl` event not .touchUpInside because touch cancelled by overlay/gesture with `cancelsTouchesInView=true` (though tapProbe false but other gestures?), app inactive or window not key? If a `UIGestureRecognizer` elsewhere has `cancelsTouchesInView=true` and recognizes, it can cancel control touches before `.touchUpInside`; window tapProbe itself cancels false, but other overlay gestures? The FxOverlayHost or scroll view might have gesture. If a top window swallows, no action. If toggle is invoked, synchronous call reaches setX unless exception; exceptions would crash. Reentrant callback can flip. Need state.

Need "raw probe on main window with `cancelsTouchesInView=false` and delegate always allow" could still cause control to delay? It doesn't prevent but if tapProbe recognizes and another control? It allows simultaneous? Delegate "恒放行" might include `shouldRecognizeSimultaneouslyWith`? If not, default no simultaneous; a tap gesture on window can prevent control action? Wait for gesture recognizers: A UITapGestureRecognizer attached to a superview can recognize a tap on a button. If it recognizes, by default `cancelsTouchesInView=false` means touches not cancelled, but does it cause control not to receive? The button may still receive if touch not cancelled. However if gesture recognizer's `delaysTouchesEnded` default true? UIGestureRecognizer `delaysTouchesEnded` defaults YES for some? Actually default is YES? Let's recall: `delaysTouchesBegan` default NO; `delaysTouchesEnded` default YES? For gesture recognizers, default `delaysTouchesEnded = YES`? Documentation: When a gesture recognizer recognizes, it cancels touches if cancelsTouchesInView. `delaysTouchesEnded` default YES? If true, touchesEnded not delivered until recognizer fails? A tap recognizer recognizes at end, might delay but then deliver. Not block. But if gesture recognizer delegate allows simultaneous? If not simultaneous, can a window tap prevent button? `UIControl` uses touch handling, not gesture? I think a superview tap gesture can coexist if cancels false; but `delaysTouchesEnded` could delay. Not root all dead. But another gesture with cancels true could. Need note.

Need maybe mention "tapProbe92 on main window is not passive enough": Gesture recognizer can affect touch delivery/delay; it adds complexity. If root already fixed, remove/disable in production or ensure `cancelsTouchesInView=false`, `delaysTouchesBegan=false`, `delaysTouchesEnded=false`, delegate simultaneous. But not main root. In final optional.

Need maybe answer "if only three changes... replace what with what" as above. Need include "if forced to bet": root fix first.

Let's prepare final answer. Need be clear and not too verbose but enough. We can use tables? Chinese. We'll use bullet list with labels.

Let's outline final:

Title: 对抗评审结论：不接受“关闭链”作为根因定案；当前最高优先级未排除是 effect UIWindow hitTest 吞触。

Then maybe one paragraph.

I. 草案逐条:
1a etc.
2.
3.
4.

II. Q1-Q6.

III. Refined triage tree.

IV. (96) minimal repair list sorted mandatory/optional and pitfalls.

Need ensure labels per item: "同意/反对/替代". Let's write.

Detailed content:

草案1a:
- 反对“钉住区即可”。 if same process/queue/ring, kill/main hang loses. Need separate append-only file, open O_APPEND, critical writes synchronously with fsync/F_FULLFSYNC; raw aggregated; never overwrite prevtail; unique session id; on launch scan orphan active. UserDefaults no. Also log before and after setX; current `fx sw` after guard cannot distinguish not called vs guard skip. Add `p96 setx enter/guard skip`.
- 同意方向 but not sufficient.

1b:
- 反对 as primary. 2000 lines = 28s at 70.5/s, 66s at 30/s; video 2min. Single prevtail overwritten. Use per-session archive with size/time retention, high freq aggregate. Keep fx events separate.

1c:
- 同意 rolling, but append-only session, dedicated IO queue; critical sync. Periodic save on main can be lost if main hang; use background for raw but critical sync before potential freeze. 

2:
- 同意 decouple, 反对 undefined periodic check as guarantee. Design:
  - background DispatchSourceTimer; atomic heartbeat.
  - main canary every 250ms.
  - every 1s while fx active main audit hitTest at console button/dim/pass-through; log blockers.
  - close transaction: request ID/generation, expect ACK; timeout then `forceStopFx(code, reason)` on main idempotent.
  - if main heartbeat stale, log hang only; cannot UIKit off-main.
  - original guard: per-effect, idempotent, not toggle, avoid global handlerTrace.
- Cross-thread: no UIKit off-main; dispatch main; if main dead no in-process cure.

3:
- 同意 independent exit; 反对 volume/shake/system gesture as primary. Recommend panic window. Implement passthrough window hitTest only button. App Store okay. Also effect window must return nil. Main thread caveat.

4:
- 反对 as-is. Blind spots. Provide refined.

Q1:
- Answer.

Q2:
- Answer.

Q3:
- Answer.

Q4:
- Answer.

Q5:
- Answer.

Q6:
- Answer.

Minimal list:
必做:
1. Window hit-test fix and audit. Effect drawing UIWindow override hitTest nil; FxOverlayHost hitTest returns nil for host/window, whitelist only actual interactive; ensure console/dim button hitTest. Instrument before/after.
2. Panic close window path. `forceStopAllFx` idempotent; hide overlays/dismiss console; button only while active.
3. Forensic archive + critical fsync + orphan marker + window sendEvent/hitTest snapshots + main heartbeat; not rely on 2000 prevtail.
Optional:
4. Rewritten 350ms guard with generation/idempotent close.
5. Background watchdog hitTest audit, not auto-close unless close transaction timeout.
6. Log throttling/time retention.
7. Remove tapProbe production or fix delays.
No: volume/shake/dynamic island as primary; expanding prevtail only; root view disabled.
Maybe "if only three changes" exactly same. Need mention "candidate: disable effect separate window entirely and draw in main via noninteractive layer" as alternative; if renderer requires window, passthrough.

Need include "looks right but doesn't solve":
- 1b.
- 2 if tap-dependent/undefined.
- 3 volume/shake.
- 4 triage only if instrumented.
- `handlerTrace95` global.

Let's ensure explicit "同意/反对" per Q? Questions not require labels but include.

Need perhaps mention "Q1 最可能仍抓不到: (a) if same queue; (b) expansion; (c) rolling on main." We can emphasize "三修中 b 最没用, a 若无独立即时落盘仍会丢, c 若仍主线程也会丢." Answer.

Need "同一秒节流 raw" may suppress stuck session raw after arm? They said raw same-second throttle; first point after arm logs. If user taps many times after same second, only throttle; but enough. Not central.

Need "arm 边沿三串 must落" if setX not called (e.g., hit-test blocks on button) no arm. Wait if effect already on? The button can't be tapped to turn on? They did open effect successfully; so arm logs should exist when opening. If logs no fx at all in retained sessions, either retained not stuck session or arm not logged. If effect opens via main console and logs arm, then stuck session should have at least arm. If no, retention issue likely. However if opening was before log window? They opened then stuck within 2min; should. But if app's arm log not flushed? synchronous. Need not.

Need "prevtail only next startup": If kill by user after stuck, new launch writes prevtail from previous. But if they then interact four sessions before export, prevtail overwritten? They said prevtail once at startup, not rolling; each subsequent launch overwrites with previous session tail. If they exported after several launches, stuck tail overwritten. Need archive.

Need mention "four sessions 83s" means they missed window, not evidence no effect. "没有 fx 面包屑" only means retained segments don't include stuck session or arm wasn't produced; cannot infer no logs at stuck. This is important: The absence in retained window is not evidence of absence during stuck. Need say current forensic design cannot support either hypothesis; don't draw conclusions.

Need maybe answer Q3 "if true main runloop blocked, video frames continue?" The video recording is OS-level, UI could be frozen with lantern static; they said every frame console & lantern present, not necessarily animating. The UI could be main-thread deadlocked; if so taps dead and watchdog on main dead. Need verify main heartbeat in sample. The video alone doesn't prove runloop alive. This is a strong point: The user says no response; if main thread blocked, UI frozen; recording still shows static overlay. Could be main thread deadlock. Need highlight in Q2. If main thread blocked due e.g., deadlock in stop/toggle, then all taps dead. The effect drawing window swallow also fits. Need not assert root. Need include "视频帧中特效是否仍在动画？若静止，主线程卡死不能排除." The prompt says "每一帧，控制台与灯笼都在，没有一帧关闭成功"; not mention animation. Need collect main heartbeat. Great.

Need include in Q2: If main thread blocked, an independent watchdog cannot call UIKit; the only reliable escape is external (OS app switcher/kill) or crash. To maintain "user always can retreat", must prevent main block, not watchdog. So draft 2's "独立看门狗" cannot guarantee.

Need maybe mention "跨线程强制清场" not allowed. Could use `DispatchQueue.main.async` but if runloop blocked queued. No safe API to mutate UIKit from background. Do not use `performSelector(onMainThread:waitUntilDone:false)` same. Could use `CFRunLoopWakeUp`? It won't break deadlock. So no.

Need "deadlock vs swallow differentiation": add main heartbeat log from `CADisplayLink` or `DispatchQueue.main.async` every 250ms. If no heartbeat during stuck, main thread hang. If heartbeat continues and taps dead, hit-test/window. This is key forensic. Put in triage.

Need "window sendEvent instrumentation" can be flaky if main thread hung (no log). Heartbeat distinguishes.

Need final length. We can be detailed but not enormous. Let's write in Chinese. Ensure no markdown table too complex. Use bold labels.

Let's compose final answer.
=== answer ===
结论先说：我不接受“关闭链坏”作为已定案根因。当前最危险的未排除项是——**特效绘制 UIWindow 本身仍参与 hitTest，整窗吞掉触摸**；以及**主线程已卡死**。这两者都能解释“任何点按无反应、控制台关不掉、探针 raw 也看不到”。草案里有几条只是取证/兜底，不是根因修复。

---

## 一、逐条评审草案 1–4

### 草案 1a：fx 事件进钉住区
**部分同意，但反对“钉住区=能保住”。**

- 如果钉住区仍与主日志同进程、同主线程/同串行队列落盘，主线程卡死、进程被杀、或最后一次 write 未 flush，同样会丢。
- 当前 `p94 fx sw` 是在 `setX` 内部、且在 `guard isX != on` 之后才落。这个面包屑**无法区分**：
  1. 根本没进 `setX`；
  2. 进了 `setX` 但 guard 跳过；
  3. 进了 `setX` 并执行。
- 必须在 `setX` 入口、guard 前、guard 跳过、状态变更后、overlay 隐藏后分别落痕。
- `UserDefaults` 不适合做即时可靠落盘；它走 cfprefsd，不是“写调用返回即落盘”。关键 fx 事件应写独立 append-only 文件，低频关键事件用 `O_APPEND` + `fsync`/`F_FULLFSYNC`。
- 还要加“孤儿 active 标记”：arm 时同步写 `fxActive=code, sessionID, generation, timestamp`；clear 时同步清。下次启动若发现上次未清，必须落 `p96 previous session ended active`，这比 prevtail 更不容易丢。

**替代：** fx 事件独立小文件 + 关键事件同步 fsync + 每 session 唯一 ID + 启动扫描孤儿 active；raw/高频事件可批处理，不参与同一环形挤出。

### 草案 1b：prevtail 200 → ≥2000 或高频节流
**反对把扩到 2000 行当主要方案。**

- 实测 70.5 行/秒，2000 行只覆盖约 28 秒；30 行/秒覆盖约 66 秒。录屏窗口 2 分钟就可能超。
- 真正问题不是“200 太小”这么简单，而是 **单个 prevtail 会被后续启动覆盖**。被卡会话后再启动几次，prevtail 就被后会话尾巴挤掉；扩到 2000 仍可能被覆盖。
- 应改成按 session 归档的 append-only 日志，或每 session 独立文件，按大小/时间保留至少多轮启动，不做单文件一次性覆盖。
- 高频行节流同意，但只用于 wall/web resize 等非关键行；fx/arm/clear/raw/dismiss/handler/setX/hitTest 不得被节流掉。

**替代：** 每 session 独立日志 + 总大小上限轮转；wall/web 高频行按秒聚合成计数；fx 事件独立保留。

### 草案 1c：prevtail 改滚动落盘
**同意方向，但实现有坑。**

- 若滚动落盘仍由主线程/主队列周期执行，主线程卡死时同样停写。
- 若每行都 fsync，会卡 UI；只对低频关键 fx 事件同步，raw/高频行走后台串行 I/O 队列批量。
- 还应写“当前 session 未正常结束”标记，而不是只滚动 tail。杀 App 后下次启动直接能把上一 session 文件归档，不依赖“先转存 200 行”。

### 草案 2：看门狗与点按脱钩
**同意脱钩，反对“未定检查项”的看门狗直接当兜底。**

必须先把“看门狗能做什么”钉死：

1. **独立队列/线程定时器**：`DispatchSourceTimer` 放专用串行队列，不能放主队列。
2. **主线程 heartbeat**：主线程每 250ms 更新原子计数。后台 watchdog 检查 heartbeat。
   - heartbeat 停 → 主线程卡死/死锁。此时后台**不能**动 UIKit。只能记录、上报，不能保证关闭。
   - heartbeat 正常 → 才允许 `DispatchQueue.main.async` 做修复/关闭。
3. **周期自检不应只查“state 是否为 on”，而应查 close path 可达性**：
   - 对当前控制台特效按钮中心、dim 中心，分别调用各 UIWindow 的 hitTest/记录返回 view。
   - 若特效绘制 window 返回自身或非白名单 view，说明它吞触摸。
   - 检查 `FxOverlayHost91.hitTest` 在控制台按钮点是否返回 `nil` 或允许 view，而不是 host/window 自身。
   - 检查控制台按钮及祖先链 `isUserInteractionEnabled/isHidden/alpha`。
   - 落 `p96 close audit code=... blockers=...`。
4. **关闭事务**：真实关闭请求带 `generation/requestID`。handler 必须在最终状态落 ACK。超时才 `forceStopFx(code, reason:)`，不要用 toggle。toggle 在超时与 handler 晚到并发时会双翻转。
5. 原 350ms 点后看门狗只能作为第二层，而且必须改成按 effect code/generation 判定，不能看全局 `handlerTrace95`。全局 trace 会被 dim 或其他 handler 递增，造成假“handler 活着”。

**跨线程 UIKit 正确姿势：** 后台只读写原子状态/日志；所有 UIView/UIWindow/UIViewController 操作必须 `DispatchQueue.main.async`。主线程死锁时没有合法跨线程强制清场姿势；`performSelector(onMainThread:)`、锁、后台直接调 `removeFromSuperview` 都是错的。

### 草案 3：独立退出路
**同意必须有，但反对音量键/摇一摇/系统手势作为主路径。**

- 音量键 KVO：依赖 AVAudioSession 状态、系统音量已最大/最小时可能无变化、会弹音量 HUD、用户会以为在调音量。公共 API，但可靠性不够。
- 摇一摇：`motionEnded` 受设备运动能力、辅助功能、用户认知、误触影响，不可发现，不能作为“永远有路可退”。
- 系统边缘手势/Home indicator：受 OS 控制，不能保证被 App 截获。
- 灵动岛/锁屏控件：需要 Live Activity/App Intent，重、慢、用户可能不在 App 内，不适合作为即时逃生。
- **推荐：特效开启期间显示一个独立的高层 panic window**。该 window 只在自己的关闭按钮 frame 返回 hitTest，其他区域必须返回 `nil` 透传。按钮直接调用 `forceStopAllFx(reason:"panic")`，再通知控制台 dismiss。App Store 合规，但必须测试多 scene、旋转、安全区、无障碍；不要试图盖系统弹窗/键盘。
- 同时，特效绘制 window 本身必须改成真正 passthrough；panic window 是保险，不是根因修复。

### 草案 4：分流判据
**反对按现有判据直接归因。**

关键盲区：

- `tapProbe92` 挂在主 window 上，`shouldReceive` 只有在主 window 收到该 touch 并进入其手势识别链时才可能调用。若上方特效 window 的 `hitTest` 返回自身，主 window 根本收不到，raw 自然无。这不只说明“窗口/覆层拦截”，还需区分是 Fx window、系统 window、presented VC、还是主 window 自身 hitTest/gesture 配置。
- raw 有、control action 无：可能是 hitTest 返回了 FxOverlayHost 的某个超大 UIControl，可能是另一个手势 `cancelsTouchesInView=true` 取消，可能是按钮/祖先 disabled。
- raw 有、handler 无：不能只归“分发/执行”，要区分 hitTest 到了非 control、control action target 失效、手势冲突。
- `handlerTrace95` 有、`fx clear` 无：可能是另一 handler 递增，不代表目标 handler 执行。
- `p94 fx sw on=0` 无：可能是没进 `setX`，也可能进了 `setX` 但 guard 跳过。当前落点不足以区分。

**替代判据：** 增加以下日志后再归因：
`main heartbeat seq`、`mainWindow.sendEvent`、`fxWindow.sendEvent`、每个 window 对该点 `hitTest` 返回 class/frame`、`tapProbe.shouldReceive`、`UIControl action enter`、`handler enter/exit token`、`setX enter stateBefore`、`setX guard-skip reason`、`setX transition`、`overlay hidden`、`console dismiss`、`forceStop`。

---

## 二、Q1–Q6 回应

### Q1：三修哪条最可能仍抓不到？钉住区同进程同队列是否会丢？是否要即时落盘？
**最可能仍抓不到：1b 的扩容；1a 若仍同队列也会丢；1c 若仍主线程滚动也会丢。**

- 同进程同队列、无 fsync，被 kill 或主线程卡死都可能丢尾巴。
- **需要独立即时落盘，但只对关键 fx 事件**：arm、clear、request close、setX enter/guard skip/transition、forceStop、window hitTest audit、previous session active。高频 raw 不要每条 fsync。
- `UserDefaults` 不适合作为可靠即时落盘；用独立文件 + `O_APPEND` + 关键事件 `fsync`/`F_FULLFSYNC`。
- 另外，若 effect 状态被持久化并在下次启动恢复，可能没有 arm 日志。必须在启动时检查“上次 active 未清”，落孤儿标记。

### Q2：主线程卡死时定时器看门狗还成立吗？
**不成立。主线程定时器不会转；后台定时器能转，但不能安全改 UIKit。**

- 后台 watchdog 可以检测 heartbeat 停、写日志、置非 UI 标志；它不能从后台直接关 window/改 view。
- 若要执行关闭，只能 `DispatchQueue.main.async`；主线程卡死时这个 block 也不会执行。
- 因此“看门狗保证用户能退出”在根因是主线程死锁时是假的。此时唯一可靠逃生是系统 app switcher/杀 App，或者避免死锁。
- 正确设计：后台 watchdog 只负责检测和发起主线程事务；主线程 heartbeat 正常时，做 close audit、hitTest audit、超时 forceStop。主线程 heartbeat 停时，记录 hang，不尝试跨线程清场。

### Q3：是否可能不在点按链，而是 setX guard/状态重入导致“关了又被改回”？
**可能，但当前证据无法定案；且现有日志不足以区分。**

若 `toggleX` 真被调用，且是同步 `toggle→stop→setX(false)`，在没有异常/崩溃/重入的情况下，应到达 `setX`。能导致“没有 on=0 日志”的机制有：

1. control action 根本没触发：window/hitTest/gesture/ancestor disabled/target 丢失。
2. 进了 `setX`，但 `isX` 已经是 false，guard 直接跳过；视觉 overlay 却仍开着，属于状态/视觉失配。
3. `startX` 的异步完成、动画 completion、`onStateChanged` 回调在 close 后重新 `setX(true)`，把状态改回。
4. `startX` 内 mutex stop 与 close 竞争，close 被吞或延后。
5. 关闭走通知 dismiss 控制台，通知未投递/目标失效。
6. 主线程已卡死，后续调用根本没执行。

**必须新增：** `setX` 入口日志在 guard 前；guard skip 原因；当前 state 与 overlay 可见性一致性检查；generation 使旧 start 回调失效；`forceStopFx` 幂等清 overlay，不依赖 toggle。

### Q4：独立退出路哪个可靠？
**首选高层 panic window + 按钮；音量键/摇一摇只能算可选辅助，不能作为保证。**

- panic window 必须实现 window 级 passthrough：只关闭按钮 frame 返回 button，其余返回 nil。
- 只在任一 fx active 时显示；按钮调用幂等 `forceStopAllFx`，并 dismiss console。
- App Store 合规风险低，但额外 UIWindow 要正确处理 scene、旋转、安全区、无障碍，不要盖系统 UI。
- 音量键 KVO 公共但不可靠；摇一摇不可发现且受限制；灵动岛/锁屏太重且不即时。

### Q5：分流判据盲区？raw 探针会被其他 window/presented VC 吞吗？
**有，且严重。**

- 若上方另一个 UIWindow 的 hitTest 返回自身，主 window 的 tapProbe 不会收到，raw 无。此时 raw 无只能说明“主 window 没拿到该 touch”，不能直接归因于 FxOverlayHost。
- 系统 window、键盘、presented VC、其他 scene 的 window 都可能改变接收者。
- 若 `rootViewController.view.isUserInteractionEnabled=false`，但 UIWindow 自身仍 enabled，window hitTest 可能返回 window 自身，整窗吞触摸。这是当前必须实测的一级嫌疑。
- 还要防 FxOverlayHost 白名单返回一个超大的 UIControl 覆盖控制台；raw 有也不代表 console 按钮能拿到 action。

**替代判据：** 先看 `fxWindow.sendEvent` 与 `mainWindow.sendEvent` 谁收到；再看 hitTest 返回 view；再看 control action；再看 handler；再看 setX enter/guard/transition；最后看 overlay hidden/dismiss。

### Q6：只能改三处，砍哪条、换什么？最小修复排序
砍掉草案 2 的“未定检查项看门狗”作为必做项，也砍掉 1b 的“2000 行扩容”作为主方案，砍掉音量/摇一摇/灵动岛作为主退出路。

**我的 96 最小修复集：**

**必做 1：修 window/hitTest 根因面。**
- 特效绘制 UIWindow 改为真正 passthrough：在 **UIWindow 级** override hitTest，纯特效 window 对触摸返回 nil，不能只设 root view `isUserInteractionEnabled=false`。
- FxOverlayHost91 的 hitTest 审计：确保对于非自有交互点返回 nil，不能让 host 或 window 自身接住；白名单只放真实交互元素，并检查是否有超大 UIControl 盖住控制台。
- 真机验证：fx 开启时，控制台按钮、dim、卡片、控制台外点按全部按预期。

**必做 2：panic 独立退出路。**
- 高层 passthrough window，只露一个“关闭特效”按钮；调用幂等 `forceStopAllFx`，清所有 fx overlay 并 dismiss console。不要走 toggle，不要依赖 console handler。

**必做 3：取证改成能抓住被卡会话。**
- 每 session 独立 append-only 日志，关键 fx 事件同步 fsync。
- 启动扫描 orphan active 标记。
- 增加 main heartbeat、mainWindow/fxWindow sendEvent、各 window hitTest 快照、setX 入口/guard/transition、overlay hidden、console dismiss。
- wall/web 高频行聚合；不再依赖单 prevtail 200 行。

**可选：**
- 重写 350ms 点后看门狗：按 effect generation、幂等 `forceStopFx`，不要 toggle，不要看全局 handlerTrace。
- 后台 watchdog + 主线程 heartbeat + 周期 close audit；主线程死锁时只记录，不尝试跨线程 UIKit。
- tapProbe 生产环境移除或严格保证不延迟/不取消控制事件。
- 音量键/摇一摇仅作为辅助，不纳入“保证可退”。

**明确点名的“看起来对但解决不了根因”条目：**
- prevtail 200→2000：主要只延长诊断窗口，还会被后续启动覆盖。
- 依赖点按到达的 tapProbe/guard：如果特效 window 吞触摸，它永远不触发，这正是当前死法的候选。
- 只把特效根视图 `isUserInteractionEnabled=false`：对 UIWindow 自身 hitTest 不够。
- 全局 `handlerTrace95` 看门狗：会误判，也会漏判，且 toggle 超时关闭有双翻转风险。
- 音量键/摇一摇/锁屏控件作为主逃生：不可靠或太慢，不能承诺“永远有路可退”。
