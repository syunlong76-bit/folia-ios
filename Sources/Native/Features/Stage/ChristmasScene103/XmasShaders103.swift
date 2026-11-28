import Foundation

// (103) 圣诞场景 Metal 着色器库。
// 移植纪律：
//  - 池着色器（poolVert/poolFrag）逐式移植样板 VERT/FRAG（亮芯
//    smoothstep(0.15,0.03,d)＋紧晕 pow(...,3.8)、(0.9+2.1*core)
//    白热芯、借粒 morph 全式：po/pr 平滑、弧线抬升、螺旋流入
//    0.34、退场风卷、缎带 sin 波、dim 唱亮 1/0.32/缎带 0.5）。
//  - 实体走 GGX-lite（DS 对账 13 从严）：逐组 roughness/
//    metallic uniforms、F0 = mix(0.04, baseColor, metallic)。
//    光照 rig 与样板同构：hemisphere(0x2c3a5c/0x1c120a,0.34)＋
//    月光 dir(0xc9d9f2,0.24 @(-16,22,-8))＋暖 rim(0xffab5e,
//    0.16 @(14,9,16))＋点光 5 盏（树心/门廊×2/路灯 dyn×2，
//    three 物理衰减 decay=2＋cutoff 平滑窗）。
//  - 输出链（DS 对账 Q9）：场景渲染进 RGBA16Float HDR，终程
//    Narkowicz ACES（exposure 0.85）＋精确 sRGB 分段编码写
//    bgra8Unorm drawable，不用硬件 sRGB 二次编码。
//  - Bloom（DS 对账 Q4）：与 UnrealBloom 同构的高斯 mip 链＋
//    soft knee 亮通（threshold 0.9 / strength 0.5）。
//  - 加色混合口径同 three AdditiveBlending：SrcAlpha, One。
//    深度：加色粒子开 depth test、关 depth write。

enum XmasShaders103 {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct FrameU {
        float4x4 viewProj;
        float4x4 view;
        float4 camPos;         // xyz used
        float time;
    };

    // ================= entities (merged GLB + procedural) =================
    struct EntGroupU {
        float4 baseColor;
        float4 emissive;       // rgb linear, intensity premultiplied CPU-side
        float2 roughMetal;
        float useTex;
        float pad;
    };
    struct LightsU {
        float4 hemiSky;
        float4 hemiGround;
        float4 moonDir;        // xyz = direction TO light
        float4 moonColor;
        float4 rimDir;
        float4 rimColor;
        float4 ptPos[5];       // xyz pos, w = cutoff distance
        float4 ptColor[5];     // rgb * intensity (flicker/cue CPU-side)
    };
    struct EntOut {
        float4 pos [[position]];
        float3 wp;
        float3 n;
        float2 uv;
        float4 col;
    };
    vertex EntOut entVert(uint vid [[vertex_id]],
                          const device float3* positions [[buffer(0)]],
                          const device float3* normals   [[buffer(1)]],
                          const device float2* uvs       [[buffer(2)]],
                          const device float4* colors    [[buffer(3)]],
                          constant FrameU& F [[buffer(4)]]) {
        EntOut o;
        o.wp = positions[vid];
        o.n = normals[vid];
        o.uv = uvs[vid];
        o.col = colors[vid];
        o.pos = F.viewProj * float4(o.wp, 1.0);
        return o;
    }
    static float3 ggxSpec(float3 N, float3 V, float3 L, float3 base,
                          float rough, float metal, float3 lightCol) {
        float3 H = normalize(L + V);
        float ndh = max(dot(N, H), 0.0);
        float vdh = max(dot(V, H), 0.0);
        float a = rough * rough;
        float a2 = a * a;
        float den = ndh * ndh * (a2 - 1.0) + 1.0;
        float D = a2 / (3.14159265 * den * den);
        float3 F0 = mix(float3(0.04), base, metal);
        float3 Fr = F0 + (1.0 - F0) * pow(1.0 - vdh, 5.0);
        return lightCol * (D * Fr * 0.25);
    }
    fragment float4 entFrag(EntOut in [[stage_in]],
                            constant EntGroupU& G [[buffer(0)]],
                            constant LightsU& L [[buffer(1)]],
                            constant FrameU& F [[buffer(2)]],
                            texture2d<float> tex [[texture(0)]],
                            sampler texSmp [[sampler(0)]]) {
        float4 base = G.baseColor * in.col;
        if (G.useTex > 0.5) {
            float4 t = tex.sample(texSmp, in.uv);
            base.rgb *= t.rgb;
            base.a *= t.a;
        }
        float3 N = normalize(in.n);
        float3 V = normalize(F.camPos.xyz - in.wp);
        float rough = G.roughMetal.x;
        float metal = G.roughMetal.y;
        float3 alb = base.rgb;
        float3 irr = mix(L.hemiGround.rgb, L.hemiSky.rgb, N.y * 0.5 + 0.5);
        float3 spec = float3(0.0);
        {
            float ndl = max(dot(N, L.moonDir.xyz), 0.0);
            irr += L.moonColor.rgb * ndl;
            if (ndl > 0.0) spec += ggxSpec(N, V, L.moonDir.xyz, alb, rough, metal, L.moonColor.rgb * ndl);
        }
        {
            float ndl = max(dot(N, L.rimDir.xyz), 0.0);
            irr += L.rimColor.rgb * ndl;
            if (ndl > 0.0) spec += ggxSpec(N, V, L.rimDir.xyz, alb, rough, metal, L.rimColor.rgb * ndl);
        }
        for (int i = 0; i < 5; i++) {
            float3 Lv = L.ptPos[i].xyz - in.wp;
            float d = length(Lv);
            float3 Ld = Lv / max(d, 0.001);
            float att = 1.0 / max(d * d, 0.04);
            float cutoff = L.ptPos[i].w;
            if (cutoff > 0.0) {
                float f = clamp(1.0 - pow(d / cutoff, 4.0), 0.0, 1.0);
                att *= f * f;
            }
            float ndl = max(dot(N, Ld), 0.0);
            float3 c = L.ptColor[i].rgb * att;
            irr += c * ndl;
            if (ndl > 0.0) spec += ggxSpec(N, V, Ld, alb, rough, metal, c * ndl);
        }
        float3 col = alb * irr * (1.0 - metal * 0.85) + spec + G.emissive.rgb;
        return float4(col, base.a);
    }

