import{n as e,r as t}from"./rolldown-runtime-hePW80VL.js";import{b as n}from"./main-BsdjnH0-.js";import{F as r,Fn as i,Ft as a,Gr as o,Vn as s,Vt as c,Xi as l,h as u,qi as d,r as f,x as p,zr as m}from"./lucide-icons-Bwc2gLl8.js";import{t as h}from"./jsx-runtime-NZYk81nU.js";import{t as g}from"./proxy-D4HbjVSQ.js";import{t as _}from"./use-transform-CVmZGyN0.js";import{t as v}from"./use-spring-CM5T8ZIR.js";import{t as y}from"./AnimatePresence-B8vJ7SO2.js";import{I as b,O as x,a as S,c as C,n as w,u as T}from"./kit-mzFtEnOY.js";import{t as E}from"./useReducedMotionFor-dSuZ8kQL.js";import{d as D,g as O,l as k,s as A}from"./types-DqG-aH3a.js";import{i as ee}from"./coverUrl-rJwTH6xF.js";import{a as te,t as ne}from"./visualizerModes-fSl480P8.js";import{o as re,p as ie,u as j}from"./ColorField-h0Q2GXKO.js";import{n as ae,r as oe,t as M}from"./colorMix-08vn8-lY.js";import{a as se,n as ce,o as le,r as ue,t as de}from"./QuickControlChip-DcgXNGCn.js";import{n as fe}from"./beatEffects-DFId9tJB.js";import{n as N,r as P,t as F}from"./panelRows-CSznzkHS.js";import{n as pe}from"./handoffProgress-Bw7P376i.js";import{i as me,l as he,n as ge,o as _e,t as ve}from"./lucideIconResolver-BFgoqpz3.js";import{c as ye,d as be,g as xe,h as I,i as L,l as Se,m as Ce,n as we,o as Te,p as Ee,r as De,s as Oe,t as ke,u as Ae}from"./paperShaderUniforms-CVOHb5ol.js";import{n as je}from"./colorExtractor-B7kaSA5M.js";import{i as Me,o as Ne}from"./motionSignals-CpYHVsF0.js";import{h as Pe,n as Fe}from"./beatFxLive-C9DBk92p.js";import{t as Ie}from"./dist-Czg6G7Yi.js";var R=t(l(),1),z=h(),Le=e=>e,Re={id:`bg-common`,titleKey:`options.visualizerBackgroundModeCommon`},ze={id:`bg-common-cover`,titleKey:`options.previewCoverBackgroundSettings`},Be=({config:e,actions:t,t:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a=e?.common,o=t?.common,s=a?.useCoverColorBg??!1;return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsxs)(x,{def:Re,bare:!0,children:[(0,z.jsx)(N,{label:n(`options.disableVisualizerVignette`),note:n(`options.disableVisualizerVignetteDesc`),checked:a?.disableVignette??!1,onChange:e=>o?.onDisableVignetteChange?.(e)}),(0,z.jsx)(N,{label:n(`options.disableVisualizerGeometricBackground`),note:n(`options.disableVisualizerGeometricBackgroundDesc`),checked:a?.disableGeometricBackground??!1,onChange:e=>o?.onDisableGeometricChange?.(e)})]}),(0,z.jsxs)(x,{def:ze,children:[(0,z.jsx)(N,{label:n(`theme.addCoverColor`),note:n(`options.coverColorBackgroundDesc`),checked:s,onChange:e=>o?.onCoverColorChange?.(e)}),(0,z.jsx)(ie,{when:s,children:(0,z.jsx)(F,{sub:!0,label:n(`options.previewCoverBackgroundOpacity`),value:a?.opacity??.75,min:0,max:1,step:.05,format:P,onChange:e=>o?.onOpacityChange?.(e),onDragStart:r,onDragEnd:i})})]})]})},Ve=384,He=160,Ue=350,We=1e3,Ge=1e3,Ke=4e3,qe=`data-picture-wait`,Je=`data-picture-arriving`,Ye={width:64,height:40},B=null,Xe=e=>{if(!B){let e=document.createElement(`canvas`);e.width=Ye.width,e.height=Ye.height,B=e.getContext(`2d`,{willReadFrequently:!0}),B&&(B.imageSmoothingQuality=`high`)}if(!B)return!1;try{B.clearRect(0,0,Ye.width,Ye.height),B.drawImage(e,0,0,Ye.width,Ye.height);let t=new Uint32Array(B.getImageData(0,0,Ye.width,Ye.height).data.buffer);return t.every(e=>e===t[0])}catch{return B=null,!1}},Ze=e=>[...e.querySelectorAll(`canvas`)].filter(e=>e.width>0&&e.height>0).map(e=>({canvas:e,blank:Xe(e)})),Qe=60,$e=e=>[...e.querySelectorAll(`*`)].slice(0,Qe).some(e=>{let t=getComputedStyle(e);return!!t.backgroundImage&&t.backgroundImage!==`none`&&t.opacity!==`0`&&e.offsetWidth>0&&e.offsetHeight>0}),et=e=>{if(!e.firstElementChild||e.querySelector(`[data-picture-wait]`))return{shows:!1,whole:!1,waits:!1};let t=Ze(e),n=t.every(e=>!e.blank),r=t.some(e=>!e.blank)||!!e.textContent?.trim()||e.querySelector(`svg, img`)!==null,i=!r&&$e(e),a=e.querySelector(`[${Je}]`)!==null;return{shows:r||i,whole:n,waits:a||i&&!n}},tt=e=>e.getAnimations({subtree:!0}).some(e=>e.playState===`running`&&Number.isFinite(Number(e.effect?.getComputedTiming().endTime))),nt=(e,t,n)=>{let r=performance.now(),i=r,a=0,o=0,s=0,c=new MutationObserver(()=>{i=performance.now()});t===`still`&&c.observe(e,{subtree:!0,childList:!0,attributes:!0,characterData:!0});let l=()=>{c.disconnect(),window.clearTimeout(o),window.cancelAnimationFrame(s)},u=()=>{o=window.setTimeout(()=>{s=window.requestAnimationFrame(f)})},d=()=>{let n=performance.now(),{shows:o,whole:s,waits:c}=et(e),l=o&&!c;return l&&!a&&(a=n),l&&(s||n-a>=Ge)&&(t===`drawn`||n-a>=Ue&&(n-i>=He&&!tt(e)||n-a>=We))?`shown`:n-r>=Ke?o?`shown`:`empty`:null},f=()=>{let e;try{e=d()}catch(t){console.warn(`[LivePicture] A stage could not be read:`,t),e=`failed`}if(e){l(),n(e);return}u()};return u(),l},rt=(e,t,n=Math.min(e.width,Ve))=>{t.width=Math.max(1,n),t.height=Math.max(1,Math.round(e.height*n/Math.max(1,e.width)));let r=t.getContext(`2d`);r&&(r.imageSmoothingQuality=`high`,r.drawImage(e,0,0,t.width,t.height))},it=e=>e.replace(/[A-Z]/g,e=>`-${e.toLowerCase()}`),at=e=>{if(!et(e).shows)return null;let t=e.cloneNode(!0),n=t.querySelectorAll(`canvas`);e.querySelectorAll(`canvas`).forEach((e,t)=>{let r=n[t];r.style.width=`${e.offsetWidth}px`,r.style.height=`${e.offsetHeight}px`,e.width>0&&e.height>0&&rt(e,r)});let r=[...e.querySelectorAll(`*`)],i=t.querySelectorAll(`*`);i.forEach(e=>{e.style.willChange=`auto`});for(let t of e.getAnimations({subtree:!0})){let e=t.effect,n=e?.target&&!e.pseudoElement?i[r.indexOf(e.target)]:void 0;if(!e?.target||!n)continue;let a=getComputedStyle(e.target);for(let t of e.getKeyframes())for(let e of Object.keys(t))e!==`offset`&&e!==`computedOffset`&&e!==`easing`&&e!==`composite`&&n.style.setProperty(it(e),a.getPropertyValue(it(e)));n.style.animation=`none`}return t},ot=e=>{let t=new Set(e.querySelectorAll(`canvas`)),n=e=>{for(let n of e)n.addedNodes.forEach(e=>{e instanceof HTMLCanvasElement?t.add(e):e instanceof Element&&e.querySelectorAll(`canvas`).forEach(e=>t.add(e))})},r=new MutationObserver(n);return r.observe(e,{subtree:!0,childList:!0}),()=>{n(r.takeRecords()),r.disconnect();for(let e of t)try{if(e.getContext(`2d`))continue;let t=e.getContext(`webgl2`)??e.getContext(`webgl`);t&&!t.isContextLost()&&t.getExtension(`WEBGL_lose_context`)?.loseContext()}catch{}}},st=e=>{let t=e.cloneNode(!0),n=t.querySelectorAll(`canvas`);return e.querySelectorAll(`canvas`).forEach((e,t)=>{e.width>0&&e.height>0&&rt(e,n[t],e.width)}),t},ct=(0,R.createContext)(null),lt=()=>{let e=(0,R.useContext)(ct);return(0,R.useLayoutEffect)(()=>{e?.claim()},[e]),(0,R.useCallback)(()=>e?.drawn(),[e])},ut=(0,R.createContext)(!1),dt=()=>(0,R.useContext)(ut),ft=e=>1-(1-e)**3,pt=(e,t)=>e.length===t.length&&e.every((e,n)=>e===t[n]),mt=(e,t,n)=>{let r=e.join(`|`),i=(0,R.useMemo)(()=>r.split(`|`),[r]),[a,o]=(0,R.useState)(i),s=(0,R.useRef)(i);return(0,R.useEffect)(()=>{let e=s.current,r=e=>{s.current=e,o(e)};if(pt(e,i))return;if(t<=0||e.length!==i.length){r(i);return}let a=t=>t>=1?i:i.map((n,r)=>ae(e[r],n,t)),c=n?.get()??1;if(n&&c<1)return n.on(`change`,e=>r(a(pe(e,c))));let l=performance.now(),u=0,d=e=>{let n=Math.min(1,(e-l)/t);r(a(n>=1?1:ft(n))),n<1&&(u=requestAnimationFrame(d))};return u=requestAnimationFrame(d),()=>cancelAnimationFrame(u)},[i,t,n]),t<=0?i:a},ht=24,gt=96,_t=()=>{if(typeof navigator>`u`)return!1;let e=navigator.userAgent,t=/iPad|iPhone|iPod/i.test(e)||navigator.platform===`MacIntel`&&navigator.maxTouchPoints>1,n=/WebKit/i.test(e),r=/CriOS|FxiOS|EdgiOS|OPiOS|DuckDuckGo|YaBrowser|GSA/i.test(e);return t&&n&&!r},vt=e=>new Promise(t=>{if(typeof document>`u`){t(null);return}let n=new Image;n.crossOrigin=`anonymous`,n.decoding=`async`,n.onload=()=>{try{let e=document.createElement(`canvas`),r=document.createElement(`canvas`);e.width=ht,e.height=ht,r.width=gt,r.height=gt;let i=e.getContext(`2d`),a=r.getContext(`2d`);if(!i||!a){t(null);return}let o=n.naturalWidth||n.width,s=n.naturalHeight||n.height,c=Math.min(o,s),l=Math.max(0,(o-c)/2),u=Math.max(0,(s-c)/2);i.imageSmoothingEnabled=!0,i.imageSmoothingQuality=`high`,i.drawImage(n,l,u,c,c,0,0,ht,ht),a.imageSmoothingEnabled=!0,a.imageSmoothingQuality=`high`,a.globalAlpha=1,a.drawImage(e,0,0,ht,ht,0,0,gt,gt),[{x:-8,y:-8,size:112,alpha:.22},{x:6,y:0,size:gt,alpha:.14},{x:0,y:6,size:gt,alpha:.14}].forEach(({x:t,y:n,size:r,alpha:i})=>{a.globalAlpha=i,a.drawImage(e,0,0,ht,ht,t,n,r,r)}),a.globalAlpha=1,t(r.toDataURL(`image/jpeg`,.72))}catch(e){console.warn(`[FluidBackground] Failed to build soft focus cover`,e),t(null)}},n.onerror=()=>t(null),n.src=e}),yt=320,bt=640,xt=1e3,St=(e,t)=>{e.fillStyle=`#000`,e.fillStyle=t;let n=String(e.fillStyle),[r,i,a]=n.startsWith(`#`)?[1,3,5].map(e=>parseInt(n.slice(e,e+2),16)):n.match(/[\d.]+/g)??[`0`,`0`,`0`];return[n,`rgba(${r}, ${i}, ${a}, 0)`]},Ct=(e,t)=>{let n=document.createElement(`canvas`);return n.width=e,n.height=t,n},wt=null,Tt=()=>{if(wt!==null)return wt;try{let e=Ct(4,1).getContext(`2d`,{willReadFrequently:!0});!e||typeof e.filter!=`string`?wt=!1:(e.filter=`blur(1px)`,e.fillStyle=`#fff`,e.fillRect(2,0,1,1),wt=e.getImageData(1,0,1,1).data[3]>0)}catch{wt=!1}return wt},Et=(e,t)=>{let{width:n,height:r}=e,i=n/Math.max(1,t*2.5),a=[],o=n,s=r;for(;o/2>=i&&o>2&&s>2;)o=Math.ceil(o/2),s=Math.ceil(s/2),a.push([o,s]);let c=[...a,...a.slice(0,-1).reverse(),[n,r]],l=e;for(let[e,t]of c){let n=Ct(e,t),r=n.getContext(`2d`);if(!r)return l;r.imageSmoothingEnabled=!0,r.imageSmoothingQuality=`high`,r.drawImage(l,0,0,e,t),l=n}return l},Dt=(e,t,n,r)=>{let i=Ct(t,n),a=i.getContext(`2d`);if(!a)return null;let o=Math.max(t/e.width,n/e.height)*1.5,s=e.width*o,c=e.height*o,l=60*t/r,u=Tt();return u&&(a.filter=`blur(${l}px)`),a.imageSmoothingEnabled=!0,a.imageSmoothingQuality=`high`,a.drawImage(e,(t-s)/2,(n-c)/2,s,c),u?i:Et(i,l)},Ot=(e,t,n,r)=>{let i=e.getContext(`2d`);if(!i)return;let{width:a,height:o}=e;if(i.clearRect(0,0,a,o),!t)return;i.drawImage(t,0,0,a,o);let s=Math.hypot(a,o),c=a*o/s,l=o/s*c,u=a/s*c,d=i.createLinearGradient(a/2-l,o/2-u,a/2+l,o/2+u),[f,p]=St(i,n),[m,h]=St(i,r);d.addColorStop(0,f),d.addColorStop(.5,p),d.addColorStop(.5,h),d.addColorStop(1,m),i.globalCompositeOperation=`overlay`,i.globalAlpha=.4,i.fillStyle=d,i.fillRect(0,0,a,o),i.globalCompositeOperation=`source-over`,i.globalAlpha=1},kt=({image:e,primaryColor:t,secondaryColor:n,onDrawn:r})=>{let i=(0,R.useRef)(null),[a,o]=(0,R.useState)(null);(0,R.useLayoutEffect)(()=>{let e=i.current;if(!e)return;let t=()=>{let t=e.clientWidth,n=e.clientHeight;o(e=>e&&e.width===t&&e.height===n?e:{width:t,height:n})};if(t(),typeof ResizeObserver>`u`)return;let n=new ResizeObserver(t);return n.observe(e),()=>n.disconnect()},[]);let s=(0,R.useRef)(r);(0,R.useLayoutEffect)(()=>{s.current=r});let c=(0,R.useRef)(!1),l=(0,R.useRef)(null);return(0,R.useLayoutEffect)(()=>{let r=i.current;if(!r||!a)return;if(a.width>0&&a.height>0){let i=Math.max(1,Math.round(yt*a.height/a.width));(r.width!==yt||r.height!==i)&&(r.width=yt,r.height=i);let o=l.current;e?(!o||o.image!==e||o.width!==r.width||o.height!==r.height||o.cssWidth!==a.width)&&(o={image:e,width:r.width,height:r.height,cssWidth:a.width,canvas:Dt(e,r.width,r.height,a.width)}):o=null,l.current=o,Ot(r,o?.canvas??null,t,n)}if(c.current)return;let o=requestAnimationFrame(()=>{c.current=!0,s.current()});return()=>cancelAnimationFrame(o)},[a,e,t,n]),(0,z.jsx)(`canvas`,{ref:i,"aria-hidden":`true`,className:`absolute inset-0 w-full h-full`})},At=(0,R.memo)(({coverUrl:e,theme:t})=>{let n=(0,R.useMemo)(_t,[]),[r,i]=(0,R.useState)(null),[a,o]=mt([t.primaryColor,t.secondaryColor],xt);(0,R.useEffect)(()=>{let t=!1;return!n||!e?(i(null),()=>{t=!0}):(i(null),vt(e).then(e=>{t||i(e)}),()=>{t=!0})},[e,n]);let s=lt(),c=(0,R.useRef)(0),[l,u]=(0,R.useState)([]),[d,f]=(0,R.useState)(()=>new Set),p=(0,R.useRef)(new Set);(0,R.useEffect)(()=>{let e=new Set(l.map(e=>e.image));p.current.forEach(t=>{e.has(t)||(t.close(),p.current.delete(t))})},[l]),(0,R.useEffect)(()=>()=>{p.current.forEach(e=>e.close()),p.current.clear()},[]),(0,R.useEffect)(()=>{if(n)return;if(!e){u([]);return}let t=!1,r=new Image;return r.decoding=`async`,r.src=e,r.decode().then(()=>{let e=Math.min(1,bt/Math.max(r.naturalWidth,r.naturalHeight));return createImageBitmap(r,{resizeWidth:Math.max(1,Math.round(r.naturalWidth*e)),resizeHeight:Math.max(1,Math.round(r.naturalHeight*e)),resizeQuality:`high`})}).then(n=>{if(t){n.close();return}p.current.add(n),u(t=>{let r=t[t.length-1];return r&&r.sourceCover===e?t:(c.current+=1,[...r?[r]:[],{image:n,sourceCover:e,key:c.current}])})},()=>{t||(u(t=>t.length>0?t:(c.current+=1,[{image:null,sourceCover:e,key:c.current}])),s())}),()=>{t=!0}},[e,n,s]);let m=dt(),h=(0,R.useRef)(m);(0,R.useLayoutEffect)(()=>{h.current=m});let[_,v]=(0,R.useState)(null);(0,R.useEffect)(()=>{(!e||n)&&s()},[e,n,s]);let y=(0,R.useCallback)(e=>{h.current&&v(e),f(t=>t.has(e)?t:new Set(t).add(e)),s()},[s]),[b,x]=(0,R.useState)(null),S=l[l.length-1],C=!!e&&!n&&!(S&&S.sourceCover===e&&S.key===b),w=n?r??e??null:null,T=n&&!!r,E=(0,R.useMemo)(()=>({transform:`scale(${T?1.28:1.2}) translateZ(0)`,opacity:T?.94:.3,willChange:`transform, opacity`,backfaceVisibility:`hidden`,WebkitBackfaceVisibility:`hidden`}),[T]);return(0,z.jsxs)(`div`,{className:`absolute inset-0 w-full h-full overflow-hidden pointer-events-none z-0`,style:{isolation:`isolate`,contain:`paint`,transform:`translateZ(0)`},...C?{[Je]:``}:{},children:[e?(0,z.jsxs)(z.Fragment,{children:[n?(0,z.jsx)(`img`,{src:w??e,alt:``,"aria-hidden":`true`,draggable:!1,decoding:`async`,className:`absolute inset-0 w-full h-full object-cover transition-opacity duration-700 ease-out`,style:E}):(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(`div`,{className:`absolute inset-0 w-full h-full transition-colors duration-1000`,style:{backgroundColor:t.backgroundColor,opacity:.8}}),l.map((e,t)=>{let n=t===l.length-1,r=d.has(e.key);return(0,z.jsx)(g.div,{className:`absolute inset-0 w-full h-full`,style:{willChange:`opacity`},initial:{opacity:+!n},animate:{opacity:n&&!r?0:1},transition:{duration:e.key===_?0:1.5,ease:`easeInOut`},onAnimationComplete:()=>{n&&r&&(u(t=>t.filter(t=>t.key===e.key)),f(t=>t.has(e.key)?new Set([e.key]):t),x(e.key))},children:(0,z.jsx)(kt,{image:e.image,primaryColor:a,secondaryColor:o,onDrawn:()=>y(e.key)})},e.key)})]}),n&&(0,z.jsxs)(z.Fragment,{children:[!T&&(0,z.jsx)(`img`,{src:e,alt:``,"aria-hidden":`true`,draggable:!1,decoding:`async`,className:`absolute inset-0 w-full h-full object-cover`,style:{transform:`scale(1.36) translateZ(0)`,opacity:.12,willChange:`transform, opacity`,backfaceVisibility:`hidden`,WebkitBackfaceVisibility:`hidden`}}),(0,z.jsx)(`div`,{className:`absolute inset-0 w-full h-full`,style:{backgroundColor:t.backgroundColor,opacity:.28}}),(0,z.jsx)(`div`,{className:`absolute inset-0 w-full h-full`,style:{background:`radial-gradient(circle at 20% 20%, ${t.accentColor}55 0%, transparent 42%), radial-gradient(circle at 80% 28%, ${t.secondaryColor}50 0%, transparent 44%), radial-gradient(circle at 50% 78%, ${t.primaryColor}28 0%, transparent 52%)`,opacity:T?.52:.7}})]})]}):(0,z.jsx)(`div`,{className:`absolute inset-0 w-full h-full transition-colors duration-1000`,style:{backgroundColor:t.backgroundColor,opacity:.8}}),(!e||n||S&&!S.image)&&(0,z.jsx)(`div`,{className:`absolute inset-0 w-full h-full`,style:{background:`linear-gradient(to bottom right, ${a}, transparent, ${o})`,opacity:n?.2:.4,mixBlendMode:n?`normal`:`overlay`}})]})},(e,t)=>{if(e.coverUrl!==t.coverUrl)return!1;let n=e.theme,r=t.theme;return n.backgroundColor===r.backgroundColor&&n.primaryColor===r.primaryColor&&n.secondaryColor===r.secondaryColor}),jt=e=>{let t=e?.join(`
`)??``;return(0,R.useEffect)(()=>{t&&me(t.split(`
`))},[t]),(0,R.useSyncExternalStore)(he,ve,ve)},Mt=e=>{switch(e.type){case`circle`:return`bass`;case`square`:return`lowMid`;case`triangle`:return`mid`;case`cross`:return`treble`;default:return`default`}},Nt=e=>e===`triangle`?`polygon(50% 0%, 0% 100%, 100% 100%)`:e===`cross`?`polygon(20% 0%, 0% 20%, 30% 50%, 0% 80%, 20% 100%, 50% 70%, 80% 100%, 100% 80%, 70% 50%, 100% 20%, 80% 0%, 50% 30%)`:`none`,Pt=(e,t)=>{let n=(e.type===`circle`||e.type===`square`)&&!e.filled;return{border:n?`1px solid ${t.secondaryColor}`:`none`,backgroundColor:n?`transparent`:t.secondaryColor,borderRadius:e.type===`circle`?`50%`:`0%`,opacity:e.opacity,clipPath:Nt(e.type)}},Ft=e=>({left:`${e.initialX}%`,top:`${e.initialY}%`,width:e.size,height:e.size,animationDuration:`${e.duration}s`,animationDelay:`${e.delay}s`,"--geometric-dir":e.reverse?-1:1,"--geometric-rotate":`${e.initialRotation}deg`}),It=(e,t)=>{if(e.iconSlot===null||t.length===0)return null;let n=t[Math.floor(e.iconSlot*t.length)];return ge(n)===`loading`?`loading`:_e(n)},Lt=({disabled:e=!1})=>e?null:(0,z.jsx)(`div`,{className:`absolute inset-0 pointer-events-none`,style:{background:`radial-gradient(circle, transparent 40%, rgba(0,0,0,0.6) 100%)`}}),Rt=({theme:e,audioPower:t,audioBands:n,shapes:r,particles:i,hideShapes:a,disableVignette:o,paused:s})=>{let c=e=>{let n=v(e||t,{stiffness:300,damping:30});return _(n,[10,200],[.95,1.45])},l={bass:c(n?.bass),lowMid:c(n?.lowMid),mid:c(n?.mid),vocal:c(n?.vocal),treble:c(n?.treble),default:c(t)},u=e.lyricsIcons||[];return(0,z.jsxs)(`div`,{className:s?`absolute inset-0 geometric-paused`:`absolute inset-0`,children:[!a&&(0,z.jsxs)(z.Fragment,{children:[r.map(t=>{let n=It(t,u),r=n===`loading`?null:n;return(0,z.jsxs)(`div`,{className:`absolute geometric-drift`,style:Ft(t),children:[(0,z.jsx)(g.div,{className:`w-full h-full transition-[color,background-color,border-color,opacity] duration-1000`,style:{...Pt(t,e),...n===null?{}:{opacity:0},scale:l[Mt(t)]}}),t.iconSlot!==null&&(0,z.jsx)(`div`,{className:`absolute inset-0 transition-opacity duration-1000`,style:{opacity:+!!r},children:(0,z.jsx)(g.div,{className:`w-full h-full flex items-center justify-center geometric-pulse transition-colors duration-1000`,style:{color:e.secondaryColor,scale:l.vocal,animationDuration:`${t.duration*.5}s`,animationDelay:`${t.delay}s`,"--geometric-peak":t.opacity*3},children:r&&(0,z.jsx)(r,{size:t.size,strokeWidth:1,absoluteStrokeWidth:!0})})})]},t.id)}),i.map(t=>(0,z.jsx)(`div`,{className:`absolute rounded-full geometric-rise transition-colors duration-1000`,style:{backgroundColor:e.accentColor,width:t.size,height:t.size,left:`${t.left}%`,top:`${t.top}%`,animationDuration:`${t.duration}s`,animationDelay:`${t.delay}s`,"--geometric-peak":t.opacity}},`p-${t.id}`))]}),(0,z.jsx)(Lt,{disabled:o})]})},zt=({theme:e,audioPower:t,audioBands:n,seed:r,hideShapes:i=!1,disableVignette:a=!1,paused:o=!1})=>{jt(e.lyricsIcons);let s=(0,R.useMemo)(()=>{let e=[`circle`,`square`,`triangle`,`cross`],t=0;return Array.from({length:15}).map((n,r)=>{let i=t<6&&Math.random()>.7?Math.random():null;return i!==null&&(t+=1),{id:r,type:e[Math.floor(Math.random()*e.length)],iconSlot:i,initialX:Math.random()*100,initialY:Math.random()*100,size:40+Math.random()*100,duration:i===null?30+Math.random()*30:20+Math.random()*20,delay:Math.random()*5,opacity:.11+Math.random()*.08,reverse:Math.random()>.5,filled:Math.random()<.3,initialRotation:Math.random()*360}})},[r]),c=(0,R.useMemo)(()=>Array.from({length:20}).map((e,t)=>({id:t,size:Math.random()*4+1,left:Math.random()*100,top:Math.random()*100,opacity:Math.random()*.3,duration:15+Math.random()*20,delay:Math.random()*10})),[r]);return(0,z.jsx)(g.div,{className:`absolute inset-0`,initial:!1,animate:{opacity:1},exit:{opacity:0},transition:{duration:.6,ease:`easeInOut`},children:(0,z.jsx)(Rt,{theme:e,audioPower:t,audioBands:n,shapes:s,particles:c,hideShapes:i,disableVignette:a,paused:o})})},Bt=R.memo(e=>{let t=String(e.seed??`default`);return(0,z.jsx)(`div`,{className:`absolute inset-0 overflow-hidden pointer-events-none`,children:(0,z.jsx)(y,{mode:`sync`,children:(0,z.jsx)(zt,{...e},t)})})},(e,t)=>{if(e.seed!==t.seed||e.audioPower!==t.audioPower||e.hideShapes!==t.hideShapes||e.disableVignette!==t.disableVignette||e.paused!==t.paused)return!1;let n=e.audioBands,r=t.audioBands;if(!n!=!r)return!1;let i=!0;if(n&&r&&(i=n.bass===r.bass&&n.lowMid===r.lowMid&&n.mid===r.mid&&n.vocal===r.vocal&&n.treble===r.treble),!i)return!1;let a=e.theme,o=t.theme,s=a.backgroundColor===o.backgroundColor&&a.primaryColor===o.primaryColor&&a.secondaryColor===o.secondaryColor&&a.accentColor===o.accentColor,c=!!(a.lyricsIcons===o.lyricsIcons||a.lyricsIcons?.length===o.lyricsIcons?.length&&a.lyricsIcons?.every((e,t)=>e===o.lyricsIcons?.[t]));return s&&c}),Vt=e({default:()=>Ht}),Ht=Le({mode:`common`,order:10,labelKey:`options.visualizerBackgroundModeCommon`,labelFallback:`Common`,glyph:(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(`path`,{d:`M4 17l5-8 5 8z`}),(0,z.jsx)(`circle`,{cx:`17.5`,cy:`8.5`,r:`3`,opacity:`0.55`})]}),command:{title:`Background: Common`,description:`Switch background to general layout`,keywords:[`background general`,`common`,`general`,`通用背景`,`ty`,`背景切换到 通用`,`背景切换到通用`]},song:({config:e,coverUrl:t,seed:n,staticMode:r})=>[r?null:n??null,e?.common?.useCoverColorBg?t??null:null],render:({config:e,theme:t,coverUrl:n,audioPower:r,audioBands:i,seed:a,staticMode:o,paused:s})=>{let c=e?.common,l=c?.useCoverColorBg??!1;return(0,z.jsxs)(z.Fragment,{children:[l&&(0,z.jsx)(`div`,{className:`absolute inset-0 z-0`,children:(0,z.jsx)(At,{coverUrl:n,theme:t})}),(0,z.jsx)(`div`,{className:`absolute inset-0 z-0 transition-all duration-1000`,style:{backgroundColor:t.backgroundColor,opacity:l?c?.opacity??.75:1}}),!o&&(0,z.jsx)(`div`,{className:`absolute inset-0 z-0`,children:(0,z.jsx)(Bt,{theme:t,audioPower:r,audioBands:i,seed:a,hideShapes:c?.disableGeometricBackground??!1,disableVignette:c?.disableVignette??!1,paused:s})})]})},renderSettingsPanel:e=>(0,z.jsx)(Be,{...e}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.common?.useCoverColorBg??!1,i=!(e?.common?.disableVignette??!1);return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(ce,{active:r,label:n(r?`theme.addCoverColor`:`theme.useDefaultColor`),onToggle:()=>t?.common?.onCoverColorChange?.(!r),children:(0,z.jsx)(m,{size:14})}),(0,z.jsx)(ce,{active:i,label:n(`options.visualizerVignette`),onToggle:()=>t?.common?.onDisableVignetteChange?.(i),children:(0,z.jsx)(d,{size:14})})]})},resetSettings:e=>{e?.common?.onOpacityChange?.(.75),e?.common?.onCoverColorChange?.(!1),e?.common?.onDisableVignetteChange?.(!1),e?.common?.onDisableGeometricChange?.(!1)}}),Ut={maxColorCount:10},Wt=`#version 300 es
precision mediump float;

uniform float u_time;

uniform vec4 u_colors[${Ut.maxColorCount}];
uniform float u_colorsCount;

uniform float u_distortion;
uniform float u_swirl;
uniform float u_grainMixer;
uniform float u_grainOverlay;

in vec2 v_objectUV;
out vec4 fragColor;

${Te}
${Ae}
${Se}

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

  for (int i = 0; i < ${Ut.maxColorCount}; i++) {
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
`,Gt=`#version 300 es
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

${be}
${Te}
${ye}
${Se}

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
`,Kt={simplex:1,warp:2,dots:3,wave:4,ripple:5,swirl:6,sphere:7},qt={random:1,"2x2":2,"4x4":3,"8x8":4},Jt=`#version 300 es
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

${Te}
${Ae}
${Ee}
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

${Oe}

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
`,Yt=`#version 300 es
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

${Te}
${Ae}
${Se}

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
`,Xt={lines:1,linesIrregular:2,wave:3,zigzag:4,pattern:5},Zt={prism:1,lens:2,contour:3,cascade:4,flat:5},Qt=`#version 300 es
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


${Se}
${Te}

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
`,$t=`#version 300 es
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

${Te}
${Se}
${Ae}

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
`,en=`#version 300 es
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

${Te}
${Ae}
${Se}

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
`,tn={classic:0,gooey:1,holes:2,soft:3},nn={square:0,hex:1};function rn(e,t){if(Object.keys(e).length!==Object.keys(t).length)return!1;for(let n in e){if(n===`colors`){let n=Array.isArray(e.colors),r=Array.isArray(t.colors);if(!n||!r){if(Object.is(e.colors,t.colors)===!1)return!1;continue}if(e.colors?.length!==t.colors?.length||!e.colors?.every((e,n)=>e===t.colors?.[n]))return!1;continue}if(Object.is(e[n],t[n])===!1)return!1}return!0}var V={name:`Default`,params:{...I,speed:1,frame:0,colors:[`#e0eaff`,`#241d9a`,`#f75092`,`#9f50d3`],distortion:.8,swirl:.1,grainMixer:0,grainOverlay:0}};({...I}),{...I},{...I};var an=(0,R.memo)(function({speed:e=V.params.speed,frame:t=V.params.frame,colors:n=V.params.colors,distortion:r=V.params.distortion,swirl:i=V.params.swirl,grainMixer:a=V.params.grainMixer,grainOverlay:o=V.params.grainOverlay,fit:s=V.params.fit,rotation:c=V.params.rotation,scale:l=V.params.scale,originX:u=V.params.originX,originY:d=V.params.originY,offsetX:f=V.params.offsetX,offsetY:p=V.params.offsetY,worldWidth:m=V.params.worldWidth,worldHeight:h=V.params.worldHeight,...g}){let _={u_colors:n.map(L),u_colorsCount:n.length,u_distortion:r,u_swirl:i,u_grainMixer:a,u_grainOverlay:o,u_fit:Ce[s],u_rotation:c,u_scale:l,u_offsetX:f,u_offsetY:p,u_originX:u,u_originY:d,u_worldWidth:m,u_worldHeight:h};return(0,z.jsx)(we,{...g,speed:e,frame:t,fragmentShader:Wt,uniforms:_})},rn),H={name:`Default`,params:{...xe,speed:1,frame:0,scale:.6,colorBack:`#000000`,colorFront:`#00b2ff`,shape:`sphere`,type:`4x4`,size:2}};({...xe}),{...xe},{...I},{...I},{...I};var on=(0,R.memo)(function({speed:e=H.params.speed,frame:t=H.params.frame,colorBack:n=H.params.colorBack,colorFront:r=H.params.colorFront,shape:i=H.params.shape,type:a=H.params.type,pxSize:o,size:s=o===void 0?H.params.size:o,fit:c=H.params.fit,scale:l=H.params.scale,rotation:u=H.params.rotation,originX:d=H.params.originX,originY:f=H.params.originY,offsetX:p=H.params.offsetX,offsetY:m=H.params.offsetY,worldWidth:h=H.params.worldWidth,worldHeight:g=H.params.worldHeight,..._}){let v={u_colorBack:L(n),u_colorFront:L(r),u_shape:Kt[i],u_type:qt[a],u_pxSize:s,u_fit:Ce[c],u_scale:l,u_rotation:u,u_offsetX:p,u_offsetY:m,u_originX:d,u_originY:f,u_worldWidth:h,u_worldHeight:g};return(0,z.jsx)(we,{..._,speed:e,frame:t,fragmentShader:Gt,uniforms:v})}),U={name:`Default`,params:{...I,fit:`cover`,scale:.6,speed:0,frame:0,colorFront:`#9fadbc`,colorBack:`#ffffff`,contrast:.3,roughness:.4,fiber:.3,fiberSize:.2,crumples:.3,crumpleSize:.35,folds:.65,foldCount:5,fade:0,drops:.2,seed:5.8}};({...I}),{...I},{...I};var sn=(0,R.memo)(function({speed:e=U.params.speed,frame:t=U.params.frame,colorFront:n=U.params.colorFront,colorBack:r=U.params.colorBack,image:i=``,contrast:a=U.params.contrast,roughness:o=U.params.roughness,fiber:s=U.params.fiber,crumples:c=U.params.crumples,folds:l=U.params.folds,drops:u=U.params.drops,seed:d=U.params.seed,fiberScale:f,fiberSize:p=f===void 0?U.params.fiberSize:.2/f,crumplesScale:m,crumpleSize:h=m===void 0?U.params.crumpleSize:.2/m,blur:g,fade:_=g===void 0?U.params.fade:g,foldsNumber:v,foldCount:y=v===void 0?U.params.foldCount:v,fit:b=U.params.fit,scale:x=U.params.scale,rotation:S=U.params.rotation,originX:C=U.params.originX,originY:w=U.params.originY,offsetX:T=U.params.offsetX,offsetY:E=U.params.offsetY,worldWidth:D=U.params.worldWidth,worldHeight:O=U.params.worldHeight,...k}){let A=typeof window<`u`&&{u_noiseTexture:De()},ee={u_image:i,u_colorFront:L(n),u_colorBack:L(r),u_contrast:a,u_roughness:o,u_fiber:s,u_fiberSize:p,u_crumples:c,u_crumpleSize:h,u_foldCount:y,u_folds:l,u_fade:_,u_drops:u,u_seed:d,...A,u_fit:Ce[b],u_scale:x,u_rotation:S,u_offsetX:T,u_offsetY:E,u_originX:C,u_originY:w,u_worldWidth:D,u_worldHeight:O};return(0,z.jsx)(we,{...k,speed:e,frame:t,fragmentShader:Jt,mipmaps:[`u_image`],uniforms:ee})},rn),W={name:`Default`,params:{...I,fit:`cover`,speed:0,frame:0,colorBack:`#00000000`,colorShadow:`#000000`,colorHighlight:`#ffffff`,shadows:.25,size:.5,angle:0,distortionShape:`prism`,highlights:.1,shape:`lines`,distortion:.5,shift:0,blur:0,edges:.25,stretch:0,margin:0,marginLeft:0,marginRight:0,marginTop:0,marginBottom:0,grainMixer:0,grainOverlay:0}};({...I}),{...I},{...I};var cn=(0,R.memo)(function({speed:e=W.params.speed,frame:t=W.params.frame,colorBack:n=W.params.colorBack,colorShadow:r=W.params.colorShadow,colorHighlight:i=W.params.colorHighlight,image:a=``,shadows:o=W.params.shadows,angle:s=W.params.angle,distortion:c=W.params.distortion,distortionShape:l=W.params.distortionShape,highlights:u=W.params.highlights,shape:d=W.params.shape,shift:f=W.params.shift,blur:p=W.params.blur,edges:m=W.params.edges,margin:h,marginLeft:g=h??W.params.marginLeft,marginRight:_=h??W.params.marginRight,marginTop:v=h??W.params.marginTop,marginBottom:y=h??W.params.marginBottom,grainMixer:b=W.params.grainMixer,grainOverlay:x=W.params.grainOverlay,stretch:S=W.params.stretch,count:C,size:w=C===void 0?W.params.size:(1/(C*1.6))**(1/6)/.7-.5,fit:T=W.params.fit,scale:E=W.params.scale,rotation:D=W.params.rotation,originX:O=W.params.originX,originY:k=W.params.originY,offsetX:A=W.params.offsetX,offsetY:ee=W.params.offsetY,worldWidth:te=W.params.worldWidth,worldHeight:ne=W.params.worldHeight,...re}){let ie={u_image:a,u_colorBack:L(n),u_colorShadow:L(r),u_colorHighlight:L(i),u_shadows:o,u_size:w,u_angle:s,u_distortion:c,u_shift:f,u_blur:p,u_edges:m,u_stretch:S,u_distortionShape:Zt[l],u_highlights:u,u_shape:Xt[d],u_marginLeft:g,u_marginRight:_,u_marginTop:v,u_marginBottom:y,u_grainMixer:b,u_grainOverlay:x,u_fit:Ce[T],u_scale:E,u_rotation:D,u_offsetX:A,u_offsetY:ee,u_originX:O,u_originY:k,u_worldWidth:te,u_worldHeight:ne};return(0,z.jsx)(we,{...re,speed:e,frame:t,fragmentShader:Yt,mipmaps:[`u_image`],uniforms:ie})}),G={name:`Default`,params:{...I,fit:`cover`,speed:0,frame:0,colorFront:`#94ffaf`,colorBack:`#000c38`,colorHighlight:`#eaff94`,type:`8x8`,size:2,colorSteps:2,originalColors:!1,inverted:!1}};({...I}),{...I},{...I};var ln=(0,R.memo)(function({speed:e=G.params.speed,frame:t=G.params.frame,colorFront:n=G.params.colorFront,colorBack:r=G.params.colorBack,colorHighlight:i=G.params.colorHighlight,image:a=``,type:o=G.params.type,colorSteps:s=G.params.colorSteps,originalColors:c=G.params.originalColors,inverted:l=G.params.inverted,pxSize:u,size:d=u===void 0?G.params.size:u,fit:f=G.params.fit,scale:p=G.params.scale,rotation:m=G.params.rotation,originX:h=G.params.originX,originY:g=G.params.originY,offsetX:_=G.params.offsetX,offsetY:v=G.params.offsetY,worldWidth:y=G.params.worldWidth,worldHeight:b=G.params.worldHeight,...x}){let S={u_image:a,u_colorFront:L(n),u_colorBack:L(r),u_colorHighlight:L(i),u_type:qt[o],u_pxSize:d,u_colorSteps:s,u_originalColors:c,u_inverted:l,u_fit:Ce[f],u_rotation:m,u_scale:p,u_offsetX:_,u_offsetY:v,u_originX:h,u_originY:g,u_worldWidth:y,u_worldHeight:b};return(0,z.jsx)(we,{...x,speed:e,frame:t,fragmentShader:Qt,uniforms:S})},rn),K={name:`Default`,params:{...I,scale:1,fit:`contain`,speed:0,frame:0,spread:.6,bias:1,angle:0,perspective:.1,count:35,dispersion:1,dispersionShift:0,dispersionColor:.6,focusCenter:.8,focusEdges:1,swirl:.35,noise:0,noiseFrequency:.25,noiseOffset:0,lensBulge:0,lensCircle:0,grainMixer:0,grainOverlay:0,imageX:0,imageY:0}};({...I}),{...I},{...I};var un=(0,R.memo)(function({speed:e=K.params.speed,frame:t=K.params.frame,image:n=``,spread:r=K.params.spread,bias:i=K.params.bias,angle:a=K.params.angle,perspective:o=K.params.perspective,count:s=K.params.count,dispersion:c=K.params.dispersion,dispersionShift:l=K.params.dispersionShift,dispersionColor:u=K.params.dispersionColor,focusCenter:d=K.params.focusCenter,focusEdges:f=K.params.focusEdges,swirl:p=K.params.swirl,noise:m=K.params.noise,noiseFrequency:h=K.params.noiseFrequency,noiseOffset:g=K.params.noiseOffset,lensBulge:_=K.params.lensBulge,lensCircle:v=K.params.lensCircle,grainMixer:y=K.params.grainMixer,grainOverlay:b=K.params.grainOverlay,imageX:x=K.params.imageX,imageY:S=K.params.imageY,fit:C=K.params.fit,scale:w=K.params.scale,rotation:T=K.params.rotation,originX:E=K.params.originX,originY:D=K.params.originY,offsetX:O=K.params.offsetX,offsetY:k=K.params.offsetY,worldWidth:A=K.params.worldWidth,worldHeight:ee=K.params.worldHeight,...te}){let ne={u_image:n,u_spread:r,u_bias:i,u_angle:a,u_perspective:o,u_count:s,u_dispersion:c,u_dispersionShift:l,u_dispersionColor:u,u_focusCenter:d,u_focusEdges:f,u_swirl:p,u_noise:m,u_noiseFrequency:h,u_noiseOffset:g,u_lensBulge:_,u_lensCircle:v,u_grainMixer:y,u_grainOverlay:b,u_imageX:x,u_imageY:S,u_fit:Ce[C],u_rotation:T,u_scale:w,u_offsetX:O,u_offsetY:k,u_originX:E,u_originY:D,u_worldWidth:A,u_worldHeight:ee};return(0,z.jsx)(we,{...te,speed:e,frame:t,fragmentShader:$t,mipmaps:[`u_image`],uniforms:ne})},rn),q={name:`Default`,params:{...I,fit:`cover`,speed:0,frame:0,colorBack:`#f2f1e8`,colorFront:`#2b2b2b`,size:.5,radius:1.25,contrast:.4,originalColors:!1,inverted:!1,grainMixer:.2,grainOverlay:.2,grainSize:.5,grid:`hex`,type:`gooey`}};({...I}),{...I},{...I};var dn=(0,R.memo)(function({speed:e=q.params.speed,frame:t=q.params.frame,colorFront:n=q.params.colorFront,colorBack:r=q.params.colorBack,image:i=``,size:a=q.params.size,radius:o=q.params.radius,contrast:s=q.params.contrast,originalColors:c=q.params.originalColors,inverted:l=q.params.inverted,grainMixer:u=q.params.grainMixer,grainOverlay:d=q.params.grainOverlay,grainSize:f=q.params.grainSize,grid:p=q.params.grid,type:m=q.params.type,fit:h=q.params.fit,scale:g=q.params.scale,rotation:_=q.params.rotation,originX:v=q.params.originX,originY:y=q.params.originY,offsetX:b=q.params.offsetX,offsetY:x=q.params.offsetY,worldWidth:S=q.params.worldWidth,worldHeight:C=q.params.worldHeight,...w}){let T={u_image:i,u_colorFront:L(n),u_colorBack:L(r),u_size:a,u_radius:o,u_contrast:s,u_originalColors:c,u_inverted:l,u_grainMixer:u,u_grainOverlay:d,u_grainSize:f,u_grid:nn[p],u_type:tn[m],u_fit:Ce[h],u_rotation:_,u_scale:g,u_offsetX:b,u_offsetY:x,u_originX:v,u_originY:y,u_worldWidth:S,u_worldHeight:C};return(0,z.jsx)(we,{...w,speed:e,frame:t,fragmentShader:en,uniforms:T})},rn),fn=Object.freeze({antialias:!1,depth:!1}),pn=e=>(t=>{if(e.current=t,t)return()=>{e.current=null;let n=t.paperShaderMount?.canvasElement;if(!n)return;let r=n.getContext(`webgl2`);queueMicrotask(()=>{!r||n.isConnected||r.isContextLost()||r.getExtension(`WEBGL_lose_context`)?.loseContext()})}}),mn=921600,hn=.12,gn=300,_n=e=>Math.min(1,Math.max(0,e/255)),vn=e=>Math.min(2,Math.max(0,e)),yn=e=>Math.min(1,Math.max(0,e)),bn=(e,t,n)=>e+(t-e)*n,xn=(e,t,n,r,i)=>(_n(e)*.22+_n(t)*.18+_n(n)*.22+_n(r)*.28+_n(i)*.1)**.55,Sn=(e,t,n,r=.84)=>Math.max(n*r,yn((e-t)*7)),Cn=(e,t)=>yn(e*.42+t*.85),wn=(e,t)=>Math.max(e,t),Tn=(e,t,n)=>n?Cn(e,t):yn(e),En=(e,t,n,r)=>vn(r?e*hn:bn(e,t,n)),Dn=(e,t,n)=>{let r=e[0]??t.secondaryColor;if(n===`cover-only`){let t=e[1]??r,n=e[2]??t;return{ditheringBack:n,ditheringFront:r,mesh:[r,t,n,e[3]??r,e[4]??t,e[5]??n]}}let i=e[1]??t.primaryColor,a=e[2]??r,o=e[3]??i;return{ditheringBack:t.backgroundColor,ditheringFront:r,mesh:[r,i,a,o,t.backgroundColor,t.accentColor]}},On=R.memo(({theme:e,coverUrl:t,audioPower:r,audioBands:i,staticMode:a,paused:o,tuning:s,blendMs:c=0,blendProgress:l})=>{let u=(0,R.useRef)(null),d=(0,R.useRef)(null),f=(0,R.useMemo)(()=>pn(u),[]),p=(0,R.useMemo)(()=>pn(d),[]),m=(0,R.useRef)(null),h=(0,R.useRef)(null),g=(0,R.useRef)(o),_=(0,R.useRef)(+!o),[v,y]=(0,R.useState)([]),b=s??A,x=b.displayMode!==`mesh`,S=b.displayMode!==`dithering`;g.current=o;let C=lt();(0,R.useEffect)(()=>{let e=!0;return t?(je(t,6).then(t=>{e&&(y(t),C())}),()=>{e=!1}):(y([]),C(),()=>{e=!1})},[t,C]);let w=(0,R.useMemo)(()=>Dn(v,e,b.colorSource),[v,e,b.colorSource]),T=mt([e.backgroundColor,w.ditheringBack,w.ditheringFront,...w.mesh],c,l),[E,D,O]=T,k=(0,R.useMemo)(()=>({ditheringBack:D,ditheringFront:O,mesh:T.slice(3)}),[T,D,O]);return(0,R.useEffect)(()=>{let e=u.current?.paperShaderMount,t=d.current?.paperShaderMount;if(a){e?.setSpeed(0),t?.setSpeed(0);return}let o=0,s=new WeakMap,c=(e,t,n)=>{let r=s.get(e);r||(r={},s.set(e,r)),r[t]!==n&&(r[t]=n,e.style[t]=n)},l=0,f=0,p=0,v=0,y=0,x=0,C=null,w=(e,t)=>bn(En(e,t,v,!0),En(e,t,v,!1),_.current),T=e=>{o=requestAnimationFrame(T);let t=g.current,a=C===null?0:1-Math.exp((C-e)/gn),s=C===null?1e3/60:e-C;C=e;let E=e=>n()?1-(1-e)**(s/(1e3/60)):e,D=n()?.84**(s/(1e3/60)):.84;_.current=bn(_.current,+!t,a);let O=t?0:_n(r.get()),k=t?0:_n(i.bass.get()),A=t?0:xn(i.bass.get(),i.lowMid.get(),i.mid.get(),i.vocal.get(),i.treble.get()),ee=t?0:_n(Math.max(i.mid.get(),i.vocal.get()));l=bn(l,O,E(.12)),f=bn(f,k,E(.16)),p=bn(p,ee,E(.13)),x=b.enhancedBeatResponse?Sn(A,y,x,D):0,y=A;let te=!t&&Pe()&&Fe(fe.latentPulse)>0?Cn(A,wn(Me.get(),Ne.get())):Tn(A,x,b.enhancedBeatResponse);v=bn(v,te,E(te>v?.42:.14));let ne=u.current?.paperShaderMount,re=d.current?.paperShaderMount;if(ne){let e=w(b.ditheringSpeed,b.ditheringAudioSpeed);ne.setSpeed(e),ke(ne,{u_pxSize:Math.max(.5,b.ditheringSize-f*b.ditheringSize*.34)},e!==0)}if(re){let e=w(b.meshSpeed,b.meshAudioSpeed);re.setSpeed(e),ke(re,{u_distortion:b.meshDistortion+l*.62,u_swirl:b.meshSwirl+p*.38},e!==0)}m.current&&(c(m.current,`opacity`,S?`${Math.min(1,b.ditheringOpacity+f*.25)}`:`1`),c(m.current,`transform`,`scale(${1.015+f*.025})`)),h.current&&(c(h.current,`filter`,`saturate(${1.04+p*.34}) brightness(${.94+l*.16})`),c(h.current,`transform`,`scale(${1.025+l*.018})`))};return o=requestAnimationFrame(T),()=>cancelAnimationFrame(o)},[i,r,S,a,b]),(0,z.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,style:{backgroundColor:E,pointerEvents:`none`},children:[S&&(0,z.jsx)(`div`,{ref:h,className:`absolute inset-0`,style:{transform:`scale(1.025)`,transformOrigin:`center`},children:(0,z.jsx)(an,{ref:p,width:`100%`,height:`100%`,colors:k.mesh,distortion:b.meshDistortion,swirl:b.meshSwirl,grainMixer:0,grainOverlay:.01,speed:a?0:b.meshSpeed,minPixelRatio:1,maxPixelCount:mn,webGlContextAttributes:fn,style:{width:`100%`,height:`100%`}})}),x&&(0,z.jsx)(`div`,{ref:m,className:`absolute inset-0`,style:{mixBlendMode:S?`soft-light`:`normal`,opacity:S?b.ditheringOpacity:1,transform:`scale(1.015)`,transformOrigin:`center`},children:(0,z.jsx)(on,{ref:f,width:`100%`,height:`100%`,colorBack:k.ditheringBack,colorFront:k.ditheringFront,shape:`warp`,type:`4x4`,size:b.ditheringSize,speed:a?0:b.ditheringSpeed,minPixelRatio:1,maxPixelCount:mn,webGlContextAttributes:fn,style:{width:`100%`,height:`100%`}})}),b.overlayEnabled&&b.overlayOpacity>0&&(0,z.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundColor:E,opacity:b.overlayOpacity}})]})}),kn={id:`bg-latent`,titleKey:`options.latentBackgroundSettings`},An={id:`bg-latent-dithering`,titleKey:`options.latentDitheringGroup`},jn={id:`bg-latent-mesh`,titleKey:`options.latentMeshGroup`},Mn=e=>e.toFixed(1),Nn=e=>e.toFixed(2),Pn=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsxs)(x,{def:kn,children:[(0,z.jsx)(j,{label:e(`options.latentDisplayMode`),children:(0,z.jsx)(C,{value:t.displayMode,options:[{value:`dithering`,label:e(`options.latentDisplayDithering`)},{value:`mesh`,label:e(`options.latentDisplayMesh`)},{value:`both`,label:e(`options.latentDisplayBoth`)}],onChange:e=>n?.({displayMode:e})})}),(0,z.jsx)(j,{label:e(`options.latentColorSource`),children:(0,z.jsx)(C,{value:t.colorSource,options:[{value:`cover-theme`,label:e(`options.latentColorSourceCoverTheme`)},{value:`cover-only`,label:e(`options.latentColorSourceCoverOnly`)}],onChange:e=>n?.({colorSource:e})})}),(0,z.jsx)(N,{label:e(`options.latentDynamicOnlyInPlayer`),note:e(`options.latentDynamicOnlyInPlayerDesc`),checked:t.dynamicOnlyInPlayer,onChange:e=>n?.({dynamicOnlyInPlayer:e})}),(0,z.jsx)(N,{label:e(`options.latentEnhancedBeatResponse`),note:e(`options.latentEnhancedBeatResponseDesc`),checked:t.enhancedBeatResponse,onChange:e=>n?.({enhancedBeatResponse:e})}),(0,z.jsx)(N,{label:e(`options.nomandBackgroundOverlay`),note:e(`options.nomandBackgroundOverlayDesc`),checked:t.overlayEnabled,onChange:e=>n?.({overlayEnabled:e})}),(0,z.jsx)(ie,{when:t.overlayEnabled,children:(0,z.jsx)(F,{...a,sub:!0,label:e(`options.nomandBackgroundOverlayOpacity`),value:t.overlayOpacity,min:0,max:1,step:.05,format:P,onChange:e=>n?.({overlayOpacity:e})})})]}),(0,z.jsxs)(x,{def:An,children:[(0,z.jsx)(F,{...a,label:e(`options.latentBaseSpeed`),value:t.ditheringSpeed,min:0,max:2,step:.1,format:Mn,onChange:e=>n?.({ditheringSpeed:e})}),(0,z.jsx)(F,{...a,label:e(`options.latentAudioSpeed`),value:t.ditheringAudioSpeed,min:0,max:2,step:.1,format:Mn,onChange:e=>n?.({ditheringAudioSpeed:e})}),(0,z.jsx)(F,{...a,label:e(`options.latentDitheringSize`),value:t.ditheringSize,min:.5,max:8,step:.25,format:Nn,onChange:e=>n?.({ditheringSize:e})}),(0,z.jsx)(F,{...a,label:e(`options.latentDitheringOpacity`),value:t.ditheringOpacity,min:0,max:1,step:.05,format:P,onChange:e=>n?.({ditheringOpacity:e})})]}),(0,z.jsxs)(x,{def:jn,children:[(0,z.jsx)(F,{...a,label:e(`options.latentBaseSpeed`),value:t.meshSpeed,min:0,max:2,step:.1,format:Mn,onChange:e=>n?.({meshSpeed:e})}),(0,z.jsx)(F,{...a,label:e(`options.latentAudioSpeed`),value:t.meshAudioSpeed,min:0,max:2,step:.1,format:Mn,onChange:e=>n?.({meshAudioSpeed:e})}),(0,z.jsx)(F,{...a,label:e(`options.latentMeshDistortion`),value:t.meshDistortion,min:0,max:2,step:.05,format:Nn,onChange:e=>n?.({meshDistortion:e})}),(0,z.jsx)(F,{...a,label:e(`options.latentMeshSwirl`),value:t.meshSwirl,min:0,max:1,step:.05,format:Nn,onChange:e=>n?.({meshSwirl:e})})]})]})},Fn=e({default:()=>Bn}),In=[`dithering`,`mesh`,`both`],Ln={dithering:`options.latentDisplayDithering`,mesh:`options.latentDisplayMesh`,both:`options.latentDisplayBoth`},Rn=[`cover-theme`,`cover-only`],zn={"cover-theme":`options.latentColorSourceCoverTheme`,"cover-only":`options.latentColorSourceCoverOnly`},Bn=Le({mode:`latent`,order:35,labelKey:`options.visualizerBackgroundModeLatent`,labelFallback:`Latent`,glyph:(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(`path`,{d:`M4.5 7.5h.01M9 7.5h.01M13.5 7.5h.01M18 7.5h.01`,strokeWidth:`2.2`,opacity:`0.55`}),(0,z.jsx)(`path`,{d:`M3 15c3-3.5 6-3.5 9 0s6 3.5 9 0`})]}),command:{title:`Background: Latent`,description:`Switch background to cover-colored audio-reactive shaders`,keywords:[`latent`,`latent background`,`shader background`,`隐现`,`隐现背景`,`音频响应背景`]},beatEffects:[{id:fe.latentPulse,nameKey:`options.beatEffect_latentPulse`,descKey:`options.beatEffect_latentPulseDesc`,source:`beats`,retired:!0}],render:({config:e,theme:t,coverUrl:n,audioPower:r,audioBands:i,staticMode:a,paused:o,blendMs:s,blendProgress:c})=>(0,z.jsx)(On,{theme:t,coverUrl:n,audioPower:r,audioBands:i,staticMode:a,paused:o,tuning:e?.latent?.tuning,blendMs:s,blendProgress:c}),renderSettingsPanel:({config:e,actions:t,...n})=>(0,z.jsx)(Pn,{...n,tuning:e?.latent?.tuning??A,onTuningChange:t?.latent?.onTuningChange}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.latent?.tuning??A,a=n(Ln[r.displayMode]),o=n(zn[r.colorSource]);return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(de,{label:a,title:`${n(`options.latentDisplayMode`)}: ${a}`,onClick:()=>t?.latent?.onTuningChange?.({displayMode:ue(In,r.displayMode)})}),(0,z.jsx)(de,{label:o,title:`${n(`options.latentColorSource`)}: ${o}`,onClick:()=>t?.latent?.onTuningChange?.({colorSource:ue(Rn,r.colorSource)})}),(0,z.jsx)(ce,{active:r.overlayEnabled,label:n(`options.nomandBackgroundOverlay`),onToggle:()=>t?.latent?.onTuningChange?.({overlayEnabled:!r.overlayEnabled}),children:(0,z.jsx)(i,{size:14})})]})},resetSettings:e=>e?.latent?.onResetTuning?.()}),Vn={id:`bg-monet-source`,titleKey:`options.monetGroupBackgroundSource`},Hn={id:`bg-monet-layout`,titleKey:`options.monetGroupLayoutPosition`},Un={id:`bg-monet-filters`,titleKey:`options.monetGroupFiltersPostProcessing`},Wn={id:`bg-monet-tint`,titleKey:`options.monetGroupColorTintWash`},Gn=(e,t,n,r)=>Number.isFinite(e)?Math.min(n,Math.max(t,e)):r,Kn=e=>{let t=e.trim().replace(/^#/,``);return/^[0-9a-fA-F]{6}$/.test(t)?`#${t.toLowerCase()}`:null},qn=e=>(0,z.jsx)(`span`,{className:`absolute inset-0`,style:{backgroundImage:e===`full-overlay`?`linear-gradient(var(--st-t3), var(--st-t3))`:`linear-gradient(90deg, var(--st-t3) 30%, transparent 62%)`}}),Jn=({t:e,tuning:t=k,onTuningChange:n,monetBackgroundImage:r,onUploadMonetBackgroundImage:i,onClearMonetBackgroundImage:a,isLoadingMonetBackgroundImage:o=!1,onSliderPointerDown:c,onSliderCommit:l})=>{let u=(0,R.useRef)(null),[d,f]=(0,R.useState)(null),m={backgroundSource:t.backgroundSource??k.backgroundSource,backgroundLayout:t.backgroundLayout??k.backgroundLayout,backgroundBlurPx:Gn(t.backgroundBlurPx??k.backgroundBlurPx,0,60,k.backgroundBlurPx),backgroundOverlayOpacity:Gn(t.backgroundOverlayOpacity??k.backgroundOverlayOpacity,0,1,k.backgroundOverlayOpacity),backgroundGrayscale:Gn(t.backgroundGrayscale??k.backgroundGrayscale,0,1,k.backgroundGrayscale),backgroundSaturation:Gn(t.backgroundSaturation??k.backgroundSaturation,0,2,k.backgroundSaturation),backgroundWash:Gn(t.backgroundWash??k.backgroundWash,0,1,k.backgroundWash),backgroundHalfPaneOffsetX:Gn(t.backgroundHalfPaneOffsetX??k.backgroundHalfPaneOffsetX,-40,40,k.backgroundHalfPaneOffsetX),backgroundWashColorMode:t.backgroundWashColorMode??k.backgroundWashColorMode,backgroundWashCustomColor:Kn(t.backgroundWashCustomColor)??k.backgroundWashCustomColor,backgroundDriftEnabled:t.backgroundDriftEnabled??k.backgroundDriftEnabled,backgroundDriftStrength:Gn(t.backgroundDriftStrength??k.backgroundDriftStrength,0,1,k.backgroundDriftStrength),backgroundStreaksEnabled:t.backgroundStreaksEnabled??k.backgroundStreaksEnabled},h={onDragStart:c,onDragEnd:l},g=async t=>{let r=Array.from(t.target.files??[]);if(t.target.value=``,f(null),!r.length||!i)return;let a=await i(r);a.ok?(n?.({backgroundSource:`uploaded-global`}),f(r[0].name)):f(a.error||e(`options.monetUploadBackground`))};return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsxs)(x,{def:Vn,children:[(0,z.jsx)(j,{label:e(`options.monetBackgroundSource`),children:(0,z.jsx)(C,{value:m.backgroundSource,options:[{value:`cover-derived`,label:e(`options.monetBackgroundSourceCover`)},{value:`uploaded-global`,label:e(`options.monetBackgroundSourceUploaded`),disabled:!r&&!o}],onChange:e=>n?.({backgroundSource:e})})}),(0,z.jsxs)(j,{label:e(`options.monetUploadBackground`),hint:d||r?.name||`-`,children:[(0,z.jsx)(b,{icon:s,onClick:()=>u.current?.click(),disabled:o||!i,children:e(`options.monetUploadBackground`)}),(0,z.jsx)(b,{icon:p,onClick:()=>void a?.(),disabled:!r||!a,children:e(`options.monetClearBackground`)}),(0,z.jsx)(`input`,{ref:u,type:`file`,accept:`.png,.jpg,.jpeg,.gif,.webp,.svg,image/*`,className:`hidden`,onChange:e=>void g(e)})]})]}),(0,z.jsxs)(x,{def:Hn,children:[(0,z.jsx)(j,{label:e(`options.monetBackgroundLayout`),below:(0,z.jsx)(T,{className:`-mx-4`,columns:4,label:e(`options.monetBackgroundLayout`),value:m.backgroundLayout,options:[{value:`half-pane-gradient`,label:e(`options.monetLayoutHalfPane`)},{value:`full-overlay`,label:e(`options.monetLayoutFullOverlay`)}],picture:qn,onChange:e=>n?.({backgroundLayout:e})})}),(0,z.jsx)(ie,{when:m.backgroundLayout===`half-pane-gradient`,children:(0,z.jsx)(F,{...h,sub:!0,label:e(`options.monetHalfPaneOffsetX`),value:m.backgroundHalfPaneOffsetX,min:-40,max:40,step:2,format:e=>`${Math.round(e)}%`,onChange:e=>n?.({backgroundHalfPaneOffsetX:e})})}),(0,z.jsx)(N,{label:e(`options.monetBackgroundDriftEnabled`),note:e(`options.monetBackgroundDriftEnabledDesc`),checked:m.backgroundDriftEnabled,onChange:e=>n?.({backgroundDriftEnabled:e})}),(0,z.jsx)(ie,{when:m.backgroundDriftEnabled,children:(0,z.jsx)(F,{...h,sub:!0,label:e(`options.monetBackgroundDriftStrength`),value:m.backgroundDriftStrength,min:0,max:1,step:.05,format:P,onChange:e=>n?.({backgroundDriftStrength:e})})})]}),(0,z.jsxs)(x,{def:Un,children:[(0,z.jsx)(F,{...h,label:e(`options.monetBackgroundBlur`),value:m.backgroundBlurPx,min:0,max:60,step:2,format:e=>`${Math.round(e)}px`,onChange:e=>n?.({backgroundBlurPx:e})}),(0,z.jsx)(F,{...h,label:e(`options.monetBackgroundSaturation`),value:m.backgroundSaturation,min:0,max:2,step:.05,format:P,onChange:e=>n?.({backgroundSaturation:e})}),(0,z.jsx)(F,{...h,label:e(`options.monetBackgroundGrayscale`),value:m.backgroundGrayscale,min:0,max:1,step:.02,format:P,onChange:e=>n?.({backgroundGrayscale:e})})]}),(0,z.jsxs)(x,{def:Wn,children:[(0,z.jsx)(F,{...h,label:e(`options.monetBackgroundOverlayOpacity`),value:m.backgroundOverlayOpacity,min:0,max:1,step:.02,format:P,onChange:e=>n?.({backgroundOverlayOpacity:e})}),(0,z.jsx)(F,{...h,label:e(`options.monetBackgroundWash`),value:m.backgroundWash,min:0,max:1,step:.02,format:P,onChange:e=>n?.({backgroundWash:e})}),(0,z.jsx)(N,{label:e(`options.monetBackgroundStreaksEnabled`),note:e(`options.monetBackgroundStreaksEnabledDesc`),checked:m.backgroundStreaksEnabled,onChange:e=>n?.({backgroundStreaksEnabled:e})}),(0,z.jsx)(j,{label:e(`options.monetBackgroundWashColorMode`),children:(0,z.jsx)(C,{value:m.backgroundWashColorMode,options:[{value:`theme`,label:e(`options.monetBackgroundWashTheme`)},{value:`custom`,label:e(`options.monetBackgroundWashCustom`)}],onChange:e=>n?.({backgroundWashColorMode:e})})}),(0,z.jsx)(ie,{when:m.backgroundWashColorMode===`custom`,children:(0,z.jsxs)(j,{sub:!0,label:e(`options.monetBackgroundWashCustomColor`),below:(0,z.jsx)(Ie,{color:m.backgroundWashCustomColor,onChange:e=>n?.({backgroundWashCustomColor:e}),style:{width:`100%`,height:180}}),children:[(0,z.jsx)(`span`,{className:`h-4 w-4 rounded-full shadow-[0_0_0_1px_var(--st-line)]`,style:{backgroundColor:m.backgroundWashCustomColor}}),(0,z.jsx)(w,{children:m.backgroundWashCustomColor.toUpperCase()})]})})]})]})},Yn=1920,Xn=1080,Zn={r:10,g:10,b:12},Qn={r:245,g:245,b:245},J=(e,t,n)=>Math.min(n,Math.max(t,e)),Y=(e,t,n)=>e+(t-e)*n,$n=(e,t,n)=>.2126*e+.7152*t+.0722*n,er=(e,t)=>$n(e.r,e.g,e.b)<=$n(t.r,t.g,t.b)?{shadow:e,highlight:t}:{shadow:t,highlight:e},tr=(e,t,n,r)=>{let i=t.width,a=t.height;if(!i||!a)return;let o=Math.max(n/i,r/a),s=i*o,c=a*o,l=(n-s)/2,u=(r-c)/2;e.drawImage(t,l,u,s,c)},nr=(e,t)=>{let n=oe(e);return n?{r:J(n.r,0,255),g:J(n.g,0,255),b:J(n.b,0,255)}:t},rr=(e,t,n,r)=>{let{shadow:i,highlight:a}=er(t,r);if(e<=.55){let t=e/.55;return{r:Y(i.r,n.r,t),g:Y(i.g,n.g,t),b:Y(i.b,n.b,t)}}let o=(e-.55)/.45;return{r:Y(n.r,a.r,o),g:Y(n.g,a.g,o),b:Y(n.b,a.b,o)}},ir=(e,t,n,r,i)=>{let a=J(i.backgroundGrayscale,0,1),o=J(i.backgroundSaturation,0,2),s=J(i.backgroundWash,0,1);if(a<=0&&Math.abs(o-1)<.001&&s<=0)return;let c=e.getImageData(0,0,t,n),l=c.data,u=nr(r.backgroundColor,Zn),d=nr(r.accentColor,u),f=nr(r.primaryColor,Qn),p=nr(i.backgroundWashCustomColor,d),m=i.backgroundWashColorMode===`custom`?p:d;for(let e=0;e<l.length;e+=4){let t=l[e],n=l[e+1],r=l[e+2];if(l[e+3]===0)continue;let i=$n(t,n,r);if(a>0&&(t=Y(t,i,a),n=Y(n,i,a),r=Y(r,i,a)),Math.abs(o-1)>=.001){let e=$n(t,n,r);t=e+(t-e)*o,n=e+(n-e)*o,r=e+(r-e)*o}if(s>0){let e=rr(J(i/255,0,1),u,m,f);t=Y(t,e.r,s),n=Y(n,e.g,s),r=Y(r,e.b,s)}l[e]=Math.round(J(t,0,255)),l[e+1]=Math.round(J(n,0,255)),l[e+2]=Math.round(J(r,0,255))}e.putImageData(c,0,0)},ar=(e,t,n,r,i)=>{let a=J(i.backgroundOverlayOpacity,0,1),o=e.createLinearGradient(0,0,t,n);o.addColorStop(0,M(r.accentColor,.08+a*.62)),o.addColorStop(.44,M(r.backgroundColor,.16+a*.58)),o.addColorStop(1,M(r.primaryColor,.06+a*.36)),e.fillStyle=o,e.fillRect(0,0,t,n);let s=e.createRadialGradient(t*.18,n*.34,0,t*.18,n*.34,t*.55);s.addColorStop(0,M(r.accentColor,a*.42)),s.addColorStop(1,M(r.backgroundColor,0)),e.fillStyle=s,e.fillRect(0,0,t,n);let c=e.createLinearGradient(t*.45,0,t,0);if(c.addColorStop(0,M(r.backgroundColor,0)),c.addColorStop(1,M(r.backgroundColor,.18+a*.38)),e.fillStyle=c,e.fillRect(0,0,t,n),i.backgroundStreaksEnabled!==!1){e.fillStyle=M(r.backgroundColor,.1+a*.08);for(let r=0;r<18;r+=1){let i=r*127%t,a=r*211%n-40;e.fillRect(i,a,1,n*.28)}}},or=(e,t,n,r,i)=>{let{width:a,height:o}=e.canvas;e.fillStyle=n.backgroundColor,e.fillRect(0,0,a,o),e.save(),i!==null&&(e.filter=`blur(${i}px)`),tr(e,t,a,o),e.restore(),ir(e,a,o,n,r),ar(e,a,o,n,r)},sr=new Map,cr=(e,t,n)=>Math.min(n,Math.max(t,e)),lr=({coverUrl:e,monetBackgroundImage:t,tuning:n})=>n.backgroundSource===`uploaded-global`?t?.url??e??null:e??t?.url??null,ur=async e=>{let t=new Image;(e.startsWith(`http://`)||e.startsWith(`https://`))&&(t.crossOrigin=`anonymous`),t.decoding=`async`;let n=new Promise((n,r)=>{t.onload=()=>n(),t.onerror=()=>r(Error(`Failed to load image: ${e}`))});t.src=e;try{await t.decode()}catch{await n}return t},dr=({coverUrl:e,monetBackgroundImage:t,theme:n,tuning:r})=>JSON.stringify({sourceUrl:lr({coverUrl:e,monetBackgroundImage:t,tuning:r}),uploadedId:r.backgroundSource===`uploaded-global`?t?.id??null:null,theme:{backgroundColor:n.backgroundColor,primaryColor:n.primaryColor,accentColor:n.accentColor},tuning:{backgroundSource:r.backgroundSource,backgroundBlurPx:r.backgroundBlurPx,backgroundOverlayOpacity:r.backgroundOverlayOpacity,backgroundGrayscale:r.backgroundGrayscale,backgroundSaturation:r.backgroundSaturation,backgroundWash:r.backgroundWash,backgroundWashColorMode:r.backgroundWashColorMode,backgroundWashCustomColor:r.backgroundWashCustomColor,backgroundStreaksEnabled:r.backgroundStreaksEnabled}}),fr=null,pr=()=>{if(fr!==null)return fr;if(typeof document>`u`)return!1;try{let e=document.createElement(`canvas`);e.width=2,e.height=2;let t=e.getContext(`2d`);return!t||typeof t.filter!=`string`?(fr=!1,!1):(t.fillStyle=`#000000`,t.fillRect(0,0,2,2),t.filter=`blur(1px)`,t.fillStyle=`#ffffff`,t.fillRect(0,0,1,1),fr=t.getImageData(1,1,1,1).data[0]>0,fr)}catch{return fr=!1,!1}},mr=null,hr=0,gr=null,_r=[],vr=()=>{for(;!gr&&_r.length>0;){let e=_r.shift();if(!e.wanted()){e.request.image.close(),e.settle(void 0);continue}let t=hr+=1;gr={...e,id:t};try{br().postMessage({...e.request,id:t},{transfer:[e.request.image]})}catch{gr=null,e.request.image.close(),e.settle(null)}}},yr=e=>{let t=gr;gr=null,t?.settle(e),vr()},br=()=>{if(mr)return mr;let e=new Worker(new URL(new URL(`monetBackground.worker-BdbhyxNv.js`,import.meta.url).href,``+import.meta.url),{type:`module`});return e.onmessage=e=>{e.data.id===gr?.id&&yr(`picture`in e.data?e.data.picture:null)},e.onerror=()=>{e.terminate(),mr=null,yr(null)},mr=e,e},xr=(e,t)=>new Promise(n=>{_r.push({request:e,wanted:t,settle:n}),vr()}),Sr=(e,t,n,r)=>{try{let i=document.createElement(`canvas`);i.width=Yn,i.height=Xn;let a=i.getContext(`2d`);return a?(or(a,e,t,n,r),new Promise(e=>i.toBlob(e,`image/jpeg`,.92))):Promise.resolve(null)}catch{return Promise.resolve(null)}},Cr=async(e,t,n,r)=>{try{return await Sr(await createImageBitmap(e),t,n,r)}catch{let i=document.createElement(`canvas`);i.width=e.naturalWidth,i.height=e.naturalHeight;let a=i.getContext(`2d`);return!a||i.width<=0||i.height<=0?null:(a.drawImage(e,0,0),Sr(i,t,n,r))}},wr=async({coverUrl:e,monetBackgroundImage:t,theme:n,tuning:r},i)=>{let a=lr({coverUrl:e,monetBackgroundImage:t,tuning:r});if(!a)return null;let o={backgroundColor:n.backgroundColor,primaryColor:n.primaryColor,accentColor:n.accentColor},s=pr()?cr(r.backgroundBlurPx,0,60):null,c=await ur(a),l,u=null;try{u=await createImageBitmap(c)}catch{u=null}if(u?(l=await xr({image:u,colors:o,tuning:r,blurPx:s},i),l===null&&i()&&(l=await Cr(c,o,r,s))):i()&&(l=await Cr(c,o,r,s)),!l)return l;let d=URL.createObjectURL(l),f=new Image;f.src=d;try{await f.decode()}catch(e){throw URL.revokeObjectURL(d),e}return d},Tr=e=>{let t=dr(e),n=sr.get(t);if(!n){let r={url:Promise.resolve(null),holders:0};r.url=wr(e,()=>r.holders>0||(sr.get(t)===r&&sr.delete(t),!1)).then(e=>e??null,()=>null),sr.set(t,r),n=r}let r=n;r.holders+=1;let i=!1;return{url:r.url,release:()=>{i||(i=!0,--r.holders)}}},Er=240,Dr=76,Or=156,kr=3.4,Ar=.035,jr=.01,Mr=12.9898,Nr=78.233,Pr=39.425,Fr=(e,t)=>(e%t+t)%t,Ir=(e,t)=>{let n=Math.sin(e*127.1+t*311.7)*43758.5453;return n-Math.floor(n)},Lr=e=>e*e*(3-2*e),Rr=(e,t,n)=>{let r=Math.floor(e),i=Ir(Fr(r,t),n);return i+(Ir(Fr(r+1,t),n)-i)*Lr(e-r)},zr=(e,t)=>{let n=Rr(e,Dr,t),r=Rr(e*2,152,t+17.31);return(n*.68+r*.32)*2-1},Br=e=>{let t=e.reduce((e,t)=>Math.max(e,Math.abs(t)),0);return t>0?e.map(e=>e/t):e},Vr=e=>{let t=Math.min(1,Math.max(0,e)),n=kr*t,r=1+n/100*2+jr,i=Ar*t,a=[],o=[],s=[];for(let e=0;e<=Or;e+=1){let t=Dr*e/Or;a.push(zr(t,Mr)),o.push(zr(t,Nr)),s.push(zr(t,Pr))}let c=Br(a),l=Br(o),u=Br(s);return{keyframes:c.map((e,t)=>({transform:`translate3d(${(e*n).toFixed(4)}%, ${(l[t]*n).toFixed(4)}%, 0) scale(${(r+i*((u[t]+1)/2)).toFixed(5)})`})),durationMs:Er*1e3,maxTravelPercent:n,minScale:r}},Hr=180,Ur=(e,t,n)=>Math.min(n,Math.max(t,e)),Wr=(e,t,n,r)=>{(0,R.useEffect)(()=>{let i=e.current;if(!i||!t||n<=0||typeof i.animate!=`function`||r)return;let a=Vr(n),o=i.animate(a.keyframes,{duration:a.durationMs,iterations:1/0,easing:`linear`});return()=>o.cancel()},[t,e,n,r])},Gr=(e,t,n)=>n.backgroundSource===`uploaded-global`?t?.url??e??null:e??t?.url??null,Kr=({coverUrl:e,monetBackgroundImage:t,theme:r,isDaylight:i=!1,tuning:a=k,transparentBackground:o=!1,staticMode:s=!1})=>{let[c,l]=(0,R.useState)(null),[u,d]=(0,R.useState)(!1),f=Gr(e,t,a),p=lt(),[m,h]=(0,R.useState)(null),_=(0,R.useRef)(null),v=(0,R.useMemo)(()=>`linear-gradient(135deg, ${M(r.accentColor,.22)}, ${M(r.backgroundColor,.96)} 50%, ${M(r.primaryColor,.18)})`,[r]),b=(0,R.useMemo)(()=>`linear-gradient(90deg, ${M(r.backgroundColor,.18)} 0%, ${M(r.backgroundColor,.32)} 34%, ${M(r.backgroundColor,.66)} 70%, ${M(r.backgroundColor,.82)} 100%)`,[r]),x=(0,R.useMemo)(()=>dr({coverUrl:e,monetBackgroundImage:t,theme:r,tuning:a}),[e,t,r,a]);(0,R.useEffect)(()=>{let n=!1,i;if(!f||o)return l(null),d(!1),p(),()=>{n=!0};d(!0);let s={coverUrl:e,monetBackgroundImage:t,theme:r,tuning:a},c=f===_.current?null:Tr(s),u=null;return i=window.setTimeout(()=>{u=Tr(s),u.url.then(e=>{n||(l(t=>t===e?t:e),d(!1),_.current=f,e&&h(t=>t??e),p())})},Hr),()=>{n=!0,i!==void 0&&window.clearTimeout(i),c?.release(),u?.release()}},[x,f,o,p]);let S=(0,R.useRef)(null),C=Ur(a.backgroundDriftStrength??0,0,1),w=!!a.backgroundDriftEnabled&&!s&&C>0&&!n();Wr(S,w,C,E(`monetBackground`));let T=(0,R.useMemo)(()=>w?{willChange:`transform`}:void 0,[w]),D=(0,R.useMemo)(()=>pr(),[])?0:a.backgroundBlurPx,O=(0,R.useMemo)(()=>D<=0?{}:{filter:`blur(${D}px)`,WebkitFilter:`blur(${D}px)`,transform:`scale(1.1) translateZ(0)`},[D]);if(o)return null;let A=c?`url(${c})`:f?`linear-gradient(135deg, ${M(r.accentColor,.2)}, ${M(r.backgroundColor,.78)}), url(${f})`:v,ee=u?{[Je]:``}:{},te=c||f||`fallback`,ne=te!==m&&{opacity:0};if(a.backgroundLayout===`full-overlay`)return(0,z.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,...ee,children:[(0,z.jsx)(`div`,{ref:S,className:`absolute inset-0`,style:T,children:(0,z.jsx)(y,{initial:!1,children:(0,z.jsx)(g.div,{initial:ne,animate:{opacity:1},exit:{opacity:0},transition:{duration:.8,ease:`easeInOut`},className:`absolute inset-0`,style:{backgroundColor:r.backgroundColor,backgroundImage:A,backgroundSize:`cover`,backgroundPosition:`center`,...O}},te)})}),(0,z.jsx)(`div`,{className:`absolute inset-0`,style:{background:b}})]});let re=(i?.7:.3)+Ur(a.backgroundOverlayOpacity,0,1)*.16,ie=Ur(50+a.backgroundHalfPaneOffsetX,10,90);return(0,z.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,...ee,children:[(0,z.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundColor:r.backgroundColor,backgroundImage:v}}),(0,z.jsx)(y,{initial:!1,children:c||f?(0,z.jsx)(`div`,{className:`absolute inset-y-0 left-0 w-[72%] sm:w-[68%] lg:w-[60%] overflow-hidden`,style:{WebkitMaskImage:`linear-gradient(90deg, rgba(0,0,0,1) 0%, rgba(0,0,0,0.94) 48%, rgba(0,0,0,0.46) 74%, rgba(0,0,0,0) 100%)`,maskImage:`linear-gradient(90deg, rgba(0,0,0,1) 0%, rgba(0,0,0,0.94) 48%, rgba(0,0,0,0.46) 74%, rgba(0,0,0,0) 100%)`},children:(0,z.jsx)(`div`,{ref:S,className:`absolute inset-0`,style:T,children:(0,z.jsx)(g.div,{initial:ne,animate:{opacity:re},exit:{opacity:0},transition:{duration:.8,ease:`easeInOut`},className:`absolute inset-0`,style:{backgroundImage:A,backgroundRepeat:`no-repeat`,backgroundSize:`cover`,backgroundPosition:`${ie}% center`,...O}},te)})}):null}),(0,z.jsx)(`div`,{className:`absolute inset-0`,style:{background:`linear-gradient(90deg, ${M(r.backgroundColor,.14)} 0%, ${M(r.backgroundColor,.28)} 28%, ${M(r.backgroundColor,.62)} 64%, ${M(r.backgroundColor,.86)} 100%)`}}),(0,z.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundImage:`radial-gradient(circle at 18% 34%, ${M(r.accentColor,.18)}, transparent 36%)`,backgroundSize:`cover`,backgroundPosition:`center`}}),(0,z.jsx)(`div`,{className:`absolute inset-0`,style:{background:b}})]})},qr=e({default:()=>Xr}),Jr={"cover-derived":`options.monetBackgroundSourceCover`,"uploaded-global":`options.monetBackgroundSourceUploaded`},Yr=e=>e&&ee(e),Xr=Le({mode:`monet`,order:20,labelKey:`options.visualizerBackgroundModeMonet`,labelFallback:`Monet`,glyph:(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(`rect`,{x:`3.5`,y:`4.5`,width:`17`,height:`15`,rx:`2`}),(0,z.jsx)(`path`,{d:`M20.5 8.5L8 19.5`,opacity:`0.55`})]}),song:({config:e,coverUrl:t})=>[Gr(Yr(t),e?.customImage,e?.monet?.tuning??k)],render:({config:e,coverUrl:t,theme:n,isDaylight:r,staticMode:i})=>(0,z.jsx)(Kr,{coverUrl:Yr(t),monetBackgroundImage:e?.customImage,theme:n,isDaylight:r,tuning:e?.monet?.tuning,transparentBackground:e?.transparent,staticMode:i}),renderSettingsPanel:({config:e,actions:t,t:n,onSliderPointerDown:r,onSliderCommit:i})=>(0,z.jsx)(Jn,{t:n,tuning:e?.monet?.tuning??k,onTuningChange:t?.monet?.onTuningChange,monetBackgroundImage:e?.customImage,onUploadMonetBackgroundImage:t?.customImage?.onUpload,onClearMonetBackgroundImage:t?.customImage?.onClear,isLoadingMonetBackgroundImage:t?.customImage?.isLoading,onSliderPointerDown:r,onSliderCommit:i}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.monet?.tuning??k,i=r.backgroundLayout===`full-overlay`,a=n(i?`options.monetLayoutFullOverlay`:`options.monetLayoutHalfPane`),s=e=>t?.monet?.onTuningChange?.(e),c=r.backgroundSource,l=n(Jr[c]),u=!!e?.customImage;return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(de,{label:a,title:`${n(`options.monetBackgroundLayout`)}: ${a}`,onClick:()=>s({backgroundLayout:i?`half-pane-gradient`:`full-overlay`})}),(0,z.jsx)(de,{label:l,title:`${n(`options.monetBackgroundSource`)}: ${l}`,disabled:!u&&c===`cover-derived`,onClick:()=>s({backgroundSource:u&&c===`cover-derived`?`uploaded-global`:`cover-derived`})}),(0,z.jsx)(ce,{active:r.backgroundStreaksEnabled,label:n(`options.monetBackgroundStreaksEnabled`),onToggle:()=>s({backgroundStreaksEnabled:!r.backgroundStreaksEnabled}),children:(0,z.jsx)(o,{size:14})}),(0,z.jsx)(ce,{active:r.backgroundDriftEnabled,label:n(`options.monetBackgroundDriftEnabled`),onToggle:()=>s({backgroundDriftEnabled:!r.backgroundDriftEnabled}),children:(0,z.jsx)(f,{size:14})})]})},resetSettings:e=>e?.monet?.onResetTuning?.()}),Zr=1.8,Qr=.01,$r=16/9,ei={fiberSize:.2,crumples:.35,crumpleSize:.35,folds:.65,foldCount:5,drops:.2,seed:5.8},ti={perspective:.4,count:20,focusCenter:.55,focusEdges:.8,swirl:.08,lensCircle:.1},ni=e=>Math.min(1,Math.max(0,e)),ri=e=>Math.min(Zr,Math.max(1,e)),ii=e=>e<=1?1:ri(e+Qr),ai=e=>ii(1/(1-2*Math.min(Math.max(e,0),.45))),oi=(e,t,n)=>n&&!t?!e:e,si=(e,t,n)=>oi(!e,t,n),ci=(e,t)=>{let{folds:n,crumples:r,drops:i}=ei;return ai(.02*(2*n+1.5*r+.2*i+.75*ni(e)+.1*ni(t)))},li=(e,t)=>{let n=.5*Math.hypot($r,1),r=ni(t),i=.7*r**(1.3+2.7*r)*(1-ti.focusEdges),a=Math.max(.35,1-i/n);if(e<=0)return ii(1/a);let o=Math.min(e,1)*1.4,s=e=>{let t=2*n/e;return Math.tan(t*o)/Math.tan(o)/t},c=Math.max(1,2*n*o/1.45);if(c>=Zr||s(Zr)>Zr*a)return Zr;if(c===1&&s(1)<=a)return ii(1/a);let l=Zr;for(let e=0;e<32;e+=1){let e=(c+l)/2;s(e)>e*a?c=e:l=e}return ii(l)},ui=(e,t)=>{let n=lt();(0,R.useEffect)(()=>{if(t===null){n();return}let r=0,i=()=>{r=requestAnimationFrame(e.current?.paperShaderMount?n:i)};return i(),()=>cancelAnimationFrame(r)},[e,t,n])},di=(e,t,n)=>n.imageSource===`uploaded-global`?t?.url??e:e??t?.url,fi=R.memo(({coverUrl:e,monetBackgroundImage:t,tuning:r,theme:i,isDaylight:a})=>{let o={...D,...r},s=di(e,t,o),c=(0,R.useRef)(null),l=(0,R.useMemo)(()=>pn(c),[]),u=n()?l:c;return ui(c,s?`${s}:${o.effect}`:null),s?(0,z.jsxs)(`div`,{className:`absolute inset-0 z-0 overflow-hidden`,style:{backgroundColor:i.backgroundColor,pointerEvents:`none`},children:[(()=>{let e={width:`100%`,height:`100%`,ref:u,image:s,fit:`cover`,minPixelRatio:1,maxPixelCount:2073600,webGlContextAttributes:fn,style:{width:`100%`,height:`100%`}};switch(o.effect){case`fluted-glass`:return(0,z.jsx)(cn,{...e,colorBack:i.backgroundColor,colorShadow:i.secondaryColor,colorHighlight:i.primaryColor,shadows:.25,size:o.flutedGlassSize,distortion:o.flutedGlassDistortion,blur:o.flutedGlassBlur,shape:`lines`,distortionShape:`prism`,highlights:.1,edges:.25},`${s}:fluted-glass`);case`paper-texture`:return(0,z.jsx)(sn,{...e,...ei,colorFront:i.accentColor,colorBack:i.backgroundColor,contrast:o.paperTextureContrast,roughness:o.paperTextureRoughness,fiber:o.paperTextureFiber,scale:ci(o.paperTextureRoughness,o.paperTextureFiber)},`${s}:paper-texture`);case`halftone-dots`:return(0,z.jsx)(dn,{...e,colorBack:i.backgroundColor,colorFront:i.accentColor,size:o.halftoneDotsSize,radius:o.halftoneDotsRadius,contrast:o.halftoneDotsContrast,originalColors:o.halftoneDotsOriginalColors,inverted:si(o.halftoneDotsInverted,o.halftoneDotsOriginalColors,a),grid:`hex`,type:`gooey`,grainMixer:.12,grainOverlay:.06,grainSize:.5},`${s}:halftone-dots`);case`lens-distortion`:return(0,z.jsx)(un,{...e,...ti,spread:o.lensDistortionSpread,dispersion:o.lensDistortionDispersion,lensBulge:o.lensDistortionBulge,scale:li(o.lensDistortionBulge,o.lensDistortionSpread)},`${s}:lens-distortion`);default:return(0,z.jsx)(ln,{...e,colorBack:i.backgroundColor,colorFront:i.accentColor,colorHighlight:i.primaryColor,originalColors:o.originalColors,inverted:oi(o.inverted,o.originalColors,a),type:o.ditheringType,size:o.size,colorSteps:o.colorSteps},`${s}:dithering`)}})(),o.overlayEnabled&&o.overlayOpacity>0&&(0,z.jsx)(`div`,{className:`absolute inset-0`,style:{backgroundColor:i.backgroundColor,opacity:o.overlayOpacity}})]}):(0,z.jsx)(`div`,{className:`absolute inset-0 z-0`,style:{backgroundColor:i.backgroundColor}})}),pi=[`2x2`,`4x4`,`8x8`],mi=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(j,{label:e(`options.nomandBackgroundDitheringType`),children:(0,z.jsx)(C,{value:t.ditheringType,options:pi.map(e=>({value:e,label:e})),onChange:e=>n?.({ditheringType:e})})}),(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundSize`),value:t.size,min:.5,max:20,step:.5,format:e=>e.toFixed(1),onChange:e=>n?.({size:e})}),(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundColorSteps`),value:t.colorSteps,min:1,max:7,step:1,format:e=>String(Math.round(e)),onChange:e=>n?.({colorSteps:e})}),(0,z.jsx)(N,{label:e(`options.nomandBackgroundOriginalColors`),checked:t.originalColors,onChange:e=>n?.({originalColors:e})}),(0,z.jsx)(N,{label:e(`options.nomandBackgroundInverted`),checked:t.inverted,onChange:e=>n?.({inverted:e})})]})},hi=e=>e.toFixed(2),gi=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundFlutedGlassSize`),value:t.flutedGlassSize,min:.1,max:1,step:.05,format:hi,onChange:e=>n?.({flutedGlassSize:e})}),(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundFlutedGlassDistortion`),value:t.flutedGlassDistortion,min:0,max:1,step:.05,format:P,onChange:e=>n?.({flutedGlassDistortion:e})}),(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundFlutedGlassBlur`),value:t.flutedGlassBlur,min:0,max:1,step:.01,format:P,onChange:e=>n?.({flutedGlassBlur:e})})]})},_i=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundHalftoneDotsSize`),value:t.halftoneDotsSize,min:.1,max:1,step:.05,format:hi,onChange:e=>n?.({halftoneDotsSize:e})}),(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundHalftoneDotsRadius`),value:t.halftoneDotsRadius,min:.1,max:2,step:.05,format:hi,onChange:e=>n?.({halftoneDotsRadius:e})}),(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundHalftoneDotsContrast`),value:t.halftoneDotsContrast,min:0,max:1,step:.05,format:P,onChange:e=>n?.({halftoneDotsContrast:e})}),(0,z.jsx)(N,{label:e(`options.nomandBackgroundOriginalColors`),checked:t.halftoneDotsOriginalColors,onChange:e=>n?.({halftoneDotsOriginalColors:e})}),(0,z.jsx)(N,{label:e(`options.nomandBackgroundInverted`),checked:t.halftoneDotsInverted,onChange:e=>n?.({halftoneDotsInverted:e})})]})},vi=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundLensDistortionSpread`),value:t.lensDistortionSpread,min:0,max:1,step:.05,format:P,onChange:e=>n?.({lensDistortionSpread:e})}),(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundLensDistortionBulge`),value:t.lensDistortionBulge,min:-1,max:1,step:.05,format:hi,onChange:e=>n?.({lensDistortionBulge:e})}),(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundLensDistortionDispersion`),value:t.lensDistortionDispersion,min:0,max:1,step:.05,format:P,onChange:e=>n?.({lensDistortionDispersion:e})})]})},yi=({t:e,tuning:t,onTuningChange:n,onSliderPointerDown:r,onSliderCommit:i})=>{let a={onDragStart:r,onDragEnd:i};return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundPaperTextureContrast`),value:t.paperTextureContrast,min:0,max:1,step:.01,format:P,onChange:e=>n?.({paperTextureContrast:e})}),(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundPaperTextureRoughness`),value:t.paperTextureRoughness,min:0,max:1,step:.01,format:P,onChange:e=>n?.({paperTextureRoughness:e})}),(0,z.jsx)(F,{...a,label:e(`options.nomandBackgroundPaperTextureFiber`),value:t.paperTextureFiber,min:0,max:1,step:.05,format:P,onChange:e=>n?.({paperTextureFiber:e})})]})},bi={id:`bg-nomand-effect`,titleKey:`options.nomandBackgroundEffect`},xi=[`dithering`,`fluted-glass`,`paper-texture`,`halftone-dots`,`lens-distortion`],Si={dithering:`options.nomandBackgroundEffectDithering`,"fluted-glass":`options.nomandBackgroundEffectFlutedGlass`,"paper-texture":`options.nomandBackgroundEffectPaperTexture`,"halftone-dots":`options.nomandBackgroundEffectHalftoneDots`,"lens-distortion":`options.nomandBackgroundEffectLensDistortion`},Ci={dithering:{backgroundImage:`conic-gradient(var(--st-t2) 25%, transparent 0 50%, var(--st-t2) 0 75%, transparent 0)`,backgroundSize:`8px 8px`},"fluted-glass":{backgroundImage:`repeating-linear-gradient(90deg, transparent 0 2px, var(--st-t2) 5px, transparent 8px)`},"paper-texture":{backgroundImage:`repeating-linear-gradient(37deg, transparent 0 3px, var(--st-t3) 3px 4px), repeating-linear-gradient(-58deg, transparent 0 5px, var(--st-t3) 5px 6px)`},"halftone-dots":{backgroundImage:`radial-gradient(var(--st-t2) 32%, transparent 36%)`,backgroundSize:`8px 8px`},"lens-distortion":{backgroundImage:`radial-gradient(circle at 50% 50%, transparent 0 22%, var(--st-t2) 24% 28%, transparent 30% 46%, var(--st-t3) 48% 52%, transparent 54%)`}},wi=e=>(0,z.jsx)(`span`,{className:`absolute inset-0`,style:Ci[e]}),Ti=e=>{let{t,tuning:n}=e;return(0,z.jsxs)(x,{def:bi,children:[(0,z.jsx)(j,{below:(0,z.jsx)(T,{className:`-mx-4`,columns:3,label:t(`options.nomandBackgroundEffect`),value:n.effect,options:xi.map(e=>({value:e,label:t(Si[e])})),picture:wi,onChange:t=>e.onTuningChange?.({effect:t})})}),n.effect===`dithering`&&(0,z.jsx)(mi,{...e}),n.effect===`fluted-glass`&&(0,z.jsx)(gi,{...e}),n.effect===`paper-texture`&&(0,z.jsx)(yi,{...e}),n.effect===`halftone-dots`&&(0,z.jsx)(_i,{...e}),n.effect===`lens-distortion`&&(0,z.jsx)(vi,{...e})]})},Ei={id:`bg-nomand`,titleKey:`options.nomandBackgroundSettings`},Di=({t:e,tuning:t,onTuningChange:n,monetBackgroundImage:r,onUploadMonetBackgroundImage:i,onClearMonetBackgroundImage:a,isLoadingMonetBackgroundImage:o=!1,onSliderPointerDown:s,onSliderCommit:c})=>{let l={...D,...t},d=(0,R.useRef)(null),[f,m]=(0,R.useState)(``),h=e=>{n?.({imageSource:e})},g=async t=>{if(!t.length||!i)return;let n=await i(t);m(n.ok?e(`options.nomandBackgroundUploadSuccess`):n.error??e(`options.nomandBackgroundUploadFailed`)),n.ok&&h(`uploaded-global`)};return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsxs)(x,{def:Ei,children:[(0,z.jsx)(j,{label:e(`options.nomandBackgroundSource`),children:(0,z.jsx)(C,{value:l.imageSource,options:[{value:`cover-derived`,label:e(`options.monetBackgroundSourceCover`)},{value:`uploaded-global`,label:e(`options.monetBackgroundSourceUploaded`),disabled:!r&&!o}],onChange:h})}),(0,z.jsxs)(j,{label:e(`options.monetUploadBackground`),hint:f||r?.name||`-`,children:[(0,z.jsx)(b,{icon:u,disabled:o||!i,onClick:()=>d.current?.click(),children:e(`options.monetUploadBackground`)}),(0,z.jsx)(b,{icon:p,disabled:!r||!a,onClick:()=>void a?.(),children:e(`options.monetClearBackground`)}),(0,z.jsx)(`input`,{ref:d,type:`file`,accept:`image/png,image/jpeg,image/webp,image/gif`,className:`hidden`,onChange:e=>{g(Array.from(e.target.files??[])),e.target.value=``}})]}),(0,z.jsx)(N,{label:e(`options.nomandBackgroundOverlay`),note:e(`options.nomandBackgroundOverlayDesc`),checked:l.overlayEnabled,onChange:e=>n?.({overlayEnabled:e})}),(0,z.jsx)(ie,{when:l.overlayEnabled,children:(0,z.jsx)(F,{sub:!0,label:e(`options.nomandBackgroundOverlayOpacity`),value:l.overlayOpacity,min:0,max:1,step:.05,format:P,onChange:e=>n?.({overlayOpacity:e}),onDragStart:s,onDragEnd:c})})]}),(0,z.jsx)(Ti,{t:e,tuning:l,onTuningChange:n,onSliderPointerDown:s,onSliderCommit:c})]})},Oi=e({default:()=>ji}),ki={"cover-derived":`options.monetBackgroundSourceCover`,"uploaded-global":`options.monetBackgroundSourceUploaded`},Ai=e=>e&&ee(e),ji=Le({mode:`nomand`,order:30,labelKey:`options.visualizerBackgroundModeNomand`,labelFallback:`Nomand`,glyph:(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(`rect`,{x:`4`,y:`4`,width:`6.5`,height:`6.5`,rx:`0.8`}),(0,z.jsx)(`rect`,{x:`13.5`,y:`4`,width:`6.5`,height:`6.5`,rx:`0.8`,opacity:`0.45`}),(0,z.jsx)(`rect`,{x:`4`,y:`13.5`,width:`6.5`,height:`6.5`,rx:`0.8`,opacity:`0.45`}),(0,z.jsx)(`rect`,{x:`13.5`,y:`13.5`,width:`6.5`,height:`6.5`,rx:`0.8`})]}),command:{title:`Background: Nomand`,description:`Switch background to theme-colored image dithering`,keywords:[`nomand`,`dithering`,`dither`,`shader background`,`漫游`,`像素画`,`像素画背景`,`抖动背景`,`网点背景`,`主题色背景`]},song:({config:e,coverUrl:t})=>[di(Ai(t),e?.customImage,{...D,...e?.nomand?.tuning})??null],render:({config:e,coverUrl:t,theme:n,isDaylight:r})=>(0,z.jsx)(fi,{coverUrl:Ai(t),monetBackgroundImage:e?.customImage,tuning:e?.nomand?.tuning,theme:n,isDaylight:r}),renderSettingsPanel:({config:e,actions:t,...n})=>(0,z.jsx)(Di,{...n,tuning:e?.nomand?.tuning??D,onTuningChange:t?.nomand?.onTuningChange,monetBackgroundImage:e?.customImage,onUploadMonetBackgroundImage:t?.customImage?.onUpload,onClearMonetBackgroundImage:t?.customImage?.onClear,isLoadingMonetBackgroundImage:t?.customImage?.isLoading}),renderQuickControls:({config:e,actions:t,t:n})=>{let r=e?.nomand?.tuning??D,a=e=>t?.nomand?.onTuningChange?.(e),o=r.imageSource,s=n(ki[o]),c=!!e?.customImage,l=n(Si[r.effect]);return(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(de,{label:s,title:`${n(`options.nomandBackgroundSource`)}: ${s}`,disabled:!c&&o===`cover-derived`,onClick:()=>a({imageSource:c&&o===`cover-derived`?`uploaded-global`:`cover-derived`})}),(0,z.jsx)(de,{label:l,title:`${n(`options.nomandBackgroundEffect`)}: ${l}`,onClick:()=>a({effect:ue(xi,r.effect)})}),(0,z.jsx)(ce,{active:r.overlayEnabled,label:n(`options.nomandBackgroundOverlay`),onToggle:()=>a({overlayEnabled:!r.overlayEnabled}),children:(0,z.jsx)(i,{size:14})})]})},resetSettings:e=>e?.nomand?.onResetTuning?.()}),Mi=5120,Ni=5121,Pi=5122,Fi=5123,Ii=5124,Li=5125,Ri=5126,zi=32819,Bi=32820,Vi=33635,Hi=5131,Ui=33640,Wi=35899,Gi=35902,Ki=36269,qi=34042,Ji={};{let e=Ji;e[Mi]=Int8Array,e[Ni]=Uint8Array,e[Pi]=Int16Array,e[Fi]=Uint16Array,e[Ii]=Int32Array,e[Li]=Uint32Array,e[Ri]=Float32Array,e[zi]=Uint16Array,e[Bi]=Uint16Array,e[Vi]=Uint16Array,e[Hi]=Uint16Array,e[Ui]=Uint32Array,e[Wi]=Uint32Array,e[Gi]=Uint32Array,e[Ki]=Uint32Array,e[qi]=Uint32Array}function Yi(e){if(e instanceof Int8Array)return Mi;if(e instanceof Uint8Array||e instanceof Uint8ClampedArray)return Ni;if(e instanceof Int16Array)return Pi;if(e instanceof Uint16Array)return Fi;if(e instanceof Int32Array)return Ii;if(e instanceof Uint32Array)return Li;if(e instanceof Float32Array)return Ri;throw Error(`unsupported typed array type`)}function Xi(e){if(e===Int8Array)return Mi;if(e===Uint8Array||e===Uint8ClampedArray)return Ni;if(e===Int16Array)return Pi;if(e===Uint16Array)return Fi;if(e===Int32Array)return Ii;if(e===Uint32Array)return Li;if(e===Float32Array)return Ri;throw Error(`unsupported typed array type`)}function Zi(e){let t=Ji[e];if(!t)throw Error(`unknown gl type`);return t}var Qi=typeof SharedArrayBuffer<`u`?function(e){return e&&e.buffer&&(e.buffer instanceof ArrayBuffer||e.buffer instanceof SharedArrayBuffer)}:function(e){return e&&e.buffer&&e.buffer instanceof ArrayBuffer};function $i(...e){console.error(...e)}function ea(...e){console.warn(...e)}var ta=new Map;function na(e,t){if(!e||typeof e!=`object`)return!1;let n=ta.get(t);n||(n=new WeakMap,ta.set(t,n));let r=n.get(e);if(r===void 0){let i=Object.prototype.toString.call(e);r=i.substring(8,i.length-1)===t,n.set(e,r)}return r}function ra(e,t){return typeof WebGLBuffer<`u`&&na(t,`WebGLBuffer`)}function ia(e,t){return typeof WebGLTexture<`u`&&na(t,`WebGLTexture`)}var aa=35044,oa=34962,sa=34963,ca=34660,la=5120,ua=5121,da=5122,fa=5123,pa=5124,ma=5125,ha=5126,ga={attribPrefix:``};function _a(e,t,n,r,i){e.bindBuffer(t,n),e.bufferData(t,r,i||aa)}function va(e,t,n,r){if(ra(e,t))return t;n||=oa;let i=e.createBuffer();return _a(e,n,i,t,r),i}function ya(e){return e===`indices`}function ba(e){return e===Int8Array||e===Uint8Array}function xa(e){return e.length?e:e.data}var Sa=/coord|texture/i,Ca=/color|colour/i;function wa(e,t){let n;if(n=Sa.test(e)?2:Ca.test(e)?4:3,t%n>0)throw Error(`Can not guess numComponents for attribute '${e}'. Tried ${n} but ${t} values is not evenly divisible by ${n}. You should specify it.`);return n}function Ta(e,t,n){return e.numComponents||e.size||wa(t,n||xa(e).length)}function Ea(e,t){if(Qi(e))return e;if(Qi(e.data))return e.data;Array.isArray(e)&&(e={data:e});let n=e.type?Oa(e.type):void 0;return n||=ya(t)?Uint16Array:Float32Array,new n(e.data)}function Da(e){return typeof e==`number`?e:e?Xi(e):ha}function Oa(e){return typeof e==`number`?Zi(e):e||Float32Array}function ka(e,t){return{buffer:t.buffer,numValues:24,type:Da(t.type),arrayType:Oa(t.type)}}function Aa(e,t){let n=t.data||t,r=Oa(t.type),i=n*r.BYTES_PER_ELEMENT,a=e.createBuffer();return e.bindBuffer(oa,a),e.bufferData(oa,i,t.drawType||aa),{buffer:a,numValues:n,type:Xi(r),arrayType:r}}function ja(e,t,n){let r=Ea(t,n);return{arrayType:r.constructor,buffer:va(e,r,void 0,t.drawType),type:Yi(r),numValues:0}}function Ma(e,t){let n={};return Object.keys(t).forEach(function(r){if(!ya(r)){let i=t[r],a=i.attrib||i.name||i.attribName||ga.attribPrefix+r;if(i.value){if(!Array.isArray(i.value)&&!Qi(i.value))throw Error(`array.value is not array or typedarray`);n[a]={value:i.value}}else{let t;t=i.buffer&&i.buffer instanceof WebGLBuffer?ka:typeof i==`number`||typeof i.data==`number`?Aa:ja;let{buffer:o,type:s,numValues:c,arrayType:l}=t(e,i,r),u=i.normalize===void 0?ba(l):i.normalize,d=Ta(i,r,c);n[a]={buffer:o,numComponents:d,type:s,normalize:u,stride:i.stride||0,offset:i.offset||0,divisor:i.divisor===void 0?void 0:i.divisor,drawType:i.drawType}}}}),e.bindBuffer(oa,null),n}function Na(e,t){return t===la||t===ua?1:t===da||t===fa?2:t===pa||t===ma||t===ha?4:0}var Pa=[`position`,`positions`,`a_position`];function Fa(e,t){let n,r=0;for(;r<Pa.length&&(n=Pa[r],!(n in t||(n=ga.attribPrefix+n,n in t)));++r);r===Pa.length&&(n=Object.keys(t)[0]);let i=t[n];if(!i.buffer)return 1;e.bindBuffer(oa,i.buffer);let a=e.getBufferParameter(oa,ca);e.bindBuffer(oa,null);let o=a/Na(e,i.type),s=i.numComponents||i.size,c=o/s;if(c%1!=0)throw Error(`numComponents ${s} not correct for length ${length}`);return c}function Ia(e,t,n){let r=Ma(e,t),i=Object.assign({},n||{});i.attribs=Object.assign({},n?n.attribs:{},r);let a=t.indices;if(a){let t=Ea(a,`indices`);i.indices=va(e,t,sa),i.numElements=t.length,i.elementType=Yi(t)}else i.numElements||=Fa(e,i.attribs);return i}function La(e){return!!e.texStorage2D}var Ra=function(){let e={},t={};function n(n){let r=n.constructor.name;if(!e[r]){for(let e in n)if(typeof n[e]==`number`){let r=t[n[e]];t[n[e]]=r?`${r} | ${e}`:e}e[r]=!0}}return function(e,r){return n(e),t[r]||(typeof r==`number`?`0x${r.toString(16)}`:r)}}();new Uint8Array([128,192,255,255]);var za=6406,Ba=6407,Va=6408,Ha=6409,Ua=6410,Wa=6402,Ga=34041,Ka=33319,qa=33320,Ja=6403,Ya=36244,Xa=36248,Za=36249,Qa={};{let e=Qa;e[za]={numColorComponents:1},e[Ha]={numColorComponents:1},e[Ua]={numColorComponents:2},e[Ba]={numColorComponents:3},e[Va]={numColorComponents:4},e[Ja]={numColorComponents:1},e[Ya]={numColorComponents:1},e[Ka]={numColorComponents:2},e[qa]={numColorComponents:2},e[Ba]={numColorComponents:3},e[Xa]={numColorComponents:3},e[Va]={numColorComponents:4},e[Za]={numColorComponents:4},e[Wa]={numColorComponents:1},e[Ga]={numColorComponents:2}}var $a=$i;function eo(e){return typeof document<`u`&&document.getElementById?document.getElementById(e):null}var to=33984,no=34962,ro=34963,io=35713,ao=35714,oo=35632,so=35633,co=35981,lo=35718,uo=35721,fo=35971,po=35382,mo=35396,ho=35398,go=35392,_o=35395,vo=5126,yo=35664,bo=35665,xo=35666,So=5124,Co=35667,wo=35668,To=35669,Eo=35670,Do=35671,Oo=35672,ko=35673,Ao=35674,jo=35675,Mo=35676,No=35678,Po=35680,Fo=35679,Io=35682,Lo=35685,Ro=35686,zo=35687,Bo=35688,Vo=35689,Ho=35690,Uo=36289,Wo=36292,Go=36293,Ko=5125,qo=36294,Jo=36295,Yo=36296,Xo=36298,Zo=36299,Qo=36300,$o=36303,es=36306,ts=36307,ns=36308,rs=36311,is=3553,as=34067,os=32879,ss=35866,X={};function cs(e,t){return X[t].bindPoint}function ls(e,t){return function(n){e.uniform1f(t,n)}}function us(e,t){return function(n){e.uniform1fv(t,n)}}function ds(e,t){return function(n){e.uniform2fv(t,n)}}function fs(e,t){return function(n){e.uniform3fv(t,n)}}function ps(e,t){return function(n){e.uniform4fv(t,n)}}function ms(e,t){return function(n){e.uniform1i(t,n)}}function hs(e,t){return function(n){e.uniform1iv(t,n)}}function gs(e,t){return function(n){e.uniform2iv(t,n)}}function _s(e,t){return function(n){e.uniform3iv(t,n)}}function vs(e,t){return function(n){e.uniform4iv(t,n)}}function ys(e,t){return function(n){e.uniform1ui(t,n)}}function bs(e,t){return function(n){e.uniform1uiv(t,n)}}function xs(e,t){return function(n){e.uniform2uiv(t,n)}}function Ss(e,t){return function(n){e.uniform3uiv(t,n)}}function Cs(e,t){return function(n){e.uniform4uiv(t,n)}}function ws(e,t){return function(n){e.uniformMatrix2fv(t,!1,n)}}function Ts(e,t){return function(n){e.uniformMatrix3fv(t,!1,n)}}function Es(e,t){return function(n){e.uniformMatrix4fv(t,!1,n)}}function Ds(e,t){return function(n){e.uniformMatrix2x3fv(t,!1,n)}}function Os(e,t){return function(n){e.uniformMatrix3x2fv(t,!1,n)}}function ks(e,t){return function(n){e.uniformMatrix2x4fv(t,!1,n)}}function As(e,t){return function(n){e.uniformMatrix4x2fv(t,!1,n)}}function js(e,t){return function(n){e.uniformMatrix3x4fv(t,!1,n)}}function Ms(e,t){return function(n){e.uniformMatrix4x3fv(t,!1,n)}}function Z(e,t,n,r){let i=cs(e,t);return La(e)?function(t){let a,o;!t||ia(e,t)?(a=t,o=null):(a=t.texture,o=t.sampler),e.uniform1i(r,n),e.activeTexture(to+n),e.bindTexture(i,a),e.bindSampler(n,o)}:function(t){e.uniform1i(r,n),e.activeTexture(to+n),e.bindTexture(i,t)}}function Q(e,t,n,r,i){let a=cs(e,t),o=new Int32Array(i);for(let e=0;e<i;++e)o[e]=n+e;return La(e)?function(t){e.uniform1iv(r,o),t.forEach(function(t,r){e.activeTexture(to+o[r]);let i,s;!t||ia(e,t)?(i=t,s=null):(i=t.texture,s=t.sampler),e.bindSampler(n,s),e.bindTexture(a,i)})}:function(t){e.uniform1iv(r,o),t.forEach(function(t,n){e.activeTexture(to+o[n]),e.bindTexture(a,t)})}}X[vo]={Type:Float32Array,size:4,setter:ls,arraySetter:us},X[yo]={Type:Float32Array,size:8,setter:ds,cols:2},X[bo]={Type:Float32Array,size:12,setter:fs,cols:3},X[xo]={Type:Float32Array,size:16,setter:ps,cols:4},X[So]={Type:Int32Array,size:4,setter:ms,arraySetter:hs},X[Co]={Type:Int32Array,size:8,setter:gs,cols:2},X[wo]={Type:Int32Array,size:12,setter:_s,cols:3},X[To]={Type:Int32Array,size:16,setter:vs,cols:4},X[Ko]={Type:Uint32Array,size:4,setter:ys,arraySetter:bs},X[qo]={Type:Uint32Array,size:8,setter:xs,cols:2},X[Jo]={Type:Uint32Array,size:12,setter:Ss,cols:3},X[Yo]={Type:Uint32Array,size:16,setter:Cs,cols:4},X[Eo]={Type:Uint32Array,size:4,setter:ms,arraySetter:hs},X[Do]={Type:Uint32Array,size:8,setter:gs,cols:2},X[Oo]={Type:Uint32Array,size:12,setter:_s,cols:3},X[ko]={Type:Uint32Array,size:16,setter:vs,cols:4},X[Ao]={Type:Float32Array,size:32,setter:ws,rows:2,cols:2},X[jo]={Type:Float32Array,size:48,setter:Ts,rows:3,cols:3},X[Mo]={Type:Float32Array,size:64,setter:Es,rows:4,cols:4},X[Lo]={Type:Float32Array,size:32,setter:Ds,rows:2,cols:3},X[Ro]={Type:Float32Array,size:32,setter:ks,rows:2,cols:4},X[zo]={Type:Float32Array,size:48,setter:Os,rows:3,cols:2},X[Bo]={Type:Float32Array,size:48,setter:js,rows:3,cols:4},X[Vo]={Type:Float32Array,size:64,setter:As,rows:4,cols:2},X[Ho]={Type:Float32Array,size:64,setter:Ms,rows:4,cols:3},X[No]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:is},X[Po]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:as},X[Fo]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:os},X[Io]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:is},X[Uo]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:ss},X[Wo]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:ss},X[Go]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:as},X[Xo]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:is},X[Zo]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:os},X[Qo]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:as},X[$o]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:ss},X[es]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:is},X[ts]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:os},X[ns]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:as},X[rs]={Type:null,size:0,setter:Z,arraySetter:Q,bindPoint:ss};function Ns(e,t){return function(n){if(n.value)switch(e.disableVertexAttribArray(t),n.value.length){case 4:e.vertexAttrib4fv(t,n.value);break;case 3:e.vertexAttrib3fv(t,n.value);break;case 2:e.vertexAttrib2fv(t,n.value);break;case 1:e.vertexAttrib1fv(t,n.value);break;default:throw Error(`the length of a float constant value must be between 1 and 4!`)}else e.bindBuffer(no,n.buffer),e.enableVertexAttribArray(t),e.vertexAttribPointer(t,n.numComponents||n.size,n.type||vo,n.normalize||!1,n.stride||0,n.offset||0),e.vertexAttribDivisor&&e.vertexAttribDivisor(t,n.divisor||0)}}function Ps(e,t){return function(n){if(n.value){if(e.disableVertexAttribArray(t),n.value.length===4)e.vertexAttrib4iv(t,n.value);else throw Error(`The length of an integer constant value must be 4!`)}else e.bindBuffer(no,n.buffer),e.enableVertexAttribArray(t),e.vertexAttribIPointer(t,n.numComponents||n.size,n.type||So,n.stride||0,n.offset||0),e.vertexAttribDivisor&&e.vertexAttribDivisor(t,n.divisor||0)}}function Fs(e,t){return function(n){if(n.value){if(e.disableVertexAttribArray(t),n.value.length===4)e.vertexAttrib4uiv(t,n.value);else throw Error(`The length of an unsigned integer constant value must be 4!`)}else e.bindBuffer(no,n.buffer),e.enableVertexAttribArray(t),e.vertexAttribIPointer(t,n.numComponents||n.size,n.type||Ko,n.stride||0,n.offset||0),e.vertexAttribDivisor&&e.vertexAttribDivisor(t,n.divisor||0)}}function Is(e,t,n){let r=n.size,i=n.count;return function(n){e.bindBuffer(no,n.buffer);let a=n.size||n.numComponents||r,o=a/i,s=n.type||vo,c=X[s].size*a,l=n.normalize||!1,u=n.offset||0,d=c/i;for(let r=0;r<i;++r)e.enableVertexAttribArray(t+r),e.vertexAttribPointer(t+r,o,s,l,c,u+d*r),e.vertexAttribDivisor&&e.vertexAttribDivisor(t+r,n.divisor||0)}}var $={};$[vo]={size:4,setter:Ns},$[yo]={size:8,setter:Ns},$[bo]={size:12,setter:Ns},$[xo]={size:16,setter:Ns},$[So]={size:4,setter:Ps},$[Co]={size:8,setter:Ps},$[wo]={size:12,setter:Ps},$[To]={size:16,setter:Ps},$[Ko]={size:4,setter:Fs},$[qo]={size:8,setter:Fs},$[Jo]={size:12,setter:Fs},$[Yo]={size:16,setter:Fs},$[Eo]={size:4,setter:Ps},$[Do]={size:8,setter:Ps},$[Oo]={size:12,setter:Ps},$[ko]={size:16,setter:Ps},$[Ao]={size:4,setter:Is,count:2},$[jo]={size:9,setter:Is,count:3},$[Mo]={size:16,setter:Is,count:4};var Ls=/ERROR:\s*\d+:(\d+)/gi;function Rs(e,t=``,n=0){let r=[...t.matchAll(Ls)],i=new Map(r.map((e,n)=>{let i=parseInt(e[1]),a=r[n+1],o=a?a.index:t.length,s=t.substring(e.index,o);return[i-1,s]}));return e.split(`
`).map((e,t)=>{let r=i.get(t);return`${t+1+n}: ${e}${r?`\n\n^^^ ${r}`:``}`}).join(`
`)}var zs=/^[ \t]*\n/;function Bs(e){let t=0;return zs.test(e)&&(t=1,e=e.replace(zs,``)),{lineOffset:t,shaderSource:e}}function Vs(e,t){return e.errorCallback(t),e.callback&&setTimeout(()=>{e.callback(`${t}\n${e.errors.join(`
`)}`)}),null}function Hs(e,t,n,r){if(r||=$a,!e.getShaderParameter(n,io)){let i=e.getShaderInfoLog(n),{lineOffset:a,shaderSource:o}=Bs(e.getShaderSource(n)),s=`${Rs(o,i,a)}\nError compiling ${Ra(e,t)}: ${i}`;return r(s),s}return``}function Us(e,t,n){let r,i,a;if(typeof t==`function`&&(n=t,t=void 0),typeof e==`function`)n=e,e=void 0;else if(e&&!Array.isArray(e)){let t=e;n=t.errorCallback,e=t.attribLocations,r=t.transformFeedbackVaryings,i=t.transformFeedbackMode,a=t.callback}let o=n||$a,s=[],c={errorCallback(e,...t){s.push(e),o(e,...t)},transformFeedbackVaryings:r,transformFeedbackMode:i,callback:a,errors:s};{let n={};Array.isArray(e)?e.forEach(function(e,r){n[e]=t?t[r]:r}):n=e||{},c.attribLocations=n}return c}var Ws=[`VERTEX_SHADER`,`FRAGMENT_SHADER`];function Gs(e,t){if(t.indexOf(`frag`)>=0)return oo;if(t.indexOf(`vert`)>=0)return so}function Ks(e,t,n){let r=e.getAttachedShaders(t);for(let t of r)n.has(t)||e.deleteShader(t);e.deleteProgram(t)}var qs=(e=0)=>new Promise(t=>setTimeout(t,e));function Js(e,t,n){let r=e.createProgram(),{attribLocations:i,transformFeedbackVaryings:a,transformFeedbackMode:o}=Us(n);for(let n=0;n<t.length;++n){let i=t[n];if(typeof i==`string`){let t=eo(i),r=t?t.text:i,a=e[Ws[n]];t&&t.type&&(a=Gs(e,t.type)||a),i=e.createShader(a),e.shaderSource(i,Bs(r).shaderSource),e.compileShader(i)}e.attachShader(r,i)}Object.entries(i).forEach(([t,n])=>e.bindAttribLocation(r,n,t));{let t=a;t&&(t.attribs&&(t=t.attribs),Array.isArray(t)||(t=Object.keys(t)),e.transformFeedbackVaryings(r,t,o||co))}return e.linkProgram(r),r}function Ys(e,t,n,r,i){let a=Us(n,r,i),o=new Set(t),s=Js(e,t,a);function c(e,t){let n=Zs(e,t,a.errorCallback);return n&&Ks(e,t,o),n}if(a.callback){Xs(e,s).then(()=>{let t=c(e,s);a.callback(t,t?void 0:s)});return}return c(e,s)?void 0:s}async function Xs(e,t){let n=e.getExtension(`KHR_parallel_shader_compile`),r=n?(e,t)=>e.getProgramParameter(t,n.COMPLETION_STATUS_KHR):()=>!0,i=0;do await qs(i),i=1e3/60;while(!r(e,t))}function Zs(e,t,n){if(n||=$a,!e.getProgramParameter(t,ao)){let r=e.getProgramInfoLog(t);return n(`Error in program linking: ${r}`),`${r}\n${e.getAttachedShaders(t).map(t=>Hs(e,e.getShaderParameter(t,e.SHADER_TYPE),t,n)).filter(e=>e).join(`
`)}`}}function Qs(e,t,n,r,i){return Ys(e,t,n,r,i)}function $s(e){let t=e.name;return t.startsWith(`gl_`)||t.startsWith(`webgl_`)}var ec=/(\.|\[|]|\w+)/g,tc=e=>e>=`0`&&e<=`9`;function nc(e,t,n,r){let i=e.split(ec).filter(e=>e!==``),a=0,o=``;for(;;){let e=i[a++];o+=e;let s=tc(e[0]),c=s?parseInt(e):e;if(s&&(o+=i[a++]),a===i.length){n[c]=t;break}{let e=i[a++],t=e===`[`,s=n[c]||(t?[]:{});n[c]=s,n=s,r[o]=r[o]||function(e){return function(t){oc(e,t)}}(s),o+=e}}}function rc(e,t){let n=0;function r(t,r,i){let a=r.name.endsWith(`[0]`),o=r.type,s=X[o];if(!s)throw Error(`unknown type: 0x${o.toString(16)}`);let c;if(s.bindPoint){let t=n;n+=r.size,c=a?s.arraySetter(e,o,t,i,r.size):s.setter(e,o,t,i,r.size)}else c=s.arraySetter&&a?s.arraySetter(e,i):s.setter(e,i);return c.location=i,c}let i={},a={},o=e.getProgramParameter(t,lo);for(let n=0;n<o;++n){let o=e.getActiveUniform(t,n);if($s(o))continue;let s=o.name;s.endsWith(`[0]`)&&(s=s.substr(0,s.length-3));let c=e.getUniformLocation(t,o.name);if(c){let e=r(t,o,c);i[s]=e,nc(s,e,a,i)}}return i}function ic(e,t){let n={},r=e.getProgramParameter(t,fo);for(let i=0;i<r;++i){let r=e.getTransformFeedbackVarying(t,i);n[r.name]={index:i,type:r.type,size:r.size}}return n}function ac(e,t){let n=e.getProgramParameter(t,lo),r=[],i=[];for(let a=0;a<n;++a){i.push(a),r.push({});let n=e.getActiveUniform(t,a);r[a].name=n.name}[[`UNIFORM_TYPE`,`type`],[`UNIFORM_SIZE`,`size`],[`UNIFORM_BLOCK_INDEX`,`blockNdx`],[`UNIFORM_OFFSET`,`offset`]].forEach(function(n){let a=n[0],o=n[1];e.getActiveUniforms(t,i,e[a]).forEach(function(e,t){r[t][o]=e})});let a={},o=e.getProgramParameter(t,po);for(let n=0;n<o;++n){let r=e.getActiveUniformBlockName(t,n),i={index:e.getUniformBlockIndex(t,r),usedByVertexShader:e.getActiveUniformBlockParameter(t,n,mo),usedByFragmentShader:e.getActiveUniformBlockParameter(t,n,ho),size:e.getActiveUniformBlockParameter(t,n,go),uniformIndices:e.getActiveUniformBlockParameter(t,n,_o)};i.used=i.usedByVertexShader||i.usedByFragmentShader,a[r]=i}return{blockSpecs:a,uniformData:r}}function oc(e,t){for(let n in t){let r=e[n];typeof r==`function`?r(t[n]):oc(e[n],t[n])}}function sc(e,...t){let n=e.uniformSetters||e,r=t.length;for(let e=0;e<r;++e){let r=t[e];if(Array.isArray(r)){let e=r.length;for(let t=0;t<e;++t)sc(n,r[t])}else for(let e in r){let t=n[e];t&&t(r[e])}}}function cc(e,t){let n={},r=e.getProgramParameter(t,uo);for(let i=0;i<r;++i){let r=e.getActiveAttrib(t,i);if($s(r))continue;let a=e.getAttribLocation(t,r.name),o=$[r.type],s=o.setter(e,a,o);s.location=a,n[r.name]=s}return n}function lc(e,t){for(let n in t){let r=e[n];r&&r(t[n])}}function uc(e,t,n){n.vertexArrayObject?e.bindVertexArray(n.vertexArrayObject):(lc(t.attribSetters||t,n.attribs),n.indices&&e.bindBuffer(ro,n.indices))}function dc(e,t){let n=rc(e,t),r=cc(e,t),i={program:t,uniformSetters:n,attribSetters:r,uniformLocations:Object.fromEntries(Object.entries(n).map(([e,t])=>[e,t.location])),attribLocations:Object.fromEntries(Object.entries(r).map(([e,t])=>[e,t.location]))};return La(e)&&(i.uniformBlockSpec=ac(e,t),i.transformFeedbackInfo=ic(e,t)),i}var fc=/\s|{|}|;/;function pc(e,t,n,r,i){let a=Us(n,r,i),o=[];if(t=t.map(function(e){if(!fc.test(e)){let t=eo(e);if(t)e=t.text;else{let t=`no element with id: ${e}`;a.errorCallback(t),o.push(t)}}return e}),o.length)return Vs(a,``);let s=a.callback;s&&(a.callback=(t,n)=>{s(t,t?void 0:dc(e,n))});let c=Qs(e,t,a);return c?dc(e,c):null}var mc=4,hc=5123;function gc(e,t,n,r,i,a){n=n===void 0?mc:n;let o=t.indices,s=t.elementType,c=r===void 0?t.numElements:r;i=i===void 0?0:i,s||o?a===void 0?e.drawElements(n,c,s===void 0?hc:t.elementType,i):e.drawElementsInstanced(n,c,s===void 0?hc:t.elementType,i,a):a===void 0?e.drawArrays(n,i,c):e.drawArraysInstanced(n,i,c,a)}var _c=6402,vc=33190,yc=36012,bc=35056,xc=36013,Sc=32854,Cc=32855,wc=36194,Tc=33189,Ec=6401,Dc=36168,Oc=34041,kc=36096,Ac=36128,jc=33306,Mc={};Mc[Oc]=jc,Mc[Ec]=Ac,Mc[Dc]=Ac,Mc[_c]=kc,Mc[Tc]=kc,Mc[vc]=kc,Mc[yc]=kc,Mc[bc]=jc,Mc[xc]=jc;var Nc={};Nc[Sc]=!0,Nc[Cc]=!0,Nc[wc]=!0,Nc[Oc]=!0,Nc[Tc]=!0,Nc[Ec]=!0,Nc[Dc]=!0;var Pc={addExtensionsToContext:!0},Fc=/^(.*?)_/;function Ic(e,t){Ra(e,0);let n=e.getExtension(t);if(n){let r={},i=Fc.exec(t)[1],a=`_`+i;for(let t in n){let o=n[t],s=typeof o==`function`,c=s?i:a,l=t;t.endsWith(c)&&(l=t.substring(0,t.length-c.length)),e[l]===void 0?s?e[l]=function(e){return function(){return e.apply(n,arguments)}}(o):(e[l]=o,r[l]=o):!s&&e[l]!==o&&ea(l,e[l],o,t)}r.constructor={name:n.constructor.name},Ra(r,0)}return n}var Lc=`ANGLE_instanced_arrays.EXT_blend_minmax.EXT_color_buffer_float.EXT_color_buffer_half_float.EXT_disjoint_timer_query.EXT_disjoint_timer_query_webgl2.EXT_frag_depth.EXT_sRGB.EXT_shader_texture_lod.EXT_texture_compression_bptc.EXT_texture_compression_rgtc.EXT_texture_filter_anisotropic.OES_element_index_uint.OES_standard_derivatives.OES_texture_float.OES_texture_float_linear.OES_texture_half_float.OES_texture_half_float_linear.OES_vertex_array_object.WEBGL_color_buffer_float.WEBGL_compressed_texture_atc.WEBGL_compressed_texture_etc1.WEBGL_compressed_texture_etc.WEBGL_compressed_texture_pvrtc.WEBGL_compressed_texture_s3tc.WEBGL_compressed_texture_s3tc_srgb.WEBGL_depth_texture.WEBGL_draw_buffers`.split(`.`);function Rc(e){for(let t=0;t<Lc.length;++t)Ic(e,Lc[t])}function zc(e,t){let n=[`webgl2`,`webgl`,`experimental-webgl`],r=null;for(let i=0;i<n.length;++i)if(r=e.getContext(n[i],t),r){Pc.addExtensionsToContext&&Rc(r);break}return r}function Bc(e,t){return zc(e,t)}function Vc(e,t){t||=1,t=Math.max(0,t);let n=e.clientWidth*t|0,r=e.clientHeight*t|0;return e.width!==n||e.height!==r?(e.width=n,e.height=r,!0):!1}var Hc=150,Uc=`
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
`,Wc=`
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
`,Gc=({theme:e,isDaylight:t,paused:r=!1,blendMs:i=0,blendProgress:a})=>{let o=(0,R.useRef)(null),s=(0,R.useRef)(null),c=(0,R.useRef)(0),l=(0,R.useRef)(null),[u,d]=mt([e.primaryColor,e.accentColor],i,a),f=oe(u)||(t?{r:0,g:0,b:0}:{r:255,g:255,b:255}),p=[f.r/255,f.g/255,f.b/255],m=oe(d)||f,h=[m.r/255,m.g/255,m.b/255],g=t?[1,1,1]:[0,0,0],_=(0,R.useRef)(r),v=(0,R.useRef)(p),y=(0,R.useRef)(h),b=(0,R.useRef)(g);return _.current=r,v.current=p,y.current=h,b.current=g,(0,R.useEffect)(()=>{let e=o.current;if(!e)return;let t=Bc(e,{alpha:!1,depth:!1,antialias:!1});if(!t)return;let r=pc(t,[Uc,Wc],e=>{console.error(`SoraBackground twgl program error:`,e)});if(!r)return;let i=new Float32Array(Hc);for(let e=0;e<Hc;e++)i[e]=e;let a=Ia(t,{a_index:{numComponents:1,data:i}}),u=null,d=()=>{s.current===null&&(s.current=requestAnimationFrame(f))},f=n=>{if(s.current=null,!_.current&&u!==null){let e=(n-u)/1e3;c.current+=e}u=_.current?null:n,Vc(e),t.viewport(0,0,t.canvas.width,t.canvas.height);let i=b.current;t.clearColor(i[0],i[1],i[2],1),t.clear(t.COLOR_BUFFER_BIT),t.enable(t.BLEND),t.blendFunc(t.ONE,t.ONE_MINUS_SRC_ALPHA);let o={u_resolution:[t.canvas.width,t.canvas.height],u_time:c.current,u_particle_color:v.current,u_particle_accent_color:y.current};t.useProgram(r.program),uc(t,r,a),sc(r,o),gc(t,a,t.POINTS),_.current||d()},p=new ResizeObserver(d);return p.observe(e),l.current=d,d(),()=>{l.current=null,p.disconnect(),s.current!==null&&(cancelAnimationFrame(s.current),s.current=null),t.deleteProgram(r.program),a.attribs&&a.attribs.a_index&&a.attribs.a_index.buffer&&t.deleteBuffer(a.attribs.a_index.buffer),n()&&!t.isContextLost()&&t.getExtension(`WEBGL_lose_context`)?.loseContext()}},[]),(0,R.useEffect)(()=>{l.current?.()},[r,t,u,d]),(0,z.jsx)(`canvas`,{ref:o,className:`absolute inset-0 w-full h-full block pointer-events-none`,style:{width:`100%`,height:`100%`,willChange:`transform`,transform:`translateZ(0)`}})},Kc={id:`bg-sora`,titleKey:`options.soraBackgroundSettings`},qc=({t:e,tuning:t,onTuningChange:n})=>(0,z.jsx)(x,{def:Kc,children:(0,z.jsx)(N,{label:e(`options.soraBlank`),note:e(`options.soraBlankDesc`),checked:t.blank,onChange:e=>n?.({blank:e})})}),Jc=e({default:()=>Yc}),Yc=Le({mode:`sora`,order:50,labelKey:`options.visualizerBackgroundModeSora`,labelFallback:`Sora`,glyph:(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(`path`,{d:`M12 5.5l1.2 2.9 2.9 1.2-2.9 1.2L12 13.7l-1.2-2.9-2.9-1.2 2.9-1.2z`}),(0,z.jsx)(`path`,{d:`M5.5 16.5h.01M18 15.5h.01M7 7h.01`,strokeWidth:`2.2`,opacity:`0.5`})]}),command:{title:`Background: Sora`,description:`Switch background to Sora (starry sky) layout`,keywords:[`sora`,`starry sky`,`star`,`星空`,`空`,`背景切换到 空`,`背景切换到空`,`背景切换到Sora`,`背景切换到星空`]},render:({config:e,theme:t,isDaylight:n,paused:r,staticMode:i,blendMs:a,blendProgress:o})=>(0,z.jsx)(`div`,{className:`absolute inset-0 z-0`,style:{backgroundColor:n?`#ffffff`:`#000000`},children:!e?.sora?.tuning?.blank&&(0,z.jsx)(Gc,{theme:t,isDaylight:n,paused:r||i,blendMs:a,blendProgress:o})}),renderSettingsPanel:({config:e,actions:t,t:n})=>(0,z.jsx)(qc,{t:n,tuning:e?.sora?.tuning??O,onTuningChange:t?.sora?.onTuningChange}),renderQuickControls:({config:e,actions:t,t:n})=>{let i=e?.sora?.tuning??O;return(0,z.jsx)(ce,{active:i.blank,label:n(`options.soraBlank`),onToggle:()=>t?.sora?.onTuningChange?.({blank:!i.blank}),children:(0,z.jsx)(r,{size:14})})},resetSettings:e=>e?.sora?.onResetTuning?.()}),Xc=({urlBackgroundList:e=[],urlBackgroundSelectedId:t=null})=>{let n=(0,R.useMemo)(()=>le(e.find(e=>e.id===t)),[e,t]),r=(0,R.useRef)(null),[i,a]=(0,R.useState)(!1);return(0,R.useEffect)(()=>{a(!1);let e=r.current;if(!e)return;let t=e.getBoundingClientRect();if(t.width>0&&t.height>0){a(!0);return}let n=new ResizeObserver(e=>{for(let t of e){let{width:e,height:r}=t.contentRect;e>0&&r>0&&(a(!0),n.disconnect())}});return n.observe(e),()=>{n.disconnect()}},[n]),n?.url?(0,z.jsxs)(`div`,{ref:r,className:`absolute inset-0 z-0 overflow-hidden`,children:[i&&(0,z.jsx)(`iframe`,{src:n.url,title:n.note||n.url,className:`w-full h-full border-0`,style:{pointerEvents:`none`},sandbox:`allow-scripts`,allowFullScreen:!0},n.url),(0,z.jsx)(`div`,{className:`absolute inset-0`,style:{background:`linear-gradient(to bottom, rgba(0,0,0,0.15), rgba(0,0,0,0.35))`,pointerEvents:`none`}})]}):null},Zc={id:`bg-url`,titleKey:`options.urlBackgroundSettings`},Qc=()=>`url-bg-${Date.now()}-${Math.random().toString(36).slice(2,8)}`,$c=({t:e,urlBackgroundList:t=[],urlBackgroundSelectedId:n=null,onAddUrlBackgroundItem:r,onUpdateUrlBackgroundItem:i,onDeleteUrlBackgroundItem:o,onSetUrlBackgroundSelectedId:s})=>{let[l,u]=(0,R.useState)(!1),[d,f]=(0,R.useState)(null),[m,h]=(0,R.useState)(``),[g,_]=(0,R.useState)(``),v=(0,R.useCallback)(()=>{h(``),_(``),u(!1),f(null)},[]),y=(0,R.useCallback)(()=>{let e=se(m);if(!e)return;let t={id:Qc(),url:e,note:g.trim()||e};r?.(t),s?.(t.id),v()},[m,g,r,s,v]),C=(0,R.useCallback)(e=>{u(!1),f(e.id),h(e.url),_(e.note)},[]),w=(0,R.useCallback)(()=>{if(!d)return;let e=se(m);e&&(i?.(d,{url:e,note:g.trim()||e}),v())},[d,m,g,i,v]),T=t=>(0,z.jsx)(j,{below:(0,z.jsxs)(`div`,{className:`flex flex-col gap-2 [&>input]:w-full`,children:[(0,z.jsx)(re,{type:`url`,value:m,onChange:h,placeholder:`https://example.com`}),(0,z.jsx)(re,{value:g,onChange:_,placeholder:e(`options.urlBackgroundNotePlaceholder`)}),(0,z.jsxs)(`div`,{className:`flex justify-end gap-2`,children:[(0,z.jsx)(b,{onClick:v,children:e(`ui.cancel`)}),(0,z.jsx)(b,{variant:`primary`,onClick:t,disabled:!m.trim(),children:e(`options.save`)})]})]})});return(0,z.jsxs)(x,{def:Zc,foot:e(`options.urlBackgroundSettingsDesc`),children:[t.map(t=>d===t.id?(0,z.jsx)(R.Fragment,{children:T(w)},t.id):(0,z.jsxs)(j,{label:(0,z.jsxs)(`button`,{type:`button`,role:`radio`,"aria-checked":t.id===n,onClick:()=>s?.(t.id),className:`flex w-full min-w-0 items-center gap-2.5 rounded text-left`,children:[(0,z.jsx)(`span`,{"aria-hidden":!0,className:`st-t-fast h-4 w-4 shrink-0 rounded-full transition-shadow ${t.id===n?`shadow-[inset_0_0_0_5px_var(--st-accent)]`:`shadow-[inset_0_0_0_1.5px_var(--st-t3)]`}`}),(0,z.jsxs)(`span`,{className:`min-w-0`,children:[(0,z.jsx)(`span`,{className:`block truncate`,children:t.note}),(0,z.jsx)(`span`,{className:`block truncate text-xs leading-[18px] text-[color:var(--st-t2)]`,children:t.url})]})]}),children:[(0,z.jsx)(b,{icon:c,tip:e(`options.urlBackgroundEdit`),onClick:()=>C(t)}),(0,z.jsx)(b,{icon:p,tip:e(`options.urlBackgroundDelete`),onClick:()=>o?.(t.id)})]},t.id)),l?T(y):(0,z.jsx)(j,{label:t.length===0?(0,z.jsx)(S,{children:e(`options.urlBackgroundEmpty`)}):void 0,children:(0,z.jsx)(b,{icon:a,onClick:()=>{f(null),h(``),_(``),u(!0)},children:e(`options.urlBackgroundAdd`)})})]})},el=e({default:()=>tl}),tl=Le({mode:`url`,order:40,labelKey:`options.visualizerBackgroundModeUrl`,labelFallback:`Embed`,glyph:(0,z.jsxs)(z.Fragment,{children:[(0,z.jsx)(`rect`,{x:`3.5`,y:`5`,width:`17`,height:`14`,rx:`2`}),(0,z.jsx)(`path`,{d:`M3.5 9.5h17`,opacity:`0.55`})]}),command:{title:`Background: Embedded Background`,description:`Switch background to embedded webpage mode`,keywords:[`embedded background`,`embed background`,`background embed`,`background url`,`url background`,`url`,`webpage`,`嵌入背景`,`网页背景`,`背景切换到 嵌入背景`,`背景切换到嵌入背景`]},render:({config:e})=>(0,z.jsx)(Xc,{urlBackgroundList:e?.url?.items,urlBackgroundSelectedId:e?.url?.selectedId}),renderSettingsPanel:({config:e,actions:t,...n})=>(0,z.jsx)($c,{...n,urlBackgroundList:e?.url?.items,urlBackgroundSelectedId:e?.url?.selectedId,onAddUrlBackgroundItem:t?.url?.onAdd,onUpdateUrlBackgroundItem:t?.url?.onUpdate,onDeleteUrlBackgroundItem:t?.url?.onDelete,onSetUrlBackgroundSelectedId:t?.url?.onSelect})}),{entries:nl,byMode:rl}=(e=>{let t=Object.entries(e).map(([e,t])=>{if(!t.default)throw Error(`[VisualizerBackgroundRegistry] Missing default export in ${e}`);return t.default}),n={};return t.forEach(e=>{if(n[e.mode])throw Error(`[VisualizerBackgroundRegistry] Duplicate background mode "${e.mode}"`);n[e.mode]=e}),{entries:[...t].sort((e,t)=>e.order-t.order),byMode:n}})(Object.assign({"./common/entry.tsx":Vt,"./latent/entry.tsx":Fn,"./monet/entry.tsx":qr,"./nomand/entry.tsx":Oi,"./sora/entry.tsx":Jc,"./url/entry.tsx":el}));te(`VisualizerBackgroundRegistry`,nl.map(e=>e.mode),ne);var il=e=>typeof e==`string`&&!!rl[e],al=e=>rl[e]??rl.latent,ol=(e,t)=>{let n=al(e),r=t(n.labelKey);return!r||r===n.labelKey?n.labelFallback:r},sl=e=>!rl[e.mode]&&(rl[e.mode]=e,nl.push(e),nl.sort((e,t)=>e.order-t.order),!0),cl=e=>{if(!rl[e])return!1;delete rl[e];let t=nl.findIndex(t=>t.mode===e);return t>=0&&nl.splice(t,1),!0};export{il as a,ct as c,Je as d,qe as f,nt as g,at as h,al as i,ut as l,ot as m,sl as n,cl as o,st as p,ol as r,jt as s,nl as t,lt as u};