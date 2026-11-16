import{n as e,r as t}from"./rolldown-runtime-hePW80VL.js";import{$ as n,Nn as r,Or as i,Tr as a,_ as o,jn as s,jt as c,l,r as u,rt as d,s as f,zt as p}from"./lucide-icons-215fvYlr.js";import{d as m,g as h,l as g,s as _}from"./types-DqG-aH3a.js";import{d as v,rt as y}from"./themeColorMath-BH3_qby6.js";import{C as b,D as x,O as S,T as C,b as w,c as T,h as E,m as D,n as O,r as k,t as A,u as j}from"./panelRows-DNeHeKwZ.js";import{t as ee}from"./jsx-runtime-NZYk81nU.js";import{n as te,t as ne}from"./use-spring-B0g0yG2C.js";import{a as re}from"./kitTheme-BzV3UEc0.js";import{n as ie,r as ae,t as M}from"./colorMix-08vn8-lY.js";import{a as oe,i as se,n as ce,r as le,t as ue}from"./QuickControlChip-CheEYNQX.js";import{t as de}from"./iosWebKit-Cy3ahWcF.js";import{a as fe,t as pe}from"./visualizerModes-fSl480P8.js";import{n as me}from"./beatEffects-B1QX-wnr.js";import{a as he,c as ge,n as _e,r as ve,t as ye}from"./lucideIconResolver-BUvw6suk.js";import{c as be,d as xe,g as Se,h as N,i as P,l as Ce,m as we,n as Te,o as Ee,p as De,r as Oe,s as ke,t as Ae,u as je}from"./paperShaderUniforms-BAb2sxq2.js";import{n as Me}from"./colorExtractor-B7kaSA5M.js";import{i as Ne,o as Pe}from"./motionSignals-Ab6l3BOb.js";import{p as Fe,t as Ie}from"./beatFxLive-BBWGHrll.js";import{t as Le}from"./dist-CcgEeink.js";import{i as Re}from"./coverUrl-rJwTH6xF.js";var F=t(i(),1),I=ee(),ze=e=>e,Be={id:`bg-common`,titleKey:`options.visualizerBackgroundModeCommon`},Ve={id:`bg-common-cover`,titleKey:`options.previewCoverBackgroundSettings`},He=({config:e,actions:t,t:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a=e?.common,o=t?.common,s=a?.useCoverColorBg??!1;return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsxs)(b,{def:Be,bare:!0,children:[(0,I.jsx)(O,{label:n(`options.disableVisualizerVignette`),note:n(`options.disableVisualizerVignetteDesc`),checked:a?.disableVignette??!1,onChange:e=>o?.onDisableVignetteChange?.(e)}),(0,I.jsx)(O,{label:n(`options.disableVisualizerGeometricBackground`),note:n(`options.disableVisualizerGeometricBackgroundDesc`),checked:a?.disableGeometricBackground??!1,onChange:e=>o?.onDisableGeometricChange?.(e)})]}),(0,I.jsxs)(b,{def:Ve,children:[(0,I.jsx)(O,{label:n(`theme.addCoverColor`),note:n(`options.coverColorBackgroundDesc`),checked:s,onChange:e=>o?.onCoverColorChange?.(e)}),(0,I.jsx)(S,{when:s,children:(0,I.jsx)(A,{sub:!0,label:n(`options.previewCoverBackgroundOpacity`),value:a?.opacity??.75,min:0,max:1,step:.05,format:k,onChange:e=>o?.onOpacityChange?.(e),onDragStart:r,onDragEnd:i})})]})]})},Ue=384,We=160,Ge=350,Ke=1e3,qe=1e3,Je=4e3,Ye=`data-picture-wait`,Xe=`data-picture-arriving`,Ze={width:64,height:40},L=null,Qe=e=>{if(!L){let e=document.createElement(`canvas`);e.width=Ze.width,e.height=Ze.height,L=e.getContext(`2d`,{willReadFrequently:!0}),L&&(L.imageSmoothingQuality=`high`)}if(!L)return!1;try{L.clearRect(0,0,Ze.width,Ze.height),L.drawImage(e,0,0,Ze.width,Ze.height);let t=new Uint32Array(L.getImageData(0,0,Ze.width,Ze.height).data.buffer);return t.every(e=>e===t[0])}catch{return L=null,!1}},$e=e=>[...e.querySelectorAll(`canvas`)].filter(e=>e.width>0&&e.height>0).map(e=>({canvas:e,blank:Qe(e)})),et=60,tt=e=>[...e.querySelectorAll(`*`)].slice(0,et).some(e=>{let t=getComputedStyle(e);return!!t.backgroundImage&&t.backgroundImage!==`none`&&t.opacity!==`0`&&e.offsetWidth>0&&e.offsetHeight>0}),nt=e=>{if(!e.firstElementChild||e.querySelector(`[data-picture-wait]`))return{shows:!1,whole:!1,waits:!1};let t=$e(e),n=t.every(e=>!e.blank),r=t.some(e=>!e.blank)||!!e.textContent?.trim()||e.querySelector(`svg, img`)!==null,i=!r&&tt(e),a=e.querySelector(`[${Xe}]`)!==null;return{shows:r||i,whole:n,waits:a||i&&!n}},rt=e=>e.getAnimations({subtree:!0}).some(e=>e.playState===`running`&&Number.isFinite(Number(e.effect?.getComputedTiming().endTime))),it=(e,t,n)=>{let r=performance.now(),i=r,a=0,o=0,s=0,c=new MutationObserver(()=>{i=performance.now()});t===`still`&&c.observe(e,{subtree:!0,childList:!0,attributes:!0,characterData:!0});let l=()=>{c.disconnect(),window.clearTimeout(o),window.cancelAnimationFrame(s)},u=()=>{o=window.setTimeout(()=>{s=window.requestAnimationFrame(f)})},d=()=>{let n=performance.now(),{shows:o,whole:s,waits:c}=nt(e),l=o&&!c;return l&&!a&&(a=n),l&&(s||n-a>=qe)&&(t===`drawn`||n-a>=Ge&&(n-i>=We&&!rt(e)||n-a>=Ke))?`shown`:n-r>=Je?o?`shown`:`empty`:null},f=()=>{let e;try{e=d()}catch(t){console.warn(`[LivePicture] A stage could not be read:`,t),e=`failed`}if(e){l(),n(e);return}u()};return u(),l},at=(e,t,n=Math.min(e.width,Ue))=>{t.width=Math.max(1,n),t.height=Math.max(1,Math.round(e.height*n/Math.max(1,e.width)));let r=t.getContext(`2d`);r&&(r.imageSmoothingQuality=`high`,r.drawImage(e,0,0,t.width,t.height))},ot=e=>e.replace(/[A-Z]/g,e=>`-${e.toLowerCase()}`),st=e=>{if(!nt(e).shows)return null;let t=e.cloneNode(!0),n=t.querySelectorAll(`canvas`);e.querySelectorAll(`canvas`).forEach((e,t)=>{let r=n[t];r.style.width=`${e.offsetWidth}px`,r.style.height=`${e.offsetHeight}px`,e.width>0&&e.height>0&&at(e,r)});let r=[...e.querySelectorAll(`*`)],i=t.querySelectorAll(`*`);i.forEach(e=>{e.style.willChange=`auto`});for(let t of e.getAnimations({subtree:!0})){let e=t.effect,n=e?.target&&!e.pseudoElement?i[r.indexOf(e.target)]:void 0;if(!e?.target||!n)continue;let a=getComputedStyle(e.target);for(let t of e.getKeyframes())for(let e of Object.keys(t))e!==`offset`&&e!==`computedOffset`&&e!==`easing`&&e!==`composite`&&n.style.setProperty(ot(e),a.getPropertyValue(ot(e)));n.style.animation=`none`}return t},ct=e=>{let t=new Set(e.querySelectorAll(`canvas`)),n=e=>{for(let n of e)n.addedNodes.forEach(e=>{e instanceof HTMLCanvasElement?t.add(e):e instanceof Element&&e.querySelectorAll(`canvas`).forEach(e=>t.add(e))})},r=new MutationObserver(n);return r.observe(e,{subtree:!0,childList:!0}),()=>{n(r.takeRecords()),r.disconnect();for(let e of t)try{if(e.getContext(`2d`))continue;let t=e.getContext(`webgl2`)??e.getContext(`webgl`);t&&!t.isContextLost()&&t.getExtension(`WEBGL_lose_context`)?.loseContext()}catch{}}},lt=e=>{let t=e.cloneNode(!0),n=t.querySelectorAll(`canvas`);return e.querySelectorAll(`canvas`).forEach((e,t)=>{e.width>0&&e.height>0&&at(e,n[t],e.width)}),t},ut=(0,F.createContext)(null),dt=()=>{let e=(0,F.useContext)(ut);return(0,F.useLayoutEffect)(()=>{e?.claim()},[e]),(0,F.useCallback)(()=>e?.drawn(),[e])},ft=(0,F.createContext)(!1),pt=()=>(0,F.useContext)(ft),mt=e=>Math.max(0,Math.min(1,e)),ht=(e,t)=>t>=1?1:mt((e-t)/(1-t)),gt=e=>1-(1-e)**3,_t=(e,t)=>e.length===t.length&&e.every((e,n)=>e===t[n]),vt=(e,t,n)=>{let r=e.join(`|`),i=(0,F.useMemo)(()=>r.split(`|`),[r]),[a,o]=(0,F.useState)(i),s=(0,F.useRef)(i);return(0,F.useEffect)(()=>{let e=s.current,r=e=>{s.current=e,o(e)};if(_t(e,i))return;if(t<=0||e.length!==i.length){r(i);return}let a=t=>t>=1?i:i.map((n,r)=>ie(e[r],n,t)),c=n?.get()??1;if(n&&c<1)return n.on(`change`,e=>r(a(ht(e,c))));let l=performance.now(),u=0,d=e=>{let n=Math.min(1,(e-l)/t);r(a(n>=1?1:gt(n))),n<1&&(u=requestAnimationFrame(d))};return u=requestAnimationFrame(d),()=>cancelAnimationFrame(u)},[i,t,n]),t<=0?i:a},yt=24,bt=96,xt=()=>{if(typeof navigator>`u`)return!1;let e=navigator.userAgent,t=/iPad|iPhone|iPod/i.test(e)||navigator.platform===`MacIntel`&&navigator.maxTouchPoints>1,n=/WebKit/i.test(e),r=/CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo|YaBrowser|GSA/i.test(e);return t&&n&&!r},St=e=>new Promise(t=>{if(typeof document>`u`){t(null);return}let n=new Image;n.crossOrigin=`anonymous`,n.decoding=`async`,n.onload=()=>{try{let e=document.createElement(`canvas`),r=document.createElement(`canvas`);e.width=yt,e.height=yt,r.width=bt,r.height=bt;let i=e.getContext(`2d`),a=r.getContext(`2d`);if(!i||!a){t(null);return}let o=n.naturalWidth||n.width,s=n.naturalHeight||n.height,c=Math.min(o,s),l=Math.max(0,(o-c)/2),u=Math.max(0,(s-c)/2);i.imageSmoothingEnabled=!0,i.imageSmoothingQuality=`high`,i.drawImage(n,l,u,c,c,0,0,yt,yt),a.imageSmoothingEnabled=!0,a.imageSmoothingQuality=`high`,a.globalAlpha=1,a.drawImage(e,0,0,yt,yt,0,0,bt,bt),[{x:-8,y:-8,size:112,alpha:.22},{x:6,y:0,size:bt,alpha:.14},{x:0,y:6,size:bt,alpha:.14}].forEach(({x:t,y:n,size:r,alpha:i})=>{a.globalAlpha=i,a.drawImage(e,0,0,yt,yt,t,n,r,r)}),a.globalAlpha=1,t(r.toDataURL(`image/jpeg`,.72))}catch(e){console.warn(`[FluidBackground] Failed to build soft focus cover`,e),t(null)}},n.onerror=()=>t(null),n.src=e}),Ct=320,wt=640,Tt=1e3,Et=(e,t)=>{e.fillStyle=`#000`,e.fillStyle=t;let n=String(e.fillStyle),[r,i,a]=n.startsWith(`#`)?[1,3,5].map(e=>parseInt(n.slice(e,e+2),16)):n.match(/[\d.]+/g)??[`0`,`0`,`0`];return[n,`rgba(${r}, ${i}, ${a}, 0)`]},Dt=(e,t)=>{let n=document.createElement(`canvas`);return n.width=e,n.height=t,n},Ot=null,kt=()=>{if(Ot!==null)return Ot;try{let e=Dt(4,1).getContext(`2d`,{willReadFrequently:!0});!e||typeof e.filter!=`string`?Ot=!1:(e.filter=`blur(1px)`,e.fillStyle=`#fff`,e.fillRect(2,0,1,1),Ot=e.getImageData(1,0,1,1).data[3]>0)}catch{Ot=!1}return Ot},At=(e,t)=>{let{width:n,height:r}=e,i=n/Math.max(1,t*2.5),a=[],o=n,s=r;for(;o/2>=i&&o>2&&s>2;)o=Math.ceil(o/2),s=Math.ceil(s/2),a.push([o,s]);let c=[...a,...a.slice(0,-1).reverse(),[n,r]],l=e;for(let[e,t]of c){let n=Dt(e,t),r=n.getContext(`2d`);if(!r)return l;r.imageSmoothingEnabled=!0,r.imageSmoothingQuality=`high`,r.drawImage(l,0,0,e,t),l=n}return l},jt=(e,t,n,r)=>{let i=Dt(t,n),a=i.getContext(`2d`);if(!a)return null;let o=Math.max(t/e.width,n/e.height)*1.5,s=e.width*o,c=e.height*o,l=60*t/r,u=kt();return u&&(a.filter=`blur(${l}px)`),a.imageSmoothingEnabled=!0,a.imageSmoothingQuality=`high`,a.drawImage(e,(t-s)/2,(n-c)/2,s,c),u?i:At(i,l)},Mt=(e,t,n,r)=>{let i=e.getContext(`2d`);if(!i)return;let{width:a,height:o}=e;if(i.clearRect(0,0,a,o),!t)return;i.drawImage(t,0,0,a,o);let s=Math.hypot(a,o),c=a*o/s,l=o/s*c,u=a/s*c,d=i.createLinearGradient(a/2-l,o/2-u,a/2+l,o/2+u),[f,p]=Et(i,n),[m,h]=Et(i,r);d.addColorStop(0,f),d.addColorStop(.5,p),d.addColorStop(.5,h),d.addColorStop(1,m),i.globalCompositeOperation=`overlay`,i.globalAlpha=.4,i.fillStyle=d,i.fillRect(0,0,a,o),i.globalCompositeOperation=`source-over`,i.globalAlpha=1},Nt=({image:e,primaryColor:t,secondaryColor:n,onDrawn:r})=>{let i=(0,F.useRef)(null),[a,o]=(0,F.useState)(null);(0,F.useLayoutEffect)(()=>{let e=i.current;if(!e)return;let t=()=>{let t=e.clientWidth,n=e.clientHeight;o(e=>e&&e.width===t&&e.height===n?e:{width:t,height:n})};if(t(),typeof ResizeObserver>`u`)return;let n=new ResizeObserver(t);return n.observe(e),()=>n.disconnect()},[]);let s=(0,F.useRef)(r);(0,F.useLayoutEffect)(()=>{s.current=r});let c=(0,F.useRef)(!1),l=(0,F.useRef)(null);return(0,F.useLayoutEffect)(()=>{let r=i.current;if(!r||!a)return;if(a.width>0&&a.height>0){let i=Math.max(1,Math.round(Ct*a.height/a.width));(r.width!==Ct||r.height!==i)&&(r.width=Ct,r.height=i);let o=l.current;e?(!o||o.image!==e||o.width!==r.width||o.height!==r.height||o.cssWidth!==a.width)&&(o={image:e,width:r.width,height:r.height,cssWidth:a.width,canvas:jt(e,r.width,r.height,a.width)}):o=null,l.current=o,Mt(r,o?.canvas??null,t,n)}if(c.current)return;let o=requestAnimationFrame(()=>{c.current=!0,s.current()});return()=>cancelAnimationFrame(o)},[a,e,t,n]),(0,I.jsx)(`canvas`,{ref:i,"aria-hidden":`true`,className:`absolute inset-0 w-full h-full`})},Pt=(0,F.memo)(({coverUrl:e,theme:t})=>{let n=(0,F.useMemo)(xt,[]),[r,i]=(0,F.useState)(null),[a,o]=vt([t.primaryColor,t.secondaryColor],Tt);(0,F.useEffect)(()=>{let t=!1;return!n||!e?(i(null),()=>{t=!0}):(i(null),St(e).then(e=>{t||i(e)}),()=>{t=!0})},[e,n]);let s=dt(),c=(0,F.useRef)(0),[l,u]=(0,F.useState)([]),[d,f]=(0,F.useState)(()=>new Set),p=(0,F.useRef)(new Set);(0,F.useEffect)(()=>{let e=new Set(l.map(e=>e.image));p.current.forEach(t=>{e.has(t)||(t.close(),p.current.delete(t))})},[l]),(0,F.useEffect)(()=>()=>{p.current.forEach(e=>e.close()),p.current.clear()},[]),(0,F.useEffect)(()=>{if(n)return;if(!e){u([]);return}let t=!1,r=new Image;return r.decoding=`async`,r.src=e,r.decode().then(()=>{let e=Math.min(1,wt/Math.max(r.naturalWidth,r.naturalHeight));return createImageBitmap(r,{resizeWidth:Math.max(1,Math.round(r.naturalWidth*e)),resizeHeight:Math.max(1,Math.round(r.naturalHeight*e)),resizeQuality:`high`})}).then(n=>{if(t){n.close();return}p.current.add(n),u(t=>{let r=t[t.length-1];return r&&r.sourceCover===e?t:(c.current+=1,[...r?[r]:[],{image:n,sourceCover:e,key:c.current}])})},()=>{t||(u(t=>t.length>0?t:(c.current+=1,[{image:null,sourceCover:e,key:c.current}])),s())}),()=>{t=!0}},[e,n,s]);let m=pt(),h=(0,F.useRef)(m);(0,F.useLayoutEffect)(()=>{h.current=m});let[g,_]=(0,F.useState)(null);(0,F.useEffect)(()=>{(!e||n)&&s()},[e,n,s]);let y=(0,F.useCallback)(e=>{h.current&&_(e),f(t=>t.has(e)?t:new Set(t).add(e)),s()},[s]),[b,x]=(0,F.useState)(null),S=l[l.length-1],C=!!e&&!n&&!(S&&S.sourceCover===e&&S.key===b),w=n?r??e??null:null,T=n&&!!r,E=(0,F.useMemo)(()=>({transform:`scale(${T?1.28:1.2}) translateZ(0)`,opacity:T?.94:.3,willChange:`transform, opacity`,backfaceVisibility:`hidden`,WebkitBackfaceVisibility:`hidden`}),[T]);return(0,I.jsxs)(`div`,{className:`absolute inset-0 w-full h-full overflow-hidden pointer-events-none z-0`,style:{isolation:`isolate`,contain:`paint`,transform:`translateZ(0)`},...C?{[Xe]:``}:{},children:[e?(0,I.jsxs)(I.Fragment,{children:[n?(0,I.jsx)(`img`,{src:w??e,alt:``,"aria-hidden":`true`,draggable:!1,decoding:`async`,className:`absolute inset-0 w-full h-full object-cover transition-opacity duration-700 ease-out`,style:E}):(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`div`,{className:`absolute inset-0 w-full h-full transition-colors duration-1000`,style:{backgroundColor:t.backgroundColor,opacity:.8}}),l.map((e,t)=>{let n=t===l.length-1,r=d.has(e.key);return(0,I.jsx)(v.div,{className:`absolute inset-0 w-full h-full`,style:{willChange:`opacity`},initial:{opacity:+!n},animate:{opacity:n&&!r?0:1},transition:{duration:e.key===g?0:1.5,ease:`easeInOut`},onAnimationComplete:()=>{n&&r&&(u(t=>t.filter(t=>t.key===e.key)),f(t=>t.has(e.key)?new Set([e.key]):t),x(e.key))},children:(0,I.jsx)(Nt,{image:e.image,primaryColor:a,secondaryColor:o,onDrawn:()=>y(e.key)})},e.key)})]}),n&&(0,I.jsxs)(I.Fragment,{children:[!T&&(0,I.jsx)(`img`,{src:e,alt:``,"aria-hidden":`true`,draggable:!1,decoding:`async`,className:`absolute inset-0 w-full h-full object-cover`,style:{transform:`scale(1.36) translateZ(0)`,opacity:.12,willChange:`transform, opacity`,backfaceVisibility:`hidden`,WebkitBackfaceVisibility:`hidden`}}),(0,I.jsx)(`div`,{className:`absolute inset-0 w-full h-full`,style:{backgroundColor:t.backgroundColor,opacity:.28}}),(0,I.jsx)(`div`,{className:`absolute inset-0 w-full h-full`,style:{background:`radial-gradient(circle at 20% 20%, ${t.accentColor}55 0%, transparent 42%), radial-gradient(circle at 80% 28%, ${t.secondaryColor}50 0%, transparent 44%), radial-gradient(circle at 50% 78%, ${t.primaryColor}28 0%, transparent 52%)`,opacity:T?.52:.7}})]})]}):(0,I.jsx)(`div`,{className:`absolute inset-0 w-full h-full transition-colors duration-1000`,style:{backgroundColor:t.backgroundColor,opacity:.8}}),(!e||n||S&&!S.image)&&(0,I.jsx)(`div`,{className:`absolute inset-0 w-full h-full`,style:{background:`linear-gradient(to bottom right, ${a}, transparent, ${o})`,opacity:n?.2:.4,mixBlendMode:n?`normal`:`overlay`}})]})},(e,t)=>{if(e.coverUrl!==t.coverUrl)return!1;let n=e.theme,r=t.theme;return n.backgroundColor===r.backgroundColor&&n.primaryColor===r.primaryColor&&n.secondaryColor===r.secondaryColor}),Ft=e=>{let t=e?.join(`
`)??``;return(0,F.useEffect)(()=>{t&&ve(t.split(`
`))},[t]),(0,F.useSyncExternalStore)(ge,ye,ye)},It=e=>{switch(e.type){case`circle`:return`bass`;case`square`:return`lowMid`;case`triangle`:return`mid`;case`cross`:return`treble`;default:return`default`}},Lt=e=>e===`triangle`?`polygon(50% 0%, 0% 100%, 100% 100%)`:e===`cross`?`polygon(20% 0%, 0% 20%, 30% 50%, 0% 80%, 20% 100%, 50% 70%, 80% 100%, 100% 80%, 70% 50%, 100% 20%, 80% 0%, 50% 30%)`:`none`,Rt=(e,t)=>{let n=(e.type===`circle`||e.type===`square`)&&!e.filled;return{border:n?`1px solid ${t.secondaryColor}`:`none`,backgroundColor:n?`transparent`:t.secondaryColor,borderRadius:e.type===`circle`?`50%`:`0%`,opacity:e.opacity,clipPath:Lt(e.type)}},zt=e=>({left:`${e.initialX}%`,top:`${e.initialY}%`,width:e.size,height:e.size,animationDuration:`${e.duration}s`,animationDelay:`${e.delay}s`,"--geometric-dir":e.reverse?-1:1,"--geometric-rotate":`${e.initialRotation}deg`}),Bt=(e,t)=>{if(e.iconSlot===null||t.length===0)return null;let n=t[Math.floor(e.iconSlot*t.length)];return _e(n)===`loading`?`loading`:he(n)},Vt=({disabled:e=!1})=>e?null:(0,I.jsx)(`div`,{className:`absolute inset-0 pointer-events-none`,style:{background:`radial-gradient(circle, transparent 40%, rgba(0,0,0,0.6) 100%)`}}),Ht=({theme:e,audioPower:t,audioBands:n,shapes:r,particles:i,hideShapes:a,disableVignette:o,paused:s})=>{let c=e=>{let n=ne(e||t,{stiffness:300,damping:30});return te(n,[10,200],[.95,1.45])},l={bass:c(n?.bass),lowMid:c(n?.lowMid),mid:c(n?.mid),vocal:c(n?.vocal),treble:c(n?.treble),default:c(t)},u=e.lyricsIcons||[];return(0,I.jsxs)(`div`,{className:s?`absolute inset-0 geometric-paused`:`absolute inset-0`,children:[!a&&(0,I.jsxs)(I.Fragment,{children:[r.map(t=>{let n=Bt(t,u),r=n===`loading`?null:n;return(0,I.jsxs)(`div`,{className:`absolute geometric-drift`,style:zt(t),children:[(0,I.jsx)(v.div,{className:`w-full h-full transition-[color,background-color,border-color,opacity] duration-1000`,style:{...Rt(t,e),...n===null?{}:{opacity:0},scale:l[It(t)]}}),t.iconSlot!==null&&(0,I.jsx)(`div`,{className:`absolute inset-0 transition-opacity duration-1000`,style:{opacity:+!!r},children:(0,I.jsx)(v.div,{className:`w-full h-full flex items-center justify-center geometric-pulse transition-colors duration-1000`,style:{color:e.secondaryColor,scale:l.vocal,animationDuration:`${t.duration*.5}s`,animationDelay:`${t.delay}s`,"--geometric-peak":t.opacity*3},children:r&&(0,I.jsx)(r,{size:t.size,strokeWidth:1,absoluteStrokeWidth:!0})})})]},t.id)}),i.map(t=>(0,I.jsx)(`div`,{className:`absolute rounded-full geometric-rise transition-colors duration-1000`,style:{backgroundColor:e.accentColor,width:t.size,height:t.size,left:`${t.left}%`,top:`${t.top}%`,animationDuration:`${t.duration}s`,animationDelay:`${t.delay}s`,"--geometric-peak":t.opacity}},`p-${t.id}`))]}),(0,I.jsx)(Vt,{disabled:o})]})},Ut=({theme:e,audioPower:t,audioBands:n,seed:r,hideShapes:i=!1,disableVignette:a=!1,paused:o=!1})=>{Ft(e.lyricsIcons);let s=(0,F.useMemo)(()=>{let e=[`circle`,`square`,`triangle`,`cross`],t=0;return Array.from({length:15}).map((n,r)=>{let i=t<6&&Math.random()>.7?Math.random():null;return i!==null&&(t+=1),{id:r,type:e[Math.floor(Math.random()*e.length)],iconSlot:i,initialX:Math.random()*100,initialY:Math.random()*100,size:40+Math.random()*100,duration:i===null?30+Math.random()*30:20+Math.random()*20,delay:Math.random()*5,opacity:.11+Math.random()*.08,reverse:Math.random()>.5,filled:Math.random()<.3,initialRotation:Math.random()*360}})},[r]),c=(0,F.useMemo)(()=>Array.from({length:20}).map((e,t)=>({id:t,size:Math.random()*4+1,left:Math.random()*100,top:Math.random()*100,opacity:Math.random()*.3,duration:15+Math.random()*20,delay:Math.random()*10})),[r]);return(0,I.jsx)(v.div,{className:`absolute inset-0`,initial:!1,animate:{opacity:1},exit:{opacity:0},transition:{duration:.6,ease:`easeInOut`},children:(0,I.jsx)(Ht,{theme:e,audioPower:t,audioBands:n,shapes:s,particles:c,hideShapes:i,disableVignette:a,paused:o})})},Wt=F.memo(e=>{let t=String(e.seed??`default`);return(0,I.jsx)(`div`,{className:`absolute inset-0 overflow-hidden pointer-events-none`,children:(0,I.jsx)(re,{mode:`sync`,children:(0,I.jsx)(Ut,{...e},t)})})},(e,t)=>{if(e.seed!==t.seed||e.audioPower!==t.audioPower||e.hideShapes!==t.hideShapes||e.disableVignette!==t.disableVignette||e.paused!==t.paused)return!1;let n=e.audioBands,r=t.audioBands;if(!n!=!r)return!1;let i=!0;if(n&&r&&(i=n.bass===r.bass&&n.lowMid===r.lowMid&&n.mid===r.mid&&n.vocal===r.vocal&&n.treble===r.treble),!i)return!1;let a=e.theme,o=t.theme,s=a.backgroundColor===o.backgroundColor&&a.primaryColor===o.primaryColor&&a.secondaryColor===o.secondaryColor&&a.accentColor===o.accentColor,c=!!(a.lyricsIcons===o.lyricsIcons||a.lyricsIcons?.length===o.lyricsIcons?.length&&a.lyricsIcons?.every((e,t)=>e===o.lyricsIcons?.[t]));return s&&c}),Gt=e({default:()=>Kt}),Kt=ze({mode:`common`,order:10,labelKey:`options.visualizerBackgroundModeCommon`,labelFallback:`Common`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`path`,{d:`M4 17l5-8 5 8z`}),(0,I.jsx)(`circle`,{cx:`17.5`,cy:`8.5`,r:`3`,opacity:`0.55`})]}),command:{title:`Background: Common`,description:`Switch background to general layout`,keywords:[`background general`,`common`,`general`,`通用背景`,`ty`,`背景切换到 通用`,`背景切换到通用`]},song:({config:e,coverUrl:t,seed:n,staticMode:r})=>[r?null:n??null,e?.common?.useCoverColorBg?t??null:null],render:({config:e,theme:t,coverUrl:n,audioPower:r,audioBands:i,seed:a,staticMode:o,paused:s})=>{let c=e?.common,l=c?.useCoverColorBg??!1;return(0,I.jsxs)(I.Fragment,{children:[l&&(0,I.jsx)(`div`,{className:`absolute inset-0 z-0`,children:(0,I.jsx)(Pt,{coverUrl:n,theme:t})}),(0,I.jsx)(`div`,{className:`absolute inset-0 z-0 transition-all duration-1000`,style:{backgroundColor:t.backgroundColor,opacity:l?c?.opacity??.75:1}}),!o&&(0,I.jsx)(`div`,{className:`absolute inset-0 z-0`,children:(0,I.jsx)(Wt,{theme:t,audioPower:r,audioBands:i,seed:a,hideShapes:c?.disableGeometricBackground??!1,disableVignette:c?.disableVignette??!1,paused:s})})]})},renderSettingsPanel:e=>(0,I.jsx)(He,{...e}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.common?.useCoverColorBg??!1,i=!(e?.common?.disableVignette??!1);return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(ce,{active:r,label:n(r?`theme.addCoverColor`:`theme.useDefaultColor`),onToggle:()=>t?.common?.onCoverColorChange?.(!r),children:(0,I.jsx)(s,{size:14})}),(0,I.jsx)(ce,{active:i,label:n(`options.visualizerVignette`),onToggle:()=>t?.common?.onDisableVignetteChange?.(i),children:(0,I.jsx)(a,{size:14})})]})},resetSettings:e=>{e?.common?.onOpacityChange?.(.75),e?.common?.onCoverColorChange?.(!1),e?.common?.onDisableVignetteChange?.(!1),e?.common?.onDisableGeometricChange?.(!1)}}),qt={maxColorCount:10},Jt=`#version 300 es
precision mediump float;

uniform float u_time;

uniform vec4 u_colors[${qt.maxColorCount}];
uniform float u_colorsCount;

uniform float u_distortion;
uniform float u_swirl;
uniform float u_grainMixer;
uniform float u_grainOverlay;

in vec2 v_objectUV;
out vec4 fragColor;

${Ee}
${je}
${Ce}

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

  for (int i = 0; i < ${qt.maxColorCount}; i++) {
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
`,Yt=`#version 300 es
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

${xe}
${Ee}
${be}
${Ce}

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
`,Xt={simplex:1,warp:2,dots:3,wave:4,ripple:5,swirl:6,sphere:7},Zt={random:1,"2x2":2,"4x4":3,"8x8":4},Qt=`#version 300 es
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

${Ee}
${je}
${De}
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

${ke}

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
`,$t=`#version 300 es
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

${Ee}
${je}
${Ce}

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
`,en={lines:1,linesIrregular:2,wave:3,zigzag:4,pattern:5},tn={prism:1,lens:2,contour:3,cascade:4,flat:5},nn=`#version 300 es
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


${Ce}
${Ee}

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
`,rn=`#version 300 es
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

${Ee}
${Ce}
${je}

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
`,an=`#version 300 es
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

${Ee}
${je}
${Ce}

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
`,on={classic:0,gooey:1,holes:2,soft:3},sn={square:0,hex:1};function cn(e,t){if(Object.keys(e).length!==Object.keys(t).length)return!1;for(let n in e){if(n===`colors`){let n=Array.isArray(e.colors),r=Array.isArray(t.colors);if(!n||!r){if(Object.is(e.colors,t.colors)===!1)return!1;continue}if(e.colors?.length!==t.colors?.length||!e.colors?.every((e,n)=>e===t.colors?.[n]))return!1;continue}if(Object.is(e[n],t[n])===!1)return!1}return!0}var R={name:`Default`,params:{...N,speed:1,frame:0,colors:[`#e0eaff`,`#241d9a`,`#f75092`,`#9f50d3`],distortion:.8,swirl:.1,grainMixer:0,grainOverlay:0}};({...N}),{...N},{...N};var ln=(0,F.memo)(function({speed:e=R.params.speed,frame:t=R.params.frame,colors:n=R.params.colors,distortion:r=R.params.distortion,swirl:i=R.params.swirl,grainMixer:a=R.params.grainMixer,grainOverlay:o=R.params.grainOverlay,fit:s=R.params.fit,rotation:c=R.params.rotation,scale:l=R.params.scale,originX:u=R.params.originX,originY:d=R.params.originY,offsetX:f=R.params.offsetX,offsetY:p=R.params.offsetY,worldWidth:m=R.params.worldWidth,worldHeight:h=R.params.worldHeight,...g}){let _={u_colors:n.map(P),u_colorsCount:n.length,u_distortion:r,u_swirl:i,u_grainMixer:a,u_grainOverlay:o,u_fit:we[s],u_rotation:c,u_scale:l,u_offsetX:f,u_offsetY:p,u_originX:u,u_originY:d,u_worldWidth:m,u_worldHeight:h};return(0,I.jsx)(Te,{...g,speed:e,frame:t,fragmentShader:Jt,uniforms:_})},cn),z={name:`Default`,params:{...Se,speed:1,frame:0,scale:.6,colorBack:`#000000`,colorFront:`#00b2ff`,shape:`sphere`,type:`4x4`,size:2}};({...Se}),{...Se},{...N},{...N},{...N};var un=(0,F.memo)(function({speed:e=z.params.speed,frame:t=z.params.frame,colorBack:n=z.params.colorBack,colorFront:r=z.params.colorFront,shape:i=z.params.shape,type:a=z.params.type,pxSize:o,size:s=o===void 0?z.params.size:o,fit:c=z.params.fit,scale:l=z.params.scale,rotation:u=z.params.rotation,originX:d=z.params.originX,originY:f=z.params.originY,offsetX:p=z.params.offsetX,offsetY:m=z.params.offsetY,worldWidth:h=z.params.worldWidth,worldHeight:g=z.params.worldHeight,..._}){let v={u_colorBack:P(n),u_colorFront:P(r),u_shape:Xt[i],u_type:Zt[a],u_pxSize:s,u_fit:we[c],u_scale:l,u_rotation:u,u_offsetX:p,u_offsetY:m,u_originX:d,u_originY:f,u_worldWidth:h,u_worldHeight:g};return(0,I.jsx)(Te,{..._,speed:e,frame:t,fragmentShader:Yt,uniforms:v})}),B={name:`Default`,params:{...N,fit:`cover`,scale:.6,speed:0,frame:0,colorFront:`#9fadbc`,colorBack:`#ffffff`,contrast:.3,roughness:.4,fiber:.3,fiberSize:.2,crumples:.3,crumpleSize:.35,folds:.65,foldCount:5,fade:0,drops:.2,seed:5.8}};({...N}),{...N},{...N};var dn=(0,F.memo)(function({speed:e=B.params.speed,frame:t=B.params.frame,colorFront:n=B.params.colorFront,colorBack:r=B.params.colorBack,image:i=``,contrast:a=B.params.contrast,roughness:o=B.params.roughness,fiber:s=B.params.fiber,crumples:c=B.params.crumples,folds:l=B.params.folds,drops:u=B.params.drops,seed:d=B.params.seed,fiberScale:f,fiberSize:p=f===void 0?B.params.fiberSize:.2/f,crumplesScale:m,crumpleSize:h=m===void 0?B.params.crumpleSize:.2/m,blur:g,fade:_=g===void 0?B.params.fade:g,foldsNumber:v,foldCount:y=v===void 0?B.params.foldCount:v,fit:b=B.params.fit,scale:x=B.params.scale,rotation:S=B.params.rotation,originX:C=B.params.originX,originY:w=B.params.originY,offsetX:T=B.params.offsetX,offsetY:E=B.params.offsetY,worldWidth:D=B.params.worldWidth,worldHeight:O=B.params.worldHeight,...k}){let A=typeof window<`u`&&{u_noiseTexture:Oe()},j={u_image:i,u_colorFront:P(n),u_colorBack:P(r),u_contrast:a,u_roughness:o,u_fiber:s,u_fiberSize:p,u_crumples:c,u_crumpleSize:h,u_foldCount:y,u_folds:l,u_fade:_,u_drops:u,u_seed:d,...A,u_fit:we[b],u_scale:x,u_rotation:S,u_offsetX:T,u_offsetY:E,u_originX:C,u_originY:w,u_worldWidth:D,u_worldHeight:O};return(0,I.jsx)(Te,{...k,speed:e,frame:t,fragmentShader:Qt,mipmaps:[`u_image`],uniforms:j})},cn),V={name:`Default`,params:{...N,fit:`cover`,speed:0,frame:0,colorBack:`#00000000`,colorShadow:`#000000`,colorHighlight:`#ffffff`,shadows:.25,size:.5,angle:0,distortionShape:`prism`,highlights:.1,shape:`lines`,distortion:.5,shift:0,blur:0,edges:.25,stretch:0,margin:0,marginLeft:0,marginRight:0,marginTop:0,marginBottom:0,grainMixer:0,grainOverlay:0}};({...N}),{...N},{...N};var fn=(0,F.memo)(function({speed:e=V.params.speed,frame:t=V.params.frame,colorBack:n=V.params.colorBack,colorShadow:r=V.params.colorShadow,colorHighlight:i=V.params.colorHighlight,image:a=``,shadows:o=V.params.shadows,angle:s=V.params.angle,distortion:c=V.params.distortion,distortionShape:l=V.params.distortionShape,highlights:u=V.params.highlights,shape:d=V.params.shape,shift:f=V.params.shift,blur:p=V.params.blur,edges:m=V.params.edges,margin:h,marginLeft:g=h??V.params.marginLeft,marginRight:_=h??V.params.marginRight,marginTop:v=h??V.params.marginTop,marginBottom:y=h??V.params.marginBottom,grainMixer:b=V.params.grainMixer,grainOverlay:x=V.params.grainOverlay,stretch:S=V.params.stretch,count:C,size:w=C===void 0?V.params.size:(1/(C*1.6))**(1/6)/.7-.5,fit:T=V.params.fit,scale:E=V.params.scale,rotation:D=V.params.rotation,originX:O=V.params.originX,originY:k=V.params.originY,offsetX:A=V.params.offsetX,offsetY:j=V.params.offsetY,worldWidth:ee=V.params.worldWidth,worldHeight:te=V.params.worldHeight,...ne}){let re={u_image:a,u_colorBack:P(n),u_colorShadow:P(r),u_colorHighlight:P(i),u_shadows:o,u_size:w,u_angle:s,u_distortion:c,u_shift:f,u_blur:p,u_edges:m,u_stretch:S,u_distortionShape:tn[l],u_highlights:u,u_shape:en[d],u_marginLeft:g,u_marginRight:_,u_marginTop:v,u_marginBottom:y,u_grainMixer:b,u_grainOverlay:x,u_fit:we[T],u_scale:E,u_rotation:D,u_offsetX:A,u_offsetY:j,u_originX:O,u_originY:k,u_worldWidth:ee,u_worldHeight:te};return(0,I.jsx)(Te,{...ne,speed:e,frame:t,fragmentShader:$t,mipmaps:[`u_image`],uniforms:re})}),H={name:`Default`,params:{...N,fit:`cover`,speed:0,frame:0,colorFront:`#94ffaf`,colorBack:`#000c38`,colorHighlight:`#eaff94`,type:`8x8`,size:2,colorSteps:2,originalColors:!1,inverted:!1}};({...N}),{...N},{...N};var pn=(0,F.memo)(function({speed:e=H.params.speed,frame:t=H.params.frame,colorFront:n=H.params.colorFront,colorBack:r=H.params.colorBack,colorHighlight:i=H.params.colorHighlight,image:a=``,type:o=H.params.type,colorSteps:s=H.params.colorSteps,originalColors:c=H.params.originalColors,inverted:l=H.params.inverted,pxSize:u,size:d=u===void 0?H.params.size:u,fit:f=H.params.fit,scale:p=H.params.scale,rotation:m=H.params.rotation,originX:h=H.params.originX,originY:g=H.params.originY,offsetX:_=H.params.offsetX,offsetY:v=H.params.offsetY,worldWidth:y=H.params.worldWidth,worldHeight:b=H.params.worldHeight,...x}){let S={u_image:a,u_colorFront:P(n),u_colorBack:P(r),u_colorHighlight:P(i),u_type:Zt[o],u_pxSize:d,u_colorSteps:s,u_originalColors:c,u_inverted:l,u_fit:we[f],u_rotation:m,u_scale:p,u_offsetX:_,u_offsetY:v,u_originX:h,u_originY:g,u_worldWidth:y,u_worldHeight:b};return(0,I.jsx)(Te,{...x,speed:e,frame:t,fragmentShader:nn,uniforms:S})},cn),U={name:`Default`,params:{...N,scale:1,fit:`contain`,speed:0,frame:0,spread:.6,bias:1,angle:0,perspective:.1,count:35,dispersion:1,dispersionShift:0,dispersionColor:.6,focusCenter:.8,focusEdges:1,swirl:.35,noise:0,noiseFrequency:.25,noiseOffset:0,lensBulge:0,lensCircle:0,grainMixer:0,grainOverlay:0,imageX:0,imageY:0}};({...N}),{...N},{...N};var mn=(0,F.memo)(function({speed:e=U.params.speed,frame:t=U.params.frame,image:n=``,spread:r=U.params.spread,bias:i=U.params.bias,angle:a=U.params.angle,perspective:o=U.params.perspective,count:s=U.params.count,dispersion:c=U.params.dispersion,dispersionShift:l=U.params.dispersionShift,dispersionColor:u=U.params.dispersionColor,focusCenter:d=U.params.focusCenter,focusEdges:f=U.params.focusEdges,swirl:p=U.params.swirl,noise:m=U.params.noise,noiseFrequency:h=U.params.noiseFrequency,noiseOffset:g=U.params.noiseOffset,lensBulge:_=U.params.lensBulge,lensCircle:v=U.params.lensCircle,grainMixer:y=U.params.grainMixer,grainOverlay:b=U.params.grainOverlay,imageX:x=U.params.imageX,imageY:S=U.params.imageY,fit:C=U.params.fit,scale:w=U.params.scale,rotation:T=U.params.rotation,originX:E=U.params.originX,originY:D=U.params.originY,offsetX:O=U.params.offsetX,offsetY:k=U.params.offsetY,worldWidth:A=U.params.worldWidth,worldHeight:j=U.params.worldHeight,...ee}){let te={u_image:n,u_spread:r,u_bias:i,u_angle:a,u_perspective:o,u_count:s,u_dispersion:c,u_dispersionShift:l,u_dispersionColor:u,u_focusCenter:d,u_focusEdges:f,u_swirl:p,u_noise:m,u_noiseFrequency:h,u_noiseOffset:g,u_lensBulge:_,u_lensCircle:v,u_grainMixer:y,u_grainOverlay:b,u_imageX:x,u_imageY:S,u_fit:we[C],u_rotation:T,u_scale:w,u_offsetX:O,u_offsetY:k,u_originX:E,u_originY:D,u_worldWidth:A,u_worldHeight:j};return(0,I.jsx)(Te,{...ee,speed:e,frame:t,fragmentShader:rn,mipmaps:[`u_image`],uniforms:te})},cn),W={name:`Default`,params:{...N,fit:`cover`,speed:0,frame:0,colorBack:`#f2f1e8`,colorFront:`#2b2b2b`,size:.5,radius:1.25,contrast:.4,originalColors:!1,inverted:!1,grainMixer:.2,grainOverlay:.2,grainSize:.5,grid:`hex`,type:`gooey`}};({...N}),{...N},{...N};var hn=(0,F.memo)(function({speed:e=W.params.speed,frame:t=W.params.frame,colorFront:n=W.params.colorFront,colorBack:r=W.params.colorBack,image:i=``,size:a=W.params.size,radius:o=W.params.radius,contrast:s=W.params.contrast,originalColors:c=W.params.originalColors,inverted:l=W.params.inverted,grainMixer:u=W.params.grainMixer,grainOverlay:d=W.params.grainOverlay,grainSize:f=W.params.grainSize,grid:p=W.params.grid,type:m=W.params.type,fit:h=W.params.fit,scale:g=W.params.scale,rotation:_=W.params.rotation,originX:v=W.params.originX,originY:y=W.params.originY,offsetX:b=W.params.offsetX,offsetY:x=W.params.offsetY,worldWidth:S=W.params.worldWidth,worldHeight:C=W.params.worldHeight,...w}){let T={u_image:i,u_colorFront:P(n),u_colorBack:P(r),u_size:a,u_radius:o,u_contrast:s,u_originalColors:c,u_inverted:l,u_grainMixer:u,u_grainOverlay:d,u_grainSize:f,u_grid:sn[p],u_type:on[m],u_fit:we[h],u_rotation:_,u_scale:g,u_offsetX:b,u_offsetY:x,u_originX:v,u_originY:y,u_worldWidth:S,u_worldHeight:C};return(0,I.jsx)(Te,{...w,speed:e,frame:t,fragmentShader:an,uniforms:T})},cn),gn=Object.freeze({antialias:!1,depth:!1}),_n=e=>(t=>{if(e.current=t,t)return()=>{e.current=null;let n=t.paperShaderMount?.canvasElement;if(!n)return;let r=n.getContext(`webgl2`);queueMicrotask(()=>{!r||n.isConnected||r.isContextLost()||r.getExtension(`WEBGL_lose_context`)?.loseContext()})}}),vn=921600,yn=.12,bn=300,G=e=>Math.min(1,Math.max(0,e/255)),xn=e=>Math.min(2,Math.max(0,e)),Sn=e=>Math.min(1,Math.max(0,e)),Cn=(e,t,n)=>e+(t-e)*n,wn=(e,t,n,r,i)=>(G(e)*.22+G(t)*.18+G(n)*.22+G(r)*.28+G(i)*.1)**.55,Tn=(e,t,n,r=.84)=>Math.max(n*r,Sn((e-t)*7)),En=(e,t)=>Sn(e*.42+t*.85),Dn=(e,t)=>Math.max(e,t),On=(e,t,n)=>n?En(e,t):Sn(e),kn=(e,t,n,r)=>xn(r?e*yn:Cn(e,t,n)),An=(e,t,n)=>{let r=e[0]??t.secondaryColor;if(n===`cover-only`){let t=e[1]??r,n=e[2]??t;return{ditheringBack:n,ditheringFront:r,mesh:[r,t,n,e[3]??r,e[4]??t,e[5]??n]}}let i=e[1]??t.primaryColor,a=e[2]??r,o=e[3]??i;return{ditheringBack:t.backgroundColor,ditheringFront:r,mesh:[r,i,a,o,t.backgroundColor,t.accentColor]}},jn=F.memo(({theme:e,coverUrl:t,audioPower:n,audioBands:r,staticMode:i,paused:a,tuning:o,blendMs:s=0,blendProgress:c})=>{let l=(0,F.useRef)(null),u=(0,F.useRef)(null),d=(0,F.useMemo)(()=>_n(l),[]),f=(0,F.useMemo)(()=>_n(u),[]),p=(0,F.useRef)(null),m=(0,F.useRef)(null),h=(0,F.useRef)(a),g=(0,F.useRef)(+!a),[v,y]=(0,F.useState)([]),b=o??_,x=b.displayMode!==`mesh`,S=b.displayMode!==`dithering`;h.current=a;let C=dt();(0,F.useEffect)(()=>{let e=!0;return t?(Me(t,6).then(t=>{e&&(y(t),C())}),()=>{e=!1}):(y([]),C(),()=>{e=!1})},[t,C]);let w=(0,F.useMemo)(()=>An(v,e,b.colorSource),[v,e,b.colorSource]),T=vt([e.backgroundColor,w.ditheringBack,w.ditheringFront,...w.mesh],s,c),[E,D,O]=T,k=(0,F.useMemo)(()=>({ditheringBack:D,ditheringFront:O,mesh:T.slice(3)}),[T,D,O]);return(0,F.useEffect)(()=>{let e=l.current?.paperShaderMount,t=u.current?.paperShaderMount;if(i){e?.setSpeed(0),t?.setSpeed(0);return}let a=0,o=new WeakMap,s=(e,t,n)=>{let r=o.get(e);r||(r={},o.set(e,r)),r[t]!==n&&(r[t]=n,e.style[t]=n)},c=0,d=0,f=0,_=0,v=0,y=0,x=null,C=(e,t)=>Cn(kn(e,t,_,!0),kn(e,t,_,!1),g.current),w=e=>{a=requestAnimationFrame(w);let t=h.current,i=x===null?0:1-Math.exp((x-e)/bn),o=x===null?1e3/60:e-x;x=e;let T=e=>de()?1-(1-e)**(o/(1e3/60)):e,E=de()?.84**(o/(1e3/60)):.84;g.current=Cn(g.current,+!t,i);let D=t?0:G(n.get()),O=t?0:G(r.bass.get()),k=t?0:wn(r.bass.get(),r.lowMid.get(),r.mid.get(),r.vocal.get(),r.treble.get()),A=t?0:G(Math.max(r.mid.get(),r.vocal.get()));c=Cn(c,D,T(.12)),d=Cn(d,O,T(.16)),f=Cn(f,A,T(.13)),y=b.enhancedBeatResponse?Tn(k,v,y,E):0,v=k;let j=!t&&Fe()&&Ie(me.latentPulse)>0?En(k,Dn(Ne.get(),Pe.get())):On(k,y,b.enhancedBeatResponse);_=Cn(_,j,T(j>_?.42:.14));let ee=l.current?.paperShaderMount,te=u.current?.paperShaderMount;if(ee){let e=C(b.ditheringSpeed,b.ditheringAudioSpeed);ee.setSpeed(e),Ae(ee,{u_pxSize:Math.max(.5,b.ditheringSize-d*b.ditheringSize*.34)},e!==0)}if(te){let e=C(b.meshSpeed,b.meshAudioSpeed);te.setSpeed(e),Ae(te,{u_distortion:b.meshDistortion+c*.62,u_swirl:b.meshSwirl+f*.38},e!==0)}p.current&&(s(p.current,`opacity`,S?`${Math.min(1,b.ditheringOpacity+d*.25)}`:`1`),s(p.current,`transform`,`scale(${1.015+d*.025})`)),m.current&&(s(m.current,`filter`,`saturate(${1.04+f*.34}) brightness(${.94+c*.16})`),s(m.current,`transform`,`scale(${1.025+c*.018})`))};return a=requestAnimationFrame(w),()=>cancelAnimationFrame(a)},[r,n,S,i,b]),(0,I.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,style:{backgroundColor:E,pointerEvents:`none`},children:[S&&(0,I.jsx)(`div`,{ref:m,className:`absolute inset-0`,style:{transform:`scale(1.025)`,transformOrigin:`center`},children:(0,I.jsx)(ln,{ref:f,width:`100%`,height:`100%`,colors:k.mesh,distortion:b.meshDistortion,swirl:b.meshSwirl,grainMixer:0,grainOverlay:.01,speed:i?0:b.meshSpeed,minPixelRatio:1,maxPixelCount:vn,webGlContextAttributes:gn,style:{width:`100%`,height:`100%`}})}),x&&(0,I.jsx)(`div`,{ref:p,className:`absolute inset-0`,style:{mixBlendMode:S?`soft-light`:`normal`,opacity:S?b.ditheringOpacity:1,transform:`scale(1.015)`,transformOrigin:`center`},children:(0,I.jsx)(un,{ref:d,width:`100%`,height:`100%`,colorBack:k.ditheringBack,colorFront:k.ditheringFront,shape:`warp`,type:`4x4`,size:b.ditheringSize,speed:i?0:b.ditheringSpeed,minPixelRatio:1,maxPixelCount:vn,webGlContextAttributes:gn,style:{width:`100%`,height:`100%`}})}),b.overlayEnabled&&b.overlayOpacity>0&&(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundColor:E,opacity:b.overlayOpacity}})]})}),Mn={id:`bg-latent`,titleKey:`options.latentBackgroundSettings`},Nn={id:`bg-latent-dithering`,titleKey:`options.latentDitheringGroup`},Pn={id:`bg-latent-mesh`,titleKey:`options.latentMeshGroup`},Fn=e=>e.toFixed(1),In=e=>e.toFixed(2),Ln=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsxs)(b,{def:Mn,children:[(0,I.jsx)(x,{label:e(`options.latentDisplayMode`),children:(0,I.jsx)(D,{value:t.displayMode,options:[{value:`dithering`,label:e(`options.latentDisplayDithering`)},{value:`mesh`,label:e(`options.latentDisplayMesh`)},{value:`both`,label:e(`options.latentDisplayBoth`)}],onChange:e=>n?.({displayMode:e})})}),(0,I.jsx)(x,{label:e(`options.latentColorSource`),children:(0,I.jsx)(D,{value:t.colorSource,options:[{value:`cover-theme`,label:e(`options.latentColorSourceCoverTheme`)},{value:`cover-only`,label:e(`options.latentColorSourceCoverOnly`)}],onChange:e=>n?.({colorSource:e})})}),(0,I.jsx)(O,{label:e(`options.latentDynamicOnlyInPlayer`),note:e(`options.latentDynamicOnlyInPlayerDesc`),checked:t.dynamicOnlyInPlayer,onChange:e=>n?.({dynamicOnlyInPlayer:e})}),(0,I.jsx)(O,{label:e(`options.latentEnhancedBeatResponse`),note:e(`options.latentEnhancedBeatResponseDesc`),checked:t.enhancedBeatResponse,onChange:e=>n?.({enhancedBeatResponse:e})}),(0,I.jsx)(O,{label:e(`options.nomandBackgroundOverlay`),note:e(`options.nomandBackgroundOverlayDesc`),checked:t.overlayEnabled,onChange:e=>n?.({overlayEnabled:e})}),(0,I.jsx)(S,{when:t.overlayEnabled,children:(0,I.jsx)(A,{...a,sub:!0,label:e(`options.nomandBackgroundOverlayOpacity`),value:t.overlayOpacity,min:0,max:1,step:.05,format:k,onChange:e=>n?.({overlayOpacity:e})})})]}),(0,I.jsxs)(b,{def:Nn,children:[(0,I.jsx)(A,{...a,label:e(`options.latentBaseSpeed`),value:t.ditheringSpeed,min:0,max:2,step:.1,format:Fn,onChange:e=>n?.({ditheringSpeed:e})}),(0,I.jsx)(A,{...a,label:e(`options.latentAudioSpeed`),value:t.ditheringAudioSpeed,min:0,max:2,step:.1,format:Fn,onChange:e=>n?.({ditheringAudioSpeed:e})}),(0,I.jsx)(A,{...a,label:e(`options.latentDitheringSize`),value:t.ditheringSize,min:.5,max:8,step:.25,format:In,onChange:e=>n?.({ditheringSize:e})}),(0,I.jsx)(A,{...a,label:e(`options.latentDitheringOpacity`),value:t.ditheringOpacity,min:0,max:1,step:.05,format:k,onChange:e=>n?.({ditheringOpacity:e})})]}),(0,I.jsxs)(b,{def:Pn,children:[(0,I.jsx)(A,{...a,label:e(`options.latentBaseSpeed`),value:t.meshSpeed,min:0,max:2,step:.1,format:Fn,onChange:e=>n?.({meshSpeed:e})}),(0,I.jsx)(A,{...a,label:e(`options.latentAudioSpeed`),value:t.meshAudioSpeed,min:0,max:2,step:.1,format:Fn,onChange:e=>n?.({meshAudioSpeed:e})}),(0,I.jsx)(A,{...a,label:e(`options.latentMeshDistortion`),value:t.meshDistortion,min:0,max:2,step:.05,format:In,onChange:e=>n?.({meshDistortion:e})}),(0,I.jsx)(A,{...a,label:e(`options.latentMeshSwirl`),value:t.meshSwirl,min:0,max:1,step:.05,format:In,onChange:e=>n?.({meshSwirl:e})})]})]})},Rn=e({default:()=>Un}),zn=[`dithering`,`mesh`,`both`],Bn={dithering:`options.latentDisplayDithering`,mesh:`options.latentDisplayMesh`,both:`options.latentDisplayBoth`},Vn=[`cover-theme`,`cover-only`],Hn={"cover-theme":`options.latentColorSourceCoverTheme`,"cover-only":`options.latentColorSourceCoverOnly`},Un=ze({mode:`latent`,order:35,labelKey:`options.visualizerBackgroundModeLatent`,labelFallback:`Latent`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`path`,{d:`M4.5 7.5h.01M9 7.5h.01M13.5 7.5h.01M18 7.5h.01`,strokeWidth:`2.2`,opacity:`0.55`}),(0,I.jsx)(`path`,{d:`M3 15c3-3.5 6-3.5 9 0s6 3.5 9 0`})]}),command:{title:`Background: Latent`,description:`Switch background to cover-colored audio-reactive shaders`,keywords:[`latent`,`latent background`,`shader background`,`隐现`,`隐现背景`,`音频响应背景`]},beatEffects:[{id:me.latentPulse,nameKey:`options.beatEffect_latentPulse`,descKey:`options.beatEffect_latentPulseDesc`,source:`beats`,retired:!0}],render:({config:e,theme:t,coverUrl:n,audioPower:r,audioBands:i,staticMode:a,paused:o,blendMs:s,blendProgress:c})=>(0,I.jsx)(jn,{theme:t,coverUrl:n,audioPower:r,audioBands:i,staticMode:a,paused:o,tuning:e?.latent?.tuning,blendMs:s,blendProgress:c}),renderSettingsPanel:({config:e,actions:t,...n})=>(0,I.jsx)(Ln,{...n,tuning:e?.latent?.tuning??_,onTuningChange:t?.latent?.onTuningChange}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.latent?.tuning??_,i=n(Bn[r.displayMode]),a=n(Hn[r.colorSource]);return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(ue,{label:i,title:`${n(`options.latentDisplayMode`)}: ${i}`,onClick:()=>t?.latent?.onTuningChange?.({displayMode:le(zn,r.displayMode)})}),(0,I.jsx)(ue,{label:a,title:`${n(`options.latentColorSource`)}: ${a}`,onClick:()=>t?.latent?.onTuningChange?.({colorSource:le(Vn,r.colorSource)})}),(0,I.jsx)(ce,{active:r.overlayEnabled,label:n(`options.nomandBackgroundOverlay`),onToggle:()=>t?.latent?.onTuningChange?.({overlayEnabled:!r.overlayEnabled}),children:(0,I.jsx)(c,{size:14})})]})},resetSettings:e=>e?.latent?.onResetTuning?.()}),Wn={id:`bg-monet-source`,titleKey:`options.monetGroupBackgroundSource`},Gn={id:`bg-monet-layout`,titleKey:`options.monetGroupLayoutPosition`},Kn={id:`bg-monet-filters`,titleKey:`options.monetGroupFiltersPostProcessing`},qn={id:`bg-monet-tint`,titleKey:`options.monetGroupColorTintWash`},Jn=(e,t,n,r)=>Number.isFinite(e)?Math.min(n,Math.max(t,e)):r,Yn=e=>{let t=e.trim().replace(/^#/,``);return/^[0-9a-fA-F]{6}$/.test(t)?`#${t.toLowerCase()}`:null},Xn=e=>(0,I.jsx)(`span`,{className:`absolute inset-0`,style:{backgroundImage:e===`full-overlay`?`linear-gradient(var(--st-t3), var(--st-t3))`:`linear-gradient(90deg, var(--st-t3) 30%, transparent 62%)`}}),Zn=({t:e,tuning:t=g,onTuningChange:n,monetBackgroundImage:r,onUploadMonetBackgroundImage:i,onClearMonetBackgroundImage:a,isLoadingMonetBackgroundImage:o=!1,onSliderPointerDown:s,onSliderCommit:c})=>{let u=(0,F.useRef)(null),[d,f]=(0,F.useState)(null),m={backgroundSource:t.backgroundSource??g.backgroundSource,backgroundLayout:t.backgroundLayout??g.backgroundLayout,backgroundBlurPx:Jn(t.backgroundBlurPx??g.backgroundBlurPx,0,60,g.backgroundBlurPx),backgroundOverlayOpacity:Jn(t.backgroundOverlayOpacity??g.backgroundOverlayOpacity,0,1,g.backgroundOverlayOpacity),backgroundGrayscale:Jn(t.backgroundGrayscale??g.backgroundGrayscale,0,1,g.backgroundGrayscale),backgroundSaturation:Jn(t.backgroundSaturation??g.backgroundSaturation,0,2,g.backgroundSaturation),backgroundWash:Jn(t.backgroundWash??g.backgroundWash,0,1,g.backgroundWash),backgroundHalfPaneOffsetX:Jn(t.backgroundHalfPaneOffsetX??g.backgroundHalfPaneOffsetX,-40,40,g.backgroundHalfPaneOffsetX),backgroundWashColorMode:t.backgroundWashColorMode??g.backgroundWashColorMode,backgroundWashCustomColor:Yn(t.backgroundWashCustomColor)??g.backgroundWashCustomColor,backgroundDriftEnabled:t.backgroundDriftEnabled??g.backgroundDriftEnabled,backgroundDriftStrength:Jn(t.backgroundDriftStrength??g.backgroundDriftStrength,0,1,g.backgroundDriftStrength),backgroundStreaksEnabled:t.backgroundStreaksEnabled??g.backgroundStreaksEnabled},h={onDragStart:s,onDragEnd:c},_=async t=>{let r=Array.from(t.target.files??[]);if(t.target.value=``,f(null),!r.length||!i)return;let a=await i(r);a.ok?(n?.({backgroundSource:`uploaded-global`}),f(r[0].name)):f(a.error||e(`options.monetUploadBackground`))};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsxs)(b,{def:Wn,children:[(0,I.jsx)(x,{label:e(`options.monetBackgroundSource`),children:(0,I.jsx)(D,{value:m.backgroundSource,options:[{value:`cover-derived`,label:e(`options.monetBackgroundSourceCover`)},{value:`uploaded-global`,label:e(`options.monetBackgroundSourceUploaded`),disabled:!r&&!o}],onChange:e=>n?.({backgroundSource:e})})}),(0,I.jsxs)(x,{label:e(`options.monetUploadBackground`),hint:d||r?.name||`-`,children:[(0,I.jsx)(C,{icon:p,onClick:()=>u.current?.click(),disabled:o||!i,children:e(`options.monetUploadBackground`)}),(0,I.jsx)(C,{icon:l,onClick:()=>void a?.(),disabled:!r||!a,children:e(`options.monetClearBackground`)}),(0,I.jsx)(`input`,{ref:u,type:`file`,accept:`.png,.jpg,.jpeg,.gif,.webp,.svg,image/*`,className:`hidden`,onChange:e=>void _(e)})]})]}),(0,I.jsxs)(b,{def:Gn,children:[(0,I.jsx)(x,{label:e(`options.monetBackgroundLayout`),below:(0,I.jsx)(E,{className:`-mx-4`,columns:4,label:e(`options.monetBackgroundLayout`),value:m.backgroundLayout,options:[{value:`half-pane-gradient`,label:e(`options.monetLayoutHalfPane`)},{value:`full-overlay`,label:e(`options.monetLayoutFullOverlay`)}],picture:Xn,onChange:e=>n?.({backgroundLayout:e})})}),(0,I.jsx)(S,{when:m.backgroundLayout===`half-pane-gradient`,children:(0,I.jsx)(A,{...h,sub:!0,label:e(`options.monetHalfPaneOffsetX`),value:m.backgroundHalfPaneOffsetX,min:-40,max:40,step:2,format:e=>`${Math.round(e)}%`,onChange:e=>n?.({backgroundHalfPaneOffsetX:e})})}),(0,I.jsx)(O,{label:e(`options.monetBackgroundDriftEnabled`),note:e(`options.monetBackgroundDriftEnabledDesc`),checked:m.backgroundDriftEnabled,onChange:e=>n?.({backgroundDriftEnabled:e})}),(0,I.jsx)(S,{when:m.backgroundDriftEnabled,children:(0,I.jsx)(A,{...h,sub:!0,label:e(`options.monetBackgroundDriftStrength`),value:m.backgroundDriftStrength,min:0,max:1,step:.05,format:k,onChange:e=>n?.({backgroundDriftStrength:e})})})]}),(0,I.jsxs)(b,{def:Kn,children:[(0,I.jsx)(A,{...h,label:e(`options.monetBackgroundBlur`),value:m.backgroundBlurPx,min:0,max:60,step:2,format:e=>`${Math.round(e)}px`,onChange:e=>n?.({backgroundBlurPx:e})}),(0,I.jsx)(A,{...h,label:e(`options.monetBackgroundSaturation`),value:m.backgroundSaturation,min:0,max:2,step:.05,format:k,onChange:e=>n?.({backgroundSaturation:e})}),(0,I.jsx)(A,{...h,label:e(`options.monetBackgroundGrayscale`),value:m.backgroundGrayscale,min:0,max:1,step:.02,format:k,onChange:e=>n?.({backgroundGrayscale:e})})]}),(0,I.jsxs)(b,{def:qn,children:[(0,I.jsx)(A,{...h,label:e(`options.monetBackgroundOverlayOpacity`),value:m.backgroundOverlayOpacity,min:0,max:1,step:.02,format:k,onChange:e=>n?.({backgroundOverlayOpacity:e})}),(0,I.jsx)(A,{...h,label:e(`options.monetBackgroundWash`),value:m.backgroundWash,min:0,max:1,step:.02,format:k,onChange:e=>n?.({backgroundWash:e})}),(0,I.jsx)(O,{label:e(`options.monetBackgroundStreaksEnabled`),note:e(`options.monetBackgroundStreaksEnabledDesc`),checked:m.backgroundStreaksEnabled,onChange:e=>n?.({backgroundStreaksEnabled:e})}),(0,I.jsx)(x,{label:e(`options.monetBackgroundWashColorMode`),children:(0,I.jsx)(D,{value:m.backgroundWashColorMode,options:[{value:`theme`,label:e(`options.monetBackgroundWashTheme`)},{value:`custom`,label:e(`options.monetBackgroundWashCustom`)}],onChange:e=>n?.({backgroundWashColorMode:e})})}),(0,I.jsx)(S,{when:m.backgroundWashColorMode===`custom`,children:(0,I.jsxs)(x,{sub:!0,label:e(`options.monetBackgroundWashCustomColor`),below:(0,I.jsx)(Le,{color:m.backgroundWashCustomColor,onChange:e=>n?.({backgroundWashCustomColor:e}),style:{width:`100%`,height:180}}),children:[(0,I.jsx)(`span`,{className:`h-4 w-4 rounded-full shadow-[0_0_0_1px_var(--st-line)]`,style:{backgroundColor:m.backgroundWashCustomColor}}),(0,I.jsx)(T,{children:m.backgroundWashCustomColor.toUpperCase()})]})})]})]})},Qn=1920,$n=1080,er={r:10,g:10,b:12},tr={r:245,g:245,b:245},K=(e,t,n)=>Math.min(n,Math.max(t,e)),q=(e,t,n)=>e+(t-e)*n,nr=(e,t,n)=>.2126*e+.7152*t+.0722*n,rr=(e,t)=>nr(e.r,e.g,e.b)<=nr(t.r,t.g,t.b)?{shadow:e,highlight:t}:{shadow:t,highlight:e},ir=(e,t,n,r)=>{let i=t.width,a=t.height;if(!i||!a)return;let o=Math.max(n/i,r/a),s=i*o,c=a*o,l=(n-s)/2,u=(r-c)/2;e.drawImage(t,l,u,s,c)},ar=(e,t)=>{let n=ae(e);return n?{r:K(n.r,0,255),g:K(n.g,0,255),b:K(n.b,0,255)}:t},or=(e,t,n,r)=>{let{shadow:i,highlight:a}=rr(t,r);if(e<=.55){let t=e/.55;return{r:q(i.r,n.r,t),g:q(i.g,n.g,t),b:q(i.b,n.b,t)}}let o=(e-.55)/.45;return{r:q(n.r,a.r,o),g:q(n.g,a.g,o),b:q(n.b,a.b,o)}},sr=(e,t,n,r,i)=>{let a=K(i.backgroundGrayscale,0,1),o=K(i.backgroundSaturation,0,2),s=K(i.backgroundWash,0,1);if(a<=0&&Math.abs(o-1)<.001&&s<=0)return;let c=e.getImageData(0,0,t,n),l=c.data,u=ar(r.backgroundColor,er),d=ar(r.accentColor,u),f=ar(r.primaryColor,tr),p=ar(i.backgroundWashCustomColor,d),m=i.backgroundWashColorMode===`custom`?p:d;for(let e=0;e<l.length;e+=4){let t=l[e],n=l[e+1],r=l[e+2];if(l[e+3]===0)continue;let i=nr(t,n,r);if(a>0&&(t=q(t,i,a),n=q(n,i,a),r=q(r,i,a)),Math.abs(o-1)>=.001){let e=nr(t,n,r);t=e+(t-e)*o,n=e+(n-e)*o,r=e+(r-e)*o}if(s>0){let e=or(K(i/255,0,1),u,m,f);t=q(t,e.r,s),n=q(n,e.g,s),r=q(r,e.b,s)}l[e]=Math.round(K(t,0,255)),l[e+1]=Math.round(K(n,0,255)),l[e+2]=Math.round(K(r,0,255))}e.putImageData(c,0,0)},cr=(e,t,n,r,i)=>{let a=K(i.backgroundOverlayOpacity,0,1),o=e.createLinearGradient(0,0,t,n);o.addColorStop(0,M(r.accentColor,.08+a*.62)),o.addColorStop(.44,M(r.backgroundColor,.16+a*.58)),o.addColorStop(1,M(r.primaryColor,.06+a*.36)),e.fillStyle=o,e.fillRect(0,0,t,n);let s=e.createRadialGradient(t*.18,n*.34,0,t*.18,n*.34,t*.55);s.addColorStop(0,M(r.accentColor,a*.42)),s.addColorStop(1,M(r.backgroundColor,0)),e.fillStyle=s,e.fillRect(0,0,t,n);let c=e.createLinearGradient(t*.45,0,t,0);if(c.addColorStop(0,M(r.backgroundColor,0)),c.addColorStop(1,M(r.backgroundColor,.18+a*.38)),e.fillStyle=c,e.fillRect(0,0,t,n),i.backgroundStreaksEnabled!==!1){e.fillStyle=M(r.backgroundColor,.1+a*.08);for(let r=0;r<18;r+=1){let i=r*127%t,a=r*211%n-40;e.fillRect(i,a,1,n*.28)}}},lr=(e,t,n,r,i)=>{let{width:a,height:o}=e.canvas;e.fillStyle=n.backgroundColor,e.fillRect(0,0,a,o),e.save(),i!==null&&(e.filter=`blur(${i}px)`),ir(e,t,a,o),e.restore(),sr(e,a,o,n,r),cr(e,a,o,n,r)},ur=new Map,dr=(e,t,n)=>Math.min(n,Math.max(t,e)),fr=({coverUrl:e,monetBackgroundImage:t,tuning:n})=>n.backgroundSource===`uploaded-global`?t?.url??e??null:e??t?.url??null,pr=async e=>{let t=new Image;(e.startsWith(`http://`)||e.startsWith(`https://`))&&(t.crossOrigin=`anonymous`),t.decoding=`async`;let n=new Promise((n,r)=>{t.onload=()=>n(),t.onerror=()=>r(Error(`Failed to load image: ${e}`))});t.src=e;try{await t.decode()}catch{await n}return t},mr=({coverUrl:e,monetBackgroundImage:t,theme:n,tuning:r})=>JSON.stringify({sourceUrl:fr({coverUrl:e,monetBackgroundImage:t,tuning:r}),uploadedId:r.backgroundSource===`uploaded-global`?t?.id??null:null,theme:{backgroundColor:n.backgroundColor,primaryColor:n.primaryColor,accentColor:n.accentColor},tuning:{backgroundSource:r.backgroundSource,backgroundBlurPx:r.backgroundBlurPx,backgroundOverlayOpacity:r.backgroundOverlayOpacity,backgroundGrayscale:r.backgroundGrayscale,backgroundSaturation:r.backgroundSaturation,backgroundWash:r.backgroundWash,backgroundWashColorMode:r.backgroundWashColorMode,backgroundWashCustomColor:r.backgroundWashCustomColor,backgroundStreaksEnabled:r.backgroundStreaksEnabled}}),hr=null,gr=()=>{if(hr!==null)return hr;if(typeof document>`u`)return!1;try{let e=document.createElement(`canvas`);e.width=2,e.height=2;let t=e.getContext(`2d`);return!t||typeof t.filter!=`string`?(hr=!1,!1):(t.fillStyle=`#000000`,t.fillRect(0,0,2,2),t.filter=`blur(1px)`,t.fillStyle=`#ffffff`,t.fillRect(0,0,1,1),hr=t.getImageData(1,1,1,1).data[0]>0,hr)}catch{return hr=!1,!1}},_r=null,vr=0,yr=null,br=[],xr=()=>{for(;!yr&&br.length>0;){let e=br.shift();if(!e.wanted()){e.request.image.close(),e.settle(void 0);continue}let t=vr+=1;yr={...e,id:t};try{Cr().postMessage({...e.request,id:t},{transfer:[e.request.image]})}catch{yr=null,e.request.image.close(),e.settle(null)}}},Sr=e=>{let t=yr;yr=null,t?.settle(e),xr()},Cr=()=>{if(_r)return _r;let e=new Worker(new URL(new URL(`monetBackground.worker-BdbhyxNv.js`,import.meta.url).href,``+import.meta.url),{type:`module`});return e.onmessage=e=>{e.data.id===yr?.id&&Sr(`picture`in e.data?e.data.picture:null)},e.onerror=()=>{e.terminate(),_r=null,Sr(null)},_r=e,e},wr=(e,t)=>new Promise(n=>{br.push({request:e,wanted:t,settle:n}),xr()}),Tr=(e,t,n,r)=>{try{let i=document.createElement(`canvas`);i.width=Qn,i.height=$n;let a=i.getContext(`2d`);return a?(lr(a,e,t,n,r),new Promise(e=>i.toBlob(e,`image/jpeg`,.92))):Promise.resolve(null)}catch{return Promise.resolve(null)}},Er=async(e,t,n,r)=>{try{return await Tr(await createImageBitmap(e),t,n,r)}catch{let i=document.createElement(`canvas`);i.width=e.naturalWidth,i.height=e.naturalHeight;let a=i.getContext(`2d`);return!a||i.width<=0||i.height<=0?null:(a.drawImage(e,0,0),Tr(i,t,n,r))}},Dr=async({coverUrl:e,monetBackgroundImage:t,theme:n,tuning:r},i)=>{let a=fr({coverUrl:e,monetBackgroundImage:t,tuning:r});if(!a)return null;let o={backgroundColor:n.backgroundColor,primaryColor:n.primaryColor,accentColor:n.accentColor},s=gr()?dr(r.backgroundBlurPx,0,60):null,c=await pr(a),l,u=null;try{u=await createImageBitmap(c)}catch{u=null}if(u?(l=await wr({image:u,colors:o,tuning:r,blurPx:s},i),l===null&&i()&&(l=await Er(c,o,r,s))):i()&&(l=await Er(c,o,r,s)),!l)return l;let d=URL.createObjectURL(l),f=new Image;f.src=d;try{await f.decode()}catch(e){throw URL.revokeObjectURL(d),e}return d},Or=e=>{let t=mr(e),n=ur.get(t);if(!n){let r={url:Promise.resolve(null),holders:0};r.url=Dr(e,()=>r.holders>0||(ur.get(t)===r&&ur.delete(t),!1)).then(e=>e??null,()=>null),ur.set(t,r),n=r}let r=n;r.holders+=1;let i=!1;return{url:r.url,release:()=>{i||(i=!0,--r.holders)}}},kr=240,Ar=76,jr=156,Mr=3.4,Nr=.035,Pr=.01,Fr=12.9898,Ir=78.233,Lr=39.425,Rr=(e,t)=>(e%t+t)%t,zr=(e,t)=>{let n=Math.sin(e*127.1+t*311.7)*43758.5453;return n-Math.floor(n)},Br=e=>e*e*(3-2*e),Vr=(e,t,n)=>{let r=Math.floor(e),i=zr(Rr(r,t),n);return i+(zr(Rr(r+1,t),n)-i)*Br(e-r)},Hr=(e,t)=>{let n=Vr(e,Ar,t),r=Vr(e*2,152,t+17.31);return(n*.68+r*.32)*2-1},Ur=e=>{let t=e.reduce((e,t)=>Math.max(e,Math.abs(t)),0);return t>0?e.map(e=>e/t):e},Wr=e=>{let t=Math.min(1,Math.max(0,e)),n=Mr*t,r=1+n/100*2+Pr,i=Nr*t,a=[],o=[],s=[];for(let e=0;e<=jr;e+=1){let t=Ar*e/jr;a.push(Hr(t,Fr)),o.push(Hr(t,Ir)),s.push(Hr(t,Lr))}let c=Ur(a),l=Ur(o),u=Ur(s);return{keyframes:c.map((e,t)=>({transform:`translate3d(${(e*n).toFixed(4)}%, ${(l[t]*n).toFixed(4)}%, 0) scale(${(r+i*((u[t]+1)/2)).toFixed(5)})`})),durationMs:kr*1e3,maxTravelPercent:n,minScale:r}},Gr=180,Kr=(e,t,n)=>Math.min(n,Math.max(t,e)),qr=(e,t,n,r)=>{(0,F.useEffect)(()=>{let i=e.current;if(!i||!t||n<=0||typeof i.animate!=`function`||r)return;let a=Wr(n),o=i.animate(a.keyframes,{duration:a.durationMs,iterations:1/0,easing:`linear`});return()=>o.cancel()},[t,e,n,r])},Jr=(e,t,n)=>n.backgroundSource===`uploaded-global`?t?.url??e??null:e??t?.url??null,Yr=({coverUrl:e,monetBackgroundImage:t,theme:n,isDaylight:r=!1,tuning:i=g,transparentBackground:a=!1,staticMode:o=!1})=>{let[s,c]=(0,F.useState)(null),[l,u]=(0,F.useState)(!1),d=Jr(e,t,i),f=dt(),[p,m]=(0,F.useState)(null),h=(0,F.useRef)(null),_=(0,F.useMemo)(()=>`linear-gradient(135deg, ${M(n.accentColor,.22)}, ${M(n.backgroundColor,.96)} 50%, ${M(n.primaryColor,.18)})`,[n]),b=(0,F.useMemo)(()=>`linear-gradient(90deg, ${M(n.backgroundColor,.18)} 0%, ${M(n.backgroundColor,.32)} 34%, ${M(n.backgroundColor,.66)} 70%, ${M(n.backgroundColor,.82)} 100%)`,[n]),x=(0,F.useMemo)(()=>mr({coverUrl:e,monetBackgroundImage:t,theme:n,tuning:i}),[e,t,n,i]);(0,F.useEffect)(()=>{let r=!1,o;if(!d||a)return c(null),u(!1),f(),()=>{r=!0};u(!0);let s={coverUrl:e,monetBackgroundImage:t,theme:n,tuning:i},l=d===h.current?null:Or(s),p=null;return o=window.setTimeout(()=>{p=Or(s),p.url.then(e=>{r||(c(t=>t===e?t:e),u(!1),h.current=d,e&&m(t=>t??e),f())})},Gr),()=>{r=!0,o!==void 0&&window.clearTimeout(o),l?.release(),p?.release()}},[x,d,a,f]);let S=(0,F.useRef)(null),C=Kr(i.backgroundDriftStrength??0,0,1),w=!!i.backgroundDriftEnabled&&!o&&C>0&&!de();qr(S,w,C,y(`monetBackground`));let T=(0,F.useMemo)(()=>w?{willChange:`transform`}:void 0,[w]),E=(0,F.useMemo)(()=>gr(),[])?0:i.backgroundBlurPx,D=(0,F.useMemo)(()=>E<=0?{}:{filter:`blur(${E}px)`,WebkitFilter:`blur(${E}px)`,transform:`scale(1.1) translateZ(0)`},[E]);if(a)return null;let O=s?`url(${s})`:d?`linear-gradient(135deg, ${M(n.accentColor,.2)}, ${M(n.backgroundColor,.78)}), url(${d})`:_,k=l?{[Xe]:``}:{},A=s||d||`fallback`,j=A!==p&&{opacity:0};if(i.backgroundLayout===`full-overlay`)return(0,I.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,...k,children:[(0,I.jsx)(`div`,{ref:S,className:`absolute inset-0`,style:T,children:(0,I.jsx)(re,{initial:!1,children:(0,I.jsx)(v.div,{initial:j,animate:{opacity:1},exit:{opacity:0},transition:{duration:.8,ease:`easeInOut`},className:`absolute inset-0`,style:{backgroundColor:n.backgroundColor,backgroundImage:O,backgroundSize:`cover`,backgroundPosition:`center`,...D}},A)})}),(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{background:b}})]});let ee=(r?.7:.3)+Kr(i.backgroundOverlayOpacity,0,1)*.16,te=Kr(50+i.backgroundHalfPaneOffsetX,10,90);return(0,I.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,...k,children:[(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundColor:n.backgroundColor,backgroundImage:_}}),(0,I.jsx)(re,{initial:!1,children:s||d?(0,I.jsx)(`div`,{className:`absolute inset-y-0 left-0 w-[72%] sm:w-[68%] lg:w-[60%] overflow-hidden`,style:{WebkitMaskImage:`linear-gradient(90deg, rgba(0,0,0,1) 0%, rgba(0,0,0,0.94) 48%, rgba(0,0,0,0.46) 74%, rgba(0,0,0,0) 100%)`,maskImage:`linear-gradient(90deg, rgba(0,0,0,1) 0%, rgba(0,0,0,0.94) 48%, rgba(0,0,0,0.46) 74%, rgba(0,0,0,0) 100%)`},children:(0,I.jsx)(`div`,{ref:S,className:`absolute inset-0`,style:T,children:(0,I.jsx)(v.div,{initial:j,animate:{opacity:ee},exit:{opacity:0},transition:{duration:.8,ease:`easeInOut`},className:`absolute inset-0`,style:{backgroundImage:O,backgroundRepeat:`no-repeat`,backgroundSize:`cover`,backgroundPosition:`${te}% center`,...D}},A)})}):null}),(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{background:`linear-gradient(90deg, ${M(n.backgroundColor,.14)} 0%, ${M(n.backgroundColor,.28)} 28%, ${M(n.backgroundColor,.62)} 64%, ${M(n.backgroundColor,.86)} 100%)`}}),(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundImage:`radial-gradient(circle at 18% 34%, ${M(n.accentColor,.18)}, transparent 36%)`,backgroundSize:`cover`,backgroundPosition:`center`}}),(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{background:b}})]})},Xr=e({default:()=>$r}),Zr={"cover-derived":`options.monetBackgroundSourceCover`,"uploaded-global":`options.monetBackgroundSourceUploaded`},Qr=e=>e&&Re(e),$r=ze({mode:`monet`,order:20,labelKey:`options.visualizerBackgroundModeMonet`,labelFallback:`Monet`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`rect`,{x:`3.5`,y:`4.5`,width:`17`,height:`15`,rx:`2`}),(0,I.jsx)(`path`,{d:`M20.5 8.5L8 19.5`,opacity:`0.55`})]}),song:({config:e,coverUrl:t})=>[Jr(Qr(t),e?.customImage,e?.monet?.tuning??g)],render:({config:e,coverUrl:t,theme:n,isDaylight:r,staticMode:i})=>(0,I.jsx)(Yr,{coverUrl:Qr(t),monetBackgroundImage:e?.customImage,theme:n,isDaylight:r,tuning:e?.monet?.tuning,transparentBackground:e?.transparent,staticMode:i}),renderSettingsPanel:({config:e,actions:t,t:n,onSliderPointerDown:r,onSliderCommit:i})=>(0,I.jsx)(Zn,{t:n,tuning:e?.monet?.tuning??g,onTuningChange:t?.monet?.onTuningChange,monetBackgroundImage:e?.customImage,onUploadMonetBackgroundImage:t?.customImage?.onUpload,onClearMonetBackgroundImage:t?.customImage?.onClear,isLoadingMonetBackgroundImage:t?.customImage?.isLoading,onSliderPointerDown:r,onSliderCommit:i}),renderQuickControls:({config:e,actions:t,t:n})=>{let i=e?.monet?.tuning??g,a=i.backgroundLayout===`full-overlay`,o=n(a?`options.monetLayoutFullOverlay`:`options.monetLayoutHalfPane`),s=e=>t?.monet?.onTuningChange?.(e),c=i.backgroundSource,l=n(Zr[c]),d=!!e?.customImage;return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(ue,{label:o,title:`${n(`options.monetBackgroundLayout`)}: ${o}`,onClick:()=>s({backgroundLayout:a?`half-pane-gradient`:`full-overlay`})}),(0,I.jsx)(ue,{label:l,title:`${n(`options.monetBackgroundSource`)}: ${l}`,disabled:!d&&c===`cover-derived`,onClick:()=>s({backgroundSource:d&&c===`cover-derived`?`uploaded-global`:`cover-derived`})}),(0,I.jsx)(ce,{active:i.backgroundStreaksEnabled,label:n(`options.monetBackgroundStreaksEnabled`),onToggle:()=>s({backgroundStreaksEnabled:!i.backgroundStreaksEnabled}),children:(0,I.jsx)(r,{size:14})}),(0,I.jsx)(ce,{active:i.backgroundDriftEnabled,label:n(`options.monetBackgroundDriftEnabled`),onToggle:()=>s({backgroundDriftEnabled:!i.backgroundDriftEnabled}),children:(0,I.jsx)(u,{size:14})})]})},resetSettings:e=>e?.monet?.onResetTuning?.()}),ei=1.8,ti=.01,ni=16/9,ri={fiberSize:.2,crumples:.35,crumpleSize:.35,folds:.65,foldCount:5,drops:.2,seed:5.8},ii={perspective:.4,count:20,focusCenter:.55,focusEdges:.8,swirl:.08,lensCircle:.1},ai=e=>Math.min(1,Math.max(0,e)),oi=e=>Math.min(ei,Math.max(1,e)),si=e=>e<=1?1:oi(e+ti),ci=e=>si(1/(1-2*Math.min(Math.max(e,0),.45))),li=(e,t,n)=>n&&!t?!e:e,ui=(e,t,n)=>li(!e,t,n),di=(e,t)=>{let{folds:n,crumples:r,drops:i}=ri;return ci(.02*(2*n+1.5*r+.2*i+.75*ai(e)+.1*ai(t)))},fi=(e,t)=>{let n=.5*Math.hypot(ni,1),r=ai(t),i=.7*r**(1.3+2.7*r)*(1-ii.focusEdges),a=Math.max(.35,1-i/n);if(e<=0)return si(1/a);let o=Math.min(e,1)*1.4,s=e=>{let t=2*n/e;return Math.tan(t*o)/Math.tan(o)/t},c=Math.max(1,2*n*o/1.45);if(c>=ei||s(ei)>ei*a)return ei;if(c===1&&s(1)<=a)return si(1/a);let l=ei;for(let e=0;e<32;e+=1){let e=(c+l)/2;s(e)>e*a?c=e:l=e}return si(l)},pi=(e,t)=>{let n=dt();(0,F.useEffect)(()=>{if(t===null){n();return}let r=0,i=()=>{r=requestAnimationFrame(e.current?.paperShaderMount?n:i)};return i(),()=>cancelAnimationFrame(r)},[e,t,n])},mi=(e,t,n)=>n.imageSource===`uploaded-global`?t?.url??e:e??t?.url,hi=F.memo(({coverUrl:e,monetBackgroundImage:t,tuning:n,theme:r,isDaylight:i})=>{let a={...m,...n},o=mi(e,t,a),s=(0,F.useRef)(null),c=(0,F.useMemo)(()=>_n(s),[]),l=de()?c:s;return pi(s,o?`${o}:${a.effect}`:null),o?(0,I.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,style:{backgroundColor:r.backgroundColor,pointerEvents:`none`},children:[(()=>{let e={width:`100%`,height:`100%`,ref:l,image:o,fit:`cover`,minPixelRatio:1,maxPixelCount:2073600,webGlContextAttributes:gn,style:{width:`100%`,height:`100%`}};switch(a.effect){case`fluted-glass`:return(0,I.jsx)(fn,{...e,colorBack:r.backgroundColor,colorShadow:r.secondaryColor,colorHighlight:r.primaryColor,shadows:.25,size:a.flutedGlassSize,distortion:a.flutedGlassDistortion,blur:a.flutedGlassBlur,shape:`lines`,distortionShape:`prism`,highlights:.1,edges:.25},`${o}:fluted-glass`);case`paper-texture`:return(0,I.jsx)(dn,{...e,...ri,colorFront:r.accentColor,colorBack:r.backgroundColor,contrast:a.paperTextureContrast,roughness:a.paperTextureRoughness,fiber:a.paperTextureFiber,scale:di(a.paperTextureRoughness,a.paperTextureFiber)},`${o}:paper-texture`);case`halftone-dots`:return(0,I.jsx)(hn,{...e,colorBack:r.backgroundColor,colorFront:r.accentColor,size:a.halftoneDotsSize,radius:a.halftoneDotsRadius,contrast:a.halftoneDotsContrast,originalColors:a.halftoneDotsOriginalColors,inverted:ui(a.halftoneDotsInverted,a.halftoneDotsOriginalColors,i),grid:`hex`,type:`gooey`,grainMixer:.12,grainOverlay:.06,grainSize:.5},`${o}:halftone-dots`);case`lens-distortion`:return(0,I.jsx)(mn,{...e,...ii,spread:a.lensDistortionSpread,dispersion:a.lensDistortionDispersion,lensBulge:a.lensDistortionBulge,scale:fi(a.lensDistortionBulge,a.lensDistortionSpread)},`${o}:lens-distortion`);default:return(0,I.jsx)(pn,{...e,colorBack:r.backgroundColor,colorFront:r.accentColor,colorHighlight:r.primaryColor,originalColors:a.originalColors,inverted:li(a.inverted,a.originalColors,i),type:a.ditheringType,size:a.size,colorSteps:a.colorSteps},`${o}:dithering`)}})(),a.overlayEnabled&&a.overlayOpacity>0&&(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundColor:r.backgroundColor,opacity:a.overlayOpacity}})]}):(0,I.jsx)(`div`,{className:`absolute inset-0 z-0`,style:{backgroundColor:r.backgroundColor}})}),gi=[`2x2`,`4x4`,`8x8`],_i=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(x,{label:e(`options.nomandBackgroundDitheringType`),children:(0,I.jsx)(D,{value:t.ditheringType,options:gi.map(e=>({value:e,label:e})),onChange:e=>n?.({ditheringType:e})})}),(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundSize`),value:t.size,min:.5,max:20,step:.5,format:e=>e.toFixed(1),onChange:e=>n?.({size:e})}),(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundColorSteps`),value:t.colorSteps,min:1,max:7,step:1,format:e=>String(Math.round(e)),onChange:e=>n?.({colorSteps:e})}),(0,I.jsx)(O,{label:e(`options.nomandBackgroundOriginalColors`),checked:t.originalColors,onChange:e=>n?.({originalColors:e})}),(0,I.jsx)(O,{label:e(`options.nomandBackgroundInverted`),checked:t.inverted,onChange:e=>n?.({inverted:e})})]})},vi=e=>e.toFixed(2),yi=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundFlutedGlassSize`),value:t.flutedGlassSize,min:.1,max:1,step:.05,format:vi,onChange:e=>n?.({flutedGlassSize:e})}),(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundFlutedGlassDistortion`),value:t.flutedGlassDistortion,min:0,max:1,step:.05,format:k,onChange:e=>n?.({flutedGlassDistortion:e})}),(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundFlutedGlassBlur`),value:t.flutedGlassBlur,min:0,max:1,step:.01,format:k,onChange:e=>n?.({flutedGlassBlur:e})})]})},bi=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundHalftoneDotsSize`),value:t.halftoneDotsSize,min:.1,max:1,step:.05,format:vi,onChange:e=>n?.({halftoneDotsSize:e})}),(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundHalftoneDotsRadius`),value:t.halftoneDotsRadius,min:.1,max:2,step:.05,format:vi,onChange:e=>n?.({halftoneDotsRadius:e})}),(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundHalftoneDotsContrast`),value:t.halftoneDotsContrast,min:0,max:1,step:.05,format:k,onChange:e=>n?.({halftoneDotsContrast:e})}),(0,I.jsx)(O,{label:e(`options.nomandBackgroundOriginalColors`),checked:t.halftoneDotsOriginalColors,onChange:e=>n?.({halftoneDotsOriginalColors:e})}),(0,I.jsx)(O,{label:e(`options.nomandBackgroundInverted`),checked:t.halftoneDotsInverted,onChange:e=>n?.({halftoneDotsInverted:e})})]})},xi=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundLensDistortionSpread`),value:t.lensDistortionSpread,min:0,max:1,step:.05,format:k,onChange:e=>n?.({lensDistortionSpread:e})}),(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundLensDistortionBulge`),value:t.lensDistortionBulge,min:-1,max:1,step:.05,format:vi,onChange:e=>n?.({lensDistortionBulge:e})}),(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundLensDistortionDispersion`),value:t.lensDistortionDispersion,min:0,max:1,step:.05,format:k,onChange:e=>n?.({lensDistortionDispersion:e})})]})},Si=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundPaperTextureContrast`),value:t.paperTextureContrast,min:0,max:1,step:.01,format:k,onChange:e=>n?.({paperTextureContrast:e})}),(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundPaperTextureRoughness`),value:t.paperTextureRoughness,min:0,max:1,step:.01,format:k,onChange:e=>n?.({paperTextureRoughness:e})}),(0,I.jsx)(A,{...a,label:e(`options.nomandBackgroundPaperTextureFiber`),value:t.paperTextureFiber,min:0,max:1,step:.05,format:k,onChange:e=>n?.({paperTextureFiber:e})})]})},Ci={id:`bg-nomand-effect`,titleKey:`options.nomandBackgroundEffect`},wi=[`dithering`,`fluted-glass`,`paper-texture`,`halftone-dots`,`lens-distortion`],Ti={dithering:`options.nomandBackgroundEffectDithering`,"fluted-glass":`options.nomandBackgroundEffectFlutedGlass`,"paper-texture":`options.nomandBackgroundEffectPaperTexture`,"halftone-dots":`options.nomandBackgroundEffectHalftoneDots`,"lens-distortion":`options.nomandBackgroundEffectLensDistortion`},Ei={dithering:{backgroundImage:`conic-gradient(var(--st-t2) 25%, transparent 0 50%, var(--st-t2) 0 75%, transparent 0)`,backgroundSize:`8px 8px`},"fluted-glass":{backgroundImage:`repeating-linear-gradient(90deg, transparent 0 2px, var(--st-t2) 5px, transparent 8px)`},"paper-texture":{backgroundImage:`repeating-linear-gradient(37deg, transparent 0 3px, var(--st-t3) 3px 4px), repeating-linear-gradient(-58deg, transparent 0 5px, var(--st-t3) 5px 6px)`},"halftone-dots":{backgroundImage:`radial-gradient(var(--st-t2) 32%, transparent 36%)`,backgroundSize:`8px 8px`},"lens-distortion":{backgroundImage:`radial-gradient(circle at 50% 50%, transparent 0 22%, var(--st-t2) 24% 28%, transparent 30% 46%, var(--st-t3) 48% 52%, transparent 54%)`}},Di=e=>(0,I.jsx)(`span`,{className:`absolute inset-0`,style:Ei[e]}),Oi=e=>{let{t,tuning:n}=e;return(0,I.jsxs)(b,{def:Ci,children:[(0,I.jsx)(x,{below:(0,I.jsx)(E,{className:`-mx-4`,columns:3,label:t(`options.nomandBackgroundEffect`),value:n.effect,options:wi.map(e=>({value:e,label:t(Ti[e])})),picture:Di,onChange:t=>e.onTuningChange?.({effect:t})})}),n.effect===`dithering`&&(0,I.jsx)(_i,{...e}),n.effect===`fluted-glass`&&(0,I.jsx)(yi,{...e}),n.effect===`paper-texture`&&(0,I.jsx)(Si,{...e}),n.effect===`halftone-dots`&&(0,I.jsx)(bi,{...e}),n.effect===`lens-distortion`&&(0,I.jsx)(xi,{...e})]})},ki={id:`bg-nomand`,titleKey:`options.nomandBackgroundSettings`},Ai=({t:e,tuning:t,onTuningChange:n,monetBackgroundImage:r,onUploadMonetBackgroundImage:i,onClearMonetBackgroundImage:a,isLoadingMonetBackgroundImage:o=!1,onSliderPointerDown:s,onSliderCommit:c})=>{let u={...m,...t},d=(0,F.useRef)(null),[p,h]=(0,F.useState)(``),g=e=>{n?.({imageSource:e})},_=async t=>{if(!t.length||!i)return;let n=await i(t);h(n.ok?e(`options.nomandBackgroundUploadSuccess`):n.error??e(`options.nomandBackgroundUploadFailed`)),n.ok&&g(`uploaded-global`)};return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsxs)(b,{def:ki,children:[(0,I.jsx)(x,{label:e(`options.nomandBackgroundSource`),children:(0,I.jsx)(D,{value:u.imageSource,options:[{value:`cover-derived`,label:e(`options.monetBackgroundSourceCover`)},{value:`uploaded-global`,label:e(`options.monetBackgroundSourceUploaded`),disabled:!r&&!o}],onChange:g})}),(0,I.jsxs)(x,{label:e(`options.monetUploadBackground`),hint:p||r?.name||`-`,children:[(0,I.jsx)(C,{icon:f,disabled:o||!i,onClick:()=>d.current?.click(),children:e(`options.monetUploadBackground`)}),(0,I.jsx)(C,{icon:l,disabled:!r||!a,onClick:()=>void a?.(),children:e(`options.monetClearBackground`)}),(0,I.jsx)(`input`,{ref:d,type:`file`,accept:`image/png,image/jpeg,image/webp,image/gif`,className:`hidden`,onChange:e=>{_(Array.from(e.target.files??[])),e.target.value=``}})]}),(0,I.jsx)(O,{label:e(`options.nomandBackgroundOverlay`),note:e(`options.nomandBackgroundOverlayDesc`),checked:u.overlayEnabled,onChange:e=>n?.({overlayEnabled:e})}),(0,I.jsx)(S,{when:u.overlayEnabled,children:(0,I.jsx)(A,{sub:!0,label:e(`options.nomandBackgroundOverlayOpacity`),value:u.overlayOpacity,min:0,max:1,step:.05,format:k,onChange:e=>n?.({overlayOpacity:e}),onDragStart:s,onDragEnd:c})})]}),(0,I.jsx)(Oi,{t:e,tuning:u,onTuningChange:n,onSliderPointerDown:s,onSliderCommit:c})]})},ji=e({default:()=>Pi}),Mi={"cover-derived":`options.monetBackgroundSourceCover`,"uploaded-global":`options.monetBackgroundSourceUploaded`},Ni=e=>e&&Re(e),Pi=ze({mode:`nomand`,order:30,labelKey:`options.visualizerBackgroundModeNomand`,labelFallback:`Nomand`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`rect`,{x:`4`,y:`4`,width:`6.5`,height:`6.5`,rx:`0.8`}),(0,I.jsx)(`rect`,{x:`13.5`,y:`4`,width:`6.5`,height:`6.5`,rx:`0.8`,opacity:`0.45`}),(0,I.jsx)(`rect`,{x:`4`,y:`13.5`,width:`6.5`,height:`6.5`,rx:`0.8`,opacity:`0.45`}),(0,I.jsx)(`rect`,{x:`13.5`,y:`13.5`,width:`6.5`,height:`6.5`,rx:`0.8`})]}),command:{title:`Background: Nomand`,description:`Switch background to theme-colored image dithering`,keywords:[`nomand`,`dithering`,`dither`,`shader background`,`漫游`,`像素画`,`像素画背景`,`抖动背景`,`网点背景`,`主题色背景`]},song:({config:e,coverUrl:t})=>[mi(Ni(t),e?.customImage,{...m,...e?.nomand?.tuning})??null],render:({config:e,coverUrl:t,theme:n,isDaylight:r})=>(0,I.jsx)(hi,{coverUrl:Ni(t),monetBackgroundImage:e?.customImage,tuning:e?.nomand?.tuning,theme:n,isDaylight:r}),renderSettingsPanel:({config:e,actions:t,...n})=>(0,I.jsx)(Ai,{...n,tuning:e?.nomand?.tuning??m,onTuningChange:t?.nomand?.onTuningChange,monetBackgroundImage:e?.customImage,onUploadMonetBackgroundImage:t?.customImage?.onUpload,onClearMonetBackgroundImage:t?.customImage?.onClear,isLoadingMonetBackgroundImage:t?.customImage?.isLoading}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.nomand?.tuning??m,i=e=>t?.nomand?.onTuningChange?.(e),a=r.imageSource,o=n(Mi[a]),s=!!e?.customImage,l=n(Ti[r.effect]);return(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(ue,{label:o,title:`${n(`options.nomandBackgroundSource`)}: ${o}`,disabled:!s&&a===`cover-derived`,onClick:()=>i({imageSource:s&&a===`cover-derived`?`uploaded-global`:`cover-derived`})}),(0,I.jsx)(ue,{label:l,title:`${n(`options.nomandBackgroundEffect`)}: ${l}`,onClick:()=>i({effect:le(wi,r.effect)})}),(0,I.jsx)(ce,{active:r.overlayEnabled,label:n(`options.nomandBackgroundOverlay`),onToggle:()=>i({overlayEnabled:!r.overlayEnabled}),children:(0,I.jsx)(c,{size:14})})]})},resetSettings:e=>e?.nomand?.onResetTuning?.()}),Fi=5120,Ii=5121,Li=5122,Ri=5123,zi=5124,Bi=5125,Vi=5126,Hi=32819,Ui=32820,Wi=33635,Gi=5131,Ki=33640,qi=35899,Ji=35902,Yi=36269,Xi=34042,Zi={};{let e=Zi;e[Fi]=Int8Array,e[Ii]=Uint8Array,e[Li]=Int16Array,e[Ri]=Uint16Array,e[zi]=Int32Array,e[Bi]=Uint32Array,e[Vi]=Float32Array,e[Hi]=Uint16Array,e[Ui]=Uint16Array,e[Wi]=Uint16Array,e[Gi]=Uint16Array,e[Ki]=Uint32Array,e[qi]=Uint32Array,e[Ji]=Uint32Array,e[Yi]=Uint32Array,e[Xi]=Uint32Array}function Qi(e){if(e instanceof Int8Array)return Fi;if(e instanceof Uint8Array||e instanceof Uint8ClampedArray)return Ii;if(e instanceof Int16Array)return Li;if(e instanceof Uint16Array)return Ri;if(e instanceof Int32Array)return zi;if(e instanceof Uint32Array)return Bi;if(e instanceof Float32Array)return Vi;throw Error(`unsupported typed array type`)}function $i(e){if(e===Int8Array)return Fi;if(e===Uint8Array||e===Uint8ClampedArray)return Ii;if(e===Int16Array)return Li;if(e===Uint16Array)return Ri;if(e===Int32Array)return zi;if(e===Uint32Array)return Bi;if(e===Float32Array)return Vi;throw Error(`unsupported typed array type`)}function ea(e){let t=Zi[e];if(!t)throw Error(`unknown gl type`);return t}var ta=typeof SharedArrayBuffer<`u`?function(e){return e&&e.buffer&&(e.buffer instanceof ArrayBuffer||e.buffer instanceof SharedArrayBuffer)}:function(e){return e&&e.buffer&&e.buffer instanceof ArrayBuffer};function na(...e){console.error(...e)}function ra(...e){console.warn(...e)}var ia=new Map;function aa(e,t){if(!e||typeof e!=`object`)return!1;let n=ia.get(t);n||(n=new WeakMap,ia.set(t,n));let r=n.get(e);if(r===void 0){let i=Object.prototype.toString.call(e);r=i.substring(8,i.length-1)===t,n.set(e,r)}return r}function oa(e,t){return typeof WebGLBuffer<`u`&&aa(t,`WebGLBuffer`)}function sa(e,t){return typeof WebGLTexture<`u`&&aa(t,`WebGLTexture`)}var ca=35044,la=34962,ua=34963,da=34660,fa=5120,pa=5121,ma=5122,ha=5123,ga=5124,_a=5125,va=5126,ya={attribPrefix:``};function ba(e,t,n,r,i){e.bindBuffer(t,n),e.bufferData(t,r,i||ca)}function xa(e,t,n,r){if(oa(e,t))return t;n||=la;let i=e.createBuffer();return ba(e,n,i,t,r),i}function Sa(e){return e===`indices`}function Ca(e){return e===Int8Array||e===Uint8Array}function wa(e){return e.length?e:e.data}var Ta=/coord|texture/i,Ea=/color|colour/i;function Da(e,t){let n;if(n=Ta.test(e)?2:Ea.test(e)?4:3,t%n>0)throw Error(`Can not guess numComponents for attribute '${e}'. Tried ${n} but ${t} values is not evenly divisible by ${n}. You should specify it.`);return n}function Oa(e,t,n){return e.numComponents||e.size||Da(t,n||wa(e).length)}function ka(e,t){if(ta(e))return e;if(ta(e.data))return e.data;Array.isArray(e)&&(e={data:e});let n=e.type?ja(e.type):void 0;return n||=Sa(t)?Uint16Array:Float32Array,new n(e.data)}function Aa(e){return typeof e==`number`?e:e?$i(e):va}function ja(e){return typeof e==`number`?ea(e):e||Float32Array}function Ma(e,t){return{buffer:t.buffer,numValues:24,type:Aa(t.type),arrayType:ja(t.type)}}function Na(e,t){let n=t.data||t,r=ja(t.type),i=n*r.BYTES_PER_ELEMENT,a=e.createBuffer();return e.bindBuffer(la,a),e.bufferData(la,i,t.drawType||ca),{buffer:a,numValues:n,type:$i(r),arrayType:r}}function Pa(e,t,n){let r=ka(t,n);return{arrayType:r.constructor,buffer:xa(e,r,void 0,t.drawType),type:Qi(r),numValues:0}}function Fa(e,t){let n={};return Object.keys(t).forEach(function(r){if(!Sa(r)){let i=t[r],a=i.attrib||i.name||i.attribName||ya.attribPrefix+r;if(i.value){if(!Array.isArray(i.value)&&!ta(i.value))throw Error(`array.value is not array or typedarray`);n[a]={value:i.value}}else{let t;t=i.buffer&&i.buffer instanceof WebGLBuffer?Ma:typeof i==`number`||typeof i.data==`number`?Na:Pa;let{buffer:o,type:s,numValues:c,arrayType:l}=t(e,i,r),u=i.normalize===void 0?Ca(l):i.normalize,d=Oa(i,r,c);n[a]={buffer:o,numComponents:d,type:s,normalize:u,stride:i.stride||0,offset:i.offset||0,divisor:i.divisor===void 0?void 0:i.divisor,drawType:i.drawType}}}}),e.bindBuffer(la,null),n}function Ia(e,t){return t===fa||t===pa?1:t===ma||t===ha?2:t===ga||t===_a||t===va?4:0}var La=[`position`,`positions`,`a_position`];function Ra(e,t){let n,r=0;for(;r<La.length&&(n=La[r],!(n in t||(n=ya.attribPrefix+n,n in t)));++r);r===La.length&&(n=Object.keys(t)[0]);let i=t[n];if(!i.buffer)return 1;e.bindBuffer(la,i.buffer);let a=e.getBufferParameter(la,da);e.bindBuffer(la,null);let o=a/Ia(e,i.type),s=i.numComponents||i.size,c=o/s;if(c%1!=0)throw Error(`numComponents ${s} not correct for length ${length}`);return c}function za(e,t,n){let r=Fa(e,t),i=Object.assign({},n||{});i.attribs=Object.assign({},n?n.attribs:{},r);let a=t.indices;if(a){let t=ka(a,`indices`);i.indices=xa(e,t,ua),i.numElements=t.length,i.elementType=Qi(t)}else i.numElements||=Ra(e,i.attribs);return i}function Ba(e){return!!e.texStorage2D}var Va=function(){let e={},t={};function n(n){let r=n.constructor.name;if(!e[r]){for(let e in n)if(typeof n[e]==`number`){let r=t[n[e]];t[n[e]]=r?`${r} | ${e}`:e}e[r]=!0}}return function(e,r){return n(e),t[r]||(typeof r==`number`?`0x${r.toString(16)}`:r)}}();new Uint8Array([128,192,255,255]);var Ha=6406,Ua=6407,Wa=6408,Ga=6409,Ka=6410,qa=6402,Ja=34041,Ya=33319,Xa=33320,Za=6403,Qa=36244,$a=36248,eo=36249,to={};{let e=to;e[Ha]={numColorComponents:1},e[Ga]={numColorComponents:1},e[Ka]={numColorComponents:2},e[Ua]={numColorComponents:3},e[Wa]={numColorComponents:4},e[Za]={numColorComponents:1},e[Qa]={numColorComponents:1},e[Ya]={numColorComponents:2},e[Xa]={numColorComponents:2},e[Ua]={numColorComponents:3},e[$a]={numColorComponents:3},e[Wa]={numColorComponents:4},e[eo]={numColorComponents:4},e[qa]={numColorComponents:1},e[Ja]={numColorComponents:2}}var no=na;function ro(e){return typeof document<`u`&&document.getElementById?document.getElementById(e):null}var io=33984,ao=34962,oo=34963,so=35713,co=35714,lo=35632,uo=35633,fo=35981,po=35718,mo=35721,ho=35971,go=35382,_o=35396,vo=35398,yo=35392,bo=35395,xo=5126,So=35664,Co=35665,wo=35666,To=5124,Eo=35667,Do=35668,Oo=35669,ko=35670,Ao=35671,jo=35672,Mo=35673,No=35674,Po=35675,Fo=35676,Io=35678,Lo=35680,Ro=35679,zo=35682,Bo=35685,Vo=35686,Ho=35687,Uo=35688,Wo=35689,Go=35690,Ko=36289,qo=36292,Jo=36293,Yo=5125,Xo=36294,Zo=36295,Qo=36296,$o=36298,es=36299,ts=36300,ns=36303,rs=36306,is=36307,as=36308,os=36311,ss=3553,cs=34067,ls=32879,us=35866,J={};function ds(e,t){return J[t].bindPoint}function fs(e,t){return function(n){e.uniform1f(t,n)}}function ps(e,t){return function(n){e.uniform1fv(t,n)}}function ms(e,t){return function(n){e.uniform2fv(t,n)}}function hs(e,t){return function(n){e.uniform3fv(t,n)}}function gs(e,t){return function(n){e.uniform4fv(t,n)}}function _s(e,t){return function(n){e.uniform1i(t,n)}}function vs(e,t){return function(n){e.uniform1iv(t,n)}}function ys(e,t){return function(n){e.uniform2iv(t,n)}}function bs(e,t){return function(n){e.uniform3iv(t,n)}}function xs(e,t){return function(n){e.uniform4iv(t,n)}}function Ss(e,t){return function(n){e.uniform1ui(t,n)}}function Cs(e,t){return function(n){e.uniform1uiv(t,n)}}function ws(e,t){return function(n){e.uniform2uiv(t,n)}}function Ts(e,t){return function(n){e.uniform3uiv(t,n)}}function Es(e,t){return function(n){e.uniform4uiv(t,n)}}function Ds(e,t){return function(n){e.uniformMatrix2fv(t,!1,n)}}function Os(e,t){return function(n){e.uniformMatrix3fv(t,!1,n)}}function ks(e,t){return function(n){e.uniformMatrix4fv(t,!1,n)}}function As(e,t){return function(n){e.uniformMatrix2x3fv(t,!1,n)}}function js(e,t){return function(n){e.uniformMatrix3x2fv(t,!1,n)}}function Ms(e,t){return function(n){e.uniformMatrix2x4fv(t,!1,n)}}function Ns(e,t){return function(n){e.uniformMatrix4x2fv(t,!1,n)}}function Ps(e,t){return function(n){e.uniformMatrix3x4fv(t,!1,n)}}function Fs(e,t){return function(n){e.uniformMatrix4x3fv(t,!1,n)}}function Y(e,t,n,r){let i=ds(e,t);return Ba(e)?function(t){let a,o;!t||sa(e,t)?(a=t,o=null):(a=t.texture,o=t.sampler),e.uniform1i(r,n),e.activeTexture(io+n),e.bindTexture(i,a),e.bindSampler(n,o)}:function(t){e.uniform1i(r,n),e.activeTexture(io+n),e.bindTexture(i,t)}}function X(e,t,n,r,i){let a=ds(e,t),o=new Int32Array(i);for(let e=0;e<i;++e)o[e]=n+e;return Ba(e)?function(t){e.uniform1iv(r,o),t.forEach(function(t,r){e.activeTexture(io+o[r]);let i,s;!t||sa(e,t)?(i=t,s=null):(i=t.texture,s=t.sampler),e.bindSampler(n,s),e.bindTexture(a,i)})}:function(t){e.uniform1iv(r,o),t.forEach(function(t,n){e.activeTexture(io+o[n]),e.bindTexture(a,t)})}}J[xo]={Type:Float32Array,size:4,setter:fs,arraySetter:ps},J[So]={Type:Float32Array,size:8,setter:ms,cols:2},J[Co]={Type:Float32Array,size:12,setter:hs,cols:3},J[wo]={Type:Float32Array,size:16,setter:gs,cols:4},J[To]={Type:Int32Array,size:4,setter:_s,arraySetter:vs},J[Eo]={Type:Int32Array,size:8,setter:ys,cols:2},J[Do]={Type:Int32Array,size:12,setter:bs,cols:3},J[Oo]={Type:Int32Array,size:16,setter:xs,cols:4},J[Yo]={Type:Uint32Array,size:4,setter:Ss,arraySetter:Cs},J[Xo]={Type:Uint32Array,size:8,setter:ws,cols:2},J[Zo]={Type:Uint32Array,size:12,setter:Ts,cols:3},J[Qo]={Type:Uint32Array,size:16,setter:Es,cols:4},J[ko]={Type:Uint32Array,size:4,setter:_s,arraySetter:vs},J[Ao]={Type:Uint32Array,size:8,setter:ys,cols:2},J[jo]={Type:Uint32Array,size:12,setter:bs,cols:3},J[Mo]={Type:Uint32Array,size:16,setter:xs,cols:4},J[No]={Type:Float32Array,size:32,setter:Ds,rows:2,cols:2},J[Po]={Type:Float32Array,size:48,setter:Os,rows:3,cols:3},J[Fo]={Type:Float32Array,size:64,setter:ks,rows:4,cols:4},J[Bo]={Type:Float32Array,size:32,setter:As,rows:2,cols:3},J[Vo]={Type:Float32Array,size:32,setter:Ms,rows:2,cols:4},J[Ho]={Type:Float32Array,size:48,setter:js,rows:3,cols:2},J[Uo]={Type:Float32Array,size:48,setter:Ps,rows:3,cols:4},J[Wo]={Type:Float32Array,size:64,setter:Ns,rows:4,cols:2},J[Go]={Type:Float32Array,size:64,setter:Fs,rows:4,cols:3},J[Io]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:ss},J[Lo]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:cs},J[Ro]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:ls},J[zo]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:ss},J[Ko]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:us},J[qo]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:us},J[Jo]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:cs},J[$o]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:ss},J[es]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:ls},J[ts]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:cs},J[ns]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:us},J[rs]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:ss},J[is]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:ls},J[as]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:cs},J[os]={Type:null,size:0,setter:Y,arraySetter:X,bindPoint:us};function Is(e,t){return function(n){if(n.value)switch(e.disableVertexAttribArray(t),n.value.length){case 4:e.vertexAttrib4fv(t,n.value);break;case 3:e.vertexAttrib3fv(t,n.value);break;case 2:e.vertexAttrib2fv(t,n.value);break;case 1:e.vertexAttrib1fv(t,n.value);break;default:throw Error(`the length of a float constant value must be between 1 and 4!`)}else e.bindBuffer(ao,n.buffer),e.enableVertexAttribArray(t),e.vertexAttribPointer(t,n.numComponents||n.size,n.type||xo,n.normalize||!1,n.stride||0,n.offset||0),e.vertexAttribDivisor&&e.vertexAttribDivisor(t,n.divisor||0)}}function Z(e,t){return function(n){if(n.value){if(e.disableVertexAttribArray(t),n.value.length===4)e.vertexAttrib4iv(t,n.value);else throw Error(`The length of an integer constant value must be 4!`)}else e.bindBuffer(ao,n.buffer),e.enableVertexAttribArray(t),e.vertexAttribIPointer(t,n.numComponents||n.size,n.type||To,n.stride||0,n.offset||0),e.vertexAttribDivisor&&e.vertexAttribDivisor(t,n.divisor||0)}}function Ls(e,t){return function(n){if(n.value){if(e.disableVertexAttribArray(t),n.value.length===4)e.vertexAttrib4uiv(t,n.value);else throw Error(`The length of an unsigned integer constant value must be 4!`)}else e.bindBuffer(ao,n.buffer),e.enableVertexAttribArray(t),e.vertexAttribIPointer(t,n.numComponents||n.size,n.type||Yo,n.stride||0,n.offset||0),e.vertexAttribDivisor&&e.vertexAttribDivisor(t,n.divisor||0)}}function Rs(e,t,n){let r=n.size,i=n.count;return function(n){e.bindBuffer(ao,n.buffer);let a=n.size||n.numComponents||r,o=a/i,s=n.type||xo,c=J[s].size*a,l=n.normalize||!1,u=n.offset||0,d=c/i;for(let r=0;r<i;++r)e.enableVertexAttribArray(t+r),e.vertexAttribPointer(t+r,o,s,l,c,u+d*r),e.vertexAttribDivisor&&e.vertexAttribDivisor(t+r,n.divisor||0)}}var Q={};Q[xo]={size:4,setter:Is},Q[So]={size:8,setter:Is},Q[Co]={size:12,setter:Is},Q[wo]={size:16,setter:Is},Q[To]={size:4,setter:Z},Q[Eo]={size:8,setter:Z},Q[Do]={size:12,setter:Z},Q[Oo]={size:16,setter:Z},Q[Yo]={size:4,setter:Ls},Q[Xo]={size:8,setter:Ls},Q[Zo]={size:12,setter:Ls},Q[Qo]={size:16,setter:Ls},Q[ko]={size:4,setter:Z},Q[Ao]={size:8,setter:Z},Q[jo]={size:12,setter:Z},Q[Mo]={size:16,setter:Z},Q[No]={size:4,setter:Rs,count:2},Q[Po]={size:9,setter:Rs,count:3},Q[Fo]={size:16,setter:Rs,count:4};var zs=/ERROR:\s*\d+:(\d+)/gi;function Bs(e,t=``,n=0){let r=[...t.matchAll(zs)],i=new Map(r.map((e,n)=>{let i=parseInt(e[1]),a=r[n+1],o=a?a.index:t.length,s=t.substring(e.index,o);return[i-1,s]}));return e.split(`
`).map((e,t)=>{let r=i.get(t);return`${t+1+n}: ${e}${r?`\n\n^^^ ${r}`:``}`}).join(`
`)}var Vs=/^[ \t]*\n/;function Hs(e){let t=0;return Vs.test(e)&&(t=1,e=e.replace(Vs,``)),{lineOffset:t,shaderSource:e}}function Us(e,t){return e.errorCallback(t),e.callback&&setTimeout(()=>{e.callback(`${t}\n${e.errors.join(`
`)}`)}),null}function Ws(e,t,n,r){if(r||=no,!e.getShaderParameter(n,so)){let i=e.getShaderInfoLog(n),{lineOffset:a,shaderSource:o}=Hs(e.getShaderSource(n)),s=`${Bs(o,i,a)}\nError compiling ${Va(e,t)}: ${i}`;return r(s),s}return``}function Gs(e,t,n){let r,i,a;if(typeof t==`function`&&(n=t,t=void 0),typeof e==`function`)n=e,e=void 0;else if(e&&!Array.isArray(e)){let t=e;n=t.errorCallback,e=t.attribLocations,r=t.transformFeedbackVaryings,i=t.transformFeedbackMode,a=t.callback}let o=n||no,s=[],c={errorCallback(e,...t){s.push(e),o(e,...t)},transformFeedbackVaryings:r,transformFeedbackMode:i,callback:a,errors:s};{let n={};Array.isArray(e)?e.forEach(function(e,r){n[e]=t?t[r]:r}):n=e||{},c.attribLocations=n}return c}var Ks=[`VERTEX_SHADER`,`FRAGMENT_SHADER`];function qs(e,t){if(t.indexOf(`frag`)>=0)return lo;if(t.indexOf(`vert`)>=0)return uo}function Js(e,t,n){let r=e.getAttachedShaders(t);for(let t of r)n.has(t)||e.deleteShader(t);e.deleteProgram(t)}var Ys=(e=0)=>new Promise(t=>setTimeout(t,e));function Xs(e,t,n){let r=e.createProgram(),{attribLocations:i,transformFeedbackVaryings:a,transformFeedbackMode:o}=Gs(n);for(let n=0;n<t.length;++n){let i=t[n];if(typeof i==`string`){let t=ro(i),r=t?t.text:i,a=e[Ks[n]];t&&t.type&&(a=qs(e,t.type)||a),i=e.createShader(a),e.shaderSource(i,Hs(r).shaderSource),e.compileShader(i)}e.attachShader(r,i)}Object.entries(i).forEach(([t,n])=>e.bindAttribLocation(r,n,t));{let t=a;t&&(t.attribs&&(t=t.attribs),Array.isArray(t)||(t=Object.keys(t)),e.transformFeedbackVaryings(r,t,o||fo))}return e.linkProgram(r),r}function Zs(e,t,n,r,i){let a=Gs(n,r,i),o=new Set(t),s=Xs(e,t,a);function c(e,t){let n=$s(e,t,a.errorCallback);return n&&Js(e,t,o),n}if(a.callback){Qs(e,s).then(()=>{let t=c(e,s);a.callback(t,t?void 0:s)});return}return c(e,s)?void 0:s}async function Qs(e,t){let n=e.getExtension(`KHR_parallel_shader_compile`),r=n?(e,t)=>e.getProgramParameter(t,n.COMPLETION_STATUS_KHR):()=>!0,i=0;do await Ys(i),i=1e3/60;while(!r(e,t))}function $s(e,t,n){if(n||=no,!e.getProgramParameter(t,co)){let r=e.getProgramInfoLog(t);return n(`Error in program linking: ${r}`),`${r}\n${e.getAttachedShaders(t).map(t=>Ws(e,e.getShaderParameter(t,e.SHADER_TYPE),t,n)).filter(e=>e).join(`
`)}`}}function ec(e,t,n,r,i){return Zs(e,t,n,r,i)}function tc(e){let t=e.name;return t.startsWith(`gl_`)||t.startsWith(`webgl_`)}var nc=/(\.|\[|]|\w+)/g,rc=e=>e>=`0`&&e<=`9`;function ic(e,t,n,r){let i=e.split(nc).filter(e=>e!==``),a=0,o=``;for(;;){let e=i[a++];o+=e;let s=rc(e[0]),c=s?parseInt(e):e;if(s&&(o+=i[a++]),a===i.length){n[c]=t;break}{let e=i[a++],t=e===`[`,s=n[c]||(t?[]:{});n[c]=s,n=s,r[o]=r[o]||function(e){return function(t){cc(e,t)}}(s),o+=e}}}function ac(e,t){let n=0;function r(t,r,i){let a=r.name.endsWith(`[0]`),o=r.type,s=J[o];if(!s)throw Error(`unknown type: 0x${o.toString(16)}`);let c;if(s.bindPoint){let t=n;n+=r.size,c=a?s.arraySetter(e,o,t,i,r.size):s.setter(e,o,t,i,r.size)}else c=s.arraySetter&&a?s.arraySetter(e,i):s.setter(e,i);return c.location=i,c}let i={},a={},o=e.getProgramParameter(t,po);for(let n=0;n<o;++n){let o=e.getActiveUniform(t,n);if(tc(o))continue;let s=o.name;s.endsWith(`[0]`)&&(s=s.substr(0,s.length-3));let c=e.getUniformLocation(t,o.name);if(c){let e=r(t,o,c);i[s]=e,ic(s,e,a,i)}}return i}function oc(e,t){let n={},r=e.getProgramParameter(t,ho);for(let i=0;i<r;++i){let r=e.getTransformFeedbackVarying(t,i);n[r.name]={index:i,type:r.type,size:r.size}}return n}function sc(e,t){let n=e.getProgramParameter(t,po),r=[],i=[];for(let a=0;a<n;++a){i.push(a),r.push({});let n=e.getActiveUniform(t,a);r[a].name=n.name}[[`UNIFORM_TYPE`,`type`],[`UNIFORM_SIZE`,`size`],[`UNIFORM_BLOCK_INDEX`,`blockNdx`],[`UNIFORM_OFFSET`,`offset`]].forEach(function(n){let a=n[0],o=n[1];e.getActiveUniforms(t,i,e[a]).forEach(function(e,t){r[t][o]=e})});let a={},o=e.getProgramParameter(t,go);for(let n=0;n<o;++n){let r=e.getActiveUniformBlockName(t,n),i={index:e.getUniformBlockIndex(t,r),usedByVertexShader:e.getActiveUniformBlockParameter(t,n,_o),usedByFragmentShader:e.getActiveUniformBlockParameter(t,n,vo),size:e.getActiveUniformBlockParameter(t,n,yo),uniformIndices:e.getActiveUniformBlockParameter(t,n,bo)};i.used=i.usedByVertexShader||i.usedByFragmentShader,a[r]=i}return{blockSpecs:a,uniformData:r}}function cc(e,t){for(let n in t){let r=e[n];typeof r==`function`?r(t[n]):cc(e[n],t[n])}}function lc(e,...t){let n=e.uniformSetters||e,r=t.length;for(let e=0;e<r;++e){let r=t[e];if(Array.isArray(r)){let e=r.length;for(let t=0;t<e;++t)lc(n,r[t])}else for(let e in r){let t=n[e];t&&t(r[e])}}}function uc(e,t){let n={},r=e.getProgramParameter(t,mo);for(let i=0;i<r;++i){let r=e.getActiveAttrib(t,i);if(tc(r))continue;let a=e.getAttribLocation(t,r.name),o=Q[r.type],s=o.setter(e,a,o);s.location=a,n[r.name]=s}return n}function dc(e,t){for(let n in t){let r=e[n];r&&r(t[n])}}function fc(e,t,n){n.vertexArrayObject?e.bindVertexArray(n.vertexArrayObject):(dc(t.attribSetters||t,n.attribs),n.indices&&e.bindBuffer(oo,n.indices))}function pc(e,t){let n=ac(e,t),r=uc(e,t),i={program:t,uniformSetters:n,attribSetters:r,uniformLocations:Object.fromEntries(Object.entries(n).map(([e,t])=>[e,t.location])),attribLocations:Object.fromEntries(Object.entries(r).map(([e,t])=>[e,t.location]))};return Ba(e)&&(i.uniformBlockSpec=sc(e,t),i.transformFeedbackInfo=oc(e,t)),i}var mc=/\s|{|}|;/;function hc(e,t,n,r,i){let a=Gs(n,r,i),o=[];if(t=t.map(function(e){if(!mc.test(e)){let t=ro(e);if(t)e=t.text;else{let t=`no element with id: ${e}`;a.errorCallback(t),o.push(t)}}return e}),o.length)return Us(a,``);let s=a.callback;s&&(a.callback=(t,n)=>{s(t,t?void 0:pc(e,n))});let c=ec(e,t,a);return c?pc(e,c):null}var gc=4,_c=5123;function vc(e,t,n,r,i,a){n=n===void 0?gc:n;let o=t.indices,s=t.elementType,c=r===void 0?t.numElements:r;i=i===void 0?0:i,s||o?a===void 0?e.drawElements(n,c,s===void 0?_c:t.elementType,i):e.drawElementsInstanced(n,c,s===void 0?_c:t.elementType,i,a):a===void 0?e.drawArrays(n,i,c):e.drawArraysInstanced(n,i,c,a)}var yc=6402,bc=33190,xc=36012,Sc=35056,Cc=36013,wc=32854,Tc=32855,Ec=36194,Dc=33189,Oc=6401,kc=36168,Ac=34041,jc=36096,Mc=36128,Nc=33306,$={};$[Ac]=Nc,$[Oc]=Mc,$[kc]=Mc,$[yc]=jc,$[Dc]=jc,$[bc]=jc,$[xc]=jc,$[Sc]=Nc,$[Cc]=Nc;var Pc={};Pc[wc]=!0,Pc[Tc]=!0,Pc[Ec]=!0,Pc[Ac]=!0,Pc[Dc]=!0,Pc[Oc]=!0,Pc[kc]=!0;var Fc={addExtensionsToContext:!0},Ic=/^(.*?)_/;function Lc(e,t){Va(e,0);let n=e.getExtension(t);if(n){let r={},i=Ic.exec(t)[1],a=`_`+i;for(let t in n){let o=n[t],s=typeof o==`function`,c=s?i:a,l=t;t.endsWith(c)&&(l=t.substring(0,t.length-c.length)),e[l]===void 0?s?e[l]=function(e){return function(){return e.apply(n,arguments)}}(o):(e[l]=o,r[l]=o):!s&&e[l]!==o&&ra(l,e[l],o,t)}r.constructor={name:n.constructor.name},Va(r,0)}return n}var Rc=`ANGLE_instanced_arrays.EXT_blend_minmax.EXT_color_buffer_float.EXT_color_buffer_half_float.EXT_disjoint_timer_query.EXT_disjoint_timer_query_webgl2.EXT_frag_depth.EXT_sRGB.EXT_shader_texture_lod.EXT_texture_compression_bptc.EXT_texture_compression_rgtc.EXT_texture_filter_anisotropic.OES_element_index_uint.OES_standard_derivatives.OES_texture_float.OES_texture_float_linear.OES_texture_half_float.OES_texture_half_float_linear.OES_vertex_array_object.WEBGL_color_buffer_float.WEBGL_compressed_texture_atc.WEBGL_compressed_texture_etc1.WEBGL_compressed_texture_etc.WEBGL_compressed_texture_pvrtc.WEBGL_compressed_texture_s3tc.WEBGL_compressed_texture_s3tc_srgb.WEBGL_depth_texture.WEBGL_draw_buffers`.split(`.`);function zc(e){for(let t=0;t<Rc.length;++t)Lc(e,Rc[t])}function Bc(e,t){let n=[`webgl2`,`webgl`,`experimental-webgl`],r=null;for(let i=0;i<n.length;++i)if(r=e.getContext(n[i],t),r){Fc.addExtensionsToContext&&zc(r);break}return r}function Vc(e,t){return Bc(e,t)}function Hc(e,t){t||=1,t=Math.max(0,t);let n=e.clientWidth*t|0,r=e.clientHeight*t|0;return e.width!==n||e.height!==r?(e.width=n,e.height=r,!0):!1}var Uc=150,Wc=`
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
`,Gc=`
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
`,Kc=({theme:e,isDaylight:t,paused:n=!1,blendMs:r=0,blendProgress:i})=>{let a=(0,F.useRef)(null),o=(0,F.useRef)(null),s=(0,F.useRef)(0),c=(0,F.useRef)(null),[l,u]=vt([e.primaryColor,e.accentColor],r,i),d=ae(l)||(t?{r:0,g:0,b:0}:{r:255,g:255,b:255}),f=[d.r/255,d.g/255,d.b/255],p=ae(u)||d,m=[p.r/255,p.g/255,p.b/255],h=t?[1,1,1]:[0,0,0],g=(0,F.useRef)(n),_=(0,F.useRef)(f),v=(0,F.useRef)(m),y=(0,F.useRef)(h);return g.current=n,_.current=f,v.current=m,y.current=h,(0,F.useEffect)(()=>{let e=a.current;if(!e)return;let t=Vc(e,{alpha:!1,depth:!1,antialias:!1});if(!t)return;let n=hc(t,[Wc,Gc],e=>{console.error(`SoraBackground twgl program error:`,e)});if(!n)return;let r=new Float32Array(Uc);for(let e=0;e<Uc;e++)r[e]=e;let i=za(t,{a_index:{numComponents:1,data:r}}),l=null,u=()=>{o.current===null&&(o.current=requestAnimationFrame(d))},d=r=>{if(o.current=null,!g.current&&l!==null){let e=(r-l)/1e3;s.current+=e}l=g.current?null:r,Hc(e),t.viewport(0,0,t.canvas.width,t.canvas.height);let a=y.current;t.clearColor(a[0],a[1],a[2],1),t.clear(t.COLOR_BUFFER_BIT),t.enable(t.BLEND),t.blendFunc(t.ONE,t.ONE_MINUS_SRC_ALPHA);let c={u_resolution:[t.canvas.width,t.canvas.height],u_time:s.current,u_particle_color:_.current,u_particle_accent_color:v.current};t.useProgram(n.program),fc(t,n,i),lc(n,c),vc(t,i,t.POINTS),g.current||u()},f=new ResizeObserver(u);return f.observe(e),c.current=u,u(),()=>{c.current=null,f.disconnect(),o.current!==null&&(cancelAnimationFrame(o.current),o.current=null),t.deleteProgram(n.program),i.attribs&&i.attribs.a_index&&i.attribs.a_index.buffer&&t.deleteBuffer(i.attribs.a_index.buffer),de()&&!t.isContextLost()&&t.getExtension(`WEBGL_lose_context`)?.loseContext()}},[]),(0,F.useEffect)(()=>{c.current?.()},[n,t,l,u]),(0,I.jsx)(`canvas`,{ref:a,className:`absolute inset-0 w-full h-full block pointer-events-none`,style:{width:`100%`,height:`100%`,willChange:`transform`,transform:`translateZ(0)`}})},qc={id:`bg-sora`,titleKey:`options.soraBackgroundSettings`},Jc=({t:e,tuning:t,onTuningChange:n})=>(0,I.jsx)(b,{def:qc,children:(0,I.jsx)(O,{label:e(`options.soraBlank`),note:e(`options.soraBlankDesc`),checked:t.blank,onChange:e=>n?.({blank:e})})}),Yc=e({default:()=>Xc}),Xc=ze({mode:`sora`,order:50,labelKey:`options.visualizerBackgroundModeSora`,labelFallback:`Sora`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`path`,{d:`M12 5.5l1.2 2.9 2.9 1.2-2.9 1.2L12 13.7l-1.2-2.9-2.9-1.2 2.9-1.2z`}),(0,I.jsx)(`path`,{d:`M5.5 16.5h.01M18 15.5h.01M7 7h.01`,strokeWidth:`2.2`,opacity:`0.5`})]}),command:{title:`Background: Sora`,description:`Switch background to Sora (starry sky) layout`,keywords:[`sora`,`starry sky`,`star`,`星空`,`空`,`背景切换到 空`,`背景切换到空`,`背景切换到Sora`,`背景切换到星空`]},render:({config:e,theme:t,isDaylight:n,paused:r,staticMode:i,blendMs:a,blendProgress:o})=>(0,I.jsx)(`div`,{className:`absolute inset-0 z-0`,style:{backgroundColor:n?`#ffffff`:`#000000`},children:!e?.sora?.tuning?.blank&&(0,I.jsx)(Kc,{theme:t,isDaylight:n,paused:r||i,blendMs:a,blendProgress:o})}),renderSettingsPanel:({config:e,actions:t,t:n})=>(0,I.jsx)(Jc,{t:n,tuning:e?.sora?.tuning??h,onTuningChange:t?.sora?.onTuningChange}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.sora?.tuning??h;return(0,I.jsx)(ce,{active:r.blank,label:n(`options.soraBlank`),onToggle:()=>t?.sora?.onTuningChange?.({blank:!r.blank}),children:(0,I.jsx)(o,{size:14})})},resetSettings:e=>e?.sora?.onResetTuning?.()}),Zc=({urlBackgroundList:e=[],urlBackgroundSelectedId:t=null})=>{let n=(0,F.useMemo)(()=>oe(e.find(e=>e.id===t)),[e,t]),r=(0,F.useRef)(null),[i,a]=(0,F.useState)(!1);return(0,F.useEffect)(()=>{a(!1);let e=r.current;if(!e)return;let t=e.getBoundingClientRect();if(t.width>0&&t.height>0){a(!0);return}let n=new ResizeObserver(e=>{for(let t of e){let{width:e,height:r}=t.contentRect;e>0&&r>0&&(a(!0),n.disconnect())}});return n.observe(e),()=>{n.disconnect()}},[n]),n?.url?(0,I.jsxs)(`div`,{ref:r,className:`absolute inset-0 z-0 overflow-hidden`,children:[i&&(0,I.jsx)(`iframe`,{src:n.url,title:n.note||n.url,className:`w-full h-full border-0`,style:{pointerEvents:`none`},sandbox:`allow-scripts`,allowFullScreen:!0},n.url),(0,I.jsx)(`div`,{className:`absolute inset-0`,style:{background:`linear-gradient(to bottom, rgba(0,0,0,0.15), rgba(0,0,0,0.35))`,pointerEvents:`none`}})]}):null},Qc={id:`bg-url`,titleKey:`options.urlBackgroundSettings`},$c=()=>`url-bg-${Date.now()}-${Math.random().toString(36).slice(2,8)}`,el=({t:e,urlBackgroundList:t=[],urlBackgroundSelectedId:r=null,onAddUrlBackgroundItem:i,onUpdateUrlBackgroundItem:a,onDeleteUrlBackgroundItem:o,onSetUrlBackgroundSelectedId:s})=>{let[c,u]=(0,F.useState)(!1),[f,p]=(0,F.useState)(null),[m,h]=(0,F.useState)(``),[g,_]=(0,F.useState)(``),v=(0,F.useCallback)(()=>{h(``),_(``),u(!1),p(null)},[]),y=(0,F.useCallback)(()=>{let e=se(m);if(!e)return;let t={id:$c(),url:e,note:g.trim()||e};i?.(t),s?.(t.id),v()},[m,g,i,s,v]),S=(0,F.useCallback)(e=>{u(!1),p(e.id),h(e.url),_(e.note)},[]),T=(0,F.useCallback)(()=>{if(!f)return;let e=se(m);e&&(a?.(f,{url:e,note:g.trim()||e}),v())},[f,m,g,a,v]),E=t=>(0,I.jsx)(x,{below:(0,I.jsxs)(`div`,{className:`flex flex-col gap-2 [&>input]:w-full`,children:[(0,I.jsx)(w,{type:`url`,value:m,onChange:h,placeholder:`https://example.com`}),(0,I.jsx)(w,{value:g,onChange:_,placeholder:e(`options.urlBackgroundNotePlaceholder`)}),(0,I.jsxs)(`div`,{className:`flex justify-end gap-2`,children:[(0,I.jsx)(C,{onClick:v,children:e(`ui.cancel`)}),(0,I.jsx)(C,{variant:`primary`,onClick:t,disabled:!m.trim(),children:e(`options.save`)})]})]})});return(0,I.jsxs)(b,{def:Qc,foot:e(`options.urlBackgroundSettingsDesc`),children:[t.map(t=>f===t.id?(0,I.jsx)(F.Fragment,{children:E(T)},t.id):(0,I.jsxs)(x,{label:(0,I.jsxs)(`button`,{type:`button`,role:`radio`,"aria-checked":t.id===r,onClick:()=>s?.(t.id),className:`flex w-full min-w-0 items-center gap-2.5 rounded text-left`,children:[(0,I.jsx)(`span`,{"aria-hidden":!0,className:`st-t-fast h-4 w-4 shrink-0 rounded-full transition-shadow ${t.id===r?`shadow-[inset_0_0_0_5px_var(--st-accent)]`:`shadow-[inset_0_0_0_1.5px_var(--st-t3)]`}`}),(0,I.jsxs)(`span`,{className:`min-w-0`,children:[(0,I.jsx)(`span`,{className:`block truncate`,children:t.note}),(0,I.jsx)(`span`,{className:`block truncate text-xs leading-[18px] text-[color:var(--st-t2)]`,children:t.url})]})]}),children:[(0,I.jsx)(C,{icon:d,tip:e(`options.urlBackgroundEdit`),onClick:()=>S(t)}),(0,I.jsx)(C,{icon:l,tip:e(`options.urlBackgroundDelete`),onClick:()=>o?.(t.id)})]},t.id)),c?E(y):(0,I.jsx)(x,{label:t.length===0?(0,I.jsx)(j,{children:e(`options.urlBackgroundEmpty`)}):void 0,children:(0,I.jsx)(C,{icon:n,onClick:()=>{p(null),h(``),_(``),u(!0)},children:e(`options.urlBackgroundAdd`)})})]})},tl=e({default:()=>nl}),nl=ze({mode:`url`,order:40,labelKey:`options.visualizerBackgroundModeUrl`,labelFallback:`Embed`,glyph:(0,I.jsxs)(I.Fragment,{children:[(0,I.jsx)(`rect`,{x:`3.5`,y:`5`,width:`17`,height:`14`,rx:`2`}),(0,I.jsx)(`path`,{d:`M3.5 9.5h17`,opacity:`0.55`})]}),command:{title:`Background: Embedded Background`,description:`Switch background to embedded webpage mode`,keywords:[`embedded background`,`embed background`,`background embed`,`background url`,`url background`,`url`,`webpage`,`嵌入背景`,`网页背景`,`背景切换到 嵌入背景`,`背景切换到嵌入背景`]},render:({config:e})=>(0,I.jsx)(Zc,{urlBackgroundList:e?.url?.items,urlBackgroundSelectedId:e?.url?.selectedId}),renderSettingsPanel:({config:e,actions:t,...n})=>(0,I.jsx)(el,{...n,urlBackgroundList:e?.url?.items,urlBackgroundSelectedId:e?.url?.selectedId,onAddUrlBackgroundItem:t?.url?.onAdd,onUpdateUrlBackgroundItem:t?.url?.onUpdate,onDeleteUrlBackgroundItem:t?.url?.onDelete,onSetUrlBackgroundSelectedId:t?.url?.onSelect})}),{entries:rl,byMode:il}=(e=>{let t=Object.entries(e).map(([e,t])=>{if(!t.default)throw Error(`[VisualizerBackgroundRegistry] Missing default export in ${e}`);return t.default}),n={};return t.forEach(e=>{if(n[e.mode])throw Error(`[VisualizerBackgroundRegistry] Duplicate background mode "${e.mode}"`);n[e.mode]=e}),{entries:[...t].sort((e,t)=>e.order-t.order),byMode:n}})(Object.assign({"./common/entry.tsx":Gt,"./latent/entry.tsx":Rn,"./monet/entry.tsx":Xr,"./nomand/entry.tsx":ji,"./sora/entry.tsx":Yc,"./url/entry.tsx":tl}));fe(`VisualizerBackgroundRegistry`,rl.map(e=>e.mode),pe);var al=e=>typeof e==`string`&&!!il[e],ol=e=>il[e]??il.latent,sl=(e,t)=>{let n=ol(e),r=t(n.labelKey);return!r||r===n.labelKey?n.labelFallback:r},cl=e=>!il[e.mode]&&(il[e.mode]=e,rl.push(e),rl.sort((e,t)=>e.order-t.order),!0),ll=e=>{if(!il[e])return!1;delete il[e];let t=rl.findIndex(t=>t.mode===e);return t>=0&&rl.splice(t,1),!0};export{it as _,al as a,ht as c,dt as d,Xe as f,st as g,ct as h,ol as i,ut as l,lt as m,cl as n,ll as o,Ye as p,sl as r,Ft as s,rl as t,ft as u};