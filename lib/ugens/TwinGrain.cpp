#include "SC_PlugIn.h"
#include <math.h>

static InterfaceTable* ft;

static const uint32 kRing = 2048;
static const uint32 kMask = kRing - 1;

struct TGrain {
    double phR, rateR, phL, rateL;
    double b1, y1, y2, winPos, winInc;
    float amp, winType, gr1, gr2, gl1, gl2;
    int counter, bufR, bufL, delay, mode;
};

struct TwinGrain : public Unit {
    int numActive, maxGrains;
    float curtrig;
    uint32 rpos;
    int64 block, lBusyUntil, ringUntil;
    int tmpDelay;
    TGrain* grains;
    float* ring;
    float* tmp;
};

extern "C" {
void TwinGrain_Ctor(TwinGrain* unit);
void TwinGrain_Dtor(TwinGrain* unit);
void TwinGrain_next(TwinGrain* unit, int inNumSamples);
}

static inline double tg_gloop(double in, double hi) {
    if (in >= hi) {
        in -= hi;
        if (in < hi)
            return in;
    } else if (in < 0.) {
        in += hi;
        if (in >= 0.)
            return in;
    } else
        return in;
    return in - hi * floor(in / hi);
}

static inline const SndBuf* tg_buf(Unit* unit, int bufnum) {
    World* world = unit->mWorld;
    if (bufnum >= (int)world->mNumSndBufs) {
        int local = bufnum - world->mNumSndBufs;
        Graph* parent = unit->mParent;
        if (local <= parent->localBufNum)
            return parent->mLocalSndBufs + local;
        return world->mSndBufs;
    }
    if (bufnum < 0)
        bufnum = 0;
    return world->mSndBufs + bufnum;
}

static inline void tg_pan(float pan, float& g1, float& g2) {
    pan = sc_clip(pan * 0.5f + 0.5f, 0.f, 1.f);
    float a = pan * pi2_f;
    g1 = cos(a);
    g2 = sin(a);
}

template <int MODE, bool CUSTOM, bool FAST, int TGT>
static inline void tg_play(TwinGrain* unit, TGrain* g, const SndBuf* bR, const SndBuf* bL, const float* win, uint32 winSamples,
                           int winGuard, float* o1, float* o2, float* l1, float* l2, int nsmps) {
    const float* dR = bR->data;
    uint32 sR = bR->samples;
    double loopR = (double)bR->frames;
    int guardR = (int)bR->frames - 2;
    const float* dL = bL ? bL->data : dR;
    uint32 sL = bL ? bL->samples : sR;
    double loopL = bL ? (double)bL->frames : loopR;
    int guardL = bL ? (int)bL->frames - 2 : guardR;
    double phR = g->phR, rateR = g->rateR, phL = g->phL, rateL = g->rateL;
    double b1 = g->b1, y1 = g->y1, y2 = g->y2, winPos = g->winPos, winInc = g->winInc;
    float amp = g->amp, gr1 = g->gr1, gr2 = g->gr2, gl1 = g->gl1, gl2 = g->gl2;
    float* r1 = unit->ring;
    float* r2 = unit->ring + kRing;
    uint32 base = unit->rpos + (uint32)g->delay;
    if (MODE == 1 && TGT == 0) {
        gr1 += gl1;
        gr2 += gl2;
    }
    for (int j = 0; j < nsmps; ++j) {
        if (!FAST)
            phR = tg_gloop(phR, loopR);
        int32 ip = (int32)phR;
        float fr = (float)(phR - (double)ip);
        const float* t1 = dR + ip;
        const float* t2 = t1 + 1;
        if (!FAST && ip > guardR)
            t2 -= sR;
        float vR = amp * (t1[0] + fr * (t2[0] - t1[0]));
        if (MODE == 0 || MODE == 1 || TGT != 0) {
            o1[j] += vR * gr1;
            o2[j] += vR * gr2;
        }
        if (MODE != 0) {
            float vL;
            if (MODE == 1) {
                vL = vR;
            } else if (MODE == 2) {
                const float* u1 = dL + ip;
                const float* u2 = u1 + 1;
                if (!FAST && ip > guardR)
                    u2 -= sL;
                vL = amp * (u1[0] + fr * (u2[0] - u1[0]));
            } else {
                if (!FAST)
                    phL = tg_gloop(phL, loopL);
                int32 iq = (int32)phL;
                float fq = (float)(phL - (double)iq);
                const float* u1 = dL + iq;
                const float* u2 = u1 + 1;
                if (!FAST && iq > guardL)
                    u2 -= sL;
                vL = amp * (u1[0] + fq * (u2[0] - u1[0]));
                phL += rateL;
            }
            if (TGT == 2) {
                uint32 k = (base + (uint32)j) & kMask;
                r1[k] += vL * gl1;
                r2[k] += vL * gl2;
            } else if (TGT == 1) {
                l1[j] += vL * gl1;
                l2[j] += vL * gl2;
            } else if (MODE != 1) {
                o1[j] += vR * gr1 + vL * gl1;
                o2[j] += vR * gr2 + vL * gl2;
            }
        }
        if (CUSTOM) {
            winPos += winInc;
            int iw = (int)winPos;
            if (iw >= (int)winSamples)
                iw = (int)winSamples - 1;
            double wf = winPos - (double)iw;
            const float* w1 = win + iw;
            const float* w2 = w1 + 1;
            if (winPos > winGuard)
                w2 -= winSamples;
            amp = (float)(w1[0] + wf * (w2[0] - w1[0]));
        } else {
            double y0 = b1 * y1 - y2;
            y2 = y1;
            y1 = y0;
            amp = (float)(y1 * y1);
        }
        phR += rateR;
    }
    g->phR = phR;
    g->phL = phL;
    g->y1 = y1;
    g->y2 = y2;
    g->winPos = winPos;
    g->amp = amp;
    g->counter -= nsmps;
}