    // ================= shared particle pool (port of sample VERT/FRAG) =================
    struct PoolU {
        float4x4 viewProj;
        float4x4 view;
        float uTime;
        float uSpread;
        float uPR;
        float uSnow;
        float4 uRipplePos;
        float uRippleT;
        float uFly;
        float uReturn;
        float4 uLyrPos;
        float uLyrCos;
        float uLyrSin;
        float uCharLit;
        float uBreath;
        float4 uWindDir;
        float uWindAmt;
        float uRibbonAmp;
        float uGust;
        float uOpacity;
        float pad0;
        float pad1;
    };
    struct PoolOut {
        float4 pos [[position]];
        float3 vColor;
        float vTw;
        float vDim;
        float pointSize [[point_size]];
    };
    vertex PoolOut poolVert(uint vid [[vertex_id]],
                            const device float3* position [[buffer(0)]],
                            const device float3* aColor   [[buffer(1)]],
                            const device float4* aMisc1   [[buffer(2)]],
                            const device float3* aDir     [[buffer(3)]],
                            const device float3* aLyr     [[buffer(4)]],
                            const device float3* aMisc2   [[buffer(5)]],
                            constant PoolU& U [[buffer(6)]]) {
        // aMisc1 = (aSize, aPhase, aSpeed, aOrbit); aMisc2 = (aLyrOn, aDelay, aChar)
        float3 p = position[vid];
        float3 col = aColor[vid];
        float aSize = aMisc1[vid].x;
        float aPhase = aMisc1[vid].y;
        float aSpeed = aMisc1[vid].z;
        float aOrbit = aMisc1[vid].w;
        float3 dirv = aDir[vid];
        float3 lyr = aLyr[vid];
        float aLyrOn = aMisc2[vid].x;
        float aDelay = aMisc2[vid].y;
        float aChar = aMisc2[vid].z;
        float tw = 0.72 + 0.28 * sin(U.uTime * aSpeed + aPhase);
        float dim = 1.0;
        float shrink = 1.0;
        if (U.uSnow > 0.5) {
            p.y = fmod(p.y - U.uTime * aSpeed * 0.55, 20.0) - 3.0;
            p.x += sin(U.uTime * 0.7 + aPhase) * 0.35 + U.uGust * (p.y * 0.09 - 0.9);
            p.z += cos(U.uTime * 0.5 + aPhase) * 0.25;
            tw = 0.8 + 0.2 * sin(U.uTime * aSpeed + aPhase);
        } else {
            float oa = U.uTime * aOrbit;
            float oc = cos(oa); float os = sin(oa);
            float nx = oc * p.x + os * p.z;
            float nz = -os * p.x + oc * p.z;
            p.x = nx; p.z = nz;
            p.y += sin(U.uTime * 0.6 + aPhase) * 0.04;
            p += dirv * U.uSpread;
            if (U.uRippleT >= 0.0) {
                float d = distance(p, U.uRipplePos.xyz);
                float wave = U.uRippleT * 3.4;
                float band = exp(-pow((d - wave) * 2.2, 2.0));
                float3 away = p - U.uRipplePos.xyz;
                float al = max(length(away), 0.001);
                p += (away / al) * band * 0.38;
                tw += band * 1.3;
            }
            if (aLyrOn > 0.5) {
                float po = clamp((U.uFly - aDelay * 0.55) / 0.45, 0.0, 1.0);
                po = po * po * (3.0 - 2.0 * po);
                float pr = clamp((U.uReturn - (1.0 - aDelay) * 0.55) / 0.45, 0.0, 1.0);
                pr = pr * pr * (3.0 - 2.0 * pr);
                float m = po * (1.0 - pr);
                if (m > 0.001) {
                    float3 gw = U.uLyrPos.xyz + float3(
                        lyr.x * U.uLyrCos + lyr.z * U.uLyrSin,
                        lyr.y,
                        -lyr.x * U.uLyrSin + lyr.z * U.uLyrCos);
                    if (aChar < -0.5) gw.y += sin(U.uTime * 1.35 + lyr.x * 1.15) * U.uRibbonAmp;
                    float3 mp = mix(p, gw, m);
                    mp.y += sin(m * 3.14159) * (0.55 + 0.4 * sin(aPhase * 7.0));
                    float sw = sin(m * 3.14159);
                    mp.x += cos(aPhase * 7.0 + m * 6.2831) * sw * 0.34;
                    mp.z += sin(aPhase * 7.0 + m * 6.2831) * sw * 0.34;
                    mp.y += sin(aPhase * 5.0 + m * 4.0) * sw * 0.12;
                    float wv = sin(pr * 3.14159);
                    mp += U.uWindDir.xyz * (wv * wv) * U.uWindAmt * (0.6 + 0.5 * sin(aPhase * 9.0));
                    p = mp;
                    float rib = step(aChar, -0.5);
                    col = mix(col, float3(1.0, 0.87, 0.62), m * mix(0.88, 0.45, rib));
                    tw *= 1.0 + m * 0.45;
                    tw *= 1.0 + (1.0 - rib) * U.uBreath * m * 0.16 * sin(U.uTime * 1.7 - aChar * 0.6);
                    dim = mix(1.0, rib > 0.5 ? 0.5 : (aChar <= U.uCharLit ? 1.0 : 0.32), m);
                    shrink = mix(1.0, 0.82, m) * (1.0 + 0.3 * sw);
                }
            }
        }
        PoolOut o;
        o.vColor = col;
        o.vTw = tw;
        o.vDim = dim;
        float4 mv = U.view * float4(p, 1.0);
        o.pos = U.viewProj * float4(p, 1.0);
        float ps = aSize * shrink * U.uPR * (150.0 / max(1.0, -mv.z)) * (0.85 + 0.3 * tw);
        o.pointSize = clamp(ps, 1.0, 420.0);
        return o;
    }
    fragment float4 poolFrag(PoolOut in [[stage_in]],
                             float2 pc [[point_coord]],
                             constant PoolU& U [[buffer(0)]]) {
        float2 uv = pc - 0.5;
        float d = length(uv);
        float core = smoothstep(0.15, 0.03, d);
        float halo = pow(smoothstep(0.5, 0.0, d), 3.8);
        float a = clamp(core + halo * 0.5, 0.0, 1.0);
        float3 col = in.vColor * in.vTw * (0.9 + 2.1 * core);
        return float4(col, a * U.uOpacity * in.vDim);
    }

