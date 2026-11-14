const __vite__mapDeps=(i,m=__vite__mapDeps,d=(m.f||(m.f=["assets/dynamicIconImports-D78kCJnW.js","assets/preload-helper-DJS5tWln.js","assets/stageLayerView-BbbKxV6Q.js","assets/lucide-icons-BymjaKfP.js","assets/noLyricLines-DtlbVAZD.js","assets/noLyricLines-QTgsb78Q.css","assets/registry-CewrmnG-.js","assets/kit-BlAGkjGU.js","assets/proxy-8Tn9130P.js","assets/use-transform-EDee-eLa.js","assets/use-motion-value-DJ39WVK-.js","assets/AnimatePresence-Csz9y39H.js","assets/ColorField-dqyopdLj.js","assets/QuickControlChip-CQkM4LPp.js","assets/panelRows-DEMl1uKz.js","assets/ThemedDialog-YVsBjnBY.js","assets/usePlaybackStore-B8iA96oZ.js","assets/foliaLyricDocument-Bb6Z1PpV.js","assets/graphemeTiming-BhIjEJVM.js","assets/motionSignals-jQwOXr3K.js","assets/FoliumMountHost-uTHB8D15.js","assets/alternateText-s3TgOEJo.js","assets/useAppChromeStore-CM35lDqb.js","assets/subtitleOverlayLayout-CaAeUMJo.js","assets/useAppViewStore-BbsVGDY-.js","assets/kinds-BH-z2A0D.js","assets/stageContext-BvHOEhNM.js","assets/audio-jdINDmaa.js"])))=>i.map(i=>d[i]);
import{f as e,l as t,p as n,t as r}from"./preload-helper-DJS5tWln.js";import{Fo as i,Ni as a,Zn as o,a as s,j as c,ko as l,qi as u,st as d,wc as f,xc as p,z as m,zn as h}from"./lucide-icons-BymjaKfP.js";import{$a as g,Bi as _,Ea as v,Gi as y,Na as b,Oa as x,Pt as S,Qa as C,Ut as w,Vi as T,Za as E,do as D,qt as ee,wa as te,zi as O}from"./noLyricLines-DtlbVAZD.js";import{A as k,D as ne,O as re,g as ie,k as ae,n as oe,t as se}from"./proxy-8Tn9130P.js";import{t as ce}from"./use-transform-EDee-eLa.js";import{t as le}from"./AnimatePresence-Csz9y39H.js";import{t as ue}from"./use-motion-value-DJ39WVK-.js";import{I as de,O as A,a as fe,c as pe,n as me,u as he}from"./kit-BlAGkjGU.js";import{o as ge,p as _e,u as j}from"./ColorField-dqyopdLj.js";import{a as ve,n as ye,o as be,r as xe,t as Se}from"./QuickControlChip-CQkM4LPp.js";import{n as M,r as N,t as P}from"./panelRows-DEMl1uKz.js";import{d as Ce}from"./foliaLyricDocument-Bb6Z1PpV.js";import{i as we,o as Te}from"./motionSignals-jQwOXr3K.js";var Ee=new Set,De=({timestamp:e})=>{Ee.forEach(t=>t.tick(e))},Oe=class extends ne{constructor(e){super(),this.state=`idle`,this.startTime=0,this.currentTime=0,this.started=!1,this.hasNextTarget=!1,this.nextTarget=0,this.stop=()=>{this.state!==`idle`&&(this.teardown(),this.options.onStop?.())},this.options=e,re(e),this.factory=e.type||k,this.generator=this.factory(e);let{driver:t}=e;t&&(this.driver=t(e=>this.tick(e))),this.startTime=this.now(),this.state=`running`,this.driver?this.driver.start():(Ee.size||g.update(De,!0),Ee.add(this))}setTarget(e,t){this.nextTarget=e,this.nextVelocity=t,this.hasNextTarget=!0}retarget(e,t){let{options:n,generator:r}=this;n.keyframes=e,n.velocity=t,this.startTime=this.now(),this.currentTime=0,r.retarget?r.retarget(e,t):this.generator=this.factory(n)}tick(e){let{options:t,hasNextTarget:n}=this,{delay:r=0,onUpdate:i,onPlay:a}=t,o=Math.round(e-this.startTime)-r,s=this.currentTime=Math.max(0,o),c=this.generator.next(s),l=o<0?t.keyframes[0]:c.value;if(n){this.hasNextTarget=!1;let{keyframes:e}=t;e[0]=l,e[1]=this.nextTarget,this.retarget(e,this.nextVelocity??this.getGeneratorVelocity())}(n||!this.started)&&(this.started=!0,a?.()),this.state===`running`&&(i?.(l),c.done&&o>=0&&!n&&!this.hasNextTarget&&this.state===`running`&&(this.notifyFinished(),this.teardown(),this.state=`finished`,t.onComplete?.()))}getGeneratorVelocity(){return ae(this.generator,this.currentTime,this.options.velocity)}now(){return this.driver?this.driver.now():E.now()}teardown(){this.state=`idle`,this.driver?this.driver.stop():(Ee.delete(this),Ee.size||C(De))}};function ke(e,t,n={}){let r=e.get(),i=null,a,o=typeof r==`string`?r.replace(/[\d.-]/g,``):void 0,s=e=>a(o?e+o:e),c=()=>e.events.animationStart?.notify(),l=()=>{i&&=(i.stop(),null),e.animation=void 0};if(e.attach((t,r)=>{a=r;let o=je(t);if(i?.state===`running`){i.setTarget(o,n.velocity);return}let u=je(e.get()),d=i?i.getGeneratorVelocity():e.getVelocity();if(l(),u===o)return;let f=i=new Oe({keyframes:[u,o],velocity:d,type:`spring`,restDelta:.001,restSpeed:.01,...n,onUpdate:s,onPlay:c});e.animation=f,f.then(()=>{i===f&&(i=null,e.animation=void 0,e.events.animationComplete?.notify())})},l),ie(t)){let r=n.skipInitialAnimation===!0,i=t.on(`change`,t=>{r?(r=!1,e.jump(Ae(t,o),!1)):e.set(Ae(t,o))}),a=e.on(`destroy`,i);return()=>{i(),a()}}return l}function Ae(e,t){return t?e+t:e}function je(e){return typeof e==`number`?e:parseFloat(e)}var F=n(f(),1);function Me(e,t={}){let{isStatic:n}=(0,F.useContext)(oe),r=()=>ie(e)?e.get():e;if(n)return ce(r);let i=ue(r());return(0,F.useInsertionEffect)(()=>ke(i,e,t),[i,JSON.stringify(t)]),i}function Ne(e,t={}){return Me(e,{type:`spring`,...t})}var I=D(),Pe=e=>e,Fe={id:`bg-common`,titleKey:`options.visualizerBackgroundModeCommon`},Ie={id:`bg-common-cover`,titleKey:`options.previewCoverBackgroundSettings`},Le=({config:e,actions:t,t:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a=e?.common,o=t?.common,s=a?.useCoverColorBg??!1;return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsxs)(A,{def:Fe,bare:!0,children:[(0,I.jsx)(M,{label:n(`options.disableVisualizerVignette`),note:n(`options.disableVisualizerVignetteDesc`),checked:a?.disableVignette??!1,onChange:e=>o?.onDisableVignetteChange?.(e)}),(0,I.jsx)(M,{label:n(`options.disableVisualizerGeometricBackground`),note:n(`options.disableVisualizerGeometricBackgroundDesc`),checked:a?.disableGeometricBackground??!1,onChange:e=>o?.onDisableGeometricChange?.(e)})]}),(0,I.jsxs)(A,{def:Ie,children:[(0,I.jsx)(M,{label:n(`theme.addCoverColor`),note:n(`options.coverColorBackgroundDesc`),checked:s,onChange:e=>o?.onCoverColorChange?.(e)}),(0,I.jsx)(_e,{when:s,children:(0,I.jsx)(P,{sub:!0,label:n(`options.previewCoverBackgroundOpacity`),value:a?.opacity??.75,min:0,max:1,step:.05,format:N,onChange:e=>o?.onOpacityChange?.(e),onDragStart:r,onDragEnd:i})})]})]})},Re=384,ze=160,Be=350,Ve=1e3,He=1e3,Ue=4e3,We=`data-picture-wait`,Ge=`data-picture-arriving`,Ke={width:64,height:40},qe=null,Je=e=>{if(!qe){let e=document.createElement(`canvas`);e.width=Ke.width,e.height=Ke.height,qe=e.getContext(`2d`,{willReadFrequently:!0}),qe&&(qe.imageSmoothingQuality=`high`)}if(!qe)return!1;try{qe.clearRect(0,0,Ke.width,Ke.height),qe.drawImage(e,0,0,Ke.width,Ke.height);let t=new Uint32Array(qe.getImageData(0,0,Ke.width,Ke.height).data.buffer);return t.every(e=>e===t[0])}catch{return qe=null,!1}},Ye=e=>[...e.querySelectorAll(`canvas`)].filter(e=>e.width>0&&e.height>0).map(e=>({canvas:e,blank:Je(e)})),Xe=60,Ze=e=>[...e.querySelectorAll(`*`)].slice(0,Xe).some(e=>{let t=getComputedStyle(e);return!!t.backgroundImage&&t.backgroundImage!==`none`&&t.opacity!==`0`&&e.offsetWidth>0&&e.offsetHeight>0}),Qe=e=>{if(!e.firstElementChild||e.querySelector(`[data-picture-wait]`))return{shows:!1,whole:!1,waits:!1};let t=Ye(e),n=t.every(e=>!e.blank),r=t.some(e=>!e.blank)||!!e.textContent?.trim()||e.querySelector(`svg, img`)!==null,i=!r&&Ze(e),a=e.querySelector(`[${Ge}]`)!==null;return{shows:r||i,whole:n,waits:a||i&&!n}},$e=e=>e.getAnimations({subtree:!0}).some(e=>e.playState===`running`&&Number.isFinite(Number(e.effect?.getComputedTiming().endTime))),et=(e,t,n)=>{let r=performance.now(),i=r,a=0,o=0,s=0,c=new MutationObserver(()=>{i=performance.now()});t===`still`&&c.observe(e,{subtree:!0,childList:!0,attributes:!0,characterData:!0});let l=()=>{c.disconnect(),window.clearTimeout(o),window.cancelAnimationFrame(s)},u=()=>{o=window.setTimeout(()=>{s=window.requestAnimationFrame(f)})},d=()=>{let n=performance.now(),{shows:o,whole:s,waits:c}=Qe(e),l=o&&!c;return l&&!a&&(a=n),l&&(s||n-a>=He)&&(t===`drawn`||n-a>=Be&&(n-i>=ze&&!$e(e)||n-a>=Ve))?`shown`:n-r>=Ue?o?`shown`:`empty`:null},f=()=>{let e;try{e=d()}catch(t){console.warn(`[LivePicture] A stage could not be read:`,t),e=`failed`}if(e){l(),n(e);return}u()};return u(),l},tt=(e,t,n=Math.min(e.width,Re))=>{t.width=Math.max(1,n),t.height=Math.max(1,Math.round(e.height*n/Math.max(1,e.width)));let r=t.getContext(`2d`);r&&(r.imageSmoothingQuality=`high`,r.drawImage(e,0,0,t.width,t.height))},nt=e=>e.replace(/[A-Z]/g,e=>`-${e.toLowerCase()}`),rt=e=>{if(!Qe(e).shows)return null;let t=e.cloneNode(!0),n=t.querySelectorAll(`canvas`);e.querySelectorAll(`canvas`).forEach((e,t)=>{let r=n[t];r.style.width=`${e.offsetWidth}px`,r.style.height=`${e.offsetHeight}px`,e.width>0&&e.height>0&&tt(e,r)});let r=[...e.querySelectorAll(`*`)],i=t.querySelectorAll(`*`);i.forEach(e=>{e.style.willChange=`auto`});for(let t of e.getAnimations({subtree:!0})){let e=t.effect,n=e?.target&&!e.pseudoElement?i[r.indexOf(e.target)]:void 0;if(!e?.target||!n)continue;let a=getComputedStyle(e.target);for(let t of e.getKeyframes())for(let e of Object.keys(t))e!==`offset`&&e!==`computedOffset`&&e!==`easing`&&e!==`composite`&&n.style.setProperty(nt(e),a.getPropertyValue(nt(e)));n.style.animation=`none`}return t},it=e=>{let t=new Set(e.querySelectorAll(`canvas`)),n=e=>{for(let n of e)n.addedNodes.forEach(e=>{e instanceof HTMLCanvasElement?t.add(e):e instanceof Element&&e.querySelectorAll(`canvas`).forEach(e=>t.add(e))})},r=new MutationObserver(n);return r.observe(e,{subtree:!0,childList:!0}),()=>{n(r.takeRecords()),r.disconnect();for(let e of t)try{if(e.getContext(`2d`))continue;let t=e.getContext(`webgl2`)??e.getContext(`webgl`);t&&!t.isContextLost()&&t.getExtension(`WEBGL_lose_context`)?.loseContext()}catch{}}},at=e=>{let t=e.cloneNode(!0),n=t.querySelectorAll(`canvas`);return e.querySelectorAll(`canvas`).forEach((e,t)=>{e.width>0&&e.height>0&&tt(e,n[t],e.width)}),t},ot=(0,F.createContext)(null),st=()=>{let e=(0,F.useContext)(ot);return(0,F.useLayoutEffect)(()=>{e?.claim()},[e]),(0,F.useCallback)(()=>e?.drawn(),[e])},ct=(0,F.createContext)(!1),lt=()=>(0,F.useContext)(ct),ut=e=>Math.max(0,Math.min(1,e)),dt=(e,t)=>t>=1?1:ut((e-t)/(1-t)),ft=(e,t)=>{let n=ut(e),r=ut(t),i=r<=0||r>=1?n:n<=r?.5*n/r:.5+.5*(n-r)/(1-r);return i*i*(3-2*i)},pt=e=>1-(1-e)**3,mt=(e,t)=>e.length===t.length&&e.every((e,n)=>e===t[n]),ht=(e,t,n)=>{let r=e.join(`|`),i=(0,F.useMemo)(()=>r.split(`|`),[r]),[a,o]=(0,F.useState)(i),s=(0,F.useRef)(i);return(0,F.useEffect)(()=>{let e=s.current,r=e=>{s.current=e,o(e)};if(mt(e,i))return;if(t<=0||e.length!==i.length){r(i);return}let a=t=>t>=1?i:i.map((n,r)=>_(e[r],n,t)),c=n?.get()??1;if(n&&c<1)return n.on(`change`,e=>r(a(dt(e,c))));let l=performance.now(),u=0,d=e=>{let n=Math.min(1,(e-l)/t);r(a(n>=1?1:pt(n))),n<1&&(u=requestAnimationFrame(d))};return u=requestAnimationFrame(d),()=>cancelAnimationFrame(u)},[i,t,n]),t<=0?i:a},gt=24,_t=96,vt=()=>{if(typeof navigator>`u`)return!1;let e=navigator.userAgent,t=/iPad|iPhone|iPod/i.test(e)||navigator.platform===`MacIntel`&&navigator.maxTouchPoints>1,n=/WebKit/i.test(e),r=/CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo|YaBrowser|GSA/i.test(e);return t&&n&&!r},yt=e=>new Promise(t=>{if(typeof document>`u`){t(null);return}let n=new Image;n.crossOrigin=`anonymous`,n.decoding=`async`,n.onload=()=>{try{let e=document.createElement(`canvas`),r=document.createElement(`canvas`);e.width=gt,e.height=gt,r.width=_t,r.height=_t;let i=e.getContext(`2d`),a=r.getContext(`2d`);if(!i||!a){t(null);return}let o=n.naturalWidth||n.width,s=n.naturalHeight||n.height,c=Math.min(o,s),l=Math.max(0,(o-c)/2),u=Math.max(0,(s-c)/2);i.imageSmoothingEnabled=!0,i.imageSmoothingQuality=`high`,i.drawImage(n,l,u,c,c,0,0,gt,gt),a.imageSmoothingEnabled=!0,a.imageSmoothingQuality=`high`,a.globalAlpha=1,a.drawImage(e,0,0,gt,gt,0,0,_t,_t),[{x:-8,y:-8,size:112,alpha:.22},{x:6,y:0,size:_t,alpha:.14},{x:0,y:6,size:_t,alpha:.14}].forEach(({x:t,y:n,size:r,alpha:i})=>{a.globalAlpha=i,a.drawImage(e,0,0,gt,gt,t,n,r,r)}),a.globalAlpha=1,t(r.toDataURL(`image/jpeg`,.72))}catch(e){console.warn(`[FluidBackground] Failed to build soft focus cover`,e),t(null)}},n.onerror=()=>t(null),n.src=e}),bt=320,xt=640,St=1e3,Ct=(e,t)=>{e.fillStyle=`#000`,e.fillStyle=t;let n=String(e.fillStyle),[r,i,a]=n.startsWith(`#`)?[1,3,5].map(e=>parseInt(n.slice(e,e+2),16)):n.match(/[\d.]+/g)??[`0`,`0`,`0`];return[n,`rgba(${r}, ${i}, ${a}, 0)`]},wt=(e,t)=>{let n=document.createElement(`canvas`);return n.width=e,n.height=t,n},Tt=null,Et=()=>{if(Tt!==null)return Tt;try{let e=wt(4,1).getContext(`2d`,{willReadFrequently:!0});!e||typeof e.filter!=`string`?Tt=!1:(e.filter=`blur(1px)`,e.fillStyle=`#fff`,e.fillRect(2,0,1,1),Tt=e.getImageData(1,0,1,1).data[3]>0)}catch{Tt=!1}return Tt},Dt=(e,t)=>{let{width:n,height:r}=e,i=n/Math.max(1,t*2.5),a=[],o=n,s=r;for(;o/2>=i&&o>2&&s>2;)o=Math.ceil(o/2),s=Math.ceil(s/2),a.push([o,s]);let c=[...a,...a.slice(0,-1).reverse(),[n,r]],l=e;for(let[e,t]of c){let n=wt(e,t),r=n.getContext(`2d`);if(!r)return l;r.imageSmoothingEnabled=!0,r.imageSmoothingQuality=`high`,r.drawImage(l,0,0,e,t),l=n}return l},Ot=(e,t,n,r)=>{let i=wt(t,n),a=i.getContext(`2d`);if(!a)return null;let o=Math.max(t/e.width,n/e.height)*1.5,s=e.width*o,c=e.height*o,l=60*t/r,u=Et();return u&&(a.filter=`blur(${l}px)`),a.imageSmoothingEnabled=!0,a.imageSmoothingQuality=`high`,a.drawImage(e,(t-s)/2,(n-c)/2,s,c),u?i:Dt(i,l)},kt=(e,t,n,r)=>{let i=e.getContext(`2d`);if(!i)return;let{width:a,height:o}=e;if(i.clearRect(0,0,a,o),!t)return;i.drawImage(t,0,0,a,o);let s=Math.hypot(a,o),c=a*o/s,l=o/s*c,u=a/s*c,d=i.createLinearGradient(a/2-l,o/2-u,a/2+l,o/2+u),[f,p]=Ct(i,n),[m,h]=Ct(i,r);d.addColorStop(0,f),d.addColorStop(.5,p),d.addColorStop(.5,h),d.addColorStop(1,m),i.globalCompositeOperation=`overlay`,i.globalAlpha=.4,i.fillStyle=d,i.fillRect(0,0,a,o),i.globalCompositeOperation=`source-over`,i.globalAlpha=1},At=({image:e,primaryColor:t,secondaryColor:n,onDrawn:r})=>{let i=(0,F.useRef)(null),[a,o]=(0,F.useState)(null);(0,F.useLayoutEffect)(()=>{let e=i.current;if(!e)return;let t=()=>{let t=e.clientWidth,n=e.clientHeight;o(e=>e&&e.width===t&&e.height===n?e:{width:t,height:n})};if(t(),typeof ResizeObserver>`u`)return;let n=new ResizeObserver(t);return n.observe(e),()=>n.disconnect()},[]);let s=(0,F.useRef)(r);(0,F.useLayoutEffect)(()=>{s.current=r});let c=(0,F.useRef)(!1),l=(0,F.useRef)(null);return(0,F.useLayoutEffect)(()=>{let r=i.current;if(!r||!a)return;if(a.width>0&&a.height>0){let i=Math.max(1,Math.round(bt*a.height/a.width));(r.width!==bt||r.height!==i)&&(r.width=bt,r.height=i);let o=l.current;e?(!o||o.image!==e||o.width!==r.width||o.height!==r.height||o.cssWidth!==a.width)&&(o={image:e,width:r.width,height:r.height,cssWidth:a.width,canvas:Ot(e,r.width,r.height,a.width)}):o=null,l.current=o,kt(r,o?.canvas??null,t,n)}if(c.current)return;let o=requestAnimationFrame(()=>{c.current=!0,s.current()});return()=>cancelAnimationFrame(o)},[a,e,t,n]),(0,I.jsx)(`canvas`,{ref:i,"aria-hidden":`true`,className:`absolute inset-0 w-full h-full`})},jt=(0,F.memo)(({coverUrl:e,theme:t})=>{let n=(0,F.useMemo)(vt,[]),[r,i]=(0,F.useState)(null),[a,o]=ht([t.primaryColor,t.secondaryColor],St);(0,F.useEffect)(()=>{let t=!1;return!n||!e?(i(null),()=>{t=!0}):(i(null),yt(e).then(e=>{t||i(e)}),()=>{t=!0})},[e,n]);let s=st(),c=(0,F.useRef)(0),[l,u]=(0,F.useState)([]),[d,f]=(0,F.useState)(()=>new Set),p=(0,F.useRef)(new Set);(0,F.useEffect)(()=>{let e=new Set(l.map(e=>e.image));p.current.forEach(t=>{e.has(t)||(t.close(),p.current.delete(t))})},[l]),(0,F.useEffect)(()=>()=>{p.current.forEach(e=>e.close()),p.current.clear()},[]),(0,F.useEffect)(()=>{if(n)return;if(!e){u([]);return}let t=!1,r=new Image;return r.decoding=`async`,r.src=e,r.decode().then(()=>{let e=Math.min(1,xt/Math.max(r.naturalWidth,r.naturalHeight));return createImageBitmap(r,{resizeWidth:Math.max(1,Math.round(r.naturalWidth*e)),resizeHeight:Math.max(1,Math.round(r.naturalHeight*e)),resizeQuality:`high`})}).then(n=>{if(t){n.close();return}p.current.add(n),u(t=>{let r=t[t.length-1];return r&&r.sourceCover===e?t:(c.current+=1,[...r?[r]:[],{image:n,sourceCover:e,key:c.current}])})},()=>{t||(u(t=>t.length>0?t:(c.current+=1,[{image:null,sourceCover:e,key:c.current}])),s())}),()=>{t=!0}},[e,n,s]);let m=lt(),h=(0,F.useRef)(m);(0,F.useLayoutEffect)(()=>{h.current=m});let[g,_]=(0,F.useState)(null);(0,F.useEffect)(()=>{(!e||n)&&s()},[e,n,s]);let v=(0,F.useCallback)(e=>{h.current&&_(e),f(t=>t.has(e)?t:new Set(t).add(e)),s()},[s]),[y,b]=(0,F.useState)(null),x=l[l.length-1],S=!!e&&!n&&!(x&&x.sourceCover===e&&x.key===y),C=n?r??e??null:null,w=n&&!!r,T=(0,F.useMemo)(()=>({transform:`scale(${w?1.28:1.2}) translateZ(0)`,opacity:w?.94:.3,willChange:`transform, opacity`,backfaceVisibility:`hidden`,WebkitBackfaceVisibility:`hidden`}),[w]);return(0,I.jsxs)(`div`,{className:`absolute inset-0 w-full h-full overflow-hidden pointer-events-none z-0`,style:{isolation:`isolate`,contain:`paint`,transform:`translateZ(0)`},...S?{[Ge]:``}:{},children:[e?(0,I.jsxs)(I.Fragment,{children:[n?(0,I.jsx)(`img`,{src:C??e,alt:``,"aria-hidden":`true`,draggable:!1,decoding:`async`,className:`absolute inset-0 w-full h-full object-cover transition-opacity duration-700 ease-out`,style:T}):(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`div`,{className:`absolute inset-0 w-full h-full transition-colors duration-1000`,style:{backgroundColor:t.backgroundColor,opacity:.8}}),l.map((e,t)=>{let n=t===l.length-1,r=d.has(e.key);return(0,I.jsx)(se.div,{className:`absolute inset-0 w-full h-full`,style:{willChange:`opacity`},initial:{opacity:+!n},animate:{opacity:n&&!r?0:1},transition:{duration:e.key===g?0:1.5,ease:`easeInOut`},onAnimationComplete:()=>{n&&r&&(u(t=>t.filter(t=>t.key===e.key)),f(t=>t.has(e.key)?new Set([e.key]):t),b(e.key))},children:(0,I.jsx)(At,{image:e.image,primaryColor:a,secondaryColor:o,onDrawn:()=>v(e.key)})},e.key)})]}),n&&(0,I.jsxs)(I.Fragment,{children:[!w&&(0,I.jsx)(`img`,{src:e,alt:``,"aria-hidden":`true`,draggable:!1,decoding:`async`,className:`absolute inset-0 w-full h-full object-cover`,style:{transform:`scale(1.36) translateZ(0)`,opacity:.12,willChange:`transform, opacity`,backfaceVisibility:`hidden`,WebkitBackfaceVisibility:`hidden`}}),(0,I.jsx)(`div`,{className:`absolute inset-0 w-full h-full`,style:{backgroundColor:t.backgroundColor,opacity:.28}}),(0,I.jsx)(`div`,{className:`absolute inset-0 w-full h-full`,style:{background:`radial-gradient(circle at 20% 20%, ${t.accentColor}55 0%, transparent 42%), radial-gradient(circle at 80% 28%, ${t.secondaryColor}50 0%, transparent 44%), radial-gradient(circle at 50% 78%, ${t.primaryColor}28 0%, transparent 52%)`,opacity:w?.52:.7}})]})]}):(0,I.jsx)(`div`,{className:`absolute inset-0 w-full h-full transition-colors duration-1000`,style:{backgroundColor:t.backgroundColor,opacity:.8}}),(!e||n||x&&!x.image)&&(0,I.jsx)(`div`,{className:`absolute inset-0 w-full h-full`,style:{background:`linear-gradient(to bottom right, ${a}, transparent, ${o})`,opacity:n?.2:.4,mixBlendMode:n?`normal`:`overlay`}})]})},(e,t)=>{if(e.coverUrl!==t.coverUrl)return!1;let n=e.theme,r=t.theme;return n.backgroundColor===r.backgroundColor&&n.primaryColor===r.primaryColor&&n.secondaryColor===r.secondaryColor}),Mt=null,Nt=null,Pt=!1,Ft=new Map,It=new Map,Lt=new Set,Rt=new Set,zt=0,Bt=e=>typeof e==`object`&&!!e&&`$$typeof`in e&&`render`in e,Vt=e=>e.replace(/(?:^|-)(\w)/g,(e,t)=>t.toUpperCase()),Ht=e=>Vt(e.trim()),Ut=e=>{let t=new Map,n=new Map,r=Object.keys(e);return[e=>e,e=>`${e}Icon`,e=>`Lucide${e}`].forEach(e=>{r.forEach(r=>{let i=e(Vt(r));t.has(i)||(t.set(i,r),n.has(i.toLowerCase())||n.set(i.toLowerCase(),i))})}),{loaders:e,keysByName:t,namesByLowercase:n}},Wt=()=>{zt+=1,Rt.forEach(e=>e())},Gt=()=>(Nt??=r(()=>import(`./dynamicIconImports-D78kCJnW.js`).then(e=>e.t).then(e=>(Mt=Ut(e.default),Pt=!1,Wt(),Mt)),__vite__mapDeps([0,1])).catch(e=>{throw Nt=null,Pt=!0,Wt(),e}),Nt),Kt=(e,t)=>{if(Ft.has(t))return Promise.resolve();let n=It.get(t);return n||(n=e.loaders[t]().then(e=>{Bt(e.default)&&(Ft.set(t,e.default),Lt.delete(t),Wt())}).catch(()=>{Lt.add(t),Wt()}).finally(()=>It.delete(t)),It.set(t,n)),n},qt=e=>typeof e==`string`?e.trim():``,Jt=async e=>{let t=(e??[]).map(qt).filter(Boolean);if(t.length===0)return;let n;try{n=await Gt()}catch{return}await Promise.all(t.map(e=>{let t=n.keysByName.has(e)?e:n.namesByLowercase.get(e.toLowerCase()),r=t?n.keysByName.get(t):void 0;return r?Kt(n,r):void 0}))},Yt=async e=>{let t=qt(e);if(!t)return!1;try{return(await Gt()).keysByName.has(t)}catch{return!1}},Xt=e=>{let t=Mt?.keysByName.get(qt(e));return t?Ft.get(t)??null:null},Zt=e=>{let t=Xt(e);if(!t||typeof t.render!=`function`)return null;try{let e=t.render({},null),n=e?.props?.iconNode??e?.props?.icon?.node;return Array.isArray(n)?n:null}catch{return null}},Qt=e=>{let t=qt(e);if(!t)return`missing`;if(!Mt)return Pt?`missing`:`loading`;let n=Mt.keysByName.get(t);return n?Ft.has(n)?`ready`:Lt.has(n)?`missing`:`loading`:`missing`},$t=e=>[...new Set((e??[]).map(e=>typeof e==`string`?Mt?.namesByLowercase.get(e.trim().toLowerCase()):void 0).filter(e=>e!==void 0&&Xt(e)!==null))],en=e=>(Rt.add(e),()=>{Rt.delete(e)}),tn=()=>zt,nn=e=>{let t=e?.join(`
`)??``;return(0,F.useEffect)(()=>{t&&Jt(t.split(`
`))},[t]),(0,F.useSyncExternalStore)(en,tn,tn)},rn=e=>{switch(e.type){case`circle`:return`bass`;case`square`:return`lowMid`;case`triangle`:return`mid`;case`cross`:return`treble`;default:return`default`}},an=e=>e===`triangle`?`polygon(50% 0%, 0% 100%, 100% 100%)`:e===`cross`?`polygon(20% 0%, 0% 20%, 30% 50%, 0% 80%, 20% 100%, 50% 70%, 80% 100%, 100% 80%, 70% 50%, 100% 20%, 80% 0%, 50% 30%)`:`none`,on=(e,t)=>{let n=(e.type===`circle`||e.type===`square`)&&!e.filled;return{border:n?`1px solid ${t.secondaryColor}`:`none`,backgroundColor:n?`transparent`:t.secondaryColor,borderRadius:e.type===`circle`?`50%`:`0%`,opacity:e.opacity,clipPath:an(e.type)}},sn=e=>({left:`${e.initialX}%`,top:`${e.initialY}%`,width:e.size,height:e.size,animationDuration:`${e.duration}s`,animationDelay:`${e.delay}s`,"--geometric-dir":e.reverse?-1:1,"--geometric-rotate":`${e.initialRotation}deg`}),cn=(e,t)=>{if(e.iconSlot===null||t.length===0)return null;let n=t[Math.floor(e.iconSlot*t.length)];return Qt(n)===`loading`?`loading`:Xt(n)},ln=({disabled:e=!1})=>e?null:(0,I.jsx)(`div`,{className:`absolute inset-0 pointer-events-none`,style:{background:`radial-gradient(circle, transparent 40%, rgba(0,0,0,0.6) 100%)`}}),un=({theme:e,audioPower:t,audioBands:n,shapes:r,particles:i,hideShapes:a,disableVignette:o,paused:s})=>{let c=e=>{let n=Ne(e||t,{stiffness:300,damping:30});return ce(n,[10,200],[.95,1.45])},l={bass:c(n?.bass),lowMid:c(n?.lowMid),mid:c(n?.mid),vocal:c(n?.vocal),treble:c(n?.treble),default:c(t)},u=e.lyricsIcons||[];return(0,I.jsxs)(`div`,{className:s?`absolute inset-0 geometric-paused`:`absolute inset-0`,children:[!a&&(0,I.jsxs)(I.Fragment,{children:[r.map(t=>{let n=cn(t,u),r=n===`loading`?null:n;return(0,I.jsxs)(`div`,{className:`absolute geometric-drift`,style:sn(t),children:[(0,I.jsx)(se.div,{className:`w-full h-full transition-[color,background-color,border-color,opacity] duration-1000`,style:{...on(t,e),...n===null?{}:{opacity:0},scale:l[rn(t)]}}),t.iconSlot!==null&&(0,I.jsx)(`div`,{className:`absolute inset-0 transition-opacity duration-1000`,style:{opacity:+!!r},children:(0,I.jsx)(se.div,{className:`w-full h-full flex items-center justify-center geometric-pulse transition-colors duration-1000`,style:{color:e.secondaryColor,scale:l.vocal,animationDuration:`${t.duration*.5}s`,animationDelay:`${t.delay}s`,"--geometric-peak":t.opacity*3},children:r&&(0,I.jsx)(r,{size:t.size,strokeWidth:1,absoluteStrokeWidth:!0})})})]},t.id)}),i.map(t=>(0,I.jsx)(`div`,{className:`absolute rounded-full geometric-rise transition-colors duration-1000`,style:{backgroundColor:e.accentColor,width:t.size,height:t.size,left:`${t.left}%`,top:`${t.top}%`,animationDuration:`${t.duration}s`,animationDelay:`${t.delay}s`,"--geometric-peak":t.opacity}},`p-${t.id}`))]}),(0,I.jsx)(ln,{disabled:o})]})},dn=({theme:e,audioPower:t,audioBands:n,seed:r,hideShapes:i=!1,disableVignette:a=!1,paused:o=!1})=>{nn(e.lyricsIcons);let s=(0,F.useMemo)(()=>{let e=[`circle`,`square`,`triangle`,`cross`],t=0;return Array.from({length:15}).map((n,r)=>{let i=t<6&&Math.random()>.7?Math.random():null;return i!==null&&(t+=1),{id:r,type:e[Math.floor(Math.random()*e.length)],iconSlot:i,initialX:Math.random()*100,initialY:Math.random()*100,size:40+Math.random()*100,duration:i===null?30+Math.random()*30:20+Math.random()*20,delay:Math.random()*5,opacity:.11+Math.random()*.08,reverse:Math.random()>.5,filled:Math.random()<.3,initialRotation:Math.random()*360}})},[r]),c=(0,F.useMemo)(()=>Array.from({length:20}).map((e,t)=>({id:t,size:Math.random()*4+1,left:Math.random()*100,top:Math.random()*100,opacity:Math.random()*.3,duration:15+Math.random()*20,delay:Math.random()*10})),[r]);return(0,I.jsx)(se.div,{className:`absolute inset-0`,initial:!1,animate:{opacity:1},exit:{opacity:0},transition:{duration:.6,ease:`easeInOut`},children:(0,I.jsx)(un,{theme:e,audioPower:t,audioBands:n,shapes:s,particles:c,hideShapes:i,disableVignette:a,paused:o})})},fn=F.memo(e=>{let t=String(e.seed??`default`);return(0,I.jsx)(`div`,{className:`absolute inset-0 overflow-hidden pointer-events-none`,children:(0,I.jsx)(le,{mode:`sync`,children:(0,I.jsx)(dn,{...e},t)})})},(e,t)=>{if(e.seed!==t.seed||e.audioPower!==t.audioPower||e.hideShapes!==t.hideShapes||e.disableVignette!==t.disableVignette||e.paused!==t.paused)return!1;let n=e.audioBands,r=t.audioBands;if(!n!=!r)return!1;let i=!0;if(n&&r&&(i=n.bass===r.bass&&n.lowMid===r.lowMid&&n.mid===r.mid&&n.vocal===r.vocal&&n.treble===r.treble),!i)return!1;let a=e.theme,o=t.theme,s=a.backgroundColor===o.backgroundColor&&a.primaryColor===o.primaryColor&&a.secondaryColor===o.secondaryColor&&a.accentColor===o.accentColor,c=!!(a.lyricsIcons===o.lyricsIcons||a.lyricsIcons?.length===o.lyricsIcons?.length&&a.lyricsIcons?.every((e,t)=>e===o.lyricsIcons?.[t]));return s&&c}),pn=e({default:()=>mn}),mn=Pe({mode:`common`,order:10,labelKey:`options.visualizerBackgroundModeCommon`,labelFallback:`Common`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`path`,{d:`M4 17l5-8 5 8z`}),(0,I.jsx)(`circle`,{cx:`17.5`,cy:`8.5`,r:`3`,opacity:`0.55`})]}),command:{title:`Background: Common`,description:`Switch background to general layout`,keywords:[`background general`,`common`,`general`,`通用背景`,`ty`,`背景切换到 通用`,`背景切换到通用`]},song:({config:e,coverUrl:t,seed:n,staticMode:r})=>[r?null:n??null,e?.common?.useCoverColorBg?t??null:null],render:({config:e,theme:t,coverUrl:n,audioPower:r,audioBands:i,seed:a,staticMode:o,paused:s})=>{let c=e?.common,l=c?.useCoverColorBg??!1;return(0,I.jsxs)(I.Fragment,{children:[l&&(0,I.jsx)(`div`,{className:`absolute inset-0 z-0`,children:(0,I.jsx)(jt,{coverUrl:n,theme:t})}),(0,I.jsx)(`div`,{className:`absolute inset-0 z-0 transition-all duration-1000`,style:{backgroundColor:t.backgroundColor,opacity:l?c?.opacity??.75:1}}),!o&&(0,I.jsx)(`div`,{className:`absolute inset-0 z-0`,children:(0,I.jsx)(fn,{theme:t,audioPower:r,audioBands:i,seed:a,hideShapes:c?.disableGeometricBackground??!1,disableVignette:c?.disableVignette??!1,paused:s})})]})},renderSettingsPanel:e=>(0,I.jsx)(Le,{...e}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.common?.useCoverColorBg??!1,i=!(e?.common?.disableVignette??!1);return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(ye,{active:r,label:n(r?`theme.addCoverColor`:`theme.useDefaultColor`),onToggle:()=>t?.common?.onCoverColorChange?.(!r),children:(0,I.jsx)(l,{size:14})}),(0,I.jsx)(ye,{active:i,label:n(`options.visualizerVignette`),onToggle:()=>t?.common?.onDisableVignetteChange?.(i),children:(0,I.jsx)(p,{size:14})})]})},resetSettings:e=>{e?.common?.onOpacityChange?.(.75),e?.common?.onCoverColorChange?.(!1),e?.common?.onDisableVignetteChange?.(!1),e?.common?.onDisableGeometricChange?.(!1)}}),hn=`#version 300 es
precision mediump float;

layout(location = 0) in vec4 a_position;

uniform vec2 u_resolution;
uniform float u_pixelRatio;
uniform float u_imageAspectRatio;
uniform float u_originX;
uniform float u_originY;
uniform float u_worldWidth;
uniform float u_worldHeight;
uniform float u_fit;
uniform float u_scale;
uniform float u_rotation;
uniform float u_offsetX;
uniform float u_offsetY;

out vec2 v_objectUV;
out vec2 v_objectBoxSize;
out vec2 v_responsiveUV;
out vec2 v_responsiveBoxGivenSize;
out vec2 v_patternUV;
out vec2 v_patternBoxSize;
out vec2 v_imageUV;

vec3 getBoxSize(float boxRatio, vec2 givenBoxSize) {
  vec2 box = vec2(0.);
  // fit = none
  box.x = boxRatio * min(givenBoxSize.x / boxRatio, givenBoxSize.y);
  float noFitBoxWidth = box.x;
  if (u_fit == 1.) { // fit = contain
    box.x = boxRatio * min(u_resolution.x / boxRatio, u_resolution.y);
  } else if (u_fit == 2.) { // fit = cover
    box.x = boxRatio * max(u_resolution.x / boxRatio, u_resolution.y);
  }
  box.y = box.x / boxRatio;
  return vec3(box, noFitBoxWidth);
}

void main() {
  gl_Position = a_position;

  vec2 uv = gl_Position.xy * .5;
  vec2 boxOrigin = vec2(.5 - u_originX, u_originY - .5);
  vec2 givenBoxSize = vec2(u_worldWidth, u_worldHeight);
  givenBoxSize = max(givenBoxSize, vec2(1.)) * u_pixelRatio;
  float r = u_rotation * 3.14159265358979323846 / 180.;
  mat2 graphicRotation = mat2(cos(r), sin(r), -sin(r), cos(r));
  vec2 graphicOffset = vec2(-u_offsetX, u_offsetY);


  // ===================================================

  float fixedRatio = 1.;
  vec2 fixedRatioBoxGivenSize = vec2(
  (u_worldWidth == 0.) ? u_resolution.x : givenBoxSize.x,
  (u_worldHeight == 0.) ? u_resolution.y : givenBoxSize.y
  );

  v_objectBoxSize = getBoxSize(fixedRatio, fixedRatioBoxGivenSize).xy;
  vec2 objectWorldScale = u_resolution.xy / v_objectBoxSize;

  v_objectUV = uv;
  v_objectUV *= objectWorldScale;
  v_objectUV += boxOrigin * (objectWorldScale - 1.);
  v_objectUV += graphicOffset;
  v_objectUV /= u_scale;
  v_objectUV = graphicRotation * v_objectUV;

  // ===================================================

  v_responsiveBoxGivenSize = vec2(
  (u_worldWidth == 0.) ? u_resolution.x : givenBoxSize.x,
  (u_worldHeight == 0.) ? u_resolution.y : givenBoxSize.y
  );
  float responsiveRatio = v_responsiveBoxGivenSize.x / v_responsiveBoxGivenSize.y;
  vec2 responsiveBoxSize = getBoxSize(responsiveRatio, v_responsiveBoxGivenSize).xy;
  vec2 responsiveBoxScale = u_resolution.xy / responsiveBoxSize;

  #ifdef ADD_HELPERS
  v_responsiveHelperBox = uv;
  v_responsiveHelperBox *= responsiveBoxScale;
  v_responsiveHelperBox += boxOrigin * (responsiveBoxScale - 1.);
  #endif

  v_responsiveUV = uv;
  v_responsiveUV *= responsiveBoxScale;
  v_responsiveUV += boxOrigin * (responsiveBoxScale - 1.);
  v_responsiveUV += graphicOffset;
  v_responsiveUV /= u_scale;
  v_responsiveUV.x *= responsiveRatio;
  v_responsiveUV = graphicRotation * v_responsiveUV;
  v_responsiveUV.x /= responsiveRatio;

  // ===================================================

  float patternBoxRatio = givenBoxSize.x / givenBoxSize.y;
  vec2 patternBoxGivenSize = vec2(
  (u_worldWidth == 0.) ? u_resolution.x : givenBoxSize.x,
  (u_worldHeight == 0.) ? u_resolution.y : givenBoxSize.y
  );
  patternBoxRatio = patternBoxGivenSize.x / patternBoxGivenSize.y;

  vec3 boxSizeData = getBoxSize(patternBoxRatio, patternBoxGivenSize);
  v_patternBoxSize = boxSizeData.xy;
  float patternBoxNoFitBoxWidth = boxSizeData.z;
  vec2 patternBoxScale = u_resolution.xy / v_patternBoxSize;

  v_patternUV = uv;
  v_patternUV += graphicOffset / patternBoxScale;
  v_patternUV += boxOrigin;
  v_patternUV -= boxOrigin / patternBoxScale;
  v_patternUV *= u_resolution.xy;
  v_patternUV /= u_pixelRatio;
  if (u_fit > 0.) {
    v_patternUV *= (patternBoxNoFitBoxWidth / v_patternBoxSize.x);
  }
  v_patternUV /= u_scale;
  v_patternUV = graphicRotation * v_patternUV;
  v_patternUV += boxOrigin / patternBoxScale;
  v_patternUV -= boxOrigin;
  // x100 is a default multiplier between vertex and fragmant shaders
  // we use it to avoid UV presision issues
  v_patternUV *= .01;

  // ===================================================

  vec2 imageBoxSize;
  if (u_fit == 1.) { // contain
    imageBoxSize.x = min(u_resolution.x / u_imageAspectRatio, u_resolution.y) * u_imageAspectRatio;
  } else if (u_fit == 2.) { // cover
    imageBoxSize.x = max(u_resolution.x / u_imageAspectRatio, u_resolution.y) * u_imageAspectRatio;
  } else {
    imageBoxSize.x = min(10.0, 10.0 / u_imageAspectRatio * u_imageAspectRatio);
  }
  imageBoxSize.y = imageBoxSize.x / u_imageAspectRatio;
  vec2 imageBoxScale = u_resolution.xy / imageBoxSize;

  v_imageUV = uv;
  v_imageUV *= imageBoxScale;
  v_imageUV += boxOrigin * (imageBoxScale - 1.);
  v_imageUV += graphicOffset;
  v_imageUV /= u_scale;
  v_imageUV.x *= u_imageAspectRatio;
  v_imageUV = graphicRotation * v_imageUV;
  v_imageUV.x /= u_imageAspectRatio;

  v_imageUV += .5;
  v_imageUV.y = 1. - v_imageUV.y;
}`,gn=8294400,_n=class{parentElement;canvasElement;gl;program=null;uniformLocations={};fragmentShader;rafId=null;lastRenderTime=0;currentFrame=0;speed=0;currentSpeed=0;providedUniforms;mipmaps=[];hasBeenDisposed=!1;resolutionChanged=!0;textures=new Map;minPixelRatio;maxPixelCount;isSafari=xn();uniformCache={};textureUnitMap=new Map;ownerDocument;constructor(e,t,n,r,i=0,a=0,o=2,s=gn,c=[]){if(e?.nodeType===1)this.parentElement=e;else throw Error(`Paper Shaders: parent element must be an HTMLElement`);if(this.ownerDocument=e.ownerDocument,!this.ownerDocument.querySelector(`style[data-paper-shader]`)){let e=this.ownerDocument.createElement(`style`);e.innerHTML=bn,e.setAttribute(`data-paper-shader`,``),this.ownerDocument.head.prepend(e)}let l=this.ownerDocument.createElement(`canvas`);this.canvasElement=l,this.parentElement.prepend(l),this.fragmentShader=t,this.providedUniforms=n,this.mipmaps=c,this.currentFrame=a,this.minPixelRatio=o,this.maxPixelCount=s;let u=l.getContext(`webgl2`,r);if(!u)throw Error(`Paper Shaders: WebGL is not supported in this browser`);this.gl=u,this.initProgram(),this.setupPositionAttribute(),this.setupUniforms(),this.setUniformValues(this.providedUniforms),this.setupResizeObserver(),visualViewport?.addEventListener(`resize`,this.handleVisualViewportChange),this.setupIntersectionObserver(),this.setSpeed(i),this.parentElement.setAttribute(`data-paper-shader`,``),this.parentElement.paperShaderMount=this,this.ownerDocument.addEventListener(`visibilitychange`,this.handleDocumentVisibilityChange)}initProgram=()=>{let e=yn(this.gl,hn,this.fragmentShader);e&&(this.program=e)};setupPositionAttribute=()=>{let e=this.gl.getAttribLocation(this.program,`a_position`),t=this.gl.createBuffer();this.gl.bindBuffer(this.gl.ARRAY_BUFFER,t),this.gl.bufferData(this.gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),this.gl.STATIC_DRAW),this.gl.enableVertexAttribArray(e),this.gl.vertexAttribPointer(e,2,this.gl.FLOAT,!1,0,0)};setupUniforms=()=>{let e={u_time:this.gl.getUniformLocation(this.program,`u_time`),u_pixelRatio:this.gl.getUniformLocation(this.program,`u_pixelRatio`),u_resolution:this.gl.getUniformLocation(this.program,`u_resolution`)};Object.entries(this.providedUniforms).forEach(([t,n])=>{if(e[t]=this.gl.getUniformLocation(this.program,t),n instanceof HTMLImageElement){let n=`${t}AspectRatio`;e[n]=this.gl.getUniformLocation(this.program,n)}}),this.uniformLocations=e};renderScale=1;parentWidth=0;parentHeight=0;parentDevicePixelWidth=0;parentDevicePixelHeight=0;devicePixelsSupported=!1;intersectionObserver=null;isInViewport=!0;resizeObserver=null;setupResizeObserver=()=>{this.resizeObserver=new ResizeObserver(([e])=>{if(e?.borderBoxSize[0]){let t=e.devicePixelContentBoxSize?.[0];t!==void 0&&(this.devicePixelsSupported=!0,this.parentDevicePixelWidth=t.inlineSize,this.parentDevicePixelHeight=t.blockSize),this.parentWidth=e.borderBoxSize[0].inlineSize,this.parentHeight=e.borderBoxSize[0].blockSize}this.handleResize()}),this.resizeObserver.observe(this.parentElement)};setupIntersectionObserver=()=>{let e=this.ownerDocument.defaultView;e?.IntersectionObserver&&(this.intersectionObserver=new e.IntersectionObserver(([e])=>{this.isInViewport=e?.isIntersecting??!0,this.updateCurrentSpeed()}),this.intersectionObserver.observe(this.parentElement))};handleVisualViewportChange=()=>{this.resizeObserver?.disconnect(),this.setupResizeObserver()};handleResize=()=>{let e=0,t=0,n=Math.max(1,window.devicePixelRatio),r=visualViewport?.scale??1;if(this.devicePixelsSupported){let i=Math.max(1,this.minPixelRatio/n);e=this.parentDevicePixelWidth*i*r,t=this.parentDevicePixelHeight*i*r}else{let i=Math.max(n,this.minPixelRatio)*r;if(this.isSafari){let e=Sn(this.ownerDocument);i*=Math.max(1,e)}e=Math.round(this.parentWidth)*i,t=Math.round(this.parentHeight)*i}let i=Math.sqrt(this.maxPixelCount)/Math.sqrt(e*t),a=Math.min(1,i),o=Math.round(e*a),s=Math.round(t*a),c=o/Math.round(this.parentWidth);(this.canvasElement.width!==o||this.canvasElement.height!==s||this.renderScale!==c)&&(this.renderScale=c,this.canvasElement.width=o,this.canvasElement.height=s,this.resolutionChanged=!0,this.gl.viewport(0,0,this.gl.canvas.width,this.gl.canvas.height),this.render(performance.now()))};render=e=>{if(this.hasBeenDisposed)return;if(this.program===null){console.warn(`Tried to render before program or gl was initialized`);return}let t=e-this.lastRenderTime;this.lastRenderTime=e,this.currentSpeed!==0&&(this.currentFrame+=t*this.currentSpeed),this.gl.clear(this.gl.COLOR_BUFFER_BIT),this.gl.useProgram(this.program),this.gl.uniform1f(this.uniformLocations.u_time,this.currentFrame*.001),this.resolutionChanged&&=(this.gl.uniform2f(this.uniformLocations.u_resolution,this.gl.canvas.width,this.gl.canvas.height),this.gl.uniform1f(this.uniformLocations.u_pixelRatio,this.renderScale),!1),this.gl.drawArrays(this.gl.TRIANGLES,0,6),this.currentSpeed===0?this.rafId=null:this.requestRender()};requestRender=()=>{this.rafId!==null&&cancelAnimationFrame(this.rafId),this.rafId=requestAnimationFrame(this.render)};setTextureUniform=(e,t)=>{if(!t.complete||t.naturalWidth===0)throw Error(`Paper Shaders: image for uniform ${e} must be fully loaded`);let n=this.textures.get(e);n&&this.gl.deleteTexture(n),this.textureUnitMap.has(e)||this.textureUnitMap.set(e,this.textureUnitMap.size);let r=this.textureUnitMap.get(e);this.gl.activeTexture(this.gl.TEXTURE0+r);let i=this.gl.createTexture();this.gl.bindTexture(this.gl.TEXTURE_2D,i),this.gl.texParameteri(this.gl.TEXTURE_2D,this.gl.TEXTURE_WRAP_S,this.gl.CLAMP_TO_EDGE),this.gl.texParameteri(this.gl.TEXTURE_2D,this.gl.TEXTURE_WRAP_T,this.gl.CLAMP_TO_EDGE),this.gl.texParameteri(this.gl.TEXTURE_2D,this.gl.TEXTURE_MIN_FILTER,this.gl.LINEAR),this.gl.texParameteri(this.gl.TEXTURE_2D,this.gl.TEXTURE_MAG_FILTER,this.gl.LINEAR),this.gl.texImage2D(this.gl.TEXTURE_2D,0,this.gl.RGBA,this.gl.RGBA,this.gl.UNSIGNED_BYTE,t),this.mipmaps.includes(e)&&(this.gl.generateMipmap(this.gl.TEXTURE_2D),this.gl.texParameteri(this.gl.TEXTURE_2D,this.gl.TEXTURE_MIN_FILTER,this.gl.LINEAR_MIPMAP_LINEAR));let a=this.gl.getError();if(a!==this.gl.NO_ERROR||i===null){console.error(`Paper Shaders: WebGL error when uploading texture:`,a);return}this.textures.set(e,i);let o=this.uniformLocations[e];if(o){this.gl.uniform1i(o,r);let n=`${e}AspectRatio`,i=this.uniformLocations[n];if(i){let e=t.naturalWidth/t.naturalHeight;this.gl.uniform1f(i,e)}}};areUniformValuesEqual=(e,t)=>e===t?!0:Array.isArray(e)&&Array.isArray(t)&&e.length===t.length?e.every((e,n)=>this.areUniformValuesEqual(e,t[n])):!1;setUniformValues=e=>{this.gl.useProgram(this.program),Object.entries(e).forEach(([e,t])=>{let n=t;if(t instanceof HTMLImageElement&&(n=`${t.src.slice(0,200)}|${t.naturalWidth}x${t.naturalHeight}`),this.areUniformValuesEqual(this.uniformCache[e],n))return;this.uniformCache[e]=n;let r=this.uniformLocations[e];if(!r){console.warn(`Uniform location for ${e} not found`);return}if(t instanceof HTMLImageElement)this.setTextureUniform(e,t);else if(Array.isArray(t)){let n=null,i=null;if(t[0]!==void 0&&Array.isArray(t[0])){let r=t[0].length;if(t.every(e=>e.length===r))n=t.flat(),i=r;else{console.warn(`All child arrays must be the same length for ${e}`);return}}else n=t,i=n.length;switch(i){case 2:this.gl.uniform2fv(r,n);break;case 3:this.gl.uniform3fv(r,n);break;case 4:this.gl.uniform4fv(r,n);break;case 9:this.gl.uniformMatrix3fv(r,!1,n);break;case 16:this.gl.uniformMatrix4fv(r,!1,n);break;default:console.warn(`Unsupported uniform array length: ${i}`)}}else typeof t==`number`?this.gl.uniform1f(r,t):typeof t==`boolean`?this.gl.uniform1i(r,+!!t):console.warn(`Unsupported uniform type for ${e}: ${typeof t}`)})};getCurrentFrame=()=>this.currentFrame;setFrame=e=>{this.currentFrame=e,this.lastRenderTime=performance.now(),this.render(performance.now())};setSpeed=(e=1)=>{this.speed=e,this.updateCurrentSpeed()};updateCurrentSpeed=()=>{this.setCurrentSpeed(this.ownerDocument.hidden||!this.isInViewport?0:this.speed)};setCurrentSpeed=e=>{this.currentSpeed=e,this.rafId===null&&e!==0&&(this.lastRenderTime=performance.now(),this.rafId=requestAnimationFrame(this.render)),this.rafId!==null&&e===0&&(cancelAnimationFrame(this.rafId),this.rafId=null)};setMaxPixelCount=(e=gn)=>{this.maxPixelCount=e,this.handleResize()};setMinPixelRatio=(e=2)=>{this.minPixelRatio=e,this.handleResize()};setUniforms=e=>{this.setUniformValues(e),this.providedUniforms={...this.providedUniforms,...e},this.render(performance.now())};handleDocumentVisibilityChange=()=>{this.updateCurrentSpeed()};dispose=()=>{this.hasBeenDisposed=!0,this.rafId!==null&&(cancelAnimationFrame(this.rafId),this.rafId=null),this.gl&&this.program&&(this.textures.forEach(e=>{this.gl.deleteTexture(e)}),this.textures.clear(),this.gl.deleteProgram(this.program),this.program=null,this.gl.bindBuffer(this.gl.ARRAY_BUFFER,null),this.gl.bindBuffer(this.gl.ELEMENT_ARRAY_BUFFER,null),this.gl.bindRenderbuffer(this.gl.RENDERBUFFER,null),this.gl.bindFramebuffer(this.gl.FRAMEBUFFER,null),this.gl.getError()),this.resizeObserver&&=(this.resizeObserver.disconnect(),null),this.intersectionObserver&&=(this.intersectionObserver.disconnect(),null),visualViewport?.removeEventListener(`resize`,this.handleVisualViewportChange),this.ownerDocument.removeEventListener(`visibilitychange`,this.handleDocumentVisibilityChange),this.uniformLocations={},this.canvasElement.remove(),delete this.parentElement.paperShaderMount}};function vn(e,t,n){let r=e.createShader(t);return r?(e.shaderSource(r,n),e.compileShader(r),e.getShaderParameter(r,e.COMPILE_STATUS)?r:(console.error(`An error occurred compiling the shaders: `+e.getShaderInfoLog(r)),e.deleteShader(r),null)):null}function yn(e,t,n){let r=e.getShaderPrecisionFormat(e.FRAGMENT_SHADER,e.MEDIUM_FLOAT),i=r?r.precision:null;i&&i<23&&(t=t.replace(/precision\s+(lowp|mediump)\s+float;/g,`precision highp float;`),n=n.replace(/precision\s+(lowp|mediump)\s+float/g,`precision highp float`).replace(/\b(uniform|varying|attribute)\s+(lowp|mediump)\s+(\w+)/g,`$1 highp $3`));let a=vn(e,e.VERTEX_SHADER,t),o=vn(e,e.FRAGMENT_SHADER,n);if(!a||!o)return null;let s=e.createProgram();return s?(e.attachShader(s,a),e.attachShader(s,o),e.linkProgram(s),e.getProgramParameter(s,e.LINK_STATUS)?(e.detachShader(s,a),e.detachShader(s,o),e.deleteShader(a),e.deleteShader(o),s):(console.error(`Unable to initialize the shader program: `+e.getProgramInfoLog(s)),e.deleteProgram(s),e.deleteShader(a),e.deleteShader(o),null)):null}var bn=`@layer paper-shaders {
  :where([data-paper-shader]) {
    isolation: isolate;
    position: relative;

    & canvas {
      contain: strict;
      display: block;
      position: absolute;
      inset: 0;
      z-index: -1;
      width: 100%;
      height: 100%;
      border-radius: inherit;
      corner-shape: inherit;
    }
  }
}`;function xn(){let e=navigator.userAgent.toLowerCase();return e.includes(`safari`)&&!e.includes(`chrome`)&&!e.includes(`android`)}function Sn(e){let t=visualViewport?.scale??1,n=visualViewport?.width??window.innerWidth,r=window.innerWidth-e.documentElement.clientWidth,i=t*n+r,a=outerWidth/i,o=Math.round(100*a);return o%5==0?o/100:o===33?1/3:o===67?2/3:o===133?4/3:a}var L={fit:`contain`,scale:1,rotation:0,offsetX:0,offsetY:0,originX:.5,originY:.5,worldWidth:0,worldHeight:0},Cn={fit:`none`,scale:1,rotation:0,offsetX:0,offsetY:0,originX:.5,originY:.5,worldWidth:0,worldHeight:0},wn={none:0,contain:1,cover:2},Tn=`
#define TWO_PI 6.28318530718
#define PI 3.14159265358979323846
`,En=`
vec2 rotate(vec2 uv, float th) {
  return mat2(cos(th), sin(th), -sin(th), cos(th)) * uv;
}
`,Dn=`
  float hash11(float p) {
    p = fract(p * 0.3183099) + 0.1;
    p *= p + 19.19;
    return fract(p * p);
  }
`,On=`
  float hash21(vec2 p) {
    p = fract(p * vec2(0.3183099, 0.3678794)) + 0.1;
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
  }
`,kn=`
  float randomR(vec2 p) {
    vec2 uv = floor(p) / 100. + .5;
    return texture(u_noiseTexture, fract(uv)).r;
  }
`,An=`
  vec2 randomGB(vec2 p) {
    vec2 uv = floor(p) / 100. + .5;
    return texture(u_noiseTexture, fract(uv)).gb;
  }
`,jn=`
  color += 1. / 256. * (fract(sin(dot(.014 * gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453123) - .5);
`,Mn=`
vec3 permute(vec3 x) { return mod(((x * 34.0) + 1.0) * x, 289.0); }
float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
    -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1;
  i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
    + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy),
      dot(x12.zw, x12.zw)), 0.0);
  m = m * m;
  m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}
`,Nn=`
float fiberRandom(vec2 p) {
  vec2 uv = floor(p) / 100.;
  return texture(u_noiseTexture, fract(uv)).b;
}

float fiberValueNoise(vec2 st) {
  vec2 i = floor(st);
  vec2 f = fract(st);
  float a = fiberRandom(i);
  float b = fiberRandom(i + vec2(1.0, 0.0));
  float c = fiberRandom(i + vec2(0.0, 1.0));
  float d = fiberRandom(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  float x1 = mix(a, b, u.x);
  float x2 = mix(c, d, u.x);
  return mix(x1, x2, u.y);
}

float fiberNoiseFbm(in vec2 n, vec2 seedOffset) {
  float total = 0.0, amplitude = 1.;
  for (int i = 0; i < 4; i++) {
    n = rotate(n, .7);
    total += fiberValueNoise(n + seedOffset) * amplitude;
    n *= 2.;
    amplitude *= 0.6;
  }
  return total;
}

float fiberNoise(vec2 uv, vec2 seedOffset) {
  float epsilon = 0.001;
  float n1 = fiberNoiseFbm(uv + vec2(epsilon, 0.0), seedOffset);
  float n2 = fiberNoiseFbm(uv - vec2(epsilon, 0.0), seedOffset);
  float n3 = fiberNoiseFbm(uv + vec2(0.0, epsilon), seedOffset);
  float n4 = fiberNoiseFbm(uv - vec2(0.0, epsilon), seedOffset);
  return length(vec2(n1 - n2, n3 - n4)) / (2.0 * epsilon);
}
`,Pn={maxColorCount:10},Fn=`#version 300 es
precision mediump float;

uniform float u_time;

uniform vec4 u_colors[${Pn.maxColorCount}];
uniform float u_colorsCount;

uniform float u_distortion;
uniform float u_swirl;
uniform float u_grainMixer;
uniform float u_grainOverlay;

in vec2 v_objectUV;
out vec4 fragColor;

${Tn}
${En}
${On}

float valueNoise(vec2 st) {
  vec2 i = floor(st);
  vec2 f = fract(st);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  float x1 = mix(a, b, u.x);
  float x2 = mix(c, d, u.x);
  return mix(x1, x2, u.y);
}

float noise(vec2 n, vec2 seedOffset) {
  return valueNoise(n + seedOffset);
}

vec2 getPosition(int i, float t) {
  float a = float(i) * .37;
  float b = .6 + fract(float(i) / 3.) * .9;
  float c = .8 + fract(float(i + 1) / 4.);

  float x = sin(t * b + a);
  float y = cos(t * c + a * 1.5);

  return .5 + .5 * vec2(x, y);
}

void main() {
  vec2 uv = v_objectUV;
  uv += .5;
  vec2 grainUV = uv * 1000.;

  float grain = noise(grainUV, vec2(0.));
  float mixerGrain = .4 * u_grainMixer * (grain - .5);

  const float firstFrameOffset = 41.5;
  float t = .5 * (u_time + firstFrameOffset);

  float radius = smoothstep(0., 1., length(uv - .5));
  float center = 1. - radius;
  for (float i = 1.; i <= 2.; i++) {
    uv.x += u_distortion * center / i * sin(t + i * .4 * smoothstep(.0, 1., uv.y)) * cos(.2 * t + i * 2.4 * smoothstep(.0, 1., uv.y));
    uv.y += u_distortion * center / i * cos(t + i * 2. * smoothstep(.0, 1., uv.x));
  }

  vec2 uvRotated = uv;
  uvRotated -= vec2(.5);
  float angle = 3. * u_swirl * radius;
  uvRotated = rotate(uvRotated, -angle);
  uvRotated += vec2(.5);

  vec3 color = vec3(0.);
  float opacity = 0.;
  float totalWeight = 0.;

  for (int i = 0; i < ${Pn.maxColorCount}; i++) {
    if (i >= int(u_colorsCount)) break;

    vec2 pos = getPosition(i, t) + mixerGrain;
    vec3 colorFraction = u_colors[i].rgb * u_colors[i].a;
    float opacityFraction = u_colors[i].a;

    float dist = length(uvRotated - pos);

    dist = pow(dist, 3.5);
    float weight = 1. / (dist + 1e-3);
    color += colorFraction * weight;
    opacity += opacityFraction * weight;
    totalWeight += weight;
  }

  color /= max(1e-4, totalWeight);
  opacity /= max(1e-4, totalWeight);

  float grainOverlay = valueNoise(rotate(grainUV, 1.) + vec2(3.));
  grainOverlay = mix(grainOverlay, valueNoise(rotate(grainUV, 2.) + vec2(-1.)), .5);
  grainOverlay = pow(grainOverlay, 1.3);

  float grainOverlayV = grainOverlay * 2. - 1.;
  vec3 grainOverlayColor = vec3(step(0., grainOverlayV));
  float grainOverlayStrength = u_grainOverlay * abs(grainOverlayV);
  grainOverlayStrength = pow(grainOverlayStrength, .8);
  color = mix(color, grainOverlayColor, .35 * grainOverlayStrength);

  opacity += .5 * grainOverlayStrength;
  opacity = clamp(opacity, 0., 1.);

  fragColor = vec4(color, opacity);
}
`,In=`#version 300 es
precision mediump float;

uniform float u_time;

uniform vec2 u_resolution;
uniform float u_pixelRatio;
uniform float u_originX;
uniform float u_originY;
uniform float u_worldWidth;
uniform float u_worldHeight;
uniform float u_fit;
uniform float u_scale;
uniform float u_rotation;
uniform float u_offsetX;
uniform float u_offsetY;

uniform float u_pxSize;
uniform vec4 u_colorBack;
uniform vec4 u_colorFront;
uniform float u_shape;
uniform float u_type;

out vec4 fragColor;

${Mn}
${Tn}
${Dn}
${On}

float getSimplexNoise(vec2 uv, float t) {
  float noise = .5 * snoise(uv - vec2(0., .3 * t));
  noise += .5 * snoise(2. * uv + vec2(0., .32 * t));

  return noise;
}

const int bayer2x2[4] = int[4](0, 2, 3, 1);
const int bayer4x4[16] = int[16](
0, 8, 2, 10,
12, 4, 14, 6,
3, 11, 1, 9,
15, 7, 13, 5
);

const int bayer8x8[64] = int[64](
0, 32, 8, 40, 2, 34, 10, 42,
48, 16, 56, 24, 50, 18, 58, 26,
12, 44, 4, 36, 14, 46, 6, 38,
60, 28, 52, 20, 62, 30, 54, 22,
3, 35, 11, 43, 1, 33, 9, 41,
51, 19, 59, 27, 49, 17, 57, 25,
15, 47, 7, 39, 13, 45, 5, 37,
63, 31, 55, 23, 61, 29, 53, 21
);

float getBayerValue(vec2 uv, int size) {
  ivec2 pos = ivec2(fract(uv / float(size)) * float(size));
  int index = pos.y * size + pos.x;

  if (size == 2) {
    return float(bayer2x2[index]) / 4.0;
  } else if (size == 4) {
    return float(bayer4x4[index]) / 16.0;
  } else if (size == 8) {
    return float(bayer8x8[index]) / 64.0;
  }
  return 0.0;
}


void main() {
  float t = .5 * u_time;

  float pxSize = u_pxSize * u_pixelRatio;
  vec2 pxSizeUV = gl_FragCoord.xy - .5 * u_resolution;
  pxSizeUV /= pxSize;
  vec2 canvasPixelizedUV = (floor(pxSizeUV) + .5) * pxSize;
  vec2 normalizedUV = canvasPixelizedUV / u_resolution;

  vec2 ditheringNoiseUV = canvasPixelizedUV;
  vec2 shapeUV = normalizedUV;

  vec2 boxOrigin = vec2(.5 - u_originX, u_originY - .5);
  vec2 givenBoxSize = vec2(u_worldWidth, u_worldHeight);
  givenBoxSize = max(givenBoxSize, vec2(1.)) * u_pixelRatio;
  float r = u_rotation * PI / 180.;
  mat2 graphicRotation = mat2(cos(r), sin(r), -sin(r), cos(r));
  vec2 graphicOffset = vec2(-u_offsetX, u_offsetY);

  float patternBoxRatio = givenBoxSize.x / givenBoxSize.y;
  vec2 boxSize = vec2(
  (u_worldWidth == 0.) ? u_resolution.x : givenBoxSize.x,
  (u_worldHeight == 0.) ? u_resolution.y : givenBoxSize.y
  );
  
  if (u_shape > 3.5) {
    vec2 objectBoxSize = vec2(0.);
    // fit = none
    objectBoxSize.x = min(boxSize.x, boxSize.y);
    if (u_fit == 1.) { // fit = contain
      objectBoxSize.x = min(u_resolution.x, u_resolution.y);
    } else if (u_fit == 2.) { // fit = cover
      objectBoxSize.x = max(u_resolution.x, u_resolution.y);
    }
    objectBoxSize.y = objectBoxSize.x;
    vec2 objectWorldScale = u_resolution.xy / objectBoxSize;

    shapeUV *= objectWorldScale;
    shapeUV += boxOrigin * (objectWorldScale - 1.);
    shapeUV += vec2(-u_offsetX, u_offsetY);
    shapeUV /= u_scale;
    shapeUV = graphicRotation * shapeUV;
  } else {
    vec2 patternBoxSize = vec2(0.);
    // fit = none
    patternBoxSize.x = patternBoxRatio * min(boxSize.x / patternBoxRatio, boxSize.y);
    float patternWorldNoFitBoxWidth = patternBoxSize.x;
    if (u_fit == 1.) { // fit = contain
      patternBoxSize.x = patternBoxRatio * min(u_resolution.x / patternBoxRatio, u_resolution.y);
    } else if (u_fit == 2.) { // fit = cover
      patternBoxSize.x = patternBoxRatio * max(u_resolution.x / patternBoxRatio, u_resolution.y);
    }
    patternBoxSize.y = patternBoxSize.x / patternBoxRatio;
    vec2 patternWorldScale = u_resolution.xy / patternBoxSize;

    shapeUV += vec2(-u_offsetX, u_offsetY) / patternWorldScale;
    shapeUV += boxOrigin;
    shapeUV -= boxOrigin / patternWorldScale;
    shapeUV *= u_resolution.xy;
    shapeUV /= u_pixelRatio;
    if (u_fit > 0.) {
      shapeUV *= (patternWorldNoFitBoxWidth / patternBoxSize.x);
    }
    shapeUV /= u_scale;
    shapeUV = graphicRotation * shapeUV;
    shapeUV += boxOrigin / patternWorldScale;
    shapeUV -= boxOrigin;
    shapeUV += .5;
  }

  float shape = 0.;
  if (u_shape < 1.5) {
    // Simplex noise
    shapeUV *= .001;

    shape = 0.5 + 0.5 * getSimplexNoise(shapeUV, t);
    shape = smoothstep(0.3, 0.9, shape);

  } else if (u_shape < 2.5) {
    // Warp
    shapeUV *= .003;

    for (float i = 1.0; i < 6.0; i++) {
      shapeUV.x += 0.6 / i * cos(i * 2.5 * shapeUV.y + t);
      shapeUV.y += 0.6 / i * cos(i * 1.5 * shapeUV.x + t);
    }

    shape = .15 / max(0.001, abs(sin(t - shapeUV.y - shapeUV.x)));
    shape = smoothstep(0.02, 1., shape);

  } else if (u_shape < 3.5) {
    // Dots
    shapeUV *= .05;

    float stripeIdx = floor(2. * shapeUV.x / TWO_PI);
    float rand = hash11(stripeIdx * 10.);
    rand = sign(rand - .5) * pow(.1 + abs(rand), .4);
    shape = sin(shapeUV.x) * cos(shapeUV.y - 5. * rand * t);
    shape = pow(abs(shape), 6.);

  } else if (u_shape < 4.5) {
    // Sine wave
    shapeUV *= 4.;

    float wave = cos(.5 * shapeUV.x - 2. * t) * sin(1.5 * shapeUV.x + t) * (.75 + .25 * cos(3. * t));
    shape = 1. - smoothstep(-1., 1., shapeUV.y + wave);

  } else if (u_shape < 5.5) {
    // Ripple

    float dist = length(shapeUV);
    float waves = sin(pow(dist, 1.7) * 7. - 3. * t) * .5 + .5;
    shape = waves;

  } else if (u_shape < 6.5) {
    // Swirl

    float l = length(shapeUV);
    float angle = 6. * atan(shapeUV.y, shapeUV.x) + 4. * t;
    float twist = 1.2;
    float offset = 1. / pow(max(l, 1e-6), twist) + angle / TWO_PI;
    float mid = smoothstep(0., 1., pow(l, twist));
    shape = mix(0., fract(offset), mid);

  } else {
    // Sphere
    shapeUV *= 2.;

    float d = 1. - pow(length(shapeUV), 2.);
    vec3 pos = vec3(shapeUV, sqrt(max(0., d)));
    vec3 lightPos = normalize(vec3(cos(1.5 * t), .8, sin(1.25 * t)));
    shape = .5 + .5 * dot(lightPos, pos);
    shape *= step(0., d);
  }


  int type = int(floor(u_type));
  float dithering = 0.0;

  switch (type) {
    case 1: {
      dithering = step(hash21(ditheringNoiseUV), shape);
    } break;
    case 2:
    dithering = getBayerValue(pxSizeUV, 2);
    break;
    case 3:
    dithering = getBayerValue(pxSizeUV, 4);
    break;
    default :
    dithering = getBayerValue(pxSizeUV, 8);
    break;
  }

  dithering -= .5;
  float res = step(.5, shape + dithering);

  vec3 fgColor = u_colorFront.rgb * u_colorFront.a;
  float fgOpacity = u_colorFront.a;
  vec3 bgColor = u_colorBack.rgb * u_colorBack.a;
  float bgOpacity = u_colorBack.a;

  vec3 color = fgColor * res;
  float opacity = fgOpacity * res;

  color += bgColor * (1. - opacity);
  opacity += bgOpacity * (1. - opacity);

  fragColor = vec4(color, opacity);
}
`,Ln={simplex:1,warp:2,dots:3,wave:4,ripple:5,swirl:6,sphere:7},Rn={random:1,"2x2":2,"4x4":3,"8x8":4},zn=`#version 300 es
precision mediump float;

uniform vec2 u_resolution;
uniform float u_pixelRatio;

uniform vec4 u_colorFront;
uniform vec4 u_colorBack;

uniform sampler2D u_image;
uniform float u_imageAspectRatio;

uniform float u_contrast;
uniform float u_roughness;
uniform float u_fiber;
uniform float u_fiberSize;
uniform float u_crumples;
uniform float u_crumpleSize;
uniform float u_folds;
uniform float u_foldCount;
uniform float u_drops;
uniform float u_seed;
uniform float u_fade;

uniform sampler2D u_noiseTexture;

in vec2 v_imageUV;

out vec4 fragColor;

float getUvFrame(vec2 uv) {
  float aax = 2. * fwidth(uv.x);
  float aay = 2. * fwidth(uv.y);

  float left   = smoothstep(0., aax, uv.x);
  float right = 1. - smoothstep(1. - aax, 1., uv.x);
  float bottom = smoothstep(0., aay, uv.y);
  float top = 1. - smoothstep(1. - aay, 1., uv.y);

  return left * right * bottom * top;
}

${Tn}
${En}
${kn}
float valueNoise(vec2 st) {
  vec2 i = floor(st);
  vec2 f = fract(st);
  float a = randomR(i);
  float b = randomR(i + vec2(1.0, 0.0));
  float c = randomR(i + vec2(0.0, 1.0));
  float d = randomR(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  float x1 = mix(a, b, u.x);
  float x2 = mix(c, d, u.x);
  return mix(x1, x2, u.y);
}
float fbm(vec2 n) {
  float total = 0.0, amplitude = .4;
  for (int i = 0; i < 3; i++) {
    total += valueNoise(n) * amplitude;
    n *= 1.99;
    amplitude *= 0.65;
  }
  return total;
}


float randomG(vec2 p) {
  vec2 uv = floor(p) / 50. + .5;
  return texture(u_noiseTexture, fract(uv)).g;
}
float roughness(vec2 p) {
  p *= .1;
  float o = 0.;
  for (float i = 0.; ++i < 4.; p *= 2.1) {
    vec4 w = vec4(floor(p), ceil(p));
    vec2 f = fract(p);
    o += mix(
    mix(randomG(w.xy), randomG(w.xw), f.y),
    mix(randomG(w.zy), randomG(w.zw), f.y),
    f.x);
    o += .2 / exp(2. * abs(sin(.2 * p.x + .5 * p.y)));
  }
  return o / 3.;
}

${Nn}

vec2 randomGB(vec2 p) {
  vec2 uv = floor(p) / 50. + .5;
  return texture(u_noiseTexture, fract(uv)).gb;
}
float crumpledNoise(vec2 t, float pw) {
  vec2 p = floor(t);
  float wsum = 0.;
  float cl = 0.;
  for (int y = -1; y < 2; y += 1) {
    for (int x = -1; x < 2; x += 1) {
      vec2 b = vec2(float(x), float(y));
      vec2 q = b + p;
      vec2 q2 = q - floor(q / 8.) * 8.;
      vec2 c = q + randomGB(q2);
      vec2 r = c - t;
      float w = pow(smoothstep(0., 1., 1. - abs(r.x)), pw) * pow(smoothstep(0., 1., 1. - abs(r.y)), pw);
      cl += (.5 + .5 * sin((q2.x + q2.y * 5.) * 8.)) * w;
      wsum += w;
    }
  }
  return pow(wsum != 0.0 ? cl / wsum : 0.0, .5) * 2.;
}
float crumplesShape(vec2 uv) {
  return crumpledNoise(uv * .25, 16.) * crumpledNoise(uv * .5, 2.);
}


vec2 folds(vec2 uv) {
  vec3 pp = vec3(0.);
  float l = 9.;
  for (float i = 0.; i < 15.; i++) {
    if (i >= u_foldCount) break;
    vec2 rand = randomGB(vec2(i, i * u_seed));
    float an = rand.x * TWO_PI;
    vec2 p = vec2(cos(an), sin(an)) * rand.y;
    float dist = distance(uv, p);
    l = min(l, dist);

    if (l == dist) {
      pp.xy = (uv - p.xy);
      pp.z = dist;
    }
  }
  return mix(pp.xy, vec2(0.), pow(pp.z, .25));
}

float drops(vec2 uv) {
  vec2 iDropsUV = floor(uv);
  vec2 fDropsUV = fract(uv);
  float dropsMinDist = 1.;
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 neighbor = vec2(float(i), float(j));
      vec2 offset = randomGB(iDropsUV + neighbor);
      offset = .5 + .5 * sin(10. * u_seed + TWO_PI * offset);
      vec2 pos = neighbor + offset - fDropsUV;
      float dist = length(pos);
      dropsMinDist = min(dropsMinDist, dropsMinDist*dist);
    }
  }
  return 1. - smoothstep(.05, .09, pow(dropsMinDist, .5));
}

float lst(float edge0, float edge1, float x) {
  return clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
}

void main() {

  vec2 imageUV = v_imageUV;
  vec2 patternUV = v_imageUV - .5;
  patternUV = 5. * (patternUV * vec2(u_imageAspectRatio, 1.));

  vec2 roughnessUv = 1.5 * (gl_FragCoord.xy - .5 * u_resolution) / u_pixelRatio;
  float roughness = roughness(roughnessUv + vec2(1., 0.)) - roughness(roughnessUv - vec2(1., 0.));

  vec2 crumplesUV = fract(patternUV * .02 / u_crumpleSize - u_seed) * 32.;
  float crumples = u_crumples * (crumplesShape(crumplesUV + vec2(.05, 0.)) - crumplesShape(crumplesUV));

  vec2 fiberUV = 2. / u_fiberSize * patternUV;
  float fiber = fiberNoise(fiberUV, vec2(0.));
  fiber = .5 * u_fiber * (fiber - 1.);

  vec2 normal = vec2(0.);
  vec2 normalImage = vec2(0.);

  vec2 foldsUV = patternUV * .12;
  foldsUV = rotate(foldsUV, 4. * u_seed);
  vec2 w = folds(foldsUV);
  foldsUV = rotate(foldsUV + .007 * cos(u_seed), .01 * sin(u_seed));
  vec2 w2 = folds(foldsUV);

  float drops = u_drops * drops(patternUV * 2.);

  float fade = u_fade * fbm(.17 * patternUV + 10. * u_seed);
  fade = clamp(8. * fade * fade * fade, 0., 1.);

  w = mix(w, vec2(0.), fade);
  w2 = mix(w2, vec2(0.), fade);
  crumples = mix(crumples, 0., fade);
  drops = mix(drops, 0., fade);
  fiber *= mix(1., .5, fade);
  roughness *= mix(1., .5, fade);

  normal.xy += u_folds * min(5. * u_contrast, 1.) * 4. * max(vec2(0.), w + w2);
  normalImage.xy += u_folds * 2. * w;

  normal.xy += crumples;
  normalImage.xy += 1.5 * crumples;

  normal.xy += 3. * drops;
  normalImage.xy += .2 * drops;

  normal.xy += u_roughness * 1.5 * roughness;
  normal.xy += fiber;

  normalImage += u_roughness * .75 * roughness;
  normalImage += .2 * fiber;

  vec3 lightPos = vec3(1., 2., 1.);
  float res = dot(normalize(vec3(normal, 9.5 - 9. * pow(u_contrast, .1))), normalize(lightPos));

  vec3 fgColor = u_colorFront.rgb * u_colorFront.a;
  float fgOpacity = u_colorFront.a;
  vec3 bgColor = u_colorBack.rgb * u_colorBack.a;
  float bgOpacity = u_colorBack.a;

  imageUV += .02 * normalImage;
  float frame = getUvFrame(imageUV);
  vec4 image = texture(u_image, imageUV);
  image.rgb += .6 * pow(u_contrast, .4) * (res - .7);

  frame *= image.a;

  vec3 color = fgColor * res;
  float opacity = fgOpacity * res;

  color += bgColor * (1. - opacity);
  opacity += bgOpacity * (1. - opacity);
  opacity = mix(opacity, 1., frame);

  color -= .007 * drops;

  color.rgb = mix(color, image.rgb, frame);

  fragColor = vec4(color, opacity);
}
`,Bn=`#version 300 es
precision mediump float;

uniform vec2 u_resolution;
uniform float u_pixelRatio;
uniform float u_rotation;

uniform vec4 u_colorBack;
uniform vec4 u_colorShadow;
uniform vec4 u_colorHighlight;

uniform sampler2D u_image;
uniform float u_imageAspectRatio;

uniform float u_size;
uniform float u_shadows;
uniform float u_angle;
uniform float u_stretch;
uniform float u_shape;
uniform float u_distortion;
uniform float u_highlights;
uniform float u_distortionShape;
uniform float u_shift;
uniform float u_blur;
uniform float u_edges;
uniform float u_marginLeft;
uniform float u_marginRight;
uniform float u_marginTop;
uniform float u_marginBottom;
uniform float u_grainMixer;
uniform float u_grainOverlay;

in vec2 v_imageUV;

out vec4 fragColor;

${Tn}
${En}
${On}

float valueNoise(vec2 st) {
  vec2 i = floor(st);
  vec2 f = fract(st);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  float x1 = mix(a, b, u.x);
  float x2 = mix(c, d, u.x);
  return mix(x1, x2, u.y);
}

float getUvFrame(vec2 uv, float softness) {
  float aax = 2. * fwidth(uv.x);
  float aay = 2. * fwidth(uv.y);
  float left   = smoothstep(0., aax + softness, uv.x);
  float right  = 1. - smoothstep(1. - softness - aax, 1., uv.x);
  float bottom = smoothstep(0., aay + softness, uv.y);
  float top    = 1. - smoothstep(1. - softness - aay, 1., uv.y);
  return left * right * bottom * top;
}

const int MAX_RADIUS = 50;
vec4 samplePremultiplied(sampler2D tex, vec2 uv) {
  vec4 c = texture(tex, uv);
  c.rgb *= c.a;
  return c;
}
vec4 getBlur(sampler2D tex, vec2 uv, vec2 texelSize, vec2 dir, float sigma) {
  if (sigma <= .5) return texture(tex, uv);
  int radius = int(min(float(MAX_RADIUS), ceil(3.0 * sigma)));

  float twoSigma2 = 2.0 * sigma * sigma;
  float gaussianNorm = 1.0 / sqrt(TWO_PI * sigma * sigma);

  vec4 sum = samplePremultiplied(tex, uv) * gaussianNorm;
  float weightSum = gaussianNorm;

  for (int i = 1; i <= MAX_RADIUS; i++) {
    if (i > radius) break;

    float x = float(i);
    float w = exp(-(x * x) / twoSigma2) * gaussianNorm;

    vec2 offset = dir * texelSize * x;
    vec4 s1 = samplePremultiplied(tex, uv + offset);
    vec4 s2 = samplePremultiplied(tex, uv - offset);

    sum += (s1 + s2) * w;
    weightSum += 2.0 * w;
  }

  vec4 result = sum / weightSum;
  if (result.a > 0.) {
    result.rgb /= result.a;
  }

  return result;
}

vec2 rotateAspect(vec2 p, float a, float aspect) {
  p.x *= aspect;
  p = rotate(p, a);
  p.x /= aspect;
  return p;
}

float smoothFract(float x) {
  float f = fract(x);
  float w = fwidth(x);

  float edge = abs(f - 0.5) - 0.5;
  float band = smoothstep(-w, w, edge);

  return mix(f, 1.0 - f, band);
}

void main() {

  float patternRotation = -u_angle * PI / 180.;
  float patternSize = mix(200., 5., u_size);

  vec2 uv = v_imageUV;

  vec2 uvMask = gl_FragCoord.xy / u_resolution.xy;
  vec2 sw = vec2(.005);
  vec4 margins = vec4(u_marginLeft, u_marginTop, u_marginRight, u_marginBottom);
  float mask =
  smoothstep(margins[0], margins[0] + sw.x, uvMask.x + sw.x) *
  smoothstep(margins[2], margins[2] + sw.x, 1.0 - uvMask.x + sw.x) *
  smoothstep(margins[1], margins[1] + sw.y, uvMask.y + sw.y) *
  smoothstep(margins[3], margins[3] + sw.y, 1.0 - uvMask.y + sw.y);
  float maskOuter =
  smoothstep(margins[0] - sw.x, margins[0], uvMask.x + sw.x) *
  smoothstep(margins[2] - sw.x, margins[2], 1.0 - uvMask.x + sw.x) *
  smoothstep(margins[1] - sw.y, margins[1], uvMask.y + sw.y) *
  smoothstep(margins[3] - sw.y, margins[3], 1.0 - uvMask.y + sw.y);
  float maskStroke = maskOuter - mask;
  float maskInner =
  smoothstep(margins[0] - 2. * sw.x, margins[0], uvMask.x) *
  smoothstep(margins[2] - 2. * sw.x, margins[2], 1.0 - uvMask.x) *
  smoothstep(margins[1] - 2. * sw.y, margins[1], uvMask.y) *
  smoothstep(margins[3] - 2. * sw.y, margins[3], 1.0 - uvMask.y);
  float maskStrokeInner = maskInner - mask;

  uv -= .5;
  uv *= patternSize;
  uv = rotateAspect(uv, patternRotation, u_imageAspectRatio);

  float curve = 0.;
  float patternY = uv.y / u_imageAspectRatio;
  if (u_shape > 4.5) {
    // pattern
    curve = .5 + .5 * sin(.5 * PI * uv.x) * cos(.5 * PI * patternY);
  } else if (u_shape > 3.5) {
    // zigzag
    curve = 10. * abs(fract(.1 * patternY) - .5);
  } else if (u_shape > 2.5) {
    // wave
    curve = 4. * sin(.23 * patternY);
  } else if (u_shape > 1.5) {
    // lines irregular
    curve = .5 + .5 * sin(.5 * uv.x) * sin(1.7 * uv.x);
  } else {
    // lines
  }

  vec2 UvToFract = uv + curve;
  vec2 fractOrigUV = fract(uv);
  vec2 floorOrigUV = floor(uv);

  float x = smoothFract(UvToFract.x);
  float xNonSmooth = fract(UvToFract.x) + .0001;

  float highlightsWidth = 2. * max(.001, fwidth(UvToFract.x));
  highlightsWidth += 2. * maskStrokeInner;
  float highlights = smoothstep(0., highlightsWidth, xNonSmooth);
  highlights *= smoothstep(1., 1. - highlightsWidth, xNonSmooth);
  highlights = 1. - highlights;
  highlights *= u_highlights;
  highlights = clamp(highlights, 0., 1.);
  highlights *= mask;

  float shadows = pow(x, 1.3);
  float distortion = 0.;
  float fadeX = 1.;
  float frameFade = 0.;

  float aa = fwidth(xNonSmooth);
  aa = max(aa, fwidth(uv.x));
  aa = max(aa, fwidth(UvToFract.x));
  aa = max(aa, .0001);

  if (u_distortionShape == 1.) {
    distortion = -pow(1.5 * x, 3.);
    distortion += (.5 - u_shift);

    frameFade = pow(1.5 * x, 3.);
    aa = max(.2, aa);
    aa += mix(.2, 0., u_size);
    fadeX = smoothstep(0., aa, xNonSmooth) * smoothstep(1., 1. - aa, xNonSmooth);
    distortion = mix(.5, distortion, fadeX);
  } else if (u_distortionShape == 2.) {
    distortion = 2. * pow(x, 2.);
    distortion -= (.5 + u_shift);

    frameFade = pow(abs(x - .5), 4.);
    aa = max(.2, aa);
    aa += mix(.2, 0., u_size);
    fadeX = smoothstep(0., aa, xNonSmooth) * smoothstep(1., 1. - aa, xNonSmooth);
    distortion = mix(.5, distortion, fadeX);
    frameFade = mix(1., frameFade, .5 * fadeX);
  } else if (u_distortionShape == 3.) {
    distortion = pow(2. * (xNonSmooth - .5), 6.);
    distortion -= .25;
    distortion -= u_shift;

    frameFade = 1. - 2. * pow(abs(x - .4), 2.);
    aa = .15;
    aa += mix(.1, 0., u_size);
    fadeX = smoothstep(0., aa, xNonSmooth) * smoothstep(1., 1. - aa, xNonSmooth);
    frameFade = mix(1., frameFade, fadeX);

  } else if (u_distortionShape == 4.) {
    x = xNonSmooth;
    distortion = sin((x + .25) * TWO_PI);
    shadows = .5 + .5 * asin(distortion) / (.5 * PI);
    distortion *= .5;
    distortion -= u_shift;
    frameFade = .5 + .5 * sin(x * TWO_PI);
  } else if (u_distortionShape == 5.) {
    distortion -= pow(abs(x), .2) * x;
    distortion += .33;
    distortion -= 3. * u_shift;
    distortion *= .33;

    frameFade = .3 * (smoothstep(.0, 1., x));
    shadows = pow(x, 2.5);

    aa = max(.1, aa);
    aa += mix(.1, 0., u_size);
    fadeX = smoothstep(0., aa, xNonSmooth) * smoothstep(1., 1. - aa, xNonSmooth);
    distortion *= fadeX;
  }

  vec2 dudx = dFdx(v_imageUV);
  vec2 dudy = dFdy(v_imageUV);
  vec2 grainUV = v_imageUV - .5;
  grainUV *= (.8 / vec2(length(dudx), length(dudy)));
  grainUV += .5;
  float grain = valueNoise(grainUV);
  grain = smoothstep(.4, .7, grain);
  grain *= u_grainMixer;
  distortion = mix(distortion, 0., grain);

  shadows = min(shadows, 1.);
  shadows += maskStrokeInner;
  shadows *= mask;
  shadows = min(shadows, 1.);
  shadows *= pow(u_shadows, 2.);
  shadows = clamp(shadows, 0., 1.);

  distortion *= 3. * u_distortion;
  frameFade *= u_distortion;

  fractOrigUV.x += distortion;
  floorOrigUV = rotateAspect(floorOrigUV, -patternRotation, u_imageAspectRatio);
  fractOrigUV = rotateAspect(fractOrigUV, -patternRotation, u_imageAspectRatio);

  uv = (floorOrigUV + fractOrigUV) / patternSize;
  uv += pow(maskStroke, 4.);

  uv += vec2(.5);

  uv = mix(v_imageUV, uv, smoothstep(0., .7, mask));
  float blur = mix(0., 50., u_blur);
  blur = mix(0., blur, smoothstep(.5, 1., mask));

  float edgeDistortion = mix(.0, .04, u_edges);
  edgeDistortion += .06 * frameFade * u_edges;
  edgeDistortion *= mask;
  float frame = getUvFrame(uv, edgeDistortion);

  float stretch = 1. - smoothstep(0., .5, xNonSmooth) * smoothstep(1., 1. - .5, xNonSmooth);
  stretch = pow(stretch, 2.);
  stretch *= mask;
  stretch *= getUvFrame(uv, .1 + .05 * mask * frameFade);
  uv.y = mix(uv.y, .5, u_stretch * stretch);

  vec4 image = getBlur(u_image, uv, 1. / u_resolution / u_pixelRatio, vec2(0., 1.), blur);
  image.rgb *= image.a;
  vec4 backColor = u_colorBack;
  backColor.rgb *= backColor.a;
  vec4 highlightColor = u_colorHighlight;
  highlightColor.rgb *= highlightColor.a;
  vec4 shadowColor = u_colorShadow;

  vec3 color = highlightColor.rgb * highlights;
  float opacity = highlightColor.a * highlights;

  shadows = mix(shadows * shadowColor.a, 0., highlights);
  color = mix(color, shadowColor.rgb * shadowColor.a, .5 * shadows);
  color += .5 * pow(shadows, .5) * shadowColor.rgb;
  opacity += shadows;
  color = clamp(color, vec3(0.), vec3(1.));
  opacity = clamp(opacity, 0., 1.);

  color += image.rgb * (1. - opacity) * frame;
  opacity += image.a * (1. - opacity) * frame;

  color += backColor.rgb * (1. - opacity);
  opacity += backColor.a * (1. - opacity);

  float grainOverlay = valueNoise(rotate(grainUV, 1.) + vec2(3.));
  grainOverlay = mix(grainOverlay, valueNoise(rotate(grainUV, 2.) + vec2(-1.)), .5);
  grainOverlay = pow(grainOverlay, 1.3);

  float grainOverlayV = grainOverlay * 2. - 1.;
  vec3 grainOverlayColor = vec3(step(0., grainOverlayV));
  float grainOverlayStrength = u_grainOverlay * abs(grainOverlayV);
  grainOverlayStrength = pow(grainOverlayStrength, .8);
  grainOverlayStrength *= mask;
  color = mix(color, grainOverlayColor, .35 * grainOverlayStrength);

  opacity += .5 * grainOverlayStrength;
  opacity = clamp(opacity, 0., 1.);

  fragColor = vec4(color, opacity);
}
`,Vn={lines:1,linesIrregular:2,wave:3,zigzag:4,pattern:5},Hn={prism:1,lens:2,contour:3,cascade:4,flat:5},Un=`#version 300 es
precision mediump float;

uniform vec2 u_resolution;
uniform float u_pixelRatio;
uniform float u_originX;
uniform float u_originY;
uniform float u_worldWidth;
uniform float u_worldHeight;
uniform float u_fit;

uniform float u_scale;
uniform float u_rotation;
uniform float u_offsetX;
uniform float u_offsetY;

uniform vec4 u_colorFront;
uniform vec4 u_colorBack;
uniform vec4 u_colorHighlight;

uniform sampler2D u_image;
uniform float u_imageAspectRatio;

uniform float u_type;
uniform float u_pxSize;
uniform bool u_originalColors;
uniform bool u_inverted;
uniform float u_colorSteps;

out vec4 fragColor;


${On}
${Tn}

float getUvFrame(vec2 uv, vec2 pad) {
  float aa = 0.0001;

  float left   = smoothstep(-pad.x, -pad.x + aa, uv.x);
  float right  = smoothstep(1.0 + pad.x, 1.0 + pad.x - aa, uv.x);
  float bottom = smoothstep(-pad.y, -pad.y + aa, uv.y);
  float top    = smoothstep(1.0 + pad.y, 1.0 + pad.y - aa, uv.y);

  return left * right * bottom * top;
}

vec2 getImageUV(vec2 uv) {
  vec2 boxOrigin = vec2(.5 - u_originX, u_originY - .5);
  float r = u_rotation * PI / 180.;
  mat2 graphicRotation = mat2(cos(r), sin(r), -sin(r), cos(r));
  vec2 graphicOffset = vec2(-u_offsetX, u_offsetY);

  vec2 imageBoxSize;
  if (u_fit == 1.) { // contain
    imageBoxSize.x = min(u_resolution.x / u_imageAspectRatio, u_resolution.y) * u_imageAspectRatio;
  } else if (u_fit == 2.) { // cover
    imageBoxSize.x = max(u_resolution.x / u_imageAspectRatio, u_resolution.y) * u_imageAspectRatio;
  } else {
    imageBoxSize.x = min(10.0, 10.0 / u_imageAspectRatio * u_imageAspectRatio);
  }
  imageBoxSize.y = imageBoxSize.x / u_imageAspectRatio;
  vec2 imageBoxScale = u_resolution.xy / imageBoxSize;

  vec2 imageUV = uv;
  imageUV *= imageBoxScale;
  imageUV += boxOrigin * (imageBoxScale - 1.);
  imageUV += graphicOffset;
  imageUV /= u_scale;
  imageUV.x *= u_imageAspectRatio;
  imageUV = graphicRotation * imageUV;
  imageUV.x /= u_imageAspectRatio;

  imageUV += .5;
  imageUV.y = 1. - imageUV.y;

  return imageUV;
}

const int bayer2x2[4] = int[4](0, 2, 3, 1);
const int bayer4x4[16] = int[16](
0, 8, 2, 10,
12, 4, 14, 6,
3, 11, 1, 9,
15, 7, 13, 5
);

const int bayer8x8[64] = int[64](
0, 32, 8, 40, 2, 34, 10, 42,
48, 16, 56, 24, 50, 18, 58, 26,
12, 44, 4, 36, 14, 46, 6, 38,
60, 28, 52, 20, 62, 30, 54, 22,
3, 35, 11, 43, 1, 33, 9, 41,
51, 19, 59, 27, 49, 17, 57, 25,
15, 47, 7, 39, 13, 45, 5, 37,
63, 31, 55, 23, 61, 29, 53, 21
);

float getBayerValue(vec2 uv, int size) {
  ivec2 pos = ivec2(fract(uv / float(size)) * float(size));
  int index = pos.y * size + pos.x;

  if (size == 2) {
    return float(bayer2x2[index]) / 4.0;
  } else if (size == 4) {
    return float(bayer4x4[index]) / 16.0;
  } else if (size == 8) {
    return float(bayer8x8[index]) / 64.0;
  }
  return 0.0;
}


void main() {

  float pxSize = u_pxSize * u_pixelRatio;
  vec2 pxSizeUV = gl_FragCoord.xy - .5 * u_resolution;
  pxSizeUV /= pxSize;
  vec2 canvasPixelizedUV = (floor(pxSizeUV) + .5) * pxSize;
  vec2 normalizedUV = canvasPixelizedUV / u_resolution;

  vec2 imageUV = getImageUV(normalizedUV);
  vec2 ditheringNoiseUV = canvasPixelizedUV;
  vec4 image = texture(u_image, imageUV);
  float frame = getUvFrame(imageUV, pxSize / u_resolution);

  int type = int(floor(u_type));
  float dithering = 0.0;

  float lum = dot(vec3(.2126, .7152, .0722), image.rgb);
  lum = u_inverted ? (1. - lum) : lum;

  switch (type) {
    case 1: {
      dithering = step(hash21(ditheringNoiseUV), lum);
    } break;
    case 2:
    dithering = getBayerValue(pxSizeUV, 2);
    break;
    case 3:
    dithering = getBayerValue(pxSizeUV, 4);
    break;
    default :
    dithering = getBayerValue(pxSizeUV, 8);
    break;
  }

  float colorSteps = max(floor(u_colorSteps), 1.);
  vec3 color = vec3(0.0);
  float opacity = 1.;

  dithering -= .5;
  float brightness = clamp(lum + dithering / colorSteps, 0.0, 1.0);
  brightness = mix(0.0, brightness, frame);
  brightness = mix(0.0, brightness, image.a);
  float quantLum = floor(brightness * colorSteps + 0.5) / colorSteps;
  quantLum = mix(0.0, quantLum, frame);

  if (u_originalColors == true) {
    vec3 normColor = image.rgb / max(lum, 0.001);
    color = normColor * quantLum;

    float quantAlpha = floor(image.a * colorSteps + 0.5) / colorSteps;
    opacity = mix(quantLum, 1., quantAlpha);
  } else {
    vec3 fgColor = u_colorFront.rgb * u_colorFront.a;
    float fgOpacity = u_colorFront.a;
    vec3 bgColor = u_colorBack.rgb * u_colorBack.a;
    float bgOpacity = u_colorBack.a;
    vec3 hlColor = u_colorHighlight.rgb * u_colorHighlight.a;
    float hlOpacity = u_colorHighlight.a;

    fgColor = mix(fgColor, hlColor, step(1.02 - .02 * u_colorSteps, brightness));
    fgOpacity = mix(fgOpacity, hlOpacity, step(1.02 - .02 * u_colorSteps, brightness));

    color = fgColor * quantLum;
    opacity = fgOpacity * quantLum;
    color += bgColor * (1.0 - opacity);
    opacity += bgOpacity * (1.0 - opacity);
  }

  fragColor = vec4(color, opacity);
}
`,Wn=`#version 300 es
precision mediump float;

uniform sampler2D u_image;
uniform float u_imageAspectRatio;
uniform float u_spread;
uniform float u_bias;
uniform float u_angle;
uniform float u_perspective;
uniform float u_count;
uniform float u_dispersion;
uniform float u_dispersionShift;
uniform float u_dispersionColor;
uniform float u_focusCenter;
uniform float u_focusEdges;
uniform float u_swirl;
uniform float u_noise;
uniform float u_noiseFrequency;
uniform float u_noiseOffset;
uniform float u_lensBulge;
uniform float u_lensCircle;
uniform float u_grainMixer;
uniform float u_grainOverlay;
uniform float u_imageX;
uniform float u_imageY;

in vec2 v_imageUV;

out vec4 fragColor;

${Tn}
${On}
${En}

float valueNoise(vec2 st) {
  vec2 i = floor(st);
  vec2 f = fract(st);
  float a = hash21(i);
  float b = hash21(i + vec2(1., 0.));
  float c = hash21(i + vec2(0., 1.));
  float d = hash21(i + vec2(1., 1.));
  vec2 u = f * f * (3. - 2. * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float getUvFrame(vec2 uv) {
  vec2 invAA = 1. / clamp(fwidth(uv), 1e-5, .02);
  vec2 lo = clamp(uv * invAA + .5, 0., 1.);
  vec2 hi = clamp((1. - uv) * invAA + .5, 0., 1.);
  return lo.x * hi.x * lo.y * hi.y;
}

vec4 sampleOverWhite(vec2 uv) {
  vec4 img = texture(u_image, uv);
  float cover = img.a * getUvFrame(uv);
  vec3 colorOverWhite = mix(vec3(1.), img.rgb, cover);
  return vec4(colorOverWhite, cover);
}

vec3 hueColor(float hue) {
  vec3 rgb = clamp(abs(mod(hue * 6. + vec3(0., 4., 2.), 6.) - 3.) - 1., 0., 1.);
  rgb = rgb * rgb * (3. - 2. * rgb);
  return rgb;
}
                                            
float boxInradius() {
  return .5 * min(u_imageAspectRatio, 1.);
}

float boxOutradius() {
  return .5 * length(vec2(u_imageAspectRatio, 1.));
}

float spreadReach() {
  return .7 * pow(u_spread, 1.3 + 2.7 * u_spread);
}

float innerCircleMask(float radius, float inradius) {
  return 1. - smoothstep(.5 * inradius, 1.1 * inradius, radius);
}

float dispersionCurve(float t, float biasPow) {
  float mirroredT = u_bias < 0. ? 1. - t : t;
  float curved = pow(mirroredT, biasPow);
  return u_bias < 0. ? 1. - curved : curved;
}

vec2 getSpread(vec2 fromCenter, float radius, vec2 warpedUV, float edgeAA, float inradius, float outradius, float reach, out float outStrength) {
  float angleRad = radians(u_angle);
  vec2 uniformDir = vec2(cos(angleRad), sin(angleRad));

  float invInradius = 1. / inradius;
  vec2 radialDir = fromCenter * invInradius;
  float maxLen = (outradius + reach) * invInradius;
  float radialLen = radius * invInradius;
  if (radialLen > maxLen) radialDir *= maxLen / radialLen;
  vec2 spreadDir = mix(uniformDir, radialDir, u_perspective);

  float bandProximity = smoothstep(inradius * .8, inradius, radius);
  float lensCircleMaxing = bandProximity * u_lensCircle * u_lensCircle * u_lensCircle;
  spreadDir = mix(spreadDir, radialDir, lensCircleMaxing);

  vec2 warpedAbs = abs(warpedUV - .5);
  float inner = mix(1., smoothstep(0., mix(inradius, outradius, u_focusCenter), radius), u_focusCenter);
  float boxDist = max(warpedAbs.x, warpedAbs.y) * 2.;
  float outer = mix(1., 1. - min(boxDist, 1.), u_focusEdges);
  float strength = inner * outer;

  strength *= mix(1., mix(.15, .03, max(-u_lensBulge, 0.)), lensCircleMaxing);

  vec2 outside = max(warpedAbs - .5, 0.);
  float margin = max(reach * length(spreadDir) * (1. - u_lensCircle), edgeAA);
  strength *= 1. - smoothstep(0., margin, length(outside));

  outStrength = strength;
  vec2 axis = spreadDir * (reach * strength);

  if (u_noise > 0.) {
    float turn = (valueNoise(fromCenter * u_noiseFrequency * 18. + u_noiseOffset * 30.) - .5) * 2. * u_noise;
    float cs = cos(turn), sn = sin(turn);
    axis = mat2(cs, -sn, sn, cs) * axis;
  }

  axis.x /= u_imageAspectRatio;
  return axis;
}

vec2 lensWarp(vec2 fromCenter, float radius, float inradius, out float bulgeFade) {
  bulgeFade = 1.;
  if (u_lensBulge == 0. && u_lensCircle <= 0.) return fromCenter;
  if (radius < 1e-5) return fromCenter;
  
  float r = radius;

  if (u_lensBulge != 0.) {
    float rn = radius / inradius;
    float bulge = abs(u_lensBulge) * (u_lensBulge > 0. ? 1.4 : 1.2);
    if (u_lensBulge > 0.) bulgeFade = 1. - smoothstep(1.45, 1.53, rn * bulge);
    float map = u_lensBulge > 0.
      ? tan(min(rn * bulge, 1.53)) / tan(bulge)
      : atan(rn * tan(bulge)) / bulge;
    float bulgeScale = map / rn;
    fromCenter *= bulgeScale;
    r *= bulgeScale;
  }

  if (u_lensCircle > 0.) {
    vec2 dir = fromCenter / max(r, 1e-5);
    vec2 halfBox = vec2(u_imageAspectRatio, 1.) * .5;
    float rBox = min(halfBox.x / max(abs(dir.x), 1e-4), halfBox.y / max(abs(dir.y), 1e-4));
    float band = inradius * mix(.03, .2, .5 * (u_lensBulge + 1.));
    float innerEdge = inradius - band;
    float over = smoothstep(0., 1., (r - innerEdge) / band);
    float g = r + (rBox - inradius) * pow(over, 14.);
    fromCenter = dir * mix(r, g, u_lensCircle);
  }

  return fromCenter;
}

void main() {
  vec2 uv = v_imageUV;

  float invAspect = 1. / u_imageAspectRatio;
  float inradius = boxInradius();
  float outradius = boxOutradius();
  float reach = spreadReach();

  vec2 fromCenter = uv - .5;
  fromCenter.x *= u_imageAspectRatio;
  float radius = length(fromCenter);

  float bulgeFade;
  vec2 warpedFromCenter = lensWarp(fromCenter, radius, inradius, bulgeFade);
  vec2 baseUV = vec2(warpedFromCenter.x * invAspect, warpedFromCenter.y) + .5;

  vec2 baseDerivative = fwidth(baseUV);
  float edgeAA = clamp(2. * max(baseDerivative.x, baseDerivative.y), .001, .02);

  float spreadStrength;
  vec2 spreadAxis = getSpread(fromCenter, radius, baseUV, edgeAA, inradius, outradius, reach, spreadStrength);

  vec2 grainUV = vec2(0.);
  if (u_grainMixer > 0. || u_grainOverlay > 0.) {
    vec2 dudx = dFdx(v_imageUV);
    vec2 dudy = dFdy(v_imageUV);
    grainUV = (v_imageUV - .5) * (.8 / vec2(length(dudx), length(dudy))) + .5;
  }

  if (u_grainMixer > 0.) {
    float grainSeed = valueNoise(grainUV);
    vec2 jit = fract(grainSeed * vec2(157.31, 113.57)) * 2. - 1.;
    spreadAxis += jit * .3 * u_grainMixer * length(spreadAxis);
  }

  float count = floor(u_count);
  int countInteger = int(count);

  float invCount = 1. / count;
  float invSpan = 1. / max(count - 1., 1.);
  float hueBase = u_dispersionColor + .5;
  float biasPower = 1. + 2. * abs(u_bias);
  vec2 tapBias = .5 - vec2(u_imageX, u_imageY);

  float centerAmount = clamp(1. - u_dispersionShift, 0., 1.);
  float edgesAmount = clamp(1. + u_dispersionShift, 0., 1.);
  float dispersion = u_dispersion * mix(edgesAmount, centerAmount, innerCircleMask(radius, inradius));
  float dispersionPower = pow(dispersion, .8);

  float warpedRadius = length(warpedFromCenter);
  float swirlAngle = u_swirl * .4 * PI * spreadStrength * u_spread * min(1., inradius / max(warpedRadius, 1e-4));

  vec3 colorSum = vec3(0.);
  vec3 weightSum = vec3(0.);
  float coverSum = 0.;

  for (int i = 0; i < ${{maxSamples:50}.maxSamples}; i++) {
    if (i >= countInteger) break;

    float layer = float(i);
    float hue = hueBase + layer * invCount;

    float spread = layer * invSpan;
    if (u_bias != 0.) spread = dispersionCurve(spread, biasPower);

    // mix(axis, -axis, spread) is axis scaled by the signed position along the fan
    float fanPos = 1. - 2. * spread;
    vec2 tapUV = baseUV + spreadAxis * fanPos - .5;

    if (u_swirl != 0.) {
      tapUV.x *= u_imageAspectRatio;
      tapUV = rotate(tapUV, swirlAngle * fanPos);
      tapUV.x *= invAspect;
    }

    vec4 tap = sampleOverWhite(tapUV + tapBias);
    vec3 weight = 1. - dispersionPower * hueColor(hue);

    colorSum += tap.rgb * weight;
    weightSum += weight;
    coverSum += tap.a;
  }

  vec3 color = colorSum / max(weightSum, 1e-4);
  float coverAvg = coverSum * invCount;

  float ground = min(color.r, min(color.g, color.b));
  float alpha = max(coverAvg, 1. - ground);
  vec3 premult = max(color - (1. - alpha), 0.);
  fragColor = vec4(premult, alpha) * bulgeFade;

  if (u_grainOverlay > 0.) {
    float grain = valueNoise(rotate(grainUV, 1.) + vec2(3.));
    grain = mix(grain, valueNoise(rotate(grainUV, 2.) + vec2(-1.)), .5);
    grain = pow(grain, 1.3);
    float grainV = grain * 2. - 1.;
    float grainStrength = pow(u_grainOverlay * abs(grainV), .8) * fragColor.a;
    fragColor.rgb = mix(fragColor.rgb, vec3(step(0., grainV)) * fragColor.a, .35 * grainStrength);
  }
}
`,Gn=`#version 300 es
precision mediump float;

uniform float u_rotation;

uniform float u_time;

uniform vec4 u_colorFront;
uniform vec4 u_colorBack;
uniform float u_radius;
uniform float u_contrast;

uniform sampler2D u_image;
uniform float u_imageAspectRatio;

uniform float u_size;
uniform float u_grainMixer;
uniform float u_grainOverlay;
uniform float u_grainSize;
uniform float u_grid;
uniform bool u_originalColors;
uniform bool u_inverted;
uniform float u_type;

in vec2 v_imageUV;

out vec4 fragColor;

${Tn}
${En}
${On}

float valueNoise(vec2 st) {
  vec2 i = floor(st);
  vec2 f = fract(st);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  vec2 u = f * f * (3.0 - 2.0 * f);
  float x1 = mix(a, b, u.x);
  float x2 = mix(c, d, u.x);
  return mix(x1, x2, u.y);
}

float lst(float edge0, float edge1, float x) {
  return clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
}

float sst(float edge0, float edge1, float x) {
  return smoothstep(edge0, edge1, x);
}

float getCircle(vec2 uv, float r, float baseR) {
  r = mix(.25 * baseR, 0., r);
  float d = length(uv - .5);
  float aa = fwidth(d);
  return 1. - smoothstep(r - aa, r + aa, d);
}

float getCell(vec2 uv) {
  float insideX = step(0.0, uv.x) * (1.0 - step(1.0, uv.x));
  float insideY = step(0.0, uv.y) * (1.0 - step(1.0, uv.y));
  return insideX * insideY;
}

float getCircleWithHole(vec2 uv, float r, float baseR) {
  float cell = getCell(uv);

  r = mix(.75 * baseR, 0., r);
  float rMod = mod(r, .5);

  float d = length(uv - .5);
  float aa = fwidth(d);
  float circle = 1. - smoothstep(rMod - aa, rMod + aa, d);
  if (r < .5) {
    return circle;
  } else {
    return cell - circle;
  }
}

float getGooeyBall(vec2 uv, float r, float baseR) {
  float d = length(uv - .5);
  float sizeRadius = .3;
  if (u_grid == 1.) {
    sizeRadius = .42;
  }
  sizeRadius = mix(sizeRadius * baseR, 0., r);
  d = 1. - sst(0., sizeRadius, d);

  d = pow(d, 2. + baseR);
  return d;
}

float getSoftBall(vec2 uv, float r, float baseR) {
  float d = length(uv - .5);
  float sizeRadius = clamp(baseR, 0., 1.);
  sizeRadius = mix(.5 * sizeRadius, 0., r);
  d = 1. - lst(0., sizeRadius, d);
  float powRadius = 1. - lst(0., 2., baseR);
  d = pow(d, 4. + 3. * powRadius);
  return d;
}

float getUvFrame(vec2 uv, vec2 pad) {
  float aa = 0.0001;

  float left   = smoothstep(-pad.x, -pad.x + aa, uv.x);
  float right  = smoothstep(1.0 + pad.x, 1.0 + pad.x - aa, uv.x);
  float bottom = smoothstep(-pad.y, -pad.y + aa, uv.y);
  float top    = smoothstep(1.0 + pad.y, 1.0 + pad.y - aa, uv.y);

  return left * right * bottom * top;
}

float sigmoid(float x, float k) {
  return 1.0 / (1.0 + exp(-k * (x - 0.5)));
}

float getLumAtPx(vec2 uv, float contrast) {
  vec4 tex = texture(u_image, uv);
  vec3 color = vec3(
  sigmoid(tex.r, contrast),
  sigmoid(tex.g, contrast),
  sigmoid(tex.b, contrast)
  );
  float lum = dot(vec3(0.2126, 0.7152, 0.0722), color);
  lum = mix(1., lum, tex.a);
  lum = u_inverted ? (1. - lum) : lum;
  return lum;
}

float getLumBall(vec2 p, vec2 pad, vec2 inCellOffset, float contrast, float baseR, float stepSize, out vec4 ballColor) {
  p += inCellOffset;
  vec2 uv_i = floor(p);
  vec2 uv_f = fract(p);
  vec2 samplingUV = (uv_i + .5 - inCellOffset) * pad + vec2(.5);
  float outOfFrame = getUvFrame(samplingUV, pad * stepSize);

  float lum = getLumAtPx(samplingUV, contrast);
  ballColor = texture(u_image, samplingUV);
  ballColor.rgb *= ballColor.a;
  ballColor *= outOfFrame;

  float ball = 0.;
  if (u_type == 0.) {
    // classic
    ball = getCircle(uv_f, lum, baseR);
  } else if (u_type == 1.) {
    // gooey
    ball = getGooeyBall(uv_f, lum, baseR);
  } else if (u_type == 2.) {
    // holes
    ball = getCircleWithHole(uv_f, lum, baseR);
  } else if (u_type == 3.) {
    // soft
    ball = getSoftBall(uv_f, lum, baseR);
  }

  return ball * outOfFrame;
}


void main() {

  float stepMultiplier = 1.;
  if (u_type == 0.) {
    // classic
    stepMultiplier = 2.;
  } else if (u_type == 1. || u_type == 3.) {
    // gooey & soft
    stepMultiplier = 6.;
  }

  float cellsPerSide = mix(300., 7., pow(u_size, .7));
  cellsPerSide /= stepMultiplier;
  float cellSizeY = 1. / cellsPerSide;
  vec2 pad = cellSizeY * vec2(1. / u_imageAspectRatio, 1.);
  if (u_type == 1. && u_grid == 1.) {
    // gooey diagonal grid works differently
    pad *= .7;
  }

  vec2 uv = v_imageUV;
  uv -= vec2(.5);
  uv /= pad;

  float contrast = mix(0., 15., pow(u_contrast, 1.5));
  float baseRadius = u_radius;
  if (u_originalColors == true) {
    contrast = mix(.1, 4., pow(u_contrast, 2.));
    baseRadius = 2. * pow(.5 * u_radius, .3);
  }

  float totalShape = 0.;
  vec3 totalColor = vec3(0.);
  float totalOpacity = 0.;

  vec4 ballColor;
  float shape;
  float stepSize = 1. / stepMultiplier;
  for (float x = -0.5; x < 0.5; x += stepSize) {
    for (float y = -0.5; y < 0.5; y += stepSize) {
      vec2 offset = vec2(x, y);

      if (u_grid == 1.) {
        float rowIndex = floor((y + .5) / stepSize);
        float colIndex = floor((x + .5) / stepSize);
        if (stepSize == 1.) {
          rowIndex = floor(uv.y + y + 1.);
          if (u_type == 1.) {
            colIndex = floor(uv.x + x + 1.);
          }
        }
        if (u_type == 1.) {
          if (mod(rowIndex + colIndex, 2.) == 1.) {
            continue;
          }
        } else {
          if (mod(rowIndex, 2.) == 1.) {
            offset.x += .5 * stepSize;
          }
        }
      }

      shape = getLumBall(uv, pad, offset, contrast, baseRadius, stepSize, ballColor);
      totalColor   += ballColor.rgb * shape;
      totalShape   += shape;
      totalOpacity += shape;
    }
  }

  const float eps = 1e-4;

  totalColor /= max(totalShape, eps);
  totalOpacity /= max(totalShape, eps);

  float finalShape = 0.;
  if (u_type == 0.) {
    finalShape = min(1., totalShape);
  } else if (u_type == 1.) {
    float aa = fwidth(totalShape);
    float th = .5;
    finalShape = smoothstep(th - aa, th + aa, totalShape);
  } else if (u_type == 2.) {
    finalShape = min(1., totalShape);
  } else if (u_type == 3.) {
    finalShape = totalShape;
  }

  vec2 grainSize = mix(2000., 200., u_grainSize) * vec2(1., 1. / u_imageAspectRatio);
  vec2 grainUV = v_imageUV - .5;
  grainUV *= grainSize;
  grainUV += .5;
  float grain = valueNoise(grainUV);
  grain = smoothstep(.55, .7 + .2 * u_grainMixer, grain);
  grain *= u_grainMixer;
  finalShape = mix(finalShape, 0., grain);

  vec3 color = vec3(0.);
  float opacity = 0.;

  if (u_originalColors == true) {
    color = totalColor * finalShape;
    opacity = totalOpacity * finalShape;

    vec3 bgColor = u_colorBack.rgb * u_colorBack.a;
    color = color + bgColor * (1. - opacity);
    opacity = opacity + u_colorBack.a * (1. - opacity);
  } else {
    vec3 fgColor = u_colorFront.rgb * u_colorFront.a;
    float fgOpacity = u_colorFront.a;
    vec3 bgColor = u_colorBack.rgb * u_colorBack.a;
    float bgOpacity = u_colorBack.a;

    color = fgColor * finalShape;
    opacity = fgOpacity * finalShape;
    color += bgColor * (1. - opacity);
    opacity += bgOpacity * (1. - opacity);
  }

  float grainOverlay = valueNoise(rotate(grainUV, 1.) + vec2(3.));
  grainOverlay = mix(grainOverlay, valueNoise(rotate(grainUV, 2.) + vec2(-1.)), .5);
  grainOverlay = pow(grainOverlay, 1.3);

  float grainOverlayV = grainOverlay * 2. - 1.;
  vec3 grainOverlayColor = vec3(step(0., grainOverlayV));
  float grainOverlayStrength = u_grainOverlay * abs(grainOverlayV);
  grainOverlayStrength = pow(grainOverlayStrength, .8);
  color = mix(color, grainOverlayColor, .5 * grainOverlayStrength);

  opacity += .5 * grainOverlayStrength;
  opacity = clamp(opacity, 0., 1.);

  fragColor = vec4(color, opacity);
}
`,Kn={classic:0,gooey:1,holes:2,soft:3},qn={square:0,hex:1};function R(e){if(Array.isArray(e))return e.length===4?e:e.length===3?[...e,1]:$n;if(typeof e!=`string`)return $n;let t,n,r,i=1;if(e.startsWith(`#`))[t,n,r,i]=Jn(e);else if(e.startsWith(`rgb`)){let a=Yn(e);if(a===null)return $n;[t,n,r,i]=a}else if(e.startsWith(`hsl`)){let a=Xn(e);if(a===null)return $n;[t,n,r,i]=Zn(a)}else return console.error(`Unsupported color format`,e),$n;return[Qn(t,0,1),Qn(n,0,1),Qn(r,0,1),Qn(i,0,1)]}function Jn(e){return e=e.replace(/^#/,``),(e.length===3||e.length===4)&&(e=e.split(``).map(e=>e+e).join(``)),e.length===6&&(e+=`ff`),/^[0-9a-f]{8}$/i.test(e)?[parseInt(e.slice(0,2),16)/255,parseInt(e.slice(2,4),16)/255,parseInt(e.slice(4,6),16)/255,parseInt(e.slice(6,8),16)/255]:(console.warn(`Invalid hex color`),$n)}function Yn(e){let t=e.match(/^rgba?\s*\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([0-9.]+))?\s*\)$/i);return t?[parseInt(t[1]??`0`)/255,parseInt(t[2]??`0`)/255,parseInt(t[3]??`0`)/255,t[4]===void 0?1:parseFloat(t[4])]:null}function Xn(e){let t=e.match(/^hsla?\s*\(\s*(\d+)\s*,\s*(\d+)%\s*,\s*(\d+)%\s*(?:,\s*([0-9.]+))?\s*\)$/i);return t?[parseInt(t[1]??`0`),parseInt(t[2]??`0`),parseInt(t[3]??`0`),t[4]===void 0?1:parseFloat(t[4])]:null}function Zn(e){let[t,n,r,i]=e,a=t/360,o=n/100,s=r/100,c,l,u;if(n===0)c=l=u=s;else{let e=(e,t,n)=>(n<0&&(n+=1),n>1&&--n,n<1/6?e+(t-e)*6*n:n<1/2?t:n<2/3?e+(t-e)*(2/3-n)*6:e),t=s<.5?s*(1+o):s+o-s*o,n=2*s-t;c=e(n,t,a+1/3),l=e(n,t,a),u=e(n,t,a-1/3)}return[c,l,u,i]}var Qn=(e,t,n)=>Math.min(Math.max(e,t),n),$n=[.5,.5,.5,1];function er(){if(typeof window>`u`)return;let e=new Image;return e.src=tr,e}var tr=`data:image/png;base64,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`;function nr(e){let t=F.useRef(void 0),n=F.useCallback(t=>{let n=e.map(e=>{if(e!=null){if(typeof e==`function`){let n=e,r=n(t);return typeof r==`function`?r:()=>{n(null)}}return e.current=t,()=>{e.current=null}}});return()=>{n.forEach(e=>e?.())}},e);return F.useMemo(()=>e.every(e=>e==null)?null:e=>{t.current&&=(t.current(),void 0),e!=null&&(t.current=n(e))},e)}function rr(e){if(e.naturalWidth<1024&&e.naturalHeight<1024){if(e.naturalWidth<1||e.naturalHeight<1)return;let t=e.naturalWidth/e.naturalHeight;e.width=Math.round(t>1?1024*t:1024),e.height=Math.round(t>1?1024:1024/t)}}async function ir(e){let t={},n=[],r=e=>{try{return e.startsWith(`/`)||new URL(e),!0}catch{return!1}},i=e=>{try{return!e.startsWith(`/`)&&new URL(e,window.location.origin).origin!==window.location.origin}catch{return!1}};return Object.entries(e).forEach(([e,a])=>{if(typeof a==`string`){let o=a||`data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==`;if(!r(o)){console.warn(`Uniform "${e}" has invalid URL "${o}". Skipping image loading.`);return}let s=new Promise((n,r)=>{let a=new Image;i(o)&&(a.crossOrigin=`anonymous`),a.onload=()=>{rr(a),t[e]=a,n()},a.onerror=()=>{console.error(`Could not set uniforms. Failed to load image at ${o}`),r()},a.src=o});n.push(s)}else if(a instanceof HTMLImageElement){let r=a.decode().then(()=>{rr(a),t[e]=a});n.push(r)}else t[e]=a}),await Promise.all(n),t}var ar=(0,F.forwardRef)(function({fragmentShader:e,uniforms:t,webGlContextAttributes:n,speed:r=0,frame:i=0,width:a,height:o,minPixelRatio:s,maxPixelCount:c,mipmaps:l,style:u,...d},f){let[p,m]=(0,F.useState)(!1),h=(0,F.useRef)(null),g=(0,F.useRef)(null),_=(0,F.useRef)(n);(0,F.useEffect)(()=>((async()=>{let n=await ir(t);h.current&&!g.current&&(g.current=new _n(h.current,e,n,_.current,r,i,s,c,l),m(!0))})(),()=>{g.current?.dispose(),g.current=null}),[e]),(0,F.useEffect)(()=>{let e=!1;return(async()=>{let n=await ir(t);e||g.current?.setUniforms(n)})(),()=>{e=!0}},[t,p]),(0,F.useEffect)(()=>{g.current?.setSpeed(r)},[r,p]),(0,F.useEffect)(()=>{g.current?.setMaxPixelCount(c)},[c,p]),(0,F.useEffect)(()=>{g.current?.setMinPixelRatio(s)},[s,p]),(0,F.useEffect)(()=>{g.current?.setFrame(i)},[i,p]);let v=nr([h,f]);return(0,I.jsx)(`div`,{ref:v,style:a!==void 0||o!==void 0?{width:typeof a==`string`&&isNaN(+a)===!1?+a:a,height:typeof o==`string`&&isNaN(+o)===!1?+o:o,...u}:u,...d})});ar.displayName=`ShaderMount`;function or(e,t){if(Object.keys(e).length!==Object.keys(t).length)return!1;for(let n in e){if(n===`colors`){let n=Array.isArray(e.colors),r=Array.isArray(t.colors);if(!n||!r){if(Object.is(e.colors,t.colors)===!1)return!1;continue}if(e.colors?.length!==t.colors?.length||!e.colors?.every((e,n)=>e===t.colors?.[n]))return!1;continue}if(Object.is(e[n],t[n])===!1)return!1}return!0}var z={name:`Default`,params:{...L,speed:1,frame:0,colors:[`#e0eaff`,`#241d9a`,`#f75092`,`#9f50d3`],distortion:.8,swirl:.1,grainMixer:0,grainOverlay:0}};({...L}),{...L},{...L};var sr=(0,F.memo)(function({speed:e=z.params.speed,frame:t=z.params.frame,colors:n=z.params.colors,distortion:r=z.params.distortion,swirl:i=z.params.swirl,grainMixer:a=z.params.grainMixer,grainOverlay:o=z.params.grainOverlay,fit:s=z.params.fit,rotation:c=z.params.rotation,scale:l=z.params.scale,originX:u=z.params.originX,originY:d=z.params.originY,offsetX:f=z.params.offsetX,offsetY:p=z.params.offsetY,worldWidth:m=z.params.worldWidth,worldHeight:h=z.params.worldHeight,...g}){let _={u_colors:n.map(R),u_colorsCount:n.length,u_distortion:r,u_swirl:i,u_grainMixer:a,u_grainOverlay:o,u_fit:wn[s],u_rotation:c,u_scale:l,u_offsetX:f,u_offsetY:p,u_originX:u,u_originY:d,u_worldWidth:m,u_worldHeight:h};return(0,I.jsx)(ar,{...g,speed:e,frame:t,fragmentShader:Fn,uniforms:_})},or),B={name:`Default`,params:{...Cn,speed:1,frame:0,scale:.6,colorBack:`#000000`,colorFront:`#00b2ff`,shape:`sphere`,type:`4x4`,size:2}};({...Cn}),{...Cn},{...L},{...L},{...L};var cr=(0,F.memo)(function({speed:e=B.params.speed,frame:t=B.params.frame,colorBack:n=B.params.colorBack,colorFront:r=B.params.colorFront,shape:i=B.params.shape,type:a=B.params.type,pxSize:o,size:s=o===void 0?B.params.size:o,fit:c=B.params.fit,scale:l=B.params.scale,rotation:u=B.params.rotation,originX:d=B.params.originX,originY:f=B.params.originY,offsetX:p=B.params.offsetX,offsetY:m=B.params.offsetY,worldWidth:h=B.params.worldWidth,worldHeight:g=B.params.worldHeight,..._}){let v={u_colorBack:R(n),u_colorFront:R(r),u_shape:Ln[i],u_type:Rn[a],u_pxSize:s,u_fit:wn[c],u_scale:l,u_rotation:u,u_offsetX:p,u_offsetY:m,u_originX:d,u_originY:f,u_worldWidth:h,u_worldHeight:g};return(0,I.jsx)(ar,{..._,speed:e,frame:t,fragmentShader:In,uniforms:v})}),V={name:`Default`,params:{...L,fit:`cover`,scale:.6,speed:0,frame:0,colorFront:`#9fadbc`,colorBack:`#ffffff`,contrast:.3,roughness:.4,fiber:.3,fiberSize:.2,crumples:.3,crumpleSize:.35,folds:.65,foldCount:5,fade:0,drops:.2,seed:5.8}};({...L}),{...L},{...L};var lr=(0,F.memo)(function({speed:e=V.params.speed,frame:t=V.params.frame,colorFront:n=V.params.colorFront,colorBack:r=V.params.colorBack,image:i=``,contrast:a=V.params.contrast,roughness:o=V.params.roughness,fiber:s=V.params.fiber,crumples:c=V.params.crumples,folds:l=V.params.folds,drops:u=V.params.drops,seed:d=V.params.seed,fiberScale:f,fiberSize:p=f===void 0?V.params.fiberSize:.2/f,crumplesScale:m,crumpleSize:h=m===void 0?V.params.crumpleSize:.2/m,blur:g,fade:_=g===void 0?V.params.fade:g,foldsNumber:v,foldCount:y=v===void 0?V.params.foldCount:v,fit:b=V.params.fit,scale:x=V.params.scale,rotation:S=V.params.rotation,originX:C=V.params.originX,originY:w=V.params.originY,offsetX:T=V.params.offsetX,offsetY:E=V.params.offsetY,worldWidth:D=V.params.worldWidth,worldHeight:ee=V.params.worldHeight,...te}){let O=typeof window<`u`&&{u_noiseTexture:er()},k={u_image:i,u_colorFront:R(n),u_colorBack:R(r),u_contrast:a,u_roughness:o,u_fiber:s,u_fiberSize:p,u_crumples:c,u_crumpleSize:h,u_foldCount:y,u_folds:l,u_fade:_,u_drops:u,u_seed:d,...O,u_fit:wn[b],u_scale:x,u_rotation:S,u_offsetX:T,u_offsetY:E,u_originX:C,u_originY:w,u_worldWidth:D,u_worldHeight:ee};return(0,I.jsx)(ar,{...te,speed:e,frame:t,fragmentShader:zn,mipmaps:[`u_image`],uniforms:k})},or),H={name:`Default`,params:{...L,fit:`cover`,speed:0,frame:0,colorBack:`#00000000`,colorShadow:`#000000`,colorHighlight:`#ffffff`,shadows:.25,size:.5,angle:0,distortionShape:`prism`,highlights:.1,shape:`lines`,distortion:.5,shift:0,blur:0,edges:.25,stretch:0,margin:0,marginLeft:0,marginRight:0,marginTop:0,marginBottom:0,grainMixer:0,grainOverlay:0}};({...L}),{...L},{...L};var ur=(0,F.memo)(function({speed:e=H.params.speed,frame:t=H.params.frame,colorBack:n=H.params.colorBack,colorShadow:r=H.params.colorShadow,colorHighlight:i=H.params.colorHighlight,image:a=``,shadows:o=H.params.shadows,angle:s=H.params.angle,distortion:c=H.params.distortion,distortionShape:l=H.params.distortionShape,highlights:u=H.params.highlights,shape:d=H.params.shape,shift:f=H.params.shift,blur:p=H.params.blur,edges:m=H.params.edges,margin:h,marginLeft:g=h??H.params.marginLeft,marginRight:_=h??H.params.marginRight,marginTop:v=h??H.params.marginTop,marginBottom:y=h??H.params.marginBottom,grainMixer:b=H.params.grainMixer,grainOverlay:x=H.params.grainOverlay,stretch:S=H.params.stretch,count:C,size:w=C===void 0?H.params.size:(1/(C*1.6))**(1/6)/.7-.5,fit:T=H.params.fit,scale:E=H.params.scale,rotation:D=H.params.rotation,originX:ee=H.params.originX,originY:te=H.params.originY,offsetX:O=H.params.offsetX,offsetY:k=H.params.offsetY,worldWidth:ne=H.params.worldWidth,worldHeight:re=H.params.worldHeight,...ie}){let ae={u_image:a,u_colorBack:R(n),u_colorShadow:R(r),u_colorHighlight:R(i),u_shadows:o,u_size:w,u_angle:s,u_distortion:c,u_shift:f,u_blur:p,u_edges:m,u_stretch:S,u_distortionShape:Hn[l],u_highlights:u,u_shape:Vn[d],u_marginLeft:g,u_marginRight:_,u_marginTop:v,u_marginBottom:y,u_grainMixer:b,u_grainOverlay:x,u_fit:wn[T],u_scale:E,u_rotation:D,u_offsetX:O,u_offsetY:k,u_originX:ee,u_originY:te,u_worldWidth:ne,u_worldHeight:re};return(0,I.jsx)(ar,{...ie,speed:e,frame:t,fragmentShader:Bn,mipmaps:[`u_image`],uniforms:ae})}),U={name:`Default`,params:{...L,fit:`cover`,speed:0,frame:0,colorFront:`#94ffaf`,colorBack:`#000c38`,colorHighlight:`#eaff94`,type:`8x8`,size:2,colorSteps:2,originalColors:!1,inverted:!1}};({...L}),{...L},{...L};var dr=(0,F.memo)(function({speed:e=U.params.speed,frame:t=U.params.frame,colorFront:n=U.params.colorFront,colorBack:r=U.params.colorBack,colorHighlight:i=U.params.colorHighlight,image:a=``,type:o=U.params.type,colorSteps:s=U.params.colorSteps,originalColors:c=U.params.originalColors,inverted:l=U.params.inverted,pxSize:u,size:d=u===void 0?U.params.size:u,fit:f=U.params.fit,scale:p=U.params.scale,rotation:m=U.params.rotation,originX:h=U.params.originX,originY:g=U.params.originY,offsetX:_=U.params.offsetX,offsetY:v=U.params.offsetY,worldWidth:y=U.params.worldWidth,worldHeight:b=U.params.worldHeight,...x}){let S={u_image:a,u_colorFront:R(n),u_colorBack:R(r),u_colorHighlight:R(i),u_type:Rn[o],u_pxSize:d,u_colorSteps:s,u_originalColors:c,u_inverted:l,u_fit:wn[f],u_rotation:m,u_scale:p,u_offsetX:_,u_offsetY:v,u_originX:h,u_originY:g,u_worldWidth:y,u_worldHeight:b};return(0,I.jsx)(ar,{...x,speed:e,frame:t,fragmentShader:Un,uniforms:S})},or),W={name:`Default`,params:{...L,scale:1,fit:`contain`,speed:0,frame:0,spread:.6,bias:1,angle:0,perspective:.1,count:35,dispersion:1,dispersionShift:0,dispersionColor:.6,focusCenter:.8,focusEdges:1,swirl:.35,noise:0,noiseFrequency:.25,noiseOffset:0,lensBulge:0,lensCircle:0,grainMixer:0,grainOverlay:0,imageX:0,imageY:0}};({...L}),{...L},{...L};var fr=(0,F.memo)(function({speed:e=W.params.speed,frame:t=W.params.frame,image:n=``,spread:r=W.params.spread,bias:i=W.params.bias,angle:a=W.params.angle,perspective:o=W.params.perspective,count:s=W.params.count,dispersion:c=W.params.dispersion,dispersionShift:l=W.params.dispersionShift,dispersionColor:u=W.params.dispersionColor,focusCenter:d=W.params.focusCenter,focusEdges:f=W.params.focusEdges,swirl:p=W.params.swirl,noise:m=W.params.noise,noiseFrequency:h=W.params.noiseFrequency,noiseOffset:g=W.params.noiseOffset,lensBulge:_=W.params.lensBulge,lensCircle:v=W.params.lensCircle,grainMixer:y=W.params.grainMixer,grainOverlay:b=W.params.grainOverlay,imageX:x=W.params.imageX,imageY:S=W.params.imageY,fit:C=W.params.fit,scale:w=W.params.scale,rotation:T=W.params.rotation,originX:E=W.params.originX,originY:D=W.params.originY,offsetX:ee=W.params.offsetX,offsetY:te=W.params.offsetY,worldWidth:O=W.params.worldWidth,worldHeight:k=W.params.worldHeight,...ne}){let re={u_image:n,u_spread:r,u_bias:i,u_angle:a,u_perspective:o,u_count:s,u_dispersion:c,u_dispersionShift:l,u_dispersionColor:u,u_focusCenter:d,u_focusEdges:f,u_swirl:p,u_noise:m,u_noiseFrequency:h,u_noiseOffset:g,u_lensBulge:_,u_lensCircle:v,u_grainMixer:y,u_grainOverlay:b,u_imageX:x,u_imageY:S,u_fit:wn[C],u_rotation:T,u_scale:w,u_offsetX:ee,u_offsetY:te,u_originX:E,u_originY:D,u_worldWidth:O,u_worldHeight:k};return(0,I.jsx)(ar,{...ne,speed:e,frame:t,fragmentShader:Wn,mipmaps:[`u_image`],uniforms:re})},or),G={name:`Default`,params:{...L,fit:`cover`,speed:0,frame:0,colorBack:`#f2f1e8`,colorFront:`#2b2b2b`,size:.5,radius:1.25,contrast:.4,originalColors:!1,inverted:!1,grainMixer:.2,grainOverlay:.2,grainSize:.5,grid:`hex`,type:`gooey`}};({...L}),{...L},{...L};var pr=(0,F.memo)(function({speed:e=G.params.speed,frame:t=G.params.frame,colorFront:n=G.params.colorFront,colorBack:r=G.params.colorBack,image:i=``,size:a=G.params.size,radius:o=G.params.radius,contrast:s=G.params.contrast,originalColors:c=G.params.originalColors,inverted:l=G.params.inverted,grainMixer:u=G.params.grainMixer,grainOverlay:d=G.params.grainOverlay,grainSize:f=G.params.grainSize,grid:p=G.params.grid,type:m=G.params.type,fit:h=G.params.fit,scale:g=G.params.scale,rotation:_=G.params.rotation,originX:v=G.params.originX,originY:y=G.params.originY,offsetX:b=G.params.offsetX,offsetY:x=G.params.offsetY,worldWidth:S=G.params.worldWidth,worldHeight:C=G.params.worldHeight,...w}){let T={u_image:i,u_colorFront:R(n),u_colorBack:R(r),u_size:a,u_radius:o,u_contrast:s,u_originalColors:c,u_inverted:l,u_grainMixer:u,u_grainOverlay:d,u_grainSize:f,u_grid:qn[p],u_type:Kn[m],u_fit:wn[h],u_rotation:_,u_scale:g,u_offsetX:b,u_offsetY:x,u_originX:v,u_originY:y,u_worldWidth:S,u_worldHeight:C};return(0,I.jsx)(ar,{...w,speed:e,frame:t,fragmentShader:Gn,uniforms:T})},or),mr=4,hr=128,gr=(e,t)=>{let n=255,r=0;for(let i of e)n=Math.min(n,i[t]),r=Math.max(r,i[t]);return r-n},_r=e=>{if(e.colors.length<2)return null;let t={r:gr(e.colors,`r`),g:gr(e.colors,`g`),b:gr(e.colors,`b`)},n=Object.keys(t).reduce((e,n)=>t[n]>t[e]?n:e,`r`),r=[...e.colors].sort((e,t)=>e[n]-t[n]),i=e.weight/2,a=0,o=1;for(let e=0;e<r.length-1&&(a+=r[e].weight,o=e+1,!(a>=i));e+=1);let s=r.slice(0,o),c=r.slice(o);return[{colors:s,weight:s.reduce((e,t)=>e+t.weight,0)},{colors:c,weight:c.reduce((e,t)=>e+t.weight,0)}]},vr=e=>{let t=e.colors.reduce((e,t)=>({r:e.r+t.r*t.weight,g:e.g+t.g*t.weight,b:e.b+t.b*t.weight}),{r:0,g:0,b:0});return{r:Math.round(t.r/e.weight),g:Math.round(t.g/e.weight),b:Math.round(t.b/e.weight),weight:e.weight}},yr=({r:e,g:t,b:n})=>`#${e.toString(16).padStart(2,`0`)}${t.toString(16).padStart(2,`0`)}${n.toString(16).padStart(2,`0`)}`,br=(e,t=5)=>{if(t<=0)return[];let n=new Map;for(let t=0;t<e.length;t+=4){if(e[t+3]<hr)continue;let r=e[t],i=e[t+1],a=e[t+2],o=r>>mr<<8|i>>mr<<4|a>>mr,s=n.get(o);s?(s.r+=r,s.g+=i,s.b+=a,s.weight+=1):n.set(o,{r,g:i,b:a,weight:1})}let r=[...n.values()].map(e=>({r:Math.round(e.r/e.weight),g:Math.round(e.g/e.weight),b:Math.round(e.b/e.weight),weight:e.weight}));if(r.length===0)return[];let i=[{colors:r,weight:r.reduce((e,t)=>e+t.weight,0)}];for(;i.length<Math.min(t,r.length);){let e=-1,t=-1;for(let n=0;n<i.length;n+=1){let r=i[n];if(r.colors.length<2)continue;let a=Math.max(gr(r.colors,`r`),gr(r.colors,`g`),gr(r.colors,`b`))*Math.sqrt(r.weight);a>t&&(t=a,e=n)}if(e<0)break;let n=_r(i[e]);if(!n)break;i.splice(e,1,...n)}return i.map(vr).sort((e,t)=>t.weight-e.weight).map(yr)},xr=(e,{silent:t=!1}={})=>new Promise(n=>{let r=new Image;r.crossOrigin=`Anonymous`,r.onload=()=>{let e=document.createElement(`canvas`),i=e.getContext(`2d`);if(!i){n(null);return}e.width=50,e.height=50;try{i.drawImage(r,0,0,50,50),n(i.getImageData(0,0,50,50).data)}catch(e){t||console.warn(`Failed to read image pixels for color extraction`,e),n(null)}},r.onerror=e=>{t||console.warn(`Failed to load image for color extraction`,e),n(null)},r.src=e}),Sr=(e,t)=>{let n=[];for(let t=0;t<e.length;t+=8){let r=e[t],i=e[t+1],a=e[t+2];if(e[t+3]<128)continue;let o=Math.max(r,i,a),s=Math.min(r,i,a),c=(o+s)/2;((o===s?0:(o-s)/(255-Math.abs(o+s-255)))>.2&&c>30&&c<220||n.length<100)&&n.push({r,g:i,b:a})}n.sort((e,t)=>{let n=(Math.max(e.r,e.g,e.b)-Math.min(e.r,e.g,e.b))/255;return(Math.max(t.r,t.g,t.b)-Math.min(t.r,t.g,t.b))/255-n});let r=[];for(let e of n){if(r.length>=t)break;(r.every(t=>Math.sqrt((e.r-t.r)**2+(e.g-t.g)**2+(e.b-t.b)**2)>20)||r.length===0)&&r.push(e)}return r.map(e=>`#${e.r.toString(16).padStart(2,`0`)}${e.g.toString(16).padStart(2,`0`)}${e.b.toString(16).padStart(2,`0`)}`)},Cr=async(e,t=5)=>{let n=await xr(e);return n?Sr(n,t):[]},wr=async(e,t=5)=>{let n=await xr(e);return n?br(n,t):[]},Tr=(e,t,n)=>{let r=e.setUniformValues;if(n&&typeof r==`function`){r(t);return}e.setUniforms(t)},Er=Object.freeze({antialias:!1,depth:!1}),Dr=e=>(t=>{if(e.current=t,t)return()=>{e.current=null;let n=t.paperShaderMount?.canvasElement;if(!n)return;let r=n.getContext(`webgl2`);queueMicrotask(()=>{!r||n.isConnected||r.isContextLost()||r.getExtension(`WEBGL_lose_context`)?.loseContext()})}}),Or=.35,kr=(e,t)=>e?.rhythmic===!1?0:!e||e.impact===void 0?t:(Or+.65*e.impact)*t,Ar=(e=[],t=1)=>({events:e,trackScale:t,lastBeat:null,lastDownbeat:null,cursor:0,lastTime:null,beatImpact:0,downbeatImpact:0,rotationSign:1,firedBeats:0,firedDownbeats:0,lastFiredT:null}),jr=(e,t)=>{let n=0,r=e.length;for(;n<r;){let i=n+r>>1;e[i].t<=t?n=i+1:r=i}return n},Mr=(e,t,n)=>{let r=new Set(t),i=e.map((e,t)=>t).filter(e=>!n||n.pulse[e]!==0),a=i.length<e.length?i.map(t=>e[t]):e,o=n&&i.length<e.length?{...n,impact:i.map(e=>n.impact[e]),low:i.map(e=>n.low[e]),mid:i.map(e=>n.mid[e]),high:i.map(e=>n.high[e]),rhythmic:i.map(e=>n.rhythmic[e]),pulse:i.map(()=>1)}:n,s=a.map((e,t)=>{let n={t:e,kind:r.has(e)?`downbeat`:`beat`};return o&&(n.impact=o.impact[t],n.tone={low:o.low[t],mid:o.mid[t],high:o.high[t]},n.rhythmic=o.rhythmic[t]!==0),n}),c=new Set(e);if(t.forEach(e=>{c.has(e)||s.push({t:e,kind:`downbeat`})}),s.sort((e,t)=>e.t-t.t),o){let e=null;s.forEach(t=>{e=t.kind===`downbeat`?0:e===null?null:e+1,t.barPos=e})}return s},Nr=(e,t,n)=>{let r=Math.max(0,n)*1e3;if(e.beatImpact*=Math.exp(-r/160*2.3),e.downbeatImpact*=Math.exp(-r/200*2.3),e.beatImpact<1e-4&&(e.beatImpact=0),e.downbeatImpact<1e-4&&(e.downbeatImpact=0),t===null||!Number.isFinite(t))return e.lastTime=null,e;let i=e.lastTime;e.lastTime=t;let a=i===null?NaN:t-i;if(i===null||a<0||a>.3)return e.cursor=jr(e.events,t),e;for(;e.cursor<e.events.length&&e.events[e.cursor].t<=t;){let n=e.events[e.cursor];e.cursor+=1;let r=Math.max(0,t-n.t)*1e3,i=n.kind===`downbeat`,a=kr(n,e.trackScale);e.beatImpact=Math.max(e.beatImpact,a*Math.exp(-r/160*2.3)),e.rotationSign=-e.rotationSign,e.lastFiredT=n.t,i?(e.downbeatImpact=Math.max(e.downbeatImpact,a*Math.exp(-r/200*2.3)),e.firedDownbeats+=1,e.lastDownbeat=n):e.lastBeat=n,e.firedBeats+=1}return e},Pr=1500,K=(()=>{try{return typeof localStorage<`u`&&localStorage.getItem(`folia.dev.beatFxDebug`)===`1`}catch{return!1}})()?{beats:0,downbeats:0,lastT:null,heardT:null,source:`none`,note:null,trackKey:null,eventCount:0,latencyMs:0,beatImpact:0,downbeatImpact:0}:null;K&&typeof window<`u`&&(window.__foliaBeatFx=K);var q=Ar(),Fr=null,Ir=null,Lr=0,Rr=!1,zr=null,Br={key:null,time:0},Vr={beat:1,downbeat:1},Hr=.5,Ur=Hr,Wr=e=>{if(e.length<2)return Hr;let t=[];for(let n=1;n<e.length;n+=1)t.push(e[n].t-e[n-1].t);t.sort((e,t)=>e-t);let n=t[t.length>>1];return n>0?n:Hr},Gr={beats:0,downbeats:0},Kr=(e,t)=>{Vr.beat=e,Vr.downbeat=t},qr=()=>Vr,Jr={},Yr=e=>{Jr=e},Xr=e=>Jr[e]??0,Zr=e=>e in Jr,Qr=()=>Gr,$r=e=>{let t=ti();Lr=e&&t?Math.max(Lr,performance.now()+Pr):0,e!==Fr&&(Br={key:null,time:0}),Fr=e,q.events=[],q.cursor=0,q.lastTime=null,q.lastBeat=null,q.lastDownbeat=null,K&&(K.trackKey=e,K.source=e?`loading`:`none`,K.note=null,K.eventCount=0)},ei=(e,t,n,r,i=1)=>{e===Fr&&(q.events=t,q.trackScale=i,Ur=Wr(t),Lr=0,q.lastTime=null,K&&(K.source=n,K.note=r??null,K.eventCount=t.length))},ti=()=>Fr!==null&&(q.events.length>0||Lr>0&&performance.now()<Lr),ni=()=>Rr,ri=()=>({key:Fr,time:zr}),ii=e=>Br.key===e?Br.time:0,ai=()=>{$r(null),q.beatImpact=0,q.downbeatImpact=0,we.set(0),Te.set(0),Ir=null,Rr=!1},oi=()=>q.lastBeat,si=()=>q.lastDownbeat,ci=()=>q.events,li=()=>Ur,ui=()=>q.trackScale,di=()=>q.rotationSign,fi=(e,t)=>{let n=performance.now(),r=Ir===null?0:Math.min(.1,(n-Ir)/1e3);Ir=n;let i=null;if(e&&!e.paused&&!e.ended){let n=t,r=(Number(n?.outputLatency)||0)+(Number(n?.baseLatency)||0);i=e.currentTime-r,K&&(K.latencyMs=r*1e3)}Rr=i!==null,zr=i,i!==null&&(Br={key:Fr,time:i}),Nr(q,i,r),Gr.beats=q.firedBeats,Gr.downbeats=q.firedDownbeats,we.set(q.beatImpact*Vr.beat),Te.set(q.downbeatImpact*Vr.downbeat),K&&(K.beats=q.firedBeats,K.downbeats=q.firedDownbeats,K.lastT=q.lastFiredT,K.heardT=i,K.beatImpact=q.beatImpact,K.downbeatImpact=q.downbeatImpact)},pi=921600,mi=.12,hi=300,gi=e=>Math.min(1,Math.max(0,e/255)),_i=e=>Math.min(2,Math.max(0,e)),vi=e=>Math.min(1,Math.max(0,e)),yi=(e,t,n)=>e+(t-e)*n,bi=(e,t,n,r,i)=>(gi(e)*.22+gi(t)*.18+gi(n)*.22+gi(r)*.28+gi(i)*.1)**.55,xi=(e,t,n,r=.84)=>Math.max(n*r,vi((e-t)*7)),Si=(e,t)=>vi(e*.42+t*.85),Ci=(e,t)=>Math.max(e,t),wi=(e,t,n)=>n?Si(e,t):vi(e),Ti=(e,t,n,r)=>_i(r?e*mi:yi(e,t,n)),Ei=(e,t,n)=>{let r=e[0]??t.secondaryColor;if(n===`cover-only`){let t=e[1]??r,n=e[2]??t;return{ditheringBack:n,ditheringFront:r,mesh:[r,t,n,e[3]??r,e[4]??t,e[5]??n]}}let i=e[1]??t.primaryColor,a=e[2]??r,o=e[3]??i;return{ditheringBack:t.backgroundColor,ditheringFront:r,mesh:[r,i,a,o,t.backgroundColor,t.accentColor]}},Di=F.memo(({theme:e,coverUrl:n,audioPower:r,audioBands:i,staticMode:a,paused:o,tuning:s,blendMs:c=0,blendProgress:l})=>{let u=(0,F.useRef)(null),d=(0,F.useRef)(null),f=(0,F.useMemo)(()=>Dr(u),[]),p=(0,F.useMemo)(()=>Dr(d),[]),m=(0,F.useRef)(null),h=(0,F.useRef)(null),g=(0,F.useRef)(o),_=(0,F.useRef)(+!o),[v,y]=(0,F.useState)([]),b=s??te,x=b.displayMode!==`mesh`,C=b.displayMode!==`dithering`;g.current=o;let w=st();(0,F.useEffect)(()=>{let e=!0;return n?(wr(n,6).then(t=>{e&&(y(t),w())}),()=>{e=!1}):(y([]),w(),()=>{e=!1})},[n,w]);let T=(0,F.useMemo)(()=>Ei(v,e,b.colorSource),[v,e,b.colorSource]),E=ht([e.backgroundColor,T.ditheringBack,T.ditheringFront,...T.mesh],c,l),[D,ee,O]=E,k=(0,F.useMemo)(()=>({ditheringBack:ee,ditheringFront:O,mesh:E.slice(3)}),[E,ee,O]);return(0,F.useEffect)(()=>{let e=u.current?.paperShaderMount,n=d.current?.paperShaderMount;if(a){e?.setSpeed(0),n?.setSpeed(0);return}let o=0,s=new WeakMap,c=(e,t,n)=>{let r=s.get(e);r||(r={},s.set(e,r)),r[t]!==n&&(r[t]=n,e.style[t]=n)},l=0,f=0,p=0,v=0,y=0,x=0,w=null,T=(e,t)=>yi(Ti(e,t,v,!0),Ti(e,t,v,!1),_.current),E=e=>{o=requestAnimationFrame(E);let n=g.current,a=w===null?0:1-Math.exp((w-e)/hi),s=w===null?1e3/60:e-w;w=e;let D=e=>t()?1-(1-e)**(s/(1e3/60)):e,ee=t()?.84**(s/(1e3/60)):.84;_.current=yi(_.current,+!n,a);let te=n?0:gi(r.get()),O=n?0:gi(i.bass.get()),k=n?0:bi(i.bass.get(),i.lowMid.get(),i.mid.get(),i.vocal.get(),i.treble.get()),ne=n?0:gi(Math.max(i.mid.get(),i.vocal.get()));l=yi(l,te,D(.12)),f=yi(f,O,D(.16)),p=yi(p,ne,D(.13)),x=b.enhancedBeatResponse?xi(k,y,x,ee):0,y=k;let re=!n&&ti()&&Xr(S.latentPulse)>0?Si(k,Ci(we.get(),Te.get())):wi(k,x,b.enhancedBeatResponse);v=yi(v,re,D(re>v?.42:.14));let ie=u.current?.paperShaderMount,ae=d.current?.paperShaderMount;if(ie){let e=T(b.ditheringSpeed,b.ditheringAudioSpeed);ie.setSpeed(e),Tr(ie,{u_pxSize:Math.max(.5,b.ditheringSize-f*b.ditheringSize*.34)},e!==0)}if(ae){let e=T(b.meshSpeed,b.meshAudioSpeed);ae.setSpeed(e),Tr(ae,{u_distortion:b.meshDistortion+l*.62,u_swirl:b.meshSwirl+p*.38},e!==0)}m.current&&(c(m.current,`opacity`,C?`${Math.min(1,b.ditheringOpacity+f*.25)}`:`1`),c(m.current,`transform`,`scale(${1.015+f*.025})`)),h.current&&(c(h.current,`filter`,`saturate(${1.04+p*.34}) brightness(${.94+l*.16})`),c(h.current,`transform`,`scale(${1.025+l*.018})`))};return o=requestAnimationFrame(E),()=>cancelAnimationFrame(o)},[i,r,C,a,b]),(0,I.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,style:{backgroundColor:D,pointerEvents:`none`},children:[C&&(0,I.jsx)(`div`,{ref:h,className:`absolute inset-0`,style:{transform:`scale(1.025)`,transformOrigin:`center`},children:(0,I.jsx)(sr,{ref:p,width:`100%`,height:`100%`,colors:k.mesh,distortion:b.meshDistortion,swirl:b.meshSwirl,grainMixer:0,grainOverlay:.01,speed:a?0:b.meshSpeed,minPixelRatio:1,maxPixelCount:pi,webGlContextAttributes:Er,style:{width:`100%`,height:`100%`}})}),x&&(0,I.jsx)(`div`,{ref:m,className:`absolute inset-0`,style:{mixBlendMode:C?`soft-light`:`normal`,opacity:C?b.ditheringOpacity:1,transform:`scale(1.015)`,transformOrigin:`center`},children:(0,I.jsx)(cr,{ref:f,width:`100%`,height:`100%`,colorBack:k.ditheringBack,colorFront:k.ditheringFront,shape:`warp`,type:`4x4`,size:b.ditheringSize,speed:a?0:b.ditheringSpeed,minPixelRatio:1,maxPixelCount:pi,webGlContextAttributes:Er,style:{width:`100%`,height:`100%`}})}),b.overlayEnabled&&b.overlayOpacity>0&&(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundColor:D,opacity:b.overlayOpacity}})]})}),Oi={id:`bg-latent`,titleKey:`options.latentBackgroundSettings`},ki={id:`bg-latent-dithering`,titleKey:`options.latentDitheringGroup`},Ai={id:`bg-latent-mesh`,titleKey:`options.latentMeshGroup`},ji=e=>e.toFixed(1),Mi=e=>e.toFixed(2),Ni=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsxs)(A,{def:Oi,children:[(0,I.jsx)(j,{label:e(`options.latentDisplayMode`),children:(0,I.jsx)(pe,{value:t.displayMode,options:[{value:`dithering`,label:e(`options.latentDisplayDithering`)},{value:`mesh`,label:e(`options.latentDisplayMesh`)},{value:`both`,label:e(`options.latentDisplayBoth`)}],onChange:e=>n?.({displayMode:e})})}),(0,I.jsx)(j,{label:e(`options.latentColorSource`),children:(0,I.jsx)(pe,{value:t.colorSource,options:[{value:`cover-theme`,label:e(`options.latentColorSourceCoverTheme`)},{value:`cover-only`,label:e(`options.latentColorSourceCoverOnly`)}],onChange:e=>n?.({colorSource:e})})}),(0,I.jsx)(M,{label:e(`options.latentDynamicOnlyInPlayer`),note:e(`options.latentDynamicOnlyInPlayerDesc`),checked:t.dynamicOnlyInPlayer,onChange:e=>n?.({dynamicOnlyInPlayer:e})}),(0,I.jsx)(M,{label:e(`options.latentEnhancedBeatResponse`),note:e(`options.latentEnhancedBeatResponseDesc`),checked:t.enhancedBeatResponse,onChange:e=>n?.({enhancedBeatResponse:e})}),(0,I.jsx)(M,{label:e(`options.nomandBackgroundOverlay`),note:e(`options.nomandBackgroundOverlayDesc`),checked:t.overlayEnabled,onChange:e=>n?.({overlayEnabled:e})}),(0,I.jsx)(_e,{when:t.overlayEnabled,children:(0,I.jsx)(P,{...a,sub:!0,label:e(`options.nomandBackgroundOverlayOpacity`),value:t.overlayOpacity,min:0,max:1,step:.05,format:N,onChange:e=>n?.({overlayOpacity:e})})})]}),(0,I.jsxs)(A,{def:ki,children:[(0,I.jsx)(P,{...a,label:e(`options.latentBaseSpeed`),value:t.ditheringSpeed,min:0,max:2,step:.1,format:ji,onChange:e=>n?.({ditheringSpeed:e})}),(0,I.jsx)(P,{...a,label:e(`options.latentAudioSpeed`),value:t.ditheringAudioSpeed,min:0,max:2,step:.1,format:ji,onChange:e=>n?.({ditheringAudioSpeed:e})}),(0,I.jsx)(P,{...a,label:e(`options.latentDitheringSize`),value:t.ditheringSize,min:.5,max:8,step:.25,format:Mi,onChange:e=>n?.({ditheringSize:e})}),(0,I.jsx)(P,{...a,label:e(`options.latentDitheringOpacity`),value:t.ditheringOpacity,min:0,max:1,step:.05,format:N,onChange:e=>n?.({ditheringOpacity:e})})]}),(0,I.jsxs)(A,{def:Ai,children:[(0,I.jsx)(P,{...a,label:e(`options.latentBaseSpeed`),value:t.meshSpeed,min:0,max:2,step:.1,format:ji,onChange:e=>n?.({meshSpeed:e})}),(0,I.jsx)(P,{...a,label:e(`options.latentAudioSpeed`),value:t.meshAudioSpeed,min:0,max:2,step:.1,format:ji,onChange:e=>n?.({meshAudioSpeed:e})}),(0,I.jsx)(P,{...a,label:e(`options.latentMeshDistortion`),value:t.meshDistortion,min:0,max:2,step:.05,format:Mi,onChange:e=>n?.({meshDistortion:e})}),(0,I.jsx)(P,{...a,label:e(`options.latentMeshSwirl`),value:t.meshSwirl,min:0,max:1,step:.05,format:Mi,onChange:e=>n?.({meshSwirl:e})})]})]})},Pi=e({default:()=>zi}),Fi=[`dithering`,`mesh`,`both`],Ii={dithering:`options.latentDisplayDithering`,mesh:`options.latentDisplayMesh`,both:`options.latentDisplayBoth`},Li=[`cover-theme`,`cover-only`],Ri={"cover-theme":`options.latentColorSourceCoverTheme`,"cover-only":`options.latentColorSourceCoverOnly`},zi=Pe({mode:`latent`,order:35,labelKey:`options.visualizerBackgroundModeLatent`,labelFallback:`Latent`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`path`,{d:`M4.5 7.5h.01M9 7.5h.01M13.5 7.5h.01M18 7.5h.01`,strokeWidth:`2.2`,opacity:`0.55`}),(0,I.jsx)(`path`,{d:`M3 15c3-3.5 6-3.5 9 0s6 3.5 9 0`})]}),command:{title:`Background: Latent`,description:`Switch background to cover-colored audio-reactive shaders`,keywords:[`latent`,`latent background`,`shader background`,`隐现`,`隐现背景`,`音频响应背景`]},beatEffects:[{id:S.latentPulse,nameKey:`options.beatEffect_latentPulse`,descKey:`options.beatEffect_latentPulseDesc`,source:`beats`,retired:!0}],render:({config:e,theme:t,coverUrl:n,audioPower:r,audioBands:i,staticMode:a,paused:o,blendMs:s,blendProgress:c})=>(0,I.jsx)(Di,{theme:t,coverUrl:n,audioPower:r,audioBands:i,staticMode:a,paused:o,tuning:e?.latent?.tuning,blendMs:s,blendProgress:c}),renderSettingsPanel:({config:e,actions:t,...n})=>(0,I.jsx)(Ni,{...n,tuning:e?.latent?.tuning??te,onTuningChange:t?.latent?.onTuningChange}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.latent?.tuning??te,i=n(Ii[r.displayMode]),o=n(Ri[r.colorSource]);return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(Se,{label:i,title:`${n(`options.latentDisplayMode`)}: ${i}`,onClick:()=>t?.latent?.onTuningChange?.({displayMode:xe(Fi,r.displayMode)})}),(0,I.jsx)(Se,{label:o,title:`${n(`options.latentColorSource`)}: ${o}`,onClick:()=>t?.latent?.onTuningChange?.({colorSource:xe(Li,r.colorSource)})}),(0,I.jsx)(ye,{active:r.overlayEnabled,label:n(`options.nomandBackgroundOverlay`),onToggle:()=>t?.latent?.onTuningChange?.({overlayEnabled:!r.overlayEnabled}),children:(0,I.jsx)(a,{size:14})})]})},resetSettings:e=>e?.latent?.onResetTuning?.()});function Bi(){return(Bi=Object.assign||function(e){for(var t=1;t<arguments.length;t++){var n=arguments[t];for(var r in n)Object.prototype.hasOwnProperty.call(n,r)&&(e[r]=n[r])}return e}).apply(this,arguments)}function Vi(e,t){if(e==null)return{};var n,r,i={},a=Object.keys(e);for(r=0;r<a.length;r++)t.indexOf(n=a[r])>=0||(i[n]=e[n]);return i}function Hi(e){var t=(0,F.useRef)(e),n=(0,F.useRef)(function(e){t.current&&t.current(e)});return t.current=e,n.current}var Ui=function(e,t,n){return t===void 0&&(t=0),n===void 0&&(n=1),e>n?n:e<t?t:e},Wi=function(e){return`touches`in e},Gi=function(e){return e&&e.ownerDocument.defaultView||self},Ki=function(e,t,n){var r=e.getBoundingClientRect(),i=Wi(t)?function(e,t){for(var n=0;n<e.length;n++)if(e[n].identifier===t)return e[n];return e[0]}(t.touches,n):t;return{left:Ui((i.pageX-(r.left+Gi(e).pageXOffset))/r.width),top:Ui((i.pageY-(r.top+Gi(e).pageYOffset))/r.height)}},qi=function(e){!Wi(e)&&e.preventDefault()},Ji=F.memo(function(e){var t=e.onMove,n=e.onKey,r=e.onEnd,i=Vi(e,[`onMove`,`onKey`,`onEnd`]),a=(0,F.useRef)(null),o=Hi(t),s=Hi(n),c=Hi(r),l=(0,F.useRef)(null),u=(0,F.useRef)(!1),d=(0,F.useMemo)(function(){var e=function(e){qi(e),(Wi(e)?e.touches.length>0:e.buttons>0)&&a.current?o(Ki(a.current,e,l.current)):(n(!1),c())},t=function(){n(!1),c()};function n(n){var r=u.current,i=Gi(a.current),o=n?i.addEventListener:i.removeEventListener;o(r?`touchmove`:`mousemove`,e),o(r?`touchend`:`mouseup`,t)}return[function(e){var t=e.nativeEvent,r=a.current;if(r&&(qi(t),!function(e,t){return t&&!Wi(e)}(t,u.current)&&r)){if(Wi(t)){u.current=!0;var i=t.changedTouches||[];i.length&&(l.current=i[0].identifier)}r.focus(),o(Ki(r,t,l.current)),n(!0)}},function(e){var t=e.which||e.keyCode;t<37||t>40||(e.preventDefault(),s({left:t===39?.05:t===37?-.05:0,top:t===40?.05:t===38?-.05:0}))},function(e){var t=e.which||e.keyCode;t>=37&&t<=40&&c()},n]},[s,o,c]),f=d[0],p=d[1],m=d[2],h=d[3];return(0,F.useEffect)(function(){return h},[h]),F.createElement(`div`,Bi({},i,{onTouchStart:f,onMouseDown:f,className:`react-colorful__interactive`,ref:a,onKeyDown:p,onKeyUp:m,tabIndex:0,role:`slider`}))}),Yi=function(e){return e.filter(Boolean).join(` `)},Xi=function(e){var t=e.color,n=e.left,r=e.top,i=r===void 0?.5:r,a=Yi([`react-colorful__pointer`,e.className]);return F.createElement(`div`,{className:a,style:{top:100*i+`%`,left:100*n+`%`}},F.createElement(`div`,{className:`react-colorful__pointer-fill`,style:{backgroundColor:t}}))},J=function(e,t,n){return t===void 0&&(t=0),n===void 0&&(n=10**t),Math.round(n*e)/n},Zi=function(e){return aa(Qi(e))},Qi=function(e){return e[0]===`#`&&(e=e.substring(1)),e.length<6?{r:parseInt(e[0]+e[0],16),g:parseInt(e[1]+e[1],16),b:parseInt(e[2]+e[2],16),a:e.length===4?J(parseInt(e[3]+e[3],16)/255,2):1}:{r:parseInt(e.substring(0,2),16),g:parseInt(e.substring(2,4),16),b:parseInt(e.substring(4,6),16),a:e.length===8?J(parseInt(e.substring(6,8),16)/255,2):1}},$i=function(e){return ia(na(e))},ea=function(e){var t=e.s,n=e.v,r=e.a,i=(200-t)*n/100;return{h:J(e.h),s:J(i>0&&i<200?t*n/100/(i<=100?i:200-i)*100:0),l:J(i/2),a:J(r,2)}},ta=function(e){var t=ea(e);return`hsl(`+t.h+`, `+t.s+`%, `+t.l+`%)`},na=function(e){var t=e.h,n=e.s,r=e.v,i=e.a;t=t/360*6,n/=100,r/=100;var a=Math.floor(t),o=r*(1-n),s=r*(1-(t-a)*n),c=r*(1-(1-t+a)*n),l=a%6;return{r:J(255*[r,s,o,o,c,r][l]),g:J(255*[c,r,r,s,o,o][l]),b:J(255*[o,o,c,r,r,s][l]),a:J(i,2)}},ra=function(e){var t=e.toString(16);return t.length<2?`0`+t:t},ia=function(e){var t=e.r,n=e.g,r=e.b,i=e.a,a=i<1?ra(J(255*i)):``;return`#`+ra(t)+ra(n)+ra(r)+a},aa=function(e){var t=e.r,n=e.g,r=e.b,i=e.a,a=Math.max(t,n,r),o=a-Math.min(t,n,r),s=o?a===t?(n-r)/o:a===n?2+(r-t)/o:4+(t-n)/o:0;return{h:60*(s<0?s+6:s),s:a?o/a*100:0,v:a/255*100,a:i}},oa=F.memo(function(e){var t=e.hue,n=e.onChange,r=e.onChangeEnd,i=Yi([`react-colorful__hue`,e.className]);return F.createElement(`div`,{className:i},F.createElement(Ji,{onMove:function(e){n({h:360*e.left})},onKey:function(e){n({h:Ui(t+360*e.left,0,360)})},onEnd:r,"aria-label":`Hue`,"aria-valuenow":J(t),"aria-valuemax":`360`,"aria-valuemin":`0`},F.createElement(Xi,{className:`react-colorful__hue-pointer`,left:t/360,color:ta({h:t,s:100,v:100,a:1})})))}),sa=F.memo(function(e){var t=e.hsva,n=e.onChange,r=e.onChangeEnd,i={backgroundColor:ta({h:t.h,s:100,v:100,a:1})};return F.createElement(`div`,{className:`react-colorful__saturation`,style:i},F.createElement(Ji,{onMove:function(e){n({s:100*e.left,v:100-100*e.top})},onKey:function(e){n({s:Ui(t.s+100*e.left,0,100),v:Ui(t.v-100*e.top,0,100)})},onEnd:r,"aria-label":`Color`,"aria-valuetext":`Saturation `+J(t.s)+`%, Brightness `+J(t.v)+`%`},F.createElement(Xi,{className:`react-colorful__saturation-pointer`,top:1-t.v/100,left:t.s/100,color:ta(t)})))}),ca=function(e,t){if(e===t)return!0;for(var n in e)if(e[n]!==t[n])return!1;return!0},la=function(e,t){return e.toLowerCase()===t.toLowerCase()||ca(Qi(e),Qi(t))};function ua(e,t,n,r){var i=Hi(n),a=Hi(r),o=(0,F.useState)(function(){return e.toHsva(t)}),s=o[0],c=o[1],l=(0,F.useRef)({color:t,hsva:s}),u=(0,F.useRef)(!1);return(0,F.useEffect)(function(){if(!e.equal(t,l.current.color)){var n=e.toHsva(t);l.current={hsva:n,color:t},c(n),u.current=!1}},[t,e]),(0,F.useEffect)(function(){var t;ca(s,l.current.hsva)||e.equal(t=e.fromHsva(s),l.current.color)||(l.current={hsva:s,color:t},i(t),u.current=!0)},[s,e,i]),[s,(0,F.useCallback)(function(e){c(function(t){return Object.assign({},t,e)})},[]),(0,F.useCallback)(function(){u.current&&(u.current=!1,a(l.current.color))},[a])]}var da=typeof window<`u`?F.useLayoutEffect:F.useEffect,fa=function(){return typeof __webpack_nonce__<`u`?__webpack_nonce__:void 0},pa=new WeakMap,ma=function(e){da(function(){var t=e.current;if(typeof document<`u`&&t){var n=t.getRootNode?t.getRootNode():t.ownerDocument,r=n&&(`head`in n||`host`in n)?n:t.ownerDocument;if(!pa.has(r)){var i=`head`in r?r.head:r,a=(i.ownerDocument||document).createElement(`style`);a.innerHTML=`.react-colorful{position:relative;display:flex;flex-direction:column;width:200px;height:200px;-webkit-user-select:none;-moz-user-select:none;-ms-user-select:none;user-select:none;cursor:default}.react-colorful__saturation{position:relative;flex-grow:1;border-color:transparent;border-bottom:12px solid #000;border-radius:8px 8px 0 0;background-image:linear-gradient(0deg,#000,transparent),linear-gradient(90deg,#fff,hsla(0,0%,100%,0))}.react-colorful__alpha-gradient,.react-colorful__pointer-fill{content:"";position:absolute;left:0;top:0;right:0;bottom:0;pointer-events:none;border-radius:inherit}.react-colorful__alpha-gradient,.react-colorful__saturation{box-shadow:inset 0 0 0 1px rgba(0,0,0,.05)}.react-colorful__alpha,.react-colorful__hue{position:relative;height:24px}.react-colorful__hue{background:linear-gradient(90deg,red 0,#ff0 17%,#0f0 33%,#0ff 50%,#00f 67%,#f0f 83%,red)}.react-colorful__last-control{border-radius:0 0 8px 8px}.react-colorful__interactive{position:absolute;left:0;top:0;right:0;bottom:0;border-radius:inherit;outline:none;touch-action:none}.react-colorful__pointer{position:absolute;z-index:1;box-sizing:border-box;width:28px;height:28px;transform:translate(-50%,-50%);background-color:#fff;border:2px solid #fff;border-radius:50%;box-shadow:0 2px 4px rgba(0,0,0,.2)}.react-colorful__interactive:focus .react-colorful__pointer{transform:translate(-50%,-50%) scale(1.1)}.react-colorful__alpha,.react-colorful__alpha-pointer{background-color:#fff;background-image:url('data:image/svg+xml;charset=utf-8,<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" fill-opacity=".05"><path d="M8 0h8v8H8zM0 8h8v8H0z"/></svg>')}.react-colorful__saturation-pointer{z-index:3}.react-colorful__hue-pointer{z-index:2}`;var o=fa();o&&a.setAttribute(`nonce`,o),pa.set(r,a),i.appendChild(a)}}},[])},ha=function(e){var t=e.className,n=e.colorModel,r=e.color,i=r===void 0?n.defaultColor:r,a=e.onChange,o=e.onChangeEnd,s=Vi(e,[`className`,`colorModel`,`color`,`onChange`,`onChangeEnd`]),c=(0,F.useRef)(null);ma(c);var l=ua(n,i,a,o),u=l[0],d=l[1],f=l[2],p=Yi([`react-colorful`,t]);return F.createElement(`div`,Bi({},s,{ref:c,className:p}),F.createElement(sa,{hsva:u,onChange:d,onChangeEnd:f}),F.createElement(oa,{hue:u.h,onChange:d,onChangeEnd:f,className:`react-colorful__last-control`}))},ga={defaultColor:`000`,toHsva:Zi,fromHsva:function(e){return $i({h:e.h,s:e.s,v:e.v,a:1})},equal:la},_a=function(e){return F.createElement(ha,Bi({},e,{colorModel:ga}))},va={id:`bg-monet-source`,titleKey:`options.monetGroupBackgroundSource`},ya={id:`bg-monet-layout`,titleKey:`options.monetGroupLayoutPosition`},ba={id:`bg-monet-filters`,titleKey:`options.monetGroupFiltersPostProcessing`},xa={id:`bg-monet-tint`,titleKey:`options.monetGroupColorTintWash`},Sa=(e,t,n,r)=>Number.isFinite(e)?Math.min(n,Math.max(t,e)):r,Ca=e=>{let t=e.trim().replace(/^#/,``);return/^[0-9a-fA-F]{6}$/.test(t)?`#${t.toLowerCase()}`:null},wa=e=>(0,I.jsx)(`span`,{className:`absolute inset-0`,style:{backgroundImage:e===`full-overlay`?`linear-gradient(var(--st-t3), var(--st-t3))`:`linear-gradient(90deg, var(--st-t3) 30%, transparent 62%)`}}),Ta=({t:e,tuning:t=v,onTuningChange:n,monetBackgroundImage:r,onUploadMonetBackgroundImage:i,onClearMonetBackgroundImage:a,isLoadingMonetBackgroundImage:o=!1,onSliderPointerDown:s,onSliderCommit:c})=>{let l=(0,F.useRef)(null),[d,f]=(0,F.useState)(null),p={backgroundSource:t.backgroundSource??v.backgroundSource,backgroundLayout:t.backgroundLayout??v.backgroundLayout,backgroundBlurPx:Sa(t.backgroundBlurPx??v.backgroundBlurPx,0,60,v.backgroundBlurPx),backgroundOverlayOpacity:Sa(t.backgroundOverlayOpacity??v.backgroundOverlayOpacity,0,1,v.backgroundOverlayOpacity),backgroundGrayscale:Sa(t.backgroundGrayscale??v.backgroundGrayscale,0,1,v.backgroundGrayscale),backgroundSaturation:Sa(t.backgroundSaturation??v.backgroundSaturation,0,2,v.backgroundSaturation),backgroundWash:Sa(t.backgroundWash??v.backgroundWash,0,1,v.backgroundWash),backgroundHalfPaneOffsetX:Sa(t.backgroundHalfPaneOffsetX??v.backgroundHalfPaneOffsetX,-40,40,v.backgroundHalfPaneOffsetX),backgroundWashColorMode:t.backgroundWashColorMode??v.backgroundWashColorMode,backgroundWashCustomColor:Ca(t.backgroundWashCustomColor)??v.backgroundWashCustomColor,backgroundDriftEnabled:t.backgroundDriftEnabled??v.backgroundDriftEnabled,backgroundDriftStrength:Sa(t.backgroundDriftStrength??v.backgroundDriftStrength,0,1,v.backgroundDriftStrength),backgroundStreaksEnabled:t.backgroundStreaksEnabled??v.backgroundStreaksEnabled},h={onDragStart:s,onDragEnd:c},g=async t=>{let r=Array.from(t.target.files??[]);if(t.target.value=``,f(null),!r.length||!i)return;let a=await i(r);a.ok?(n?.({backgroundSource:`uploaded-global`}),f(r[0].name)):f(a.error||e(`options.monetUploadBackground`))};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsxs)(A,{def:va,children:[(0,I.jsx)(j,{label:e(`options.monetBackgroundSource`),children:(0,I.jsx)(pe,{value:p.backgroundSource,options:[{value:`cover-derived`,label:e(`options.monetBackgroundSourceCover`)},{value:`uploaded-global`,label:e(`options.monetBackgroundSourceUploaded`),disabled:!r&&!o}],onChange:e=>n?.({backgroundSource:e})})}),(0,I.jsxs)(j,{label:e(`options.monetUploadBackground`),hint:d||r?.name||`-`,children:[(0,I.jsx)(de,{icon:u,onClick:()=>l.current?.click(),disabled:o||!i,children:e(`options.monetUploadBackground`)}),(0,I.jsx)(de,{icon:m,onClick:()=>void a?.(),disabled:!r||!a,children:e(`options.monetClearBackground`)}),(0,I.jsx)(`input`,{ref:l,type:`file`,accept:`.png,.jpg,.jpeg,.gif,.webp,.svg,image/*`,className:`hidden`,onChange:e=>void g(e)})]})]}),(0,I.jsxs)(A,{def:ya,children:[(0,I.jsx)(j,{label:e(`options.monetBackgroundLayout`),below:(0,I.jsx)(he,{className:`-mx-4`,columns:4,label:e(`options.monetBackgroundLayout`),value:p.backgroundLayout,options:[{value:`half-pane-gradient`,label:e(`options.monetLayoutHalfPane`)},{value:`full-overlay`,label:e(`options.monetLayoutFullOverlay`)}],picture:wa,onChange:e=>n?.({backgroundLayout:e})})}),(0,I.jsx)(_e,{when:p.backgroundLayout===`half-pane-gradient`,children:(0,I.jsx)(P,{...h,sub:!0,label:e(`options.monetHalfPaneOffsetX`),value:p.backgroundHalfPaneOffsetX,min:-40,max:40,step:2,format:e=>`${Math.round(e)}%`,onChange:e=>n?.({backgroundHalfPaneOffsetX:e})})}),(0,I.jsx)(M,{label:e(`options.monetBackgroundDriftEnabled`),note:e(`options.monetBackgroundDriftEnabledDesc`),checked:p.backgroundDriftEnabled,onChange:e=>n?.({backgroundDriftEnabled:e})}),(0,I.jsx)(_e,{when:p.backgroundDriftEnabled,children:(0,I.jsx)(P,{...h,sub:!0,label:e(`options.monetBackgroundDriftStrength`),value:p.backgroundDriftStrength,min:0,max:1,step:.05,format:N,onChange:e=>n?.({backgroundDriftStrength:e})})})]}),(0,I.jsxs)(A,{def:ba,children:[(0,I.jsx)(P,{...h,label:e(`options.monetBackgroundBlur`),value:p.backgroundBlurPx,min:0,max:60,step:2,format:e=>`${Math.round(e)}px`,onChange:e=>n?.({backgroundBlurPx:e})}),(0,I.jsx)(P,{...h,label:e(`options.monetBackgroundSaturation`),value:p.backgroundSaturation,min:0,max:2,step:.05,format:N,onChange:e=>n?.({backgroundSaturation:e})}),(0,I.jsx)(P,{...h,label:e(`options.monetBackgroundGrayscale`),value:p.backgroundGrayscale,min:0,max:1,step:.02,format:N,onChange:e=>n?.({backgroundGrayscale:e})})]}),(0,I.jsxs)(A,{def:xa,children:[(0,I.jsx)(P,{...h,label:e(`options.monetBackgroundOverlayOpacity`),value:p.backgroundOverlayOpacity,min:0,max:1,step:.02,format:N,onChange:e=>n?.({backgroundOverlayOpacity:e})}),(0,I.jsx)(P,{...h,label:e(`options.monetBackgroundWash`),value:p.backgroundWash,min:0,max:1,step:.02,format:N,onChange:e=>n?.({backgroundWash:e})}),(0,I.jsx)(M,{label:e(`options.monetBackgroundStreaksEnabled`),note:e(`options.monetBackgroundStreaksEnabledDesc`),checked:p.backgroundStreaksEnabled,onChange:e=>n?.({backgroundStreaksEnabled:e})}),(0,I.jsx)(j,{label:e(`options.monetBackgroundWashColorMode`),children:(0,I.jsx)(pe,{value:p.backgroundWashColorMode,options:[{value:`theme`,label:e(`options.monetBackgroundWashTheme`)},{value:`custom`,label:e(`options.monetBackgroundWashCustom`)}],onChange:e=>n?.({backgroundWashColorMode:e})})}),(0,I.jsx)(_e,{when:p.backgroundWashColorMode===`custom`,children:(0,I.jsxs)(j,{sub:!0,label:e(`options.monetBackgroundWashCustomColor`),below:(0,I.jsx)(_a,{color:p.backgroundWashCustomColor,onChange:e=>n?.({backgroundWashCustomColor:e}),style:{width:`100%`,height:180}}),children:[(0,I.jsx)(`span`,{className:`h-4 w-4 rounded-full shadow-[0_0_0_1px_var(--st-line)]`,style:{backgroundColor:p.backgroundWashCustomColor}}),(0,I.jsx)(me,{children:p.backgroundWashCustomColor.toUpperCase()})]})})]})]})},Ea=1920,Da=1080,Oa={r:10,g:10,b:12},ka={r:245,g:245,b:245},Aa=(e,t,n)=>Math.min(n,Math.max(t,e)),Y=(e,t,n)=>e+(t-e)*n,ja=(e,t,n)=>.2126*e+.7152*t+.0722*n,Ma=(e,t)=>ja(e.r,e.g,e.b)<=ja(t.r,t.g,t.b)?{shadow:e,highlight:t}:{shadow:t,highlight:e},Na=(e,t,n,r)=>{let i=t.width,a=t.height;if(!i||!a)return;let o=Math.max(n/i,r/a),s=i*o,c=a*o,l=(n-s)/2,u=(r-c)/2;e.drawImage(t,l,u,s,c)},Pa=(e,t)=>{let n=T(e);return n?{r:Aa(n.r,0,255),g:Aa(n.g,0,255),b:Aa(n.b,0,255)}:t},Fa=(e,t,n,r)=>{let{shadow:i,highlight:a}=Ma(t,r);if(e<=.55){let t=e/.55;return{r:Y(i.r,n.r,t),g:Y(i.g,n.g,t),b:Y(i.b,n.b,t)}}let o=(e-.55)/.45;return{r:Y(n.r,a.r,o),g:Y(n.g,a.g,o),b:Y(n.b,a.b,o)}},Ia=(e,t,n,r,i)=>{let a=Aa(i.backgroundGrayscale,0,1),o=Aa(i.backgroundSaturation,0,2),s=Aa(i.backgroundWash,0,1);if(a<=0&&Math.abs(o-1)<.001&&s<=0)return;let c=e.getImageData(0,0,t,n),l=c.data,u=Pa(r.backgroundColor,Oa),d=Pa(r.accentColor,u),f=Pa(r.primaryColor,ka),p=Pa(i.backgroundWashCustomColor,d),m=i.backgroundWashColorMode===`custom`?p:d;for(let e=0;e<l.length;e+=4){let t=l[e],n=l[e+1],r=l[e+2];if(l[e+3]===0)continue;let i=ja(t,n,r);if(a>0&&(t=Y(t,i,a),n=Y(n,i,a),r=Y(r,i,a)),Math.abs(o-1)>=.001){let e=ja(t,n,r);t=e+(t-e)*o,n=e+(n-e)*o,r=e+(r-e)*o}if(s>0){let e=Fa(Aa(i/255,0,1),u,m,f);t=Y(t,e.r,s),n=Y(n,e.g,s),r=Y(r,e.b,s)}l[e]=Math.round(Aa(t,0,255)),l[e+1]=Math.round(Aa(n,0,255)),l[e+2]=Math.round(Aa(r,0,255))}e.putImageData(c,0,0)},La=(e,t,n,r,i)=>{let a=Aa(i.backgroundOverlayOpacity,0,1),o=e.createLinearGradient(0,0,t,n);o.addColorStop(0,O(r.accentColor,.08+a*.62)),o.addColorStop(.44,O(r.backgroundColor,.16+a*.58)),o.addColorStop(1,O(r.primaryColor,.06+a*.36)),e.fillStyle=o,e.fillRect(0,0,t,n);let s=e.createRadialGradient(t*.18,n*.34,0,t*.18,n*.34,t*.55);s.addColorStop(0,O(r.accentColor,a*.42)),s.addColorStop(1,O(r.backgroundColor,0)),e.fillStyle=s,e.fillRect(0,0,t,n);let c=e.createLinearGradient(t*.45,0,t,0);if(c.addColorStop(0,O(r.backgroundColor,0)),c.addColorStop(1,O(r.backgroundColor,.18+a*.38)),e.fillStyle=c,e.fillRect(0,0,t,n),i.backgroundStreaksEnabled!==!1){e.fillStyle=O(r.backgroundColor,.1+a*.08);for(let r=0;r<18;r+=1){let i=r*127%t,a=r*211%n-40;e.fillRect(i,a,1,n*.28)}}},Ra=(e,t,n,r,i)=>{let{width:a,height:o}=e.canvas;e.fillStyle=n.backgroundColor,e.fillRect(0,0,a,o),e.save(),i!==null&&(e.filter=`blur(${i}px)`),Na(e,t,a,o),e.restore(),Ia(e,a,o,n,r),La(e,a,o,n,r)},za=new Map,Ba=(e,t,n)=>Math.min(n,Math.max(t,e)),Va=({coverUrl:e,monetBackgroundImage:t,tuning:n})=>n.backgroundSource===`uploaded-global`?t?.url??e??null:e??t?.url??null,Ha=async e=>{let t=new Image;(e.startsWith(`http://`)||e.startsWith(`https://`))&&(t.crossOrigin=`anonymous`),t.decoding=`async`;let n=new Promise((n,r)=>{t.onload=()=>n(),t.onerror=()=>r(Error(`Failed to load image: ${e}`))});t.src=e;try{await t.decode()}catch{await n}return t},Ua=({coverUrl:e,monetBackgroundImage:t,theme:n,tuning:r})=>JSON.stringify({sourceUrl:Va({coverUrl:e,monetBackgroundImage:t,tuning:r}),uploadedId:r.backgroundSource===`uploaded-global`?t?.id??null:null,theme:{backgroundColor:n.backgroundColor,primaryColor:n.primaryColor,accentColor:n.accentColor},tuning:{backgroundSource:r.backgroundSource,backgroundBlurPx:r.backgroundBlurPx,backgroundOverlayOpacity:r.backgroundOverlayOpacity,backgroundGrayscale:r.backgroundGrayscale,backgroundSaturation:r.backgroundSaturation,backgroundWash:r.backgroundWash,backgroundWashColorMode:r.backgroundWashColorMode,backgroundWashCustomColor:r.backgroundWashCustomColor,backgroundStreaksEnabled:r.backgroundStreaksEnabled}}),Wa=null,Ga=()=>{if(Wa!==null)return Wa;if(typeof document>`u`)return!1;try{let e=document.createElement(`canvas`);e.width=2,e.height=2;let t=e.getContext(`2d`);return!t||typeof t.filter!=`string`?(Wa=!1,!1):(t.fillStyle=`#000000`,t.fillRect(0,0,2,2),t.filter=`blur(1px)`,t.fillStyle=`#ffffff`,t.fillRect(0,0,1,1),Wa=t.getImageData(1,1,1,1).data[0]>0,Wa)}catch{return Wa=!1,!1}},Ka=null,qa=0,Ja=null,Ya=[],Xa=()=>{for(;!Ja&&Ya.length>0;){let e=Ya.shift();if(!e.wanted()){e.request.image.close(),e.settle(void 0);continue}let t=qa+=1;Ja={...e,id:t};try{Qa().postMessage({...e.request,id:t},{transfer:[e.request.image]})}catch{Ja=null,e.request.image.close(),e.settle(null)}}},Za=e=>{let t=Ja;Ja=null,t?.settle(e),Xa()},Qa=()=>{if(Ka)return Ka;let e=new Worker(new URL(`/assets/monetBackground.worker-BdbhyxNv.js`,``+import.meta.url),{type:`module`});return e.onmessage=e=>{e.data.id===Ja?.id&&Za(`picture`in e.data?e.data.picture:null)},e.onerror=()=>{e.terminate(),Ka=null,Za(null)},Ka=e,e},$a=(e,t)=>new Promise(n=>{Ya.push({request:e,wanted:t,settle:n}),Xa()}),eo=(e,t,n,r)=>{try{let i=document.createElement(`canvas`);i.width=Ea,i.height=Da;let a=i.getContext(`2d`);return a?(Ra(a,e,t,n,r),new Promise(e=>i.toBlob(e,`image/jpeg`,.92))):Promise.resolve(null)}catch{return Promise.resolve(null)}},to=async(e,t,n,r)=>{try{return await eo(await createImageBitmap(e),t,n,r)}catch{let i=document.createElement(`canvas`);i.width=e.naturalWidth,i.height=e.naturalHeight;let a=i.getContext(`2d`);return!a||i.width<=0||i.height<=0?null:(a.drawImage(e,0,0),eo(i,t,n,r))}},no=async({coverUrl:e,monetBackgroundImage:t,theme:n,tuning:r},i)=>{let a=Va({coverUrl:e,monetBackgroundImage:t,tuning:r});if(!a)return null;let o={backgroundColor:n.backgroundColor,primaryColor:n.primaryColor,accentColor:n.accentColor},s=Ga()?Ba(r.backgroundBlurPx,0,60):null,c=await Ha(a),l,u=null;try{u=await createImageBitmap(c)}catch{u=null}if(u?(l=await $a({image:u,colors:o,tuning:r,blurPx:s},i),l===null&&i()&&(l=await to(c,o,r,s))):i()&&(l=await to(c,o,r,s)),!l)return l;let d=URL.createObjectURL(l),f=new Image;f.src=d;try{await f.decode()}catch(e){throw URL.revokeObjectURL(d),e}return d},ro=e=>{let t=Ua(e),n=za.get(t);if(!n){let r={url:Promise.resolve(null),holders:0};r.url=no(e,()=>r.holders>0||(za.get(t)===r&&za.delete(t),!1)).then(e=>e??null,()=>null),za.set(t,r),n=r}let r=n;r.holders+=1;let i=!1;return{url:r.url,release:()=>{i||(i=!0,--r.holders)}}},io=240,ao=76,oo=156,so=3.4,co=.035,lo=.01,uo=12.9898,fo=78.233,po=39.425,mo=(e,t)=>(e%t+t)%t,ho=(e,t)=>{let n=Math.sin(e*127.1+t*311.7)*43758.5453;return n-Math.floor(n)},go=e=>e*e*(3-2*e),_o=(e,t,n)=>{let r=Math.floor(e),i=ho(mo(r,t),n);return i+(ho(mo(r+1,t),n)-i)*go(e-r)},vo=(e,t)=>{let n=_o(e,ao,t),r=_o(e*2,152,t+17.31);return(n*.68+r*.32)*2-1},yo=e=>{let t=e.reduce((e,t)=>Math.max(e,Math.abs(t)),0);return t>0?e.map(e=>e/t):e},bo=e=>{let t=Math.min(1,Math.max(0,e)),n=so*t,r=1+n/100*2+lo,i=co*t,a=[],o=[],s=[];for(let e=0;e<=oo;e+=1){let t=ao*e/oo;a.push(vo(t,uo)),o.push(vo(t,fo)),s.push(vo(t,po))}let c=yo(a),l=yo(o),u=yo(s);return{keyframes:c.map((e,t)=>({transform:`translate3d(${(e*n).toFixed(4)}%, ${(l[t]*n).toFixed(4)}%, 0) scale(${(r+i*((u[t]+1)/2)).toFixed(5)})`})),durationMs:io*1e3,maxTravelPercent:n,minScale:r}},xo=180,So=(e,t,n)=>Math.min(n,Math.max(t,e)),Co=(e,t,n,r)=>{(0,F.useEffect)(()=>{let i=e.current;if(!i||!t||n<=0||typeof i.animate!=`function`||r)return;let a=bo(n),o=i.animate(a.keyframes,{duration:a.durationMs,iterations:1/0,easing:`linear`});return()=>o.cancel()},[t,e,n,r])},wo=(e,t,n)=>n.backgroundSource===`uploaded-global`?t?.url??e??null:e??t?.url??null,To=({coverUrl:e,monetBackgroundImage:n,theme:r,isDaylight:i=!1,tuning:a=v,transparentBackground:o=!1,staticMode:s=!1})=>{let[c,l]=(0,F.useState)(null),[u,d]=(0,F.useState)(!1),f=wo(e,n,a),p=st(),[m,h]=(0,F.useState)(null),g=(0,F.useRef)(null),_=(0,F.useMemo)(()=>`linear-gradient(135deg, ${O(r.accentColor,.22)}, ${O(r.backgroundColor,.96)} 50%, ${O(r.primaryColor,.18)})`,[r]),b=(0,F.useMemo)(()=>`linear-gradient(90deg, ${O(r.backgroundColor,.18)} 0%, ${O(r.backgroundColor,.32)} 34%, ${O(r.backgroundColor,.66)} 70%, ${O(r.backgroundColor,.82)} 100%)`,[r]),x=(0,F.useMemo)(()=>Ua({coverUrl:e,monetBackgroundImage:n,theme:r,tuning:a}),[e,n,r,a]);(0,F.useEffect)(()=>{let t=!1,i;if(!f||o)return l(null),d(!1),p(),()=>{t=!0};d(!0);let s={coverUrl:e,monetBackgroundImage:n,theme:r,tuning:a},c=f===g.current?null:ro(s),u=null;return i=window.setTimeout(()=>{u=ro(s),u.url.then(e=>{t||(l(t=>t===e?t:e),d(!1),g.current=f,e&&h(t=>t??e),p())})},xo),()=>{t=!0,i!==void 0&&window.clearTimeout(i),c?.release(),u?.release()}},[x,f,o,p]);let S=(0,F.useRef)(null),C=So(a.backgroundDriftStrength??0,0,1),w=!!a.backgroundDriftEnabled&&!s&&C>0&&!t();Co(S,w,C,y(`monetBackground`));let T=(0,F.useMemo)(()=>w?{willChange:`transform`}:void 0,[w]),E=(0,F.useMemo)(()=>Ga(),[])?0:a.backgroundBlurPx,D=(0,F.useMemo)(()=>E<=0?{}:{filter:`blur(${E}px)`,WebkitFilter:`blur(${E}px)`,transform:`scale(1.1) translateZ(0)`},[E]);if(o)return null;let ee=c?`url(${c})`:f?`linear-gradient(135deg, ${O(r.accentColor,.2)}, ${O(r.backgroundColor,.78)}), url(${f})`:_,te=u?{[Ge]:``}:{},k=c||f||`fallback`,ne=k!==m&&{opacity:0};if(a.backgroundLayout===`full-overlay`)return(0,I.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,...te,children:[(0,I.jsx)(`div`,{ref:S,className:`absolute inset-0`,style:T,children:(0,I.jsx)(le,{initial:!1,children:(0,I.jsx)(se.div,{initial:ne,animate:{opacity:1},exit:{opacity:0},transition:{duration:.8,ease:`easeInOut`},className:`absolute inset-0`,style:{backgroundColor:r.backgroundColor,backgroundImage:ee,backgroundSize:`cover`,backgroundPosition:`center`,...D}},k)})}),(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{background:b}})]});let re=(i?.7:.3)+So(a.backgroundOverlayOpacity,0,1)*.16,ie=So(50+a.backgroundHalfPaneOffsetX,10,90);return(0,I.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,...te,children:[(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundColor:r.backgroundColor,backgroundImage:_}}),(0,I.jsx)(le,{initial:!1,children:c||f?(0,I.jsx)(`div`,{className:`absolute inset-y-0 left-0 w-[72%] sm:w-[68%] lg:w-[60%] overflow-hidden`,style:{WebkitMaskImage:`linear-gradient(90deg, rgba(0,0,0,1) 0%, rgba(0,0,0,0.94) 48%, rgba(0,0,0,0.46) 74%, rgba(0,0,0,0) 100%)`,maskImage:`linear-gradient(90deg, rgba(0,0,0,1) 0%, rgba(0,0,0,0.94) 48%, rgba(0,0,0,0.46) 74%, rgba(0,0,0,0) 100%)`},children:(0,I.jsx)(`div`,{ref:S,className:`absolute inset-0`,style:T,children:(0,I.jsx)(se.div,{initial:ne,animate:{opacity:re},exit:{opacity:0},transition:{duration:.8,ease:`easeInOut`},className:`absolute inset-0`,style:{backgroundImage:ee,backgroundRepeat:`no-repeat`,backgroundSize:`cover`,backgroundPosition:`${ie}% center`,...D}},k)})}):null}),(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{background:`linear-gradient(90deg, ${O(r.backgroundColor,.14)} 0%, ${O(r.backgroundColor,.28)} 28%, ${O(r.backgroundColor,.62)} 64%, ${O(r.backgroundColor,.86)} 100%)`}}),(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundImage:`radial-gradient(circle at 18% 34%, ${O(r.accentColor,.18)}, transparent 36%)`,backgroundSize:`cover`,backgroundPosition:`center`}}),(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{background:b}})]})},Eo=e({default:()=>ko}),Do={"cover-derived":`options.monetBackgroundSourceCover`,"uploaded-global":`options.monetBackgroundSourceUploaded`},Oo=e=>e&&Ce(e),ko=Pe({mode:`monet`,order:20,labelKey:`options.visualizerBackgroundModeMonet`,labelFallback:`Monet`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`rect`,{x:`3.5`,y:`4.5`,width:`17`,height:`15`,rx:`2`}),(0,I.jsx)(`path`,{d:`M20.5 8.5L8 19.5`,opacity:`0.55`})]}),song:({config:e,coverUrl:t})=>[wo(Oo(t),e?.customImage,e?.monet?.tuning??v)],render:({config:e,coverUrl:t,theme:n,isDaylight:r,staticMode:i})=>(0,I.jsx)(To,{coverUrl:Oo(t),monetBackgroundImage:e?.customImage,theme:n,isDaylight:r,tuning:e?.monet?.tuning,transparentBackground:e?.transparent,staticMode:i}),renderSettingsPanel:({config:e,actions:t,t:n,onSliderPointerDown:r,onSliderCommit:i})=>(0,I.jsx)(Ta,{t:n,tuning:e?.monet?.tuning??v,onTuningChange:t?.monet?.onTuningChange,monetBackgroundImage:e?.customImage,onUploadMonetBackgroundImage:t?.customImage?.onUpload,onClearMonetBackgroundImage:t?.customImage?.onClear,isLoadingMonetBackgroundImage:t?.customImage?.isLoading,onSliderPointerDown:r,onSliderCommit:i}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.monet?.tuning??v,a=r.backgroundLayout===`full-overlay`,o=n(a?`options.monetLayoutFullOverlay`:`options.monetLayoutHalfPane`),c=e=>t?.monet?.onTuningChange?.(e),l=r.backgroundSource,u=n(Do[l]),d=!!e?.customImage;return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(Se,{label:o,title:`${n(`options.monetBackgroundLayout`)}: ${o}`,onClick:()=>c({backgroundLayout:a?`half-pane-gradient`:`full-overlay`})}),(0,I.jsx)(Se,{label:u,title:`${n(`options.monetBackgroundSource`)}: ${u}`,disabled:!d&&l===`cover-derived`,onClick:()=>c({backgroundSource:d&&l===`cover-derived`?`uploaded-global`:`cover-derived`})}),(0,I.jsx)(ye,{active:r.backgroundStreaksEnabled,label:n(`options.monetBackgroundStreaksEnabled`),onToggle:()=>c({backgroundStreaksEnabled:!r.backgroundStreaksEnabled}),children:(0,I.jsx)(i,{size:14})}),(0,I.jsx)(ye,{active:r.backgroundDriftEnabled,label:n(`options.monetBackgroundDriftEnabled`),onToggle:()=>c({backgroundDriftEnabled:!r.backgroundDriftEnabled}),children:(0,I.jsx)(s,{size:14})})]})},resetSettings:e=>e?.monet?.onResetTuning?.()}),Ao=1.8,jo=.01,Mo=16/9,No={fiberSize:.2,crumples:.35,crumpleSize:.35,folds:.65,foldCount:5,drops:.2,seed:5.8},Po={perspective:.4,count:20,focusCenter:.55,focusEdges:.8,swirl:.08,lensCircle:.1},Fo=e=>Math.min(1,Math.max(0,e)),Io=e=>Math.min(Ao,Math.max(1,e)),Lo=e=>e<=1?1:Io(e+jo),Ro=e=>Lo(1/(1-2*Math.min(Math.max(e,0),.45))),zo=(e,t,n)=>n&&!t?!e:e,Bo=(e,t,n)=>zo(!e,t,n),Vo=(e,t)=>{let{folds:n,crumples:r,drops:i}=No;return Ro(.02*(2*n+1.5*r+.2*i+.75*Fo(e)+.1*Fo(t)))},Ho=(e,t)=>{let n=.5*Math.hypot(Mo,1),r=Fo(t),i=.7*r**(1.3+2.7*r)*(1-Po.focusEdges),a=Math.max(.35,1-i/n);if(e<=0)return Lo(1/a);let o=Math.min(e,1)*1.4,s=e=>{let t=2*n/e;return Math.tan(t*o)/Math.tan(o)/t},c=Math.max(1,2*n*o/1.45);if(c>=Ao||s(Ao)>Ao*a)return Ao;if(c===1&&s(1)<=a)return Lo(1/a);let l=Ao;for(let e=0;e<32;e+=1){let e=(c+l)/2;s(e)>e*a?c=e:l=e}return Lo(l)},Uo=(e,t)=>{let n=st();(0,F.useEffect)(()=>{if(t===null){n();return}let r=0,i=()=>{r=requestAnimationFrame(e.current?.paperShaderMount?n:i)};return i(),()=>cancelAnimationFrame(r)},[e,t,n])},Wo=(e,t,n)=>n.imageSource===`uploaded-global`?t?.url??e:e??t?.url,Go=F.memo(({coverUrl:e,monetBackgroundImage:n,tuning:r,theme:i,isDaylight:a})=>{let o={...x,...r},s=Wo(e,n,o),c=(0,F.useRef)(null),l=(0,F.useMemo)(()=>Dr(c),[]),u=t()?l:c;return Uo(c,s?`${s}:${o.effect}`:null),s?(0,I.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,style:{backgroundColor:i.backgroundColor,pointerEvents:`none`},children:[(()=>{let e={width:`100%`,height:`100%`,ref:u,image:s,fit:`cover`,minPixelRatio:1,maxPixelCount:2073600,webGlContextAttributes:Er,style:{width:`100%`,height:`100%`}};switch(o.effect){case`fluted-glass`:return(0,I.jsx)(ur,{...e,colorBack:i.backgroundColor,colorShadow:i.secondaryColor,colorHighlight:i.primaryColor,shadows:.25,size:o.flutedGlassSize,distortion:o.flutedGlassDistortion,blur:o.flutedGlassBlur,shape:`lines`,distortionShape:`prism`,highlights:.1,edges:.25},`${s}:fluted-glass`);case`paper-texture`:return(0,I.jsx)(lr,{...e,...No,colorFront:i.accentColor,colorBack:i.backgroundColor,contrast:o.paperTextureContrast,roughness:o.paperTextureRoughness,fiber:o.paperTextureFiber,scale:Vo(o.paperTextureRoughness,o.paperTextureFiber)},`${s}:paper-texture`);case`halftone-dots`:return(0,I.jsx)(pr,{...e,colorBack:i.backgroundColor,colorFront:i.accentColor,size:o.halftoneDotsSize,radius:o.halftoneDotsRadius,contrast:o.halftoneDotsContrast,originalColors:o.halftoneDotsOriginalColors,inverted:Bo(o.halftoneDotsInverted,o.halftoneDotsOriginalColors,a),grid:`hex`,type:`gooey`,grainMixer:.12,grainOverlay:.06,grainSize:.5},`${s}:halftone-dots`);case`lens-distortion`:return(0,I.jsx)(fr,{...e,...Po,spread:o.lensDistortionSpread,dispersion:o.lensDistortionDispersion,lensBulge:o.lensDistortionBulge,scale:Ho(o.lensDistortionBulge,o.lensDistortionSpread)},`${s}:lens-distortion`);default:return(0,I.jsx)(dr,{...e,colorBack:i.backgroundColor,colorFront:i.accentColor,colorHighlight:i.primaryColor,originalColors:o.originalColors,inverted:zo(o.inverted,o.originalColors,a),type:o.ditheringType,size:o.size,colorSteps:o.colorSteps},`${s}:dithering`)}})(),o.overlayEnabled&&o.overlayOpacity>0&&(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundColor:i.backgroundColor,opacity:o.overlayOpacity}})]}):(0,I.jsx)(`div`,{className:`absolute inset-0 z-0`,style:{backgroundColor:i.backgroundColor}})}),Ko=[`2x2`,`4x4`,`8x8`],qo=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(j,{label:e(`options.nomandBackgroundDitheringType`),children:(0,I.jsx)(pe,{value:t.ditheringType,options:Ko.map(e=>({value:e,label:e})),onChange:e=>n?.({ditheringType:e})})}),(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundSize`),value:t.size,min:.5,max:20,step:.5,format:e=>e.toFixed(1),onChange:e=>n?.({size:e})}),(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundColorSteps`),value:t.colorSteps,min:1,max:7,step:1,format:e=>String(Math.round(e)),onChange:e=>n?.({colorSteps:e})}),(0,I.jsx)(M,{label:e(`options.nomandBackgroundOriginalColors`),checked:t.originalColors,onChange:e=>n?.({originalColors:e})}),(0,I.jsx)(M,{label:e(`options.nomandBackgroundInverted`),checked:t.inverted,onChange:e=>n?.({inverted:e})})]})},Jo=e=>e.toFixed(2),Yo=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundFlutedGlassSize`),value:t.flutedGlassSize,min:.1,max:1,step:.05,format:Jo,onChange:e=>n?.({flutedGlassSize:e})}),(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundFlutedGlassDistortion`),value:t.flutedGlassDistortion,min:0,max:1,step:.05,format:N,onChange:e=>n?.({flutedGlassDistortion:e})}),(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundFlutedGlassBlur`),value:t.flutedGlassBlur,min:0,max:1,step:.01,format:N,onChange:e=>n?.({flutedGlassBlur:e})})]})},Xo=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundHalftoneDotsSize`),value:t.halftoneDotsSize,min:.1,max:1,step:.05,format:Jo,onChange:e=>n?.({halftoneDotsSize:e})}),(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundHalftoneDotsRadius`),value:t.halftoneDotsRadius,min:.1,max:2,step:.05,format:Jo,onChange:e=>n?.({halftoneDotsRadius:e})}),(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundHalftoneDotsContrast`),value:t.halftoneDotsContrast,min:0,max:1,step:.05,format:N,onChange:e=>n?.({halftoneDotsContrast:e})}),(0,I.jsx)(M,{label:e(`options.nomandBackgroundOriginalColors`),checked:t.halftoneDotsOriginalColors,onChange:e=>n?.({halftoneDotsOriginalColors:e})}),(0,I.jsx)(M,{label:e(`options.nomandBackgroundInverted`),checked:t.halftoneDotsInverted,onChange:e=>n?.({halftoneDotsInverted:e})})]})},Zo=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundLensDistortionSpread`),value:t.lensDistortionSpread,min:0,max:1,step:.05,format:N,onChange:e=>n?.({lensDistortionSpread:e})}),(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundLensDistortionBulge`),value:t.lensDistortionBulge,min:-1,max:1,step:.05,format:Jo,onChange:e=>n?.({lensDistortionBulge:e})}),(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundLensDistortionDispersion`),value:t.lensDistortionDispersion,min:0,max:1,step:.05,format:N,onChange:e=>n?.({lensDistortionDispersion:e})})]})},Qo=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundPaperTextureContrast`),value:t.paperTextureContrast,min:0,max:1,step:.01,format:N,onChange:e=>n?.({paperTextureContrast:e})}),(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundPaperTextureRoughness`),value:t.paperTextureRoughness,min:0,max:1,step:.01,format:N,onChange:e=>n?.({paperTextureRoughness:e})}),(0,I.jsx)(P,{...a,label:e(`options.nomandBackgroundPaperTextureFiber`),value:t.paperTextureFiber,min:0,max:1,step:.05,format:N,onChange:e=>n?.({paperTextureFiber:e})})]})},$o={id:`bg-nomand-effect`,titleKey:`options.nomandBackgroundEffect`},es=[`dithering`,`fluted-glass`,`paper-texture`,`halftone-dots`,`lens-distortion`],ts={dithering:`options.nomandBackgroundEffectDithering`,"fluted-glass":`options.nomandBackgroundEffectFlutedGlass`,"paper-texture":`options.nomandBackgroundEffectPaperTexture`,"halftone-dots":`options.nomandBackgroundEffectHalftoneDots`,"lens-distortion":`options.nomandBackgroundEffectLensDistortion`},ns={dithering:{backgroundImage:`conic-gradient(var(--st-t2) 25%, transparent 0 50%, var(--st-t2) 0 75%, transparent 0)`,backgroundSize:`8px 8px`},"fluted-glass":{backgroundImage:`repeating-linear-gradient(90deg, transparent 0 2px, var(--st-t2) 5px, transparent 8px)`},"paper-texture":{backgroundImage:`repeating-linear-gradient(37deg, transparent 0 3px, var(--st-t3) 3px 4px), repeating-linear-gradient(-58deg, transparent 0 5px, var(--st-t3) 5px 6px)`},"halftone-dots":{backgroundImage:`radial-gradient(var(--st-t2) 32%, transparent 36%)`,backgroundSize:`8px 8px`},"lens-distortion":{backgroundImage:`radial-gradient(circle at 50% 50%, transparent 0 22%, var(--st-t2) 24% 28%, transparent 30% 46%, var(--st-t3) 48% 52%, transparent 54%)`}},rs=e=>(0,I.jsx)(`span`,{className:`absolute inset-0`,style:ns[e]}),is=e=>{let{t,tuning:n}=e;return(0,I.jsxs)(A,{def:$o,children:[(0,I.jsx)(j,{below:(0,I.jsx)(he,{className:`-mx-4`,columns:3,label:t(`options.nomandBackgroundEffect`),value:n.effect,options:es.map(e=>({value:e,label:t(ts[e])})),picture:rs,onChange:t=>e.onTuningChange?.({effect:t})})}),n.effect===`dithering`&&(0,I.jsx)(qo,{...e}),n.effect===`fluted-glass`&&(0,I.jsx)(Yo,{...e}),n.effect===`paper-texture`&&(0,I.jsx)(Qo,{...e}),n.effect===`halftone-dots`&&(0,I.jsx)(Xo,{...e}),n.effect===`lens-distortion`&&(0,I.jsx)(Zo,{...e})]})},as={id:`bg-nomand`,titleKey:`options.nomandBackgroundSettings`},os=({t:e,tuning:t,onTuningChange:n,monetBackgroundImage:r,onUploadMonetBackgroundImage:i,onClearMonetBackgroundImage:a,isLoadingMonetBackgroundImage:o=!1,onSliderPointerDown:s,onSliderCommit:l})=>{let u={...x,...t},d=(0,F.useRef)(null),[f,p]=(0,F.useState)(``),h=e=>{n?.({imageSource:e})},g=async t=>{if(!t.length||!i)return;let n=await i(t);p(n.ok?e(`options.nomandBackgroundUploadSuccess`):n.error??e(`options.nomandBackgroundUploadFailed`)),n.ok&&h(`uploaded-global`)};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsxs)(A,{def:as,children:[(0,I.jsx)(j,{label:e(`options.nomandBackgroundSource`),children:(0,I.jsx)(pe,{value:u.imageSource,options:[{value:`cover-derived`,label:e(`options.monetBackgroundSourceCover`)},{value:`uploaded-global`,label:e(`options.monetBackgroundSourceUploaded`),disabled:!r&&!o}],onChange:h})}),(0,I.jsxs)(j,{label:e(`options.monetUploadBackground`),hint:f||r?.name||`-`,children:[(0,I.jsx)(de,{icon:c,disabled:o||!i,onClick:()=>d.current?.click(),children:e(`options.monetUploadBackground`)}),(0,I.jsx)(de,{icon:m,disabled:!r||!a,onClick:()=>void a?.(),children:e(`options.monetClearBackground`)}),(0,I.jsx)(`input`,{ref:d,type:`file`,accept:`image/png,image/jpeg,image/webp,image/gif`,className:`hidden`,onChange:e=>{g(Array.from(e.target.files??[])),e.target.value=``}})]}),(0,I.jsx)(M,{label:e(`options.nomandBackgroundOverlay`),note:e(`options.nomandBackgroundOverlayDesc`),checked:u.overlayEnabled,onChange:e=>n?.({overlayEnabled:e})}),(0,I.jsx)(_e,{when:u.overlayEnabled,children:(0,I.jsx)(P,{sub:!0,label:e(`options.nomandBackgroundOverlayOpacity`),value:u.overlayOpacity,min:0,max:1,step:.05,format:N,onChange:e=>n?.({overlayOpacity:e}),onDragStart:s,onDragEnd:l})})]}),(0,I.jsx)(is,{t:e,tuning:u,onTuningChange:n,onSliderPointerDown:s,onSliderCommit:l})]})},ss=e({default:()=>us}),cs={"cover-derived":`options.monetBackgroundSourceCover`,"uploaded-global":`options.monetBackgroundSourceUploaded`},ls=e=>e&&Ce(e),us=Pe({mode:`nomand`,order:30,labelKey:`options.visualizerBackgroundModeNomand`,labelFallback:`Nomand`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`rect`,{x:`4`,y:`4`,width:`6.5`,height:`6.5`,rx:`0.8`}),(0,I.jsx)(`rect`,{x:`13.5`,y:`4`,width:`6.5`,height:`6.5`,rx:`0.8`,opacity:`0.45`}),(0,I.jsx)(`rect`,{x:`4`,y:`13.5`,width:`6.5`,height:`6.5`,rx:`0.8`,opacity:`0.45`}),(0,I.jsx)(`rect`,{x:`13.5`,y:`13.5`,width:`6.5`,height:`6.5`,rx:`0.8`})]}),command:{title:`Background: Nomand`,description:`Switch background to theme-colored image dithering`,keywords:[`nomand`,`dithering`,`dither`,`shader background`,`漫游`,`像素画`,`像素画背景`,`抖动背景`,`网点背景`,`主题色背景`]},song:({config:e,coverUrl:t})=>[Wo(ls(t),e?.customImage,{...x,...e?.nomand?.tuning})??null],render:({config:e,coverUrl:t,theme:n,isDaylight:r})=>(0,I.jsx)(Go,{coverUrl:ls(t),monetBackgroundImage:e?.customImage,tuning:e?.nomand?.tuning,theme:n,isDaylight:r}),renderSettingsPanel:({config:e,actions:t,...n})=>(0,I.jsx)(os,{...n,tuning:e?.nomand?.tuning??x,onTuningChange:t?.nomand?.onTuningChange,monetBackgroundImage:e?.customImage,onUploadMonetBackgroundImage:t?.customImage?.onUpload,onClearMonetBackgroundImage:t?.customImage?.onClear,isLoadingMonetBackgroundImage:t?.customImage?.isLoading}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.nomand?.tuning??x,i=e=>t?.nomand?.onTuningChange?.(e),o=r.imageSource,s=n(cs[o]),c=!!e?.customImage,l=n(ts[r.effect]);return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(Se,{label:s,title:`${n(`options.nomandBackgroundSource`)}: ${s}`,disabled:!c&&o===`cover-derived`,onClick:()=>i({imageSource:c&&o===`cover-derived`?`uploaded-global`:`cover-derived`})}),(0,I.jsx)(Se,{label:l,title:`${n(`options.nomandBackgroundEffect`)}: ${l}`,onClick:()=>i({effect:xe(es,r.effect)})}),(0,I.jsx)(ye,{active:r.overlayEnabled,label:n(`options.nomandBackgroundOverlay`),onToggle:()=>i({overlayEnabled:!r.overlayEnabled}),children:(0,I.jsx)(a,{size:14})})]})},resetSettings:e=>e?.nomand?.onResetTuning?.()}),ds=5120,fs=5121,ps=5122,ms=5123,hs=5124,gs=5125,_s=5126,vs=32819,ys=32820,bs=33635,xs=5131,Ss=33640,Cs=35899,ws=35902,Ts=36269,Es=34042,Ds={};{let e=Ds;e[ds]=Int8Array,e[fs]=Uint8Array,e[ps]=Int16Array,e[ms]=Uint16Array,e[hs]=Int32Array,e[gs]=Uint32Array,e[_s]=Float32Array,e[vs]=Uint16Array,e[ys]=Uint16Array,e[bs]=Uint16Array,e[xs]=Uint16Array,e[Ss]=Uint32Array,e[Cs]=Uint32Array,e[ws]=Uint32Array,e[Ts]=Uint32Array,e[Es]=Uint32Array}function Os(e){if(e instanceof Int8Array)return ds;if(e instanceof Uint8Array||e instanceof Uint8ClampedArray)return fs;if(e instanceof Int16Array)return ps;if(e instanceof Uint16Array)return ms;if(e instanceof Int32Array)return hs;if(e instanceof Uint32Array)return gs;if(e instanceof Float32Array)return _s;throw Error(`unsupported typed array type`)}function ks(e){if(e===Int8Array)return ds;if(e===Uint8Array||e===Uint8ClampedArray)return fs;if(e===Int16Array)return ps;if(e===Uint16Array)return ms;if(e===Int32Array)return hs;if(e===Uint32Array)return gs;if(e===Float32Array)return _s;throw Error(`unsupported typed array type`)}function As(e){let t=Ds[e];if(!t)throw Error(`unknown gl type`);return t}var js=typeof SharedArrayBuffer<`u`?function(e){return e&&e.buffer&&(e.buffer instanceof ArrayBuffer||e.buffer instanceof SharedArrayBuffer)}:function(e){return e&&e.buffer&&e.buffer instanceof ArrayBuffer};function Ms(...e){console.error(...e)}function Ns(...e){console.warn(...e)}var Ps=new Map;function Fs(e,t){if(!e||typeof e!=`object`)return!1;let n=Ps.get(t);n||(n=new WeakMap,Ps.set(t,n));let r=n.get(e);if(r===void 0){let i=Object.prototype.toString.call(e);r=i.substring(8,i.length-1)===t,n.set(e,r)}return r}function Is(e,t){return typeof WebGLBuffer<`u`&&Fs(t,`WebGLBuffer`)}function Ls(e,t){return typeof WebGLTexture<`u`&&Fs(t,`WebGLTexture`)}var Rs=35044,zs=34962,Bs=34963,Vs=34660,Hs=5120,Us=5121,Ws=5122,Gs=5123,Ks=5124,qs=5125,Js=5126,Ys={attribPrefix:``};function Xs(e,t,n,r,i){e.bindBuffer(t,n),e.bufferData(t,r,i||Rs)}function Zs(e,t,n,r){if(Is(e,t))return t;n||=zs;let i=e.createBuffer();return Xs(e,n,i,t,r),i}function Qs(e){return e===`indices`}function $s(e){return e===Int8Array||e===Uint8Array}function ec(e){return e.length?e:e.data}var tc=/coord|texture/i,nc=/color|colour/i;function rc(e,t){let n;if(n=tc.test(e)?2:nc.test(e)?4:3,t%n>0)throw Error(`Can not guess numComponents for attribute '${e}'. Tried ${n} but ${t} values is not evenly divisible by ${n}. You should specify it.`);return n}function ic(e,t,n){return e.numComponents||e.size||rc(t,n||ec(e).length)}function ac(e,t){if(js(e))return e;if(js(e.data))return e.data;Array.isArray(e)&&(e={data:e});let n=e.type?sc(e.type):void 0;return n||=Qs(t)?Uint16Array:Float32Array,new n(e.data)}function oc(e){return typeof e==`number`?e:e?ks(e):Js}function sc(e){return typeof e==`number`?As(e):e||Float32Array}function cc(e,t){return{buffer:t.buffer,numValues:24,type:oc(t.type),arrayType:sc(t.type)}}function lc(e,t){let n=t.data||t,r=sc(t.type),i=n*r.BYTES_PER_ELEMENT,a=e.createBuffer();return e.bindBuffer(zs,a),e.bufferData(zs,i,t.drawType||Rs),{buffer:a,numValues:n,type:ks(r),arrayType:r}}function uc(e,t,n){let r=ac(t,n);return{arrayType:r.constructor,buffer:Zs(e,r,void 0,t.drawType),type:Os(r),numValues:0}}function dc(e,t){let n={};return Object.keys(t).forEach(function(r){if(!Qs(r)){let i=t[r],a=i.attrib||i.name||i.attribName||Ys.attribPrefix+r;if(i.value){if(!Array.isArray(i.value)&&!js(i.value))throw Error(`array.value is not array or typedarray`);n[a]={value:i.value}}else{let t;t=i.buffer&&i.buffer instanceof WebGLBuffer?cc:typeof i==`number`||typeof i.data==`number`?lc:uc;let{buffer:o,type:s,numValues:c,arrayType:l}=t(e,i,r),u=i.normalize===void 0?$s(l):i.normalize,d=ic(i,r,c);n[a]={buffer:o,numComponents:d,type:s,normalize:u,stride:i.stride||0,offset:i.offset||0,divisor:i.divisor===void 0?void 0:i.divisor,drawType:i.drawType}}}}),e.bindBuffer(zs,null),n}function fc(e,t){return t===Hs||t===Us?1:t===Ws||t===Gs?2:t===Ks||t===qs||t===Js?4:0}var pc=[`position`,`positions`,`a_position`];function mc(e,t){let n,r=0;for(;r<pc.length&&(n=pc[r],!(n in t||(n=Ys.attribPrefix+n,n in t)));++r);r===pc.length&&(n=Object.keys(t)[0]);let i=t[n];if(!i.buffer)return 1;e.bindBuffer(zs,i.buffer);let a=e.getBufferParameter(zs,Vs);e.bindBuffer(zs,null);let o=a/fc(e,i.type),s=i.numComponents||i.size,c=o/s;if(c%1!=0)throw Error(`numComponents ${s} not correct for length ${length}`);return c}function hc(e,t,n){let r=dc(e,t),i=Object.assign({},n||{});i.attribs=Object.assign({},n?n.attribs:{},r);let a=t.indices;if(a){let t=ac(a,`indices`);i.indices=Zs(e,t,Bs),i.numElements=t.length,i.elementType=Os(t)}else i.numElements||=mc(e,i.attribs);return i}function gc(e){return!!e.texStorage2D}var _c=function(){let e={},t={};function n(n){let r=n.constructor.name;if(!e[r]){for(let e in n)if(typeof n[e]==`number`){let r=t[n[e]];t[n[e]]=r?`${r} | ${e}`:e}e[r]=!0}}return function(e,r){return n(e),t[r]||(typeof r==`number`?`0x${r.toString(16)}`:r)}}();new Uint8Array([128,192,255,255]);var vc=6406,yc=6407,bc=6408,xc=6409,Sc=6410,Cc=6402,wc=34041,Tc=33319,Ec=33320,Dc=6403,Oc=36244,kc=36248,Ac=36249,jc={};{let e=jc;e[vc]={numColorComponents:1},e[xc]={numColorComponents:1},e[Sc]={numColorComponents:2},e[yc]={numColorComponents:3},e[bc]={numColorComponents:4},e[Dc]={numColorComponents:1},e[Oc]={numColorComponents:1},e[Tc]={numColorComponents:2},e[Ec]={numColorComponents:2},e[yc]={numColorComponents:3},e[kc]={numColorComponents:3},e[bc]={numColorComponents:4},e[Ac]={numColorComponents:4},e[Cc]={numColorComponents:1},e[wc]={numColorComponents:2}}var Mc=Ms;function Nc(e){return typeof document<`u`&&document.getElementById?document.getElementById(e):null}var Pc=33984,Fc=34962,Ic=34963,Lc=35713,Rc=35714,zc=35632,Bc=35633,Vc=35981,Hc=35718,Uc=35721,Wc=35971,Gc=35382,Kc=35396,qc=35398,Jc=35392,Yc=35395,Xc=5126,Zc=35664,Qc=35665,$c=35666,el=5124,tl=35667,nl=35668,rl=35669,il=35670,al=35671,ol=35672,sl=35673,cl=35674,ll=35675,ul=35676,dl=35678,fl=35680,pl=35679,ml=35682,hl=35685,gl=35686,_l=35687,vl=35688,yl=35689,bl=35690,xl=36289,Sl=36292,Cl=36293,wl=5125,Tl=36294,El=36295,Dl=36296,Ol=36298,kl=36299,Al=36300,jl=36303,Ml=36306,Nl=36307,Pl=36308,Fl=36311,Il=3553,Ll=34067,Rl=32879,zl=35866,X={};function Bl(e,t){return X[t].bindPoint}function Vl(e,t){return function(n){e.uniform1f(t,n)}}function Hl(e,t){return function(n){e.uniform1fv(t,n)}}function Ul(e,t){return function(n){e.uniform2fv(t,n)}}function Wl(e,t){return function(n){e.uniform3fv(t,n)}}function Gl(e,t){return function(n){e.uniform4fv(t,n)}}function Kl(e,t){return function(n){e.uniform1i(t,n)}}function ql(e,t){return function(n){e.uniform1iv(t,n)}}function Jl(e,t){return function(n){e.uniform2iv(t,n)}}function Yl(e,t){return function(n){e.uniform3iv(t,n)}}function Xl(e,t){return function(n){e.uniform4iv(t,n)}}function Zl(e,t){return function(n){e.uniform1ui(t,n)}}function Ql(e,t){return function(n){e.uniform1uiv(t,n)}}function $l(e,t){return function(n){e.uniform2uiv(t,n)}}function eu(e,t){return function(n){e.uniform3uiv(t,n)}}function tu(e,t){return function(n){e.uniform4uiv(t,n)}}function nu(e,t){return function(n){e.uniformMatrix2fv(t,!1,n)}}function ru(e,t){return function(n){e.uniformMatrix3fv(t,!1,n)}}function iu(e,t){return function(n){e.uniformMatrix4fv(t,!1,n)}}function au(e,t){return function(n){e.uniformMatrix2x3fv(t,!1,n)}}function ou(e,t){return function(n){e.uniformMatrix3x2fv(t,!1,n)}}function su(e,t){return function(n){e.uniformMatrix2x4fv(t,!1,n)}}function cu(e,t){return function(n){e.uniformMatrix4x2fv(t,!1,n)}}function lu(e,t){return function(n){e.uniformMatrix3x4fv(t,!1,n)}}function uu(e,t){return function(n){e.uniformMatrix4x3fv(t,!1,n)}}function Z(e,t,n,r){let i=Bl(e,t);return gc(e)?function(t){let a,o;!t||Ls(e,t)?(a=t,o=null):(a=t.texture,o=t.sampler),e.uniform1i(r,n),e.activeTexture(Pc+n),e.bindTexture(i,a),e.bindSampler(n,o)}:function(t){e.uniform1i(r,n),e.activeTexture(Pc+n),e.bindTexture(i,t)}}function Q(e,t,n,r,i){let a=Bl(e,t),o=new Int32Array(i);for(let e=0;e<i;++e)o[e]=n+e;return gc(e)?function(t){e.uniform1iv(r,o),t.forEach(function(t,r){e.activeTexture(Pc+o[r]);let i,s;!t||Ls(e,t)?(i=t,s=null):(i=t.texture,s=t.sampler),e.bindSampler(n,s),e.bindTexture(a,i)})}:function(t){e.uniform1iv(r,o),t.forEach(function(t,n){e.activeTexture(Pc+o[n]),e.bindTexture(a,t)})}}X[Xc]={Type:Float32Array,size:4,setter:Vl,arraySetter:Hl},X[Zc]={Type:Float32Array,size:8,setter:Ul,cols:2},X[Qc]={Type:Float32Array,size:12,setter:Wl,cols:3},X[$c]={Type:Float32Array,size:16,setter:Gl,cols:4},X[el]={Type:Int32Array,size:4,setter:Kl,arraySetter:ql},X[tl]={Type:Int32Array,size:8,setter:Jl,cols:2},X[nl]={Type:Int32Array,size:12,setter:Yl,cols:3},X[rl]={Type:Int32Array,size:16,setter:Xl,cols:4},X[wl]={Type:Uint32Array,size:4,setter:Zl,arraySetter:Ql},X[Tl]={Type:Uint32Array,size:8,setter:$l,cols:2},X[El]={Type:Uint32Array,size:12,setter:eu,cols:3},X[Dl]={Type:Uint32Array,size:16,setter:tu,cols:4},X[il]={Type:Uint32Array,size:4,setter:Kl,arraySetter:ql},X[al]={Type:Uint32Array,size:8,setter:Jl,cols:2},X[ol]={Type:Uint32Array,size:12,setter:Yl,cols:3},X[sl]={Type:Uint32Array,size:16,setter:Xl,cols:4},X[cl]={Type:Float32Array,size:32,setter:nu,rows:2,cols:2},X[ll]={Type:Float32Array,size:48,setter:ru,rows:3,cols:3},X[ul]={Type:Float32Array,size:64,setter:iu,rows:4,cols:4},X[hl]={Type:Float32Array,size:32,setter:au,rows:2,cols:3},X[gl]={Type:Float32Array,size:32,setter:su,rows:2,cols:4},X[_l]={Type:Float32Array,size:48,setter:ou,rows:3,cols:2},X[vl]={Type:Float32Array,size:48,setter:lu,rows:3,cols:4},X[yl]={Type:Float32Array,size:64,setter:cu,rows:4,cols:2},X[bl]={Type:Float32Array,size:64,setter:uu,rows:4,cols:3},X[dl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Il},X[fl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Ll},X[pl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Rl},X[ml]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Il},X[xl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:zl},X[Sl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:zl},X[Cl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Ll},X[Ol]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Il},X[kl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Rl},X[Al]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Ll},X[jl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:zl},X[Ml]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Il},X[Nl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Rl},X[Pl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:Ll},X[Fl]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:zl};function du(e,t){return function(n){if(n.value)switch(e.disableVertexAttribArray(t),n.value.length){case 4:e.vertexAttrib4fv(t,n.value);break;case 3:e.vertexAttrib3fv(t,n.value);break;case 2:e.vertexAttrib2fv(t,n.value);break;case 1:e.vertexAttrib1fv(t,n.value);break;default:throw Error(`the length of a float constant value must be between 1 and 4!`)}else e.bindBuffer(Fc,n.buffer),e.enableVertexAttribArray(t),e.vertexAttribPointer(t,n.numComponents||n.size,n.type||Xc,n.normalize||!1,n.stride||0,n.offset||0),e.vertexAttribDivisor&&e.vertexAttribDivisor(t,n.divisor||0)}}function fu(e,t){return function(n){if(n.value){if(e.disableVertexAttribArray(t),n.value.length===4)e.vertexAttrib4iv(t,n.value);else throw Error(`The length of an integer constant value must be 4!`)}else e.bindBuffer(Fc,n.buffer),e.enableVertexAttribArray(t),e.vertexAttribIPointer(t,n.numComponents||n.size,n.type||el,n.stride||0,n.offset||0),e.vertexAttribDivisor&&e.vertexAttribDivisor(t,n.divisor||0)}}function pu(e,t){return function(n){if(n.value){if(e.disableVertexAttribArray(t),n.value.length===4)e.vertexAttrib4uiv(t,n.value);else throw Error(`The length of an unsigned integer constant value must be 4!`)}else e.bindBuffer(Fc,n.buffer),e.enableVertexAttribArray(t),e.vertexAttribIPointer(t,n.numComponents||n.size,n.type||wl,n.stride||0,n.offset||0),e.vertexAttribDivisor&&e.vertexAttribDivisor(t,n.divisor||0)}}function mu(e,t,n){let r=n.size,i=n.count;return function(n){e.bindBuffer(Fc,n.buffer);let a=n.size||n.numComponents||r,o=a/i,s=n.type||Xc,c=X[s].size*a,l=n.normalize||!1,u=n.offset||0,d=c/i;for(let r=0;r<i;++r)e.enableVertexAttribArray(t+r),e.vertexAttribPointer(t+r,o,s,l,c,u+d*r),e.vertexAttribDivisor&&e.vertexAttribDivisor(t+r,n.divisor||0)}}var $={};$[Xc]={size:4,setter:du},$[Zc]={size:8,setter:du},$[Qc]={size:12,setter:du},$[$c]={size:16,setter:du},$[el]={size:4,setter:fu},$[tl]={size:8,setter:fu},$[nl]={size:12,setter:fu},$[rl]={size:16,setter:fu},$[wl]={size:4,setter:pu},$[Tl]={size:8,setter:pu},$[El]={size:12,setter:pu},$[Dl]={size:16,setter:pu},$[il]={size:4,setter:fu},$[al]={size:8,setter:fu},$[ol]={size:12,setter:fu},$[sl]={size:16,setter:fu},$[cl]={size:4,setter:mu,count:2},$[ll]={size:9,setter:mu,count:3},$[ul]={size:16,setter:mu,count:4};var hu=/ERROR:\s*\d+:(\d+)/gi;function gu(e,t=``,n=0){let r=[...t.matchAll(hu)],i=new Map(r.map((e,n)=>{let i=parseInt(e[1]),a=r[n+1],o=a?a.index:t.length,s=t.substring(e.index,o);return[i-1,s]}));return e.split(`
`).map((e,t)=>{let r=i.get(t);return`${t+1+n}: ${e}${r?`\n\n^^^ ${r}`:``}`}).join(`
`)}var _u=/^[ \t]*\n/;function vu(e){let t=0;return _u.test(e)&&(t=1,e=e.replace(_u,``)),{lineOffset:t,shaderSource:e}}function yu(e,t){return e.errorCallback(t),e.callback&&setTimeout(()=>{e.callback(`${t}\n${e.errors.join(`
`)}`)}),null}function bu(e,t,n,r){if(r||=Mc,!e.getShaderParameter(n,Lc)){let i=e.getShaderInfoLog(n),{lineOffset:a,shaderSource:o}=vu(e.getShaderSource(n)),s=`${gu(o,i,a)}\nError compiling ${_c(e,t)}: ${i}`;return r(s),s}return``}function xu(e,t,n){let r,i,a;if(typeof t==`function`&&(n=t,t=void 0),typeof e==`function`)n=e,e=void 0;else if(e&&!Array.isArray(e)){let t=e;n=t.errorCallback,e=t.attribLocations,r=t.transformFeedbackVaryings,i=t.transformFeedbackMode,a=t.callback}let o=n||Mc,s=[],c={errorCallback(e,...t){s.push(e),o(e,...t)},transformFeedbackVaryings:r,transformFeedbackMode:i,callback:a,errors:s};{let n={};Array.isArray(e)?e.forEach(function(e,r){n[e]=t?t[r]:r}):n=e||{},c.attribLocations=n}return c}var Su=[`VERTEX_SHADER`,`FRAGMENT_SHADER`];function Cu(e,t){if(t.indexOf(`frag`)>=0)return zc;if(t.indexOf(`vert`)>=0)return Bc}function wu(e,t,n){let r=e.getAttachedShaders(t);for(let t of r)n.has(t)||e.deleteShader(t);e.deleteProgram(t)}var Tu=(e=0)=>new Promise(t=>setTimeout(t,e));function Eu(e,t,n){let r=e.createProgram(),{attribLocations:i,transformFeedbackVaryings:a,transformFeedbackMode:o}=xu(n);for(let n=0;n<t.length;++n){let i=t[n];if(typeof i==`string`){let t=Nc(i),r=t?t.text:i,a=e[Su[n]];t&&t.type&&(a=Cu(e,t.type)||a),i=e.createShader(a),e.shaderSource(i,vu(r).shaderSource),e.compileShader(i)}e.attachShader(r,i)}Object.entries(i).forEach(([t,n])=>e.bindAttribLocation(r,n,t));{let t=a;t&&(t.attribs&&(t=t.attribs),Array.isArray(t)||(t=Object.keys(t)),e.transformFeedbackVaryings(r,t,o||Vc))}return e.linkProgram(r),r}function Du(e,t,n,r,i){let a=xu(n,r,i),o=new Set(t),s=Eu(e,t,a);function c(e,t){let n=ku(e,t,a.errorCallback);return n&&wu(e,t,o),n}if(a.callback){Ou(e,s).then(()=>{let t=c(e,s);a.callback(t,t?void 0:s)});return}return c(e,s)?void 0:s}async function Ou(e,t){let n=e.getExtension(`KHR_parallel_shader_compile`),r=n?(e,t)=>e.getProgramParameter(t,n.COMPLETION_STATUS_KHR):()=>!0,i=0;do await Tu(i),i=1e3/60;while(!r(e,t))}function ku(e,t,n){if(n||=Mc,!e.getProgramParameter(t,Rc)){let r=e.getProgramInfoLog(t);return n(`Error in program linking: ${r}`),`${r}\n${e.getAttachedShaders(t).map(t=>bu(e,e.getShaderParameter(t,e.SHADER_TYPE),t,n)).filter(e=>e).join(`
`)}`}}function Au(e,t,n,r,i){return Du(e,t,n,r,i)}function ju(e){let t=e.name;return t.startsWith(`gl_`)||t.startsWith(`webgl_`)}var Mu=/(\.|\[|]|\w+)/g,Nu=e=>e>=`0`&&e<=`9`;function Pu(e,t,n,r){let i=e.split(Mu).filter(e=>e!==``),a=0,o=``;for(;;){let e=i[a++];o+=e;let s=Nu(e[0]),c=s?parseInt(e):e;if(s&&(o+=i[a++]),a===i.length){n[c]=t;break}{let e=i[a++],t=e===`[`,s=n[c]||(t?[]:{});n[c]=s,n=s,r[o]=r[o]||function(e){return function(t){Ru(e,t)}}(s),o+=e}}}function Fu(e,t){let n=0;function r(t,r,i){let a=r.name.endsWith(`[0]`),o=r.type,s=X[o];if(!s)throw Error(`unknown type: 0x${o.toString(16)}`);let c;if(s.bindPoint){let t=n;n+=r.size,c=a?s.arraySetter(e,o,t,i,r.size):s.setter(e,o,t,i,r.size)}else c=s.arraySetter&&a?s.arraySetter(e,i):s.setter(e,i);return c.location=i,c}let i={},a={},o=e.getProgramParameter(t,Hc);for(let n=0;n<o;++n){let o=e.getActiveUniform(t,n);if(ju(o))continue;let s=o.name;s.endsWith(`[0]`)&&(s=s.substr(0,s.length-3));let c=e.getUniformLocation(t,o.name);if(c){let e=r(t,o,c);i[s]=e,Pu(s,e,a,i)}}return i}function Iu(e,t){let n={},r=e.getProgramParameter(t,Wc);for(let i=0;i<r;++i){let r=e.getTransformFeedbackVarying(t,i);n[r.name]={index:i,type:r.type,size:r.size}}return n}function Lu(e,t){let n=e.getProgramParameter(t,Hc),r=[],i=[];for(let a=0;a<n;++a){i.push(a),r.push({});let n=e.getActiveUniform(t,a);r[a].name=n.name}[[`UNIFORM_TYPE`,`type`],[`UNIFORM_SIZE`,`size`],[`UNIFORM_BLOCK_INDEX`,`blockNdx`],[`UNIFORM_OFFSET`,`offset`]].forEach(function(n){let a=n[0],o=n[1];e.getActiveUniforms(t,i,e[a]).forEach(function(e,t){r[t][o]=e})});let a={},o=e.getProgramParameter(t,Gc);for(let n=0;n<o;++n){let r=e.getActiveUniformBlockName(t,n),i={index:e.getUniformBlockIndex(t,r),usedByVertexShader:e.getActiveUniformBlockParameter(t,n,Kc),usedByFragmentShader:e.getActiveUniformBlockParameter(t,n,qc),size:e.getActiveUniformBlockParameter(t,n,Jc),uniformIndices:e.getActiveUniformBlockParameter(t,n,Yc)};i.used=i.usedByVertexShader||i.usedByFragmentShader,a[r]=i}return{blockSpecs:a,uniformData:r}}function Ru(e,t){for(let n in t){let r=e[n];typeof r==`function`?r(t[n]):Ru(e[n],t[n])}}function zu(e,...t){let n=e.uniformSetters||e,r=t.length;for(let e=0;e<r;++e){let r=t[e];if(Array.isArray(r)){let e=r.length;for(let t=0;t<e;++t)zu(n,r[t])}else for(let e in r){let t=n[e];t&&t(r[e])}}}function Bu(e,t){let n={},r=e.getProgramParameter(t,Uc);for(let i=0;i<r;++i){let r=e.getActiveAttrib(t,i);if(ju(r))continue;let a=e.getAttribLocation(t,r.name),o=$[r.type],s=o.setter(e,a,o);s.location=a,n[r.name]=s}return n}function Vu(e,t){for(let n in t){let r=e[n];r&&r(t[n])}}function Hu(e,t,n){n.vertexArrayObject?e.bindVertexArray(n.vertexArrayObject):(Vu(t.attribSetters||t,n.attribs),n.indices&&e.bindBuffer(Ic,n.indices))}function Uu(e,t){let n=Fu(e,t),r=Bu(e,t),i={program:t,uniformSetters:n,attribSetters:r,uniformLocations:Object.fromEntries(Object.entries(n).map(([e,t])=>[e,t.location])),attribLocations:Object.fromEntries(Object.entries(r).map(([e,t])=>[e,t.location]))};return gc(e)&&(i.uniformBlockSpec=Lu(e,t),i.transformFeedbackInfo=Iu(e,t)),i}var Wu=/\s|{|}|;/;function Gu(e,t,n,r,i){let a=xu(n,r,i),o=[];if(t=t.map(function(e){if(!Wu.test(e)){let t=Nc(e);if(t)e=t.text;else{let t=`no element with id: ${e}`;a.errorCallback(t),o.push(t)}}return e}),o.length)return yu(a,``);let s=a.callback;s&&(a.callback=(t,n)=>{s(t,t?void 0:Uu(e,n))});let c=Au(e,t,a);return c?Uu(e,c):null}var Ku=4,qu=5123;function Ju(e,t,n,r,i,a){n=n===void 0?Ku:n;let o=t.indices,s=t.elementType,c=r===void 0?t.numElements:r;i=i===void 0?0:i,s||o?a===void 0?e.drawElements(n,c,s===void 0?qu:t.elementType,i):e.drawElementsInstanced(n,c,s===void 0?qu:t.elementType,i,a):a===void 0?e.drawArrays(n,i,c):e.drawArraysInstanced(n,i,c,a)}var Yu=6402,Xu=33190,Zu=36012,Qu=35056,$u=36013,ed=32854,td=32855,nd=36194,rd=33189,id=6401,ad=36168,od=34041,sd=36096,cd=36128,ld=33306,ud={};ud[od]=ld,ud[id]=cd,ud[ad]=cd,ud[Yu]=sd,ud[rd]=sd,ud[Xu]=sd,ud[Zu]=sd,ud[Qu]=ld,ud[$u]=ld;var dd={};dd[ed]=!0,dd[td]=!0,dd[nd]=!0,dd[od]=!0,dd[rd]=!0,dd[id]=!0,dd[ad]=!0;var fd={addExtensionsToContext:!0},pd=/^(.*?)_/;function md(e,t){_c(e,0);let n=e.getExtension(t);if(n){let r={},i=pd.exec(t)[1],a=`_`+i;for(let t in n){let o=n[t],s=typeof o==`function`,c=s?i:a,l=t;t.endsWith(c)&&(l=t.substring(0,t.length-c.length)),e[l]===void 0?s?e[l]=function(e){return function(){return e.apply(n,arguments)}}(o):(e[l]=o,r[l]=o):!s&&e[l]!==o&&Ns(l,e[l],o,t)}r.constructor={name:n.constructor.name},_c(r,0)}return n}var hd=`ANGLE_instanced_arrays.EXT_blend_minmax.EXT_color_buffer_float.EXT_color_buffer_half_float.EXT_disjoint_timer_query.EXT_disjoint_timer_query_webgl2.EXT_frag_depth.EXT_sRGB.EXT_shader_texture_lod.EXT_texture_compression_bptc.EXT_texture_compression_rgtc.EXT_texture_filter_anisotropic.OES_element_index_uint.OES_standard_derivatives.OES_texture_float.OES_texture_float_linear.OES_texture_half_float.OES_texture_half_float_linear.OES_vertex_array_object.WEBGL_color_buffer_float.WEBGL_compressed_texture_atc.WEBGL_compressed_texture_etc1.WEBGL_compressed_texture_etc.WEBGL_compressed_texture_pvrtc.WEBGL_compressed_texture_s3tc.WEBGL_compressed_texture_s3tc_srgb.WEBGL_depth_texture.WEBGL_draw_buffers`.split(`.`);function gd(e){for(let t=0;t<hd.length;++t)md(e,hd[t])}function _d(e,t){let n=[`webgl2`,`webgl`,`experimental-webgl`],r=null;for(let i=0;i<n.length;++i)if(r=e.getContext(n[i],t),r){fd.addExtensionsToContext&&gd(r);break}return r}function vd(e,t){return _d(e,t)}function yd(e,t){t||=1,t=Math.max(0,t);let n=e.clientWidth*t|0,r=e.clientHeight*t|0;return e.width!==n||e.height!==r?(e.width=n,e.height=r,!0):!1}var bd=150,xd=`
attribute float a_index;
uniform vec2 u_resolution;
uniform float u_time;
varying float v_color_type;
varying float v_intensity_base;

float hash2(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void main() {
  float seed = a_index * 123.456;
  
  float speed_rand = hash2(vec2(seed, 1.1));
  float size_rand = hash2(vec2(seed, 2.2));
  float y_rand = hash2(vec2(seed, 3.3));
  float x_rand = hash2(vec2(seed, 4.4));
  float blink_rand = hash2(vec2(seed, 5.5));
  float color_type_rand = hash2(vec2(seed, 6.6));

  float aspect = u_resolution.x / u_resolution.y;
  float speed = 0.008 + speed_rand * 0.024;
  float size = 0.0006 + 0.0032 * pow(size_rand, 3.8);
  
  float y = -0.45 + y_rand * 0.9;
  
  float margin = 0.05;
  float width = aspect + margin * 2.0;
  float x = fract(x_rand + u_time * speed);
  x = x * width - (aspect * 0.5 + margin);
  
  float wave = sin(u_time * 0.3 + y_rand * 6.283) * 0.005;
  
  float ndc_x = x / (aspect * 0.5);
  float ndc_y = (y + wave) / 0.5;
  
  gl_Position = vec4(ndc_x, ndc_y, 0.0, 1.0);
  
  // Point size in pixels. 
  float pointSize = size * u_resolution.y * 3.5;
  gl_PointSize = max(2.0, pointSize);
  
  float blink = 0.3 + 0.7 * sin(u_time * (1.0 + blink_rand * 2.5) + x_rand * 6.283);
  v_intensity_base = blink;
  v_color_type = color_type_rand;
}
`,Sd=`
precision mediump float;
uniform vec3 u_particle_color;
uniform vec3 u_particle_accent_color;

varying float v_color_type;
varying float v_intensity_base;

void main() {
  vec2 pc = gl_PointCoord - 0.5;
  float dist = length(pc);
  
  float alpha = smoothstep(0.5, 0.1, dist) * v_intensity_base;
  if (alpha < 0.01) discard;
  
  vec3 baseColor = v_color_type > 0.90 ? u_particle_accent_color : u_particle_color;
  
  // Pre-multiplied alpha blending
  gl_FragColor = vec4(baseColor * alpha, alpha);
}
`,Cd=({theme:e,isDaylight:n,paused:r=!1,blendMs:i=0,blendProgress:a})=>{let o=(0,F.useRef)(null),s=(0,F.useRef)(null),c=(0,F.useRef)(0),l=(0,F.useRef)(null),[u,d]=ht([e.primaryColor,e.accentColor],i,a),f=T(u)||(n?{r:0,g:0,b:0}:{r:255,g:255,b:255}),p=[f.r/255,f.g/255,f.b/255],m=T(d)||f,h=[m.r/255,m.g/255,m.b/255],g=n?[1,1,1]:[0,0,0],_=(0,F.useRef)(r),v=(0,F.useRef)(p),y=(0,F.useRef)(h),b=(0,F.useRef)(g);return _.current=r,v.current=p,y.current=h,b.current=g,(0,F.useEffect)(()=>{let e=o.current;if(!e)return;let n=vd(e,{alpha:!1,depth:!1,antialias:!1});if(!n)return;let r=Gu(n,[xd,Sd],e=>{console.error(`SoraBackground twgl program error:`,e)});if(!r)return;let i=new Float32Array(bd);for(let e=0;e<bd;e++)i[e]=e;let a=hc(n,{a_index:{numComponents:1,data:i}}),u=null,d=()=>{s.current===null&&(s.current=requestAnimationFrame(f))},f=t=>{if(s.current=null,!_.current&&u!==null){let e=(t-u)/1e3;c.current+=e}u=_.current?null:t,yd(e),n.viewport(0,0,n.canvas.width,n.canvas.height);let i=b.current;n.clearColor(i[0],i[1],i[2],1),n.clear(n.COLOR_BUFFER_BIT),n.enable(n.BLEND),n.blendFunc(n.ONE,n.ONE_MINUS_SRC_ALPHA);let o={u_resolution:[n.canvas.width,n.canvas.height],u_time:c.current,u_particle_color:v.current,u_particle_accent_color:y.current};n.useProgram(r.program),Hu(n,r,a),zu(r,o),Ju(n,a,n.POINTS),_.current||d()},p=new ResizeObserver(d);return p.observe(e),l.current=d,d(),()=>{l.current=null,p.disconnect(),s.current!==null&&(cancelAnimationFrame(s.current),s.current=null),n.deleteProgram(r.program),a.attribs&&a.attribs.a_index&&a.attribs.a_index.buffer&&n.deleteBuffer(a.attribs.a_index.buffer),t()&&!n.isContextLost()&&n.getExtension(`WEBGL_lose_context`)?.loseContext()}},[]),(0,F.useEffect)(()=>{l.current?.()},[r,n,u,d]),(0,I.jsx)(`canvas`,{ref:o,className:`absolute inset-0 w-full h-full block pointer-events-none`,style:{width:`100%`,height:`100%`,willChange:`transform`,transform:`translateZ(0)`}})},wd={id:`bg-sora`,titleKey:`options.soraBackgroundSettings`},Td=({t:e,tuning:t,onTuningChange:n})=>(0,I.jsx)(A,{def:wd,children:(0,I.jsx)(M,{label:e(`options.soraBlank`),note:e(`options.soraBlankDesc`),checked:t.blank,onChange:e=>n?.({blank:e})})}),Ed=e({default:()=>Dd}),Dd=Pe({mode:`sora`,order:50,labelKey:`options.visualizerBackgroundModeSora`,labelFallback:`Sora`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`path`,{d:`M12 5.5l1.2 2.9 2.9 1.2-2.9 1.2L12 13.7l-1.2-2.9-2.9-1.2 2.9-1.2z`}),(0,I.jsx)(`path`,{d:`M5.5 16.5h.01M18 15.5h.01M7 7h.01`,strokeWidth:`2.2`,opacity:`0.5`})]}),command:{title:`Background: Sora`,description:`Switch background to Sora (starry sky) layout`,keywords:[`sora`,`starry sky`,`star`,`星空`,`空`,`背景切换到 空`,`背景切换到空`,`背景切换到Sora`,`背景切换到星空`]},render:({config:e,theme:t,isDaylight:n,paused:r,staticMode:i,blendMs:a,blendProgress:o})=>(0,I.jsx)(`div`,{className:`absolute inset-0 z-0`,style:{backgroundColor:n?`#ffffff`:`#000000`},children:!e?.sora?.tuning?.blank&&(0,I.jsx)(Cd,{theme:t,isDaylight:n,paused:r||i,blendMs:a,blendProgress:o})}),renderSettingsPanel:({config:e,actions:t,t:n})=>(0,I.jsx)(Td,{t:n,tuning:e?.sora?.tuning??b,onTuningChange:t?.sora?.onTuningChange}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.sora?.tuning??b;return(0,I.jsx)(ye,{active:r.blank,label:n(`options.soraBlank`),onToggle:()=>t?.sora?.onTuningChange?.({blank:!r.blank}),children:(0,I.jsx)(d,{size:14})})},resetSettings:e=>e?.sora?.onResetTuning?.()}),Od=({urlBackgroundList:e=[],urlBackgroundSelectedId:t=null})=>{let n=(0,F.useMemo)(()=>be(e.find(e=>e.id===t)),[e,t]),r=(0,F.useRef)(null),[i,a]=(0,F.useState)(!1);return(0,F.useEffect)(()=>{a(!1);let e=r.current;if(!e)return;let t=e.getBoundingClientRect();if(t.width>0&&t.height>0){a(!0);return}let n=new ResizeObserver(e=>{for(let t of e){let{width:e,height:r}=t.contentRect;e>0&&r>0&&(a(!0),n.disconnect())}});return n.observe(e),()=>{n.disconnect()}},[n]),n?.url?(0,I.jsxs)(`div`,{ref:r,className:`absolute inset-0 z-0 overflow-hidden`,children:[i&&(0,I.jsx)(`iframe`,{src:n.url,title:n.note||n.url,className:`w-full h-full border-0`,style:{pointerEvents:`none`},sandbox:`allow-scripts`,allowFullScreen:!0},n.url),(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{background:`linear-gradient(to bottom, rgba(0,0,0,0.15), rgba(0,0,0,0.35))`,pointerEvents:`none`}})]}):null},kd={id:`bg-url`,titleKey:`options.urlBackgroundSettings`},Ad=()=>`url-bg-${Date.now()}-${Math.random().toString(36).slice(2,8)}`,jd=({t:e,urlBackgroundList:t=[],urlBackgroundSelectedId:n=null,onAddUrlBackgroundItem:r,onUpdateUrlBackgroundItem:i,onDeleteUrlBackgroundItem:a,onSetUrlBackgroundSelectedId:s})=>{let[c,l]=(0,F.useState)(!1),[u,d]=(0,F.useState)(null),[f,p]=(0,F.useState)(``),[g,_]=(0,F.useState)(``),v=(0,F.useCallback)(()=>{p(``),_(``),l(!1),d(null)},[]),y=(0,F.useCallback)(()=>{let e=ve(f);if(!e)return;let t={id:Ad(),url:e,note:g.trim()||e};r?.(t),s?.(t.id),v()},[f,g,r,s,v]),b=(0,F.useCallback)(e=>{l(!1),d(e.id),p(e.url),_(e.note)},[]),x=(0,F.useCallback)(()=>{if(!u)return;let e=ve(f);e&&(i?.(u,{url:e,note:g.trim()||e}),v())},[u,f,g,i,v]),S=t=>(0,I.jsx)(j,{below:(0,I.jsxs)(`div`,{className:`flex flex-col gap-2 [&>input]:w-full`,children:[(0,I.jsx)(ge,{type:`url`,value:f,onChange:p,placeholder:`https://example.com`}),(0,I.jsx)(ge,{value:g,onChange:_,placeholder:e(`options.urlBackgroundNotePlaceholder`)}),(0,I.jsxs)(`div`,{className:`flex justify-end gap-2`,children:[(0,I.jsx)(de,{onClick:v,children:e(`ui.cancel`)}),(0,I.jsx)(de,{variant:`primary`,onClick:t,disabled:!f.trim(),children:e(`options.save`)})]})]})});return(0,I.jsxs)(A,{def:kd,foot:e(`options.urlBackgroundSettingsDesc`),children:[t.map(t=>u===t.id?(0,I.jsx)(F.Fragment,{children:S(x)},t.id):(0,I.jsxs)(j,{label:(0,I.jsxs)(`button`,{type:`button`,role:`radio`,"aria-checked":t.id===n,onClick:()=>s?.(t.id),className:`flex w-full min-w-0 items-center gap-2.5 rounded text-left`,children:[(0,I.jsx)(`span`,{"aria-hidden":!0,className:`st-t-fast h-4 w-4 shrink-0 rounded-full transition-shadow ${t.id===n?`shadow-[inset_0_0_0_5px_var(--st-accent)]`:`shadow-[inset_0_0_0_1.5px_var(--st-t3)]`}`}),(0,I.jsxs)(`span`,{className:`min-w-0`,children:[(0,I.jsx)(`span`,{className:`block truncate`,children:t.note}),(0,I.jsx)(`span`,{className:`block truncate text-xs leading-[18px] text-[color:var(--st-t2)]`,children:t.url})]})]}),children:[(0,I.jsx)(de,{icon:o,tip:e(`options.urlBackgroundEdit`),onClick:()=>b(t)}),(0,I.jsx)(de,{icon:m,tip:e(`options.urlBackgroundDelete`),onClick:()=>a?.(t.id)})]},t.id)),c?S(y):(0,I.jsx)(j,{label:t.length===0?(0,I.jsx)(fe,{children:e(`options.urlBackgroundEmpty`)}):void 0,children:(0,I.jsx)(de,{icon:h,onClick:()=>{d(null),p(``),_(``),l(!0)},children:e(`options.urlBackgroundAdd`)})})]})},Md=e({default:()=>Nd}),Nd=Pe({mode:`url`,order:40,labelKey:`options.visualizerBackgroundModeUrl`,labelFallback:`Embed`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`rect`,{x:`3.5`,y:`5`,width:`17`,height:`14`,rx:`2`}),(0,I.jsx)(`path`,{d:`M3.5 9.5h17`,opacity:`0.55`})]}),command:{title:`Background: Embedded Background`,description:`Switch background to embedded webpage mode`,keywords:[`embedded background`,`embed background`,`background embed`,`background url`,`url background`,`url`,`webpage`,`嵌入背景`,`网页背景`,`背景切换到 嵌入背景`,`背景切换到嵌入背景`]},render:({config:e})=>(0,I.jsx)(Od,{urlBackgroundList:e?.url?.items,urlBackgroundSelectedId:e?.url?.selectedId}),renderSettingsPanel:({config:e,actions:t,...n})=>(0,I.jsx)(jd,{...n,urlBackgroundList:e?.url?.items,urlBackgroundSelectedId:e?.url?.selectedId,onAddUrlBackgroundItem:t?.url?.onAdd,onUpdateUrlBackgroundItem:t?.url?.onUpdate,onDeleteUrlBackgroundItem:t?.url?.onDelete,onSetUrlBackgroundSelectedId:t?.url?.onSelect})}),{entries:Pd,byMode:Fd}=(e=>{let t=Object.entries(e).map(([e,t])=>{if(!t.default)throw Error(`[VisualizerBackgroundRegistry] Missing default export in ${e}`);return t.default}),n={};return t.forEach(e=>{if(n[e.mode])throw Error(`[VisualizerBackgroundRegistry] Duplicate background mode "${e.mode}"`);n[e.mode]=e}),{entries:[...t].sort((e,t)=>e.order-t.order),byMode:n}})(Object.assign({"./common/entry.tsx":pn,"./latent/entry.tsx":Pi,"./monet/entry.tsx":Eo,"./nomand/entry.tsx":ss,"./sora/entry.tsx":Ed,"./url/entry.tsx":Md}));ee(`VisualizerBackgroundRegistry`,Pd.map(e=>e.mode),w);var Id=e=>typeof e==`string`&&!!Fd[e],Ld=e=>Fd[e]??Fd.latent,Rd=(e,t)=>{let n=Ld(e),r=t(n.labelKey);return!r||r===n.labelKey?n.labelFallback:r},zd=e=>!Fd[e.mode]&&(Fd[e.mode]=e,Pd.push(e),Pd.sort((e,t)=>e.order-t.order),!0),Bd=e=>{if(!Fd[e])return!1;delete Fd[e];let t=Pd.findIndex(t=>t.mode===e);return t>=0&&Pd.splice(t,1),!0},Vd=e=>typeof e!=`number`||!Number.isFinite(e)?null:Math.round(Math.min(900,Math.max(100,e))/10)*10,Hd=(e,t)=>Vd(e?.fontWeight)??t,Ud=`"獅尾四季春加糖SC"`,Wd={sans:`"Inter", "Noto Sans CJK SC", "Noto Sans JP", "Source Han Sans SC", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Helvetica Neue", Arial, sans-serif`,serif:`${Ud}, "Iowan Old Style", "Noto Serif CJK SC", "Noto Serif JP", "Source Han Serif SC", "Songti SC", "STSong", "Georgia", serif`,mono:`"IBM Plex Mono", "Sarasa Mono SC", "Noto Sans Mono CJK SC", "Noto Sans Mono", "SFMono-Regular", Consolas, monospace`},Gd={sans:`system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", "Inter", "Helvetica Neue", Arial, "Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans JP", "Source Han Sans JP", "Hiragino Sans", "Yu Gothic", Meiryo, sans-serif`,serif:`${Ud}, "Folia Noto Serif SC", "Iowan Old Style", Georgia, "Times New Roman", "Noto Serif CJK SC", "Source Han Serif SC", "Songti SC", "STSong", "SimSun", "Noto Serif JP", "Source Han Serif JP", "Yu Mincho", "MS PMincho", serif`,mono:`Consolas, "IBM Plex Mono", "SFMono-Regular", Menlo, Monaco, "Sarasa Mono SC", "Noto Sans Mono CJK SC", "SimHei", "DengXian", "Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans Mono CJK JP", "MS Gothic", monospace`},Kd=new Set([`serif`,`sans-serif`,`monospace`,`cursive`,`fantasy`,`system-ui`,`ui-serif`,`ui-sans-serif`,`ui-monospace`,`ui-rounded`,`emoji`,`math`,`fangsong`]),qd=e=>`"${e.replace(/["\\]/g,`\\$&`)}"`,Jd=e=>e.trim().replace(/^['"]|['"]$/g,``).trim(),Yd=e=>{let t=Jd(e);return t?Kd.has(t.toLowerCase())?t:qd(t):null},Xd=e=>{let t=new Set,n=[];return e?.forEach(e=>{let r=Jd(e??``);if(!r)return;let i=r.toLocaleLowerCase();t.has(i)||(t.add(i),n.push(r))}),n},Zd=e=>{let t=[...e.fontFamily?[e.fontFamily]:[],...e.fontFamilyStack??[]];return t.length===0?[]:Xd(t).map(Yd).filter(e=>!!e)},Qd=e=>Wd[e]??Wd.sans,$d=e=>{let t=Qd(e.fontStyle),n=Zd(e);return n.length===0?t:`${n.join(`, `)}, ${t}`},ef=e=>{let t=Gd[e.fontStyle]??Gd.sans,n=Zd(e);return n.length===0?t:`${n.join(`, `)}, ${t}`},tf=typeof window>`u`?new URLSearchParams:new URLSearchParams(window.location.search),nf=typeof window<`u`&&(tf.get(`obs`)===`1`||window.location.pathname===`/obs`),rf=tf.get(`obsSource`),af=!nf&&tf.get(`remote`)===`1`,of=typeof window<`u`&&!nf&&!af,sf=e=>{let t=new Set;return{subscribe:e=>(t.add(e),()=>t.delete(e)),notify:()=>{t.forEach(t=>{try{t()}catch(t){console.warn(`[Folium] ${e} failed`,t)}})}}},cf=e=>{let t=(0,F.useRef)(null);return t.current??=sf(e),t.current},lf=(e,t)=>{let n=(0,F.useRef)(!1);(0,F.useEffect)(()=>{if(!n.current){n.current=!0;return}e.notify()},t)},uf=/^[a-z0-9][a-z0-9-]*$/,df=(e,t)=>`${e}:${t}`,ff=(e,t={})=>{let n=new Map,r=sf(`${e} listener`),i=Object.freeze([]),a=()=>{i=Object.freeze(Array.from(n.values())),r.notify()},o=r=>{let i=n.get(r);if(i){n.delete(r);try{t.onRemove?.(i)}catch(t){console.warn(`[Folium] ${e}: removing ${r} failed`,t)}a()}};return{name:e,register:(r,i)=>{if(!i||typeof i!=`object`||typeof i.id!=`string`||!uf.test(i.id))throw Error(`[Folium] ${e}.register: id must match /^[a-z0-9][a-z0-9-]*$/`);let s=df(r,i.id);if(n.has(s))throw Error(`[Folium] ${e}.register: duplicate id "${s}"`);let c=t.validate?t.validate(i,{modId:r,id:s}):i,l={id:s,modId:r,name:i.id,def:c};n.set(s,l);try{t.onAdd?.(l)}catch(e){throw n.delete(s),e}return a(),Object.freeze({id:s,unregister:()=>{n.get(s)===l&&o(s)}})},unregister:o,unregisterAll:e=>{Array.from(n.values()).filter(t=>t.modId===e).forEach(e=>o(e.id))},get:e=>n.get(e)??null,list:()=>i,subscribe:r.subscribe}},pf=e=>(0,F.useSyncExternalStore)(e.subscribe,e.list,e.list),mf=[`player.stage.back`,`player.stage.front`,`app.overlay`],hf=ff(`stageLayers`,{validate:e=>{if(!mf.includes(e.slot))throw Error(`stageLayers.register: slot must be one of ${mf.join(`, `)}`);if(typeof e.mount!=`function`)throw Error(`stageLayers.register: mount must be a function`);return e}}),gf=F.lazy(()=>r(()=>import(`./stageLayerView-BbbKxV6Q.js`),__vite__mapDeps([2,1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27]))),_f=e=>pf(hf).some(t=>t.def.slot===e.slot)?(0,I.jsx)(F.Suspense,{fallback:null,children:(0,I.jsx)(gf,{...e})}):null,vf=Object.freeze({top:0,right:0,bottom:0,left:0}),yf=(e,t)=>{if(![e.left,e.top,e.width,e.height].every(Number.isFinite))return null;let n=Math.max(t.left,e.left),r=Math.max(t.top,e.top),i=Math.min(t.left+t.width,e.left+e.width),a=Math.min(t.top+t.height,e.top+e.height);return i<=n||a<=r?null:Object.freeze({left:n,top:r,width:i-n,height:a-r})},bf=(e,t,n=vf)=>{let r=new Map;for(let n of t){let t=yf(n.rect,e);if(!t)continue;let i=r.get(n.key),a=i?{left:Math.min(i.rect.left,t.left),top:Math.min(i.rect.top,t.top),width:Math.max(i.rect.left+i.rect.width,t.left+t.width)-Math.min(i.rect.left,t.left),height:Math.max(i.rect.top+i.rect.height,t.top+t.height)-Math.min(i.rect.top,t.top)}:t;r.set(n.key,Object.freeze({role:n.role,kind:n.kind,rect:Object.freeze(a)}))}let i=(e,t)=>Number.isFinite(e)?Math.min(Math.max(0,e),t):0,a=i(n.top,e.height),o=i(n.left,e.width);return Object.freeze({bounds:Object.freeze({left:e.left,top:e.top,width:e.width,height:e.height}),insets:Object.freeze({top:a,left:o,right:i(n.right,e.width-o),bottom:i(n.bottom,e.height-a)}),obstacles:Object.freeze([...r.entries()].sort(([e],[t])=>e.localeCompare(t)).map(([,e])=>e))})},xf=(e,t)=>{if(e===t)return!0;if(!e||!t||e.obstacles.length!==t.obstacles.length)return!1;let n=(e,t)=>e.left===t.left&&e.top===t.top&&e.width===t.width&&e.height===t.height;return n(e.bounds,t.bounds)&&[`top`,`right`,`bottom`,`left`].every(n=>e.insets[n]===t.insets[n])&&e.obstacles.every((e,r)=>{let i=t.obstacles[r];return e.role===i.role&&e.kind===i.kind&&n(e.rect,i.rect)})},Sf=(()=>{let e=null,t=null,n=null,r=vf,i,a,o=new Map,s=new Set,c=()=>{let i=e?.isConnected?e.getBoundingClientRect():null,a=i&&i.width>0&&i.height>0?bf(i,[...o.values()].flatMap(({read:e})=>{let t=e(i);return t?[t]:[]}),r):null;return t===e&&xf(n,a)?!1:(t=e,n=a,!0)},l=()=>{if(c())for(let e of[...s])try{e()}catch(e){console.warn(`[Folium] layout subscriber failed`,e)}},u=()=>{s.size&&i===void 0&&(e||n!==null)&&(i=setTimeout(()=>{i=void 0,l()},80))},d=()=>{if(a?.disconnect(),window.removeEventListener(`resize`,u),window.removeEventListener(`scroll`,u,!0),!e||!s.size){a=void 0;return}!a&&typeof ResizeObserver<`u`&&(a=new ResizeObserver(u)),a?.observe(e);for(let e of o.values())e.element&&a?.observe(e.element);window.addEventListener(`resize`,u),window.addEventListener(`scroll`,u,!0)};return{source:{get:()=>!e?.isConnected||!s.size?null:t===e?n:null,subscribe:e=>{s.add(e),s.size===1&&d(),u();let r=!1;return()=>{r||(r=!0,s.delete(e),s.size||(clearTimeout(i),i=void 0,d(),n=null,t=null))}}},invalidate:u,registerRoot:(t,n=vf)=>(e=t,r={...n},d(),u(),()=>{e===t&&(e=null),d(),u()}),register:(e,t)=>{let n=Symbol();return o.set(n,{element:e,read:t}),d(),u(),()=>{o.delete(n),d(),u()}}}})();export{ar as $,Qr as A,ti as B,Id as C,rt as Ct,Xr as D,$r as E,ii as F,fi as G,Kr as H,di as I,kr as J,Or as K,ui as L,qr as M,oi as N,li as O,si as P,xr as Q,Zr as R,Ld as S,it as St,_a as T,Ne as Tt,Yr as U,ei as V,ai as W,Cr as X,Tr as Y,wr as Z,Hd as _,ct as _t,ff as a,wn as at,zd as b,We as bt,cf as c,Yt as ct,nf as d,Xt as dt,er as et,af as f,$t as ft,$d as g,ot as gt,Vd as h,dt as ht,hf as i,An as it,ri as j,ci as k,lf as l,Jt as lt,Xd as m,ft as mt,vf as n,jn as nt,df as o,nn as ot,rf as p,Zt as pt,Mr as q,_f as r,Tn as rt,pf as s,Qt as st,Sf as t,R as tt,of as u,Ht as ut,ef as v,st as vt,Bd as w,et as wt,Rd as x,at as xt,Pd as y,Ge as yt,ni as z};