static inline bool tg_inside(double ph, double rate, int n, int guard) {
    double e = ph + rate * (double)n;
    double lo = ph < e ? ph : e, hi = ph < e ? e : ph;
    return lo >= 0. && hi < (double)guard;
}

template <bool CUSTOM, bool FAST, int TGT>
static inline void tg_mode(TwinGrain* unit, TGrain* g, const SndBuf* bR, const SndBuf* bL, const float* win, uint32 winSamples,
                           int winGuard, float* o1, float* o2, float* l1, float* l2, int nsmps) {
    switch (g->mode) {
    case 0:
        tg_play<0, CUSTOM, FAST, TGT>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, l1, l2, nsmps);
        break;
    case 1:
        tg_play<1, CUSTOM, FAST, TGT>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, l1, l2, nsmps);
        break;
    case 2:
        tg_play<2, CUSTOM, FAST, TGT>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, l1, l2, nsmps);
        break;
    default:
        tg_play<3, CUSTOM, FAST, TGT>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, l1, l2, nsmps);
        break;
    }
}

template <bool CUSTOM>
static inline void tg_route(TwinGrain* unit, TGrain* g, const SndBuf* bR, const SndBuf* bL, const float* win, uint32 winSamples,
                            int winGuard, float* o1, float* o2, int nsmps) {
    float* l1 = o1;
    float* l2 = o2;
    int tgt = 0;
    if (g->mode != 0 && g->delay > 0) {
        if (unit->tmpDelay < 0) {
            unit->tmpDelay = g->delay;
            float* c = unit->tmp;
            for (int j = 0, n = 2 * unit->mBufLength; j < n; ++j)
                c[j] = 0.f;
        }
        if (unit->tmpDelay == g->delay) {
            l1 = unit->tmp;
            l2 = unit->tmp + unit->mBufLength;
            tgt = 1;
        } else
            tgt = 2;
        int64 until = unit->block + (g->delay + nsmps) / unit->mBufLength + 1;
        if (until > unit->ringUntil)
            unit->ringUntil = until;
    }
    bool fast = tg_inside(g->phR, g->rateR, nsmps, (int)bR->frames - 2)
        && (g->mode != 3 || tg_inside(g->phL, g->rateL, nsmps, (int)bL->frames - 2));
    if (fast) {
        if (tgt == 0)
            tg_mode<CUSTOM, true, 0>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, l1, l2, nsmps);
        else if (tgt == 1)
            tg_mode<CUSTOM, true, 1>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, l1, l2, nsmps);
        else
            tg_mode<CUSTOM, true, 2>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, l1, l2, nsmps);
    } else {
        if (tgt == 0)
            tg_mode<CUSTOM, false, 0>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, l1, l2, nsmps);
        else if (tgt == 1)
            tg_mode<CUSTOM, false, 1>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, l1, l2, nsmps);
        else
            tg_mode<CUSTOM, false, 2>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, l1, l2, nsmps);
    }
}