    // ================= falling snow + accumulation (crystal sprites) =================
    struct SnowU {
        float4x4 viewProj;
        float4x4 view;
        float4 camPos;         // xyz used
        float uTime;
        float uPR;
        float uMode;      // 0 = falling (fade by distance), 1 = accumulation (age envelope)
        float uOpacity;
        float pad;
    };
    struct SnowOut {
        float4 pos [[position]];
        float vPh;
        float vFade;
        float vAge;       // accumulation: envelope alpha
        float pointSize [[point_size]];
    };
    vertex SnowOut snowVert(uint vid [[vertex_id]],
                            const device float3* position [[buffer(0)]],
                            const device float3* aMisc   [[buffer(1)]],  // size, phase, birthOrSpeed
                            const device float*  aLife   [[buffer(2)]],
                            constant SnowU& U [[buffer(3)]]) {
        SnowOut o;
        float3 p = position[vid];
        float size = aMisc[vid].x;
        o.vPh = aMisc[vid].y;
        float4 mv = U.view * float4(p, 1.0);
        float dist = length(U.camPos.xyz - p);
        o.vFade = smoothstep(2.5, 7.0, dist) * (1.0 - 0.35 * smoothstep(34.0, 55.0, dist));
        o.vAge = 1.0;
        if (U.uMode > 0.5) {
            float age = U.uTime - aMisc[vid].z;
            float life = aLife[vid];
            float env = smoothstep(0.0, 0.5, age) * (1.0 - smoothstep(life - 7.0, life, age));
            if (age < 0.0 || age > life) env = 0.0;
            o.vAge = env;
            if (env <= 0.0) size = 0.0;
        }
        o.pos = U.viewProj * float4(p, 1.0);
        float ps = size * U.uPR * (150.0 / max(1.0, -mv.z));
        o.pointSize = clamp(ps, 1.5, 120.0 * U.uPR);
        if (size <= 0.0) o.pointSize = 0.0;
        return o;
    }
    fragment float4 snowFrag(SnowOut in [[stage_in]],
                             float2 pc [[point_coord]],
                             constant SnowU& U [[buffer(0)]],
                             texture2d<float> tex [[texture(0)]],
                             sampler texSmp [[sampler(0)]]) {
        float2 c = pc - 0.5;
        float ca = cos(in.vPh), sa = sin(in.vPh);
        float2 ruv = float2(c.x * ca - c.y * sa, c.x * sa + c.y * ca) + 0.5;
        float4 t = tex.sample(texSmp, ruv);
        float a = t.a;
        // flakes whose phase hash > 0.62 read as plain round dots (sample rule)
        float hash = fract(sin(in.vPh * 127.1) * 43758.5453);
        if (hash > 0.62) {
            float d = length(c);
            a = smoothstep(0.5, 0.12, d);
        }
        float alpha = a * in.vFade * in.vAge * U.uOpacity;
        if (alpha < 0.004) discard_fragment();
        return float4(float3(0.93, 0.97, 1.0), alpha);
    }

    // ================= billboards (star / glows / moon / smoke / glyph shade+glow) =================
    struct SprInst {
        float3 center;
        float2 size;
        float4 color;      // rgb linear, a = opacity multiplier
    };
    struct SprU {
        float4x4 viewProj;
        float4x4 view;
    };
    struct SprOut {
        float4 pos [[position]];
        float2 uv;
        float4 color;
    };
    vertex SprOut sprVert(uint vid [[vertex_id]], uint iid [[instance_id]],
                          const device SprInst* insts [[buffer(0)]],
                          constant SprU& U [[buffer(1)]]) {
        SprInst s = insts[iid];
        float2 ct[6] = { float2(-0.5,-0.5), float2(0.5,-0.5), float2(-0.5,0.5),
                         float2(0.5,-0.5), float2(0.5,0.5), float2(-0.5,0.5) };
        float2 corner = ct[vid % 6];
        float3 right = float3(U.view[0][0], U.view[1][0], U.view[2][0]);
        float3 up    = float3(U.view[0][1], U.view[1][1], U.view[2][1]);
        float3 wp = s.center + right * (corner.x * s.size.x) + up * (corner.y * s.size.y);
        SprOut o;
        o.pos = U.viewProj * float4(wp, 1.0);
        o.uv = float2(corner.x + 0.5, 0.5 - corner.y);
        o.color = s.color;
        return o;
    }
    fragment float4 sprFrag(SprOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            sampler texSmp [[sampler(0)]]) {
        float4 t = tex.sample(texSmp, in.uv);
        return float4(t.rgb * in.color.rgb, t.a * in.color.a);
    }