static inline bool tg_render(TwinGrain* unit, TGrain* g, float* o1, float* o2, int nsmps) {
    const SndBuf* bR = tg_buf(unit, g->bufR);
    if (!bR->data || bR->channels != 1 || bR->frames < 2)
        return false;
    const SndBuf* bL = 0;
    if (g->mode >= 2) {
        bL = tg_buf(unit, g->bufL);
        if (!bL->data || bL->channels != 1 || bL->frames < 2)
            return false;
        if (g->mode == 2 && bL->frames != bR->frames)
            g->mode = 3;
    }
    const float* win = 0;
    uint32 winSamples = 0;
    int winGuard = 0;
    bool custom = g->winType >= 0.f;
    if (custom) {
        World* world = unit->mWorld;
        if (g->winType >= world->mNumSndBufs)
            return false;
        const SndBuf* w = world->mSndBufs + (int)g->winType;
        win = w->data;
        if (!win)
            return false;
        winSamples = w->samples;
        winGuard = (int)w->frames - 1;
    }
    if (custom)
        tg_route<true>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, nsmps);
    else
        tg_route<false>(unit, g, bR, bL, win, winSamples, winGuard, o1, o2, nsmps);
    return true;
}

static void tg_start(TwinGrain* unit, int inNumSamples) {
    if (unit->numActive + 1 >= unit->maxGrains)
        return;
    World* world = unit->mWorld;
    float winType = IN0(10);
    if (winType >= world->mNumSndBufs)
        return;
    if (winType >= 0.f && !world->mSndBufs[(int)winType].data)
        return;
    int bufR = (int)IN0(3);
    const SndBuf* bR = tg_buf(unit, bufR);
    if (!bR->data || bR->channels != 1 || bR->frames < 2)
        return;
    double rateR = IN0(5) * bR->samplerate * SAMPLEDUR;
    double phR = IN0(7) * (double)bR->frames;
    if (!sc_isfinite(phR))
        return;
    double counter = IN0(1) * SAMPLERATE;
    counter = sc_max(4., counter);
    TGrain* g = unit->grains + unit->numActive;
    g->counter = (int)counter;
    g->bufR = bufR;
    g->phR = phR;
    g->rateR = rateR;
    g->winType = winType;
    if (winType < 0.f) {
        double w = pi / g->counter;
        g->b1 = 2. * cos(w);
        g->y1 = sin(w);
        g->y2 = 0.;
        g->amp = (float)(g->y1 * g->y1);
        g->winPos = g->winInc = 0.;
    } else {
        const SndBuf* w = world->mSndBufs + (int)winType;
        g->amp = w->data[0];
        g->winPos = 0.;
        g->winInc = (double)w->samples / g->counter;
        g->b1 = g->y1 = g->y2 = 0.;
    }
    tg_pan(IN0(9), g->gr1, g->gr2);
    int nblk = (int)IN0(11);
    bool lOn = nblk <= 0 || unit->block > unit->lBusyUntil;
    g->mode = 0;
    g->delay = 0;
    g->phL = 0.;
    g->rateL = 0.;
    g->gl1 = g->gl2 = 0.f;
    if (lOn) {
        if (nblk > 0)
            unit->lBusyUntil = unit->block + nblk;
        int bufL = (int)IN0(2);
        const SndBuf* bL = tg_buf(unit, bufL);
        double phL = IN0(6) * (double)(bL->frames);
        if (bL->data && bL->channels == 1 && bL->frames >= 2 && sc_isfinite(phL)) {
            double rateL = IN0(4) * bL->samplerate * SAMPLEDUR;
            g->bufL = bufL;
            g->phL = phL;
            g->rateL = rateL;
            tg_pan(IN0(8), g->gl1, g->gl2);
            int d = nblk > 0 ? nblk * BUFLENGTH : 0;
            int dmax = (int)kRing - BUFLENGTH;
            g->delay = d > dmax ? dmax : d;
            g->mode = 3;
            if (bL->frames == bR->frames) {
                double fr = (double)bR->frames;
                double off = phL - phR;
                off -= fr * floor(off / fr + 0.5);
                double ar = fabs(rateR);
                double dev = fabs(rateL - rateR) * g->counter;
                double tol = IN0(13);
                double cs = off == 0. ? 0. : (ar > 1e-9 ? fabs(off) / ar : 1e30);
                if (cs + dev <= tol || (off == 0. && rateL == rateR))
                    g->mode = bL->data == bR->data ? 1 : 2;
            }
        }
    }
    unit->numActive++;
    int nsmps = sc_min(g->counter, inNumSamples);
    if (!tg_render(unit, g, OUT(0), OUT(1), nsmps))
        g->counter -= nsmps;
    if (g->counter <= 0)
        *g = unit->grains[--unit->numActive];
}