    // ================= ground discs (contact shadows / warm pools / tree pool) =================
    struct DiscInst {
        float3 center;
        float2 size;       // full width/depth in world units
        float rotY;
        float4 color;      // rgb tint, a = opacity
    };
    struct DiscOut {
        float4 pos [[position]];
        float2 uv;
        float4 color;
    };
    vertex DiscOut discVert(uint vid [[vertex_id]], uint iid [[instance_id]],
                            const device DiscInst* insts [[buffer(0)]],
                            constant SprU& U [[buffer(1)]]) {
        DiscInst s = insts[iid];
        float2 ct[6] = { float2(-0.5,-0.5), float2(0.5,-0.5), float2(-0.5,0.5),
                         float2(0.5,-0.5), float2(0.5,0.5), float2(-0.5,0.5) };
        float2 corner = ct[vid % 6];
        float cs = cos(s.rotY), sn = sin(s.rotY);
        float lx = corner.x * s.size.x, lz = corner.y * s.size.y;
        float3 wp = s.center + float3(lx * cs + lz * sn, 0.0, -lx * sn + lz * cs);
        DiscOut o;
        o.pos = U.viewProj * float4(wp, 1.0);
        o.uv = float2(corner.x + 0.5, corner.y + 0.5);
        o.color = s.color;
        return o;
    }
    fragment float4 discFrag(DiscOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler texSmp [[sampler(0)]]) {
        float4 t = tex.sample(texSmp, in.uv);
        return float4(t.rgb * in.color.rgb, t.a * in.color.a);
    }

    // ================= bloom + final =================
    struct QuadOut {
        float4 pos [[position]];
        float2 uv;
    };
    vertex QuadOut quadVert(uint vid [[vertex_id]]) {
        QuadOut o;
        float2 p = float2((vid & 1) == 0 ? -1.0 : 1.0, (vid & 2) == 0 ? -1.0 : 1.0);
        o.pos = float4(p, 0.0, 1.0);
        o.uv = float2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5);
        return o;
    }
    struct BloomU {
        float threshold;
        float knee;
        float2 texel;
        float2 dir;
        float weight;
        float pad0;
        float pad1;
    };
    fragment float4 brightFrag(QuadOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler texSmp [[sampler(0)]],
                               constant BloomU& B [[buffer(0)]]) {
        float3 c = tex.sample(texSmp, in.uv).rgb;
        float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
        float f = smoothstep(B.threshold - B.knee, B.threshold + B.knee, luma);
        return float4(c * f, 1.0);
    }
    fragment float4 blurFrag(QuadOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler texSmp [[sampler(0)]],
                             constant BloomU& B [[buffer(0)]]) {
        float3 acc = tex.sample(texSmp, in.uv).rgb * 0.227027;
        float2 o1 = B.dir * B.texel * 1.3846153;
        float2 o2 = B.dir * B.texel * 3.2307692;
        acc += tex.sample(texSmp, in.uv + o1).rgb * 0.3162162;
        acc += tex.sample(texSmp, in.uv - o1).rgb * 0.3162162;
        acc += tex.sample(texSmp, in.uv + o2).rgb * 0.0702703;
        acc += tex.sample(texSmp, in.uv - o2).rgb * 0.0702703;
        return float4(acc, 1.0);
    }
    fragment float4 downFrag(QuadOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             sampler texSmp [[sampler(0)]],
                             constant BloomU& B [[buffer(0)]]) {
        float3 acc = float3(0.0);
        float2 t = B.texel;
        acc += tex.sample(texSmp, in.uv + float2(-t.x, -t.y)).rgb;
        acc += tex.sample(texSmp, in.uv + float2( t.x, -t.y)).rgb;
        acc += tex.sample(texSmp, in.uv + float2(-t.x,  t.y)).rgb;
        acc += tex.sample(texSmp, in.uv + float2( t.x,  t.y)).rgb;
        return float4(acc * 0.25 * B.weight, 1.0);
    }
    struct FinalU {
        float bloomStrength;
        float exposure;
        float2 pad;
    };
    static float3 acesNarkowicz(float3 x) {
        return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
    }
    static float3 srgbEncode(float3 c) {
        float3 lo = c * 12.92;
        float3 hi = 1.055 * pow(max(c, float3(0.0)), float3(1.0 / 2.4)) - 0.055;
        return mix(lo, hi, step(float3(0.0031308), c));
    }
    fragment float4 finalFrag(QuadOut in [[stage_in]],
                              texture2d<float> scene [[texture(0)]],
                              texture2d<float> bloomA [[texture(1)]],
                              texture2d<float> bloomB [[texture(2)]],
                              texture2d<float> bloomC [[texture(3)]],
                              sampler texSmp [[sampler(0)]],
                              constant FinalU& F [[buffer(0)]]) {
        float3 c = scene.sample(texSmp, in.uv).rgb;
        float3 b = bloomA.sample(texSmp, in.uv).rgb * 1.0
                 + bloomB.sample(texSmp, in.uv).rgb * 0.7
                 + bloomC.sample(texSmp, in.uv).rgb * 0.45;
        c += b * F.bloomStrength;
        c = acesNarkowicz(c * F.exposure);
        c = srgbEncode(c);
        return float4(c, 1.0);
    }
    """
}