void TwinGrain_next(TwinGrain* unit, int inNumSamples) {
    float* o1 = OUT(0);
    float* o2 = OUT(1);
    float* r1 = unit->ring;
    float* r2 = unit->ring + kRing;
    uint32 rp = unit->rpos;
    if (unit->block <= unit->ringUntil) {
        for (int j = 0; j < inNumSamples; ++j) {
            uint32 k = (rp + (uint32)j) & kMask;
            o1[j] = r1[k];
            o2[j] = r2[k];
            r1[k] = 0.f;
            r2[k] = 0.f;
        }
    } else {
        for (int j = 0; j < inNumSamples; ++j) {
            o1[j] = 0.f;
            o2[j] = 0.f;
        }
    }
    unit->tmpDelay = -1;
    float* t1 = unit->tmp;
    float* t2 = unit->tmp + unit->mBufLength;
    for (int i = 0; i < unit->numActive;) {
        TGrain* g = unit->grains + i;
        int nsmps = sc_min(g->counter, inNumSamples);
        if (!tg_render(unit, g, o1, o2, nsmps))
            g->counter -= inNumSamples;
        if (g->counter <= 0) {
            *g = unit->grains[--unit->numActive];
            continue;
        }
        ++i;
    }
    float trig = IN0(0);
    if (trig > 0.f && unit->curtrig <= 0.f)
        tg_start(unit, inNumSamples);
    unit->curtrig = trig;
    int td = unit->tmpDelay;
    if (td > 0) {
        uint32 b = rp + (uint32)td;
        for (int j = 0; j < inNumSamples; ++j) {
            uint32 k = (b + (uint32)j) & kMask;
            r1[k] += t1[j];
            r2[k] += t2[j];
        }
    }
    unit->rpos = (rp + (uint32)inNumSamples) & kMask;
    unit->block++;
}

void TwinGrain_Ctor(TwinGrain* unit) {
    unit->numActive = 0;
    unit->curtrig = 0.f;
    unit->rpos = 0;
    unit->block = 0;
    unit->lBusyUntil = -1;
    unit->ringUntil = -1;
    unit->maxGrains = (int)IN0(12);
    if (unit->maxGrains < 2)
        unit->maxGrains = 2;
    unit->grains = (TGrain*)RTAlloc(unit->mWorld, unit->maxGrains * sizeof(TGrain));
    unit->ring = (float*)RTAlloc(unit->mWorld, 2 * kRing * sizeof(float));
    unit->tmp = (float*)RTAlloc(unit->mWorld, 2 * unit->mBufLength * sizeof(float));
    unit->tmpDelay = -1;
    if (!unit->grains || !unit->ring || !unit->tmp) {
        if (unit->grains)
            RTFree(unit->mWorld, unit->grains);
        if (unit->ring)
            RTFree(unit->mWorld, unit->ring);
        if (unit->tmp)
            RTFree(unit->mWorld, unit->tmp);
        unit->grains = 0;
        unit->ring = 0;
        unit->tmp = 0;
        SETCALC(ft->fClearUnitOutputs);
        ClearUnitOutputs(unit, 1);
        return;
    }
    memset(unit->ring, 0, 2 * kRing * sizeof(float));
    SETCALC(TwinGrain_next);
    OUT0(0) = 0.f;
    OUT0(1) = 0.f;
}

void TwinGrain_Dtor(TwinGrain* unit) {
    if (unit->grains)
        RTFree(unit->mWorld, unit->grains);
    if (unit->ring)
        RTFree(unit->mWorld, unit->ring);
    if (unit->tmp)
        RTFree(unit->mWorld, unit->tmp);
}

PluginLoad(TwinGrain) {
    ft = inTable;
    DefineDtorUnit(TwinGrain);
}
