// ============================================================
// Ray tracer: GR geodesics + volumetric accretion disk
// ============================================================
import java.util.concurrent.*;

// ── GR acceleration (Schwarzschild geodesic, 3+1 form) ──────
Vec3 grAccel(Vec3 pos, Vec3 vel) {
  float r   = pos.mag() + 1e-9f;
  Vec3  Lv  = pos.cross(vel);
  float L2  = Lv.magSq();
  float grt = (3f * RS * L2) / (2f * r*r*r*r*r);
  return pos.scale(-grt);
}

// ── Dormand–Prince 5(4) adaptive step ───────────────────────
// Returns float[7]: px,py,pz, vx,vy,vz, error
float[] dopri5(Vec3 pos, Vec3 vel, float dt) {
  final float a21=1f/5f;
  final float a31=3f/40f,     a32=9f/40f;
  final float a41=44f/45f,    a42=-56f/15f,     a43=32f/9f;
  final float a51=19372f/6561f,a52=-25360f/2187f,a53=64448f/6561f, a54=-212f/729f;
  final float a61=9017f/3168f, a62=-355f/33f,    a63=46732f/5247f, a64=49f/176f, a65=-5103f/18656f;
  // 5th-order weights
  final float b1=35f/384f, b3=500f/1113f, b4=125f/192f, b5=-2187f/6784f, b6=11f/84f;
  // 4th-order weights (error)
  final float e1=5179f/57600f, e3=7571f/16695f, e4=393f/640f,
              e5=-92097f/339200f, e6=187f/2100f, e7=1f/40f;

  // Stage 1
  Vec3 k1p = vel,           k1v = grAccel(pos,vel);
  // Stage 2
  Vec3 k2p = vel.addScaled(k1v,dt*a21);
  Vec3 k2v = grAccel(pos.addScaled(k1p,dt*a21), k2p);
  // Stage 3
  Vec3 k3p = vel.addScaled(k1v,dt*a31).addScaled(k2v,dt*a32);
  Vec3 k3v = grAccel(pos.addScaled(k1p,dt*a31).addScaled(k2p,dt*a32), k3p);
  // Stage 4
  Vec3 k4p = vel.addScaled(k1v,dt*a41).addScaled(k2v,dt*a42).addScaled(k3v,dt*a43);
  Vec3 k4v = grAccel(pos.addScaled(k1p,dt*a41).addScaled(k2p,dt*a42).addScaled(k3p,dt*a43), k4p);
  // Stage 5
  Vec3 k5p = vel.addScaled(k1v,dt*a51).addScaled(k2v,dt*a52).addScaled(k3v,dt*a53).addScaled(k4v,dt*a54);
  Vec3 k5v = grAccel(
    pos.addScaled(k1p,dt*a51).addScaled(k2p,dt*a52).addScaled(k3p,dt*a53).addScaled(k4p,dt*a54), k5p);
  // Stage 6
  Vec3 k6p = vel.addScaled(k1v,dt*a61).addScaled(k2v,dt*a62).addScaled(k3v,dt*a63).addScaled(k4v,dt*a64).addScaled(k5v,dt*a65);
  Vec3 k6v = grAccel(
    pos.addScaled(k1p,dt*a61).addScaled(k2p,dt*a62).addScaled(k3p,dt*a63).addScaled(k4p,dt*a64).addScaled(k5p,dt*a65), k6p);

  // 5th-order solution
  Vec3 pos5 = pos.addScaled(k1p,dt*b1).addScaled(k3p,dt*b3).addScaled(k4p,dt*b4).addScaled(k5p,dt*b5).addScaled(k6p,dt*b6);
  Vec3 vel5 = vel.addScaled(k1v,dt*b1).addScaled(k3v,dt*b3).addScaled(k4v,dt*b4).addScaled(k5v,dt*b5).addScaled(k6v,dt*b6);

  // Stage 7 (FSAL: k7_pos = vel5)
  Vec3 k7p = vel5;

  // 4th-order solution (for error)
  Vec3 pos4 = pos.addScaled(k1p,dt*e1).addScaled(k3p,dt*e3).addScaled(k4p,dt*e4).addScaled(k5p,dt*e5).addScaled(k6p,dt*e6).addScaled(k7p,dt*e7);

  float err = pos5.sub(pos4).mag();
  return new float[]{ pos5.x,pos5.y,pos5.z, vel5.x,vel5.y,vel5.z, err };
}

// ── Density sample from cylindrical grid ────────────────────
float sampleWorldDensity(Vec3 p) {
  float r = p.xzMag();
  if (r<=CYL_RMN || r>=CYL_RMX || abs(p.y)>=CYL_HH) return 0f;
  float vf = exp(-(p.y*p.y)/(2f*DISK_THICK*DISK_THICK));
  Vec3 pg  = worldToGrid(new Vec3(p.x, 0f, p.z));
  return sampleGrid(density, pg) * vf;
}

// ── Sun surface: FBM noise tint ─────────────────────────────
Vec3 getSunSurface(Vec3 spos, Vec3 baseCol) {
  float n1 = fbmRidged(spos.scale(SUN_NSC1));
  float n2 = fbmRidged(spos.scale(SUN_NSC2));
  float fn = pow(n1*0.7f+n2*0.3f, SUN_NCON);
  return baseCol.mix(new Vec3(1f,1f,0.9f), fn).scale(1f+fn*SUN_BBST);
}

// ── Doppler-beamed disk emission ─────────────────────────────
Vec3 getDiskEmission(Vec3 pos, Vec3 rayDir) {
  float rxz = pos.xzMag();
  float tf  = pow(DISK_IN/(rxz+1e-6f), 2.5f);
  float tm  = pow(clamp01(tf), 0.8f);
  Vec3 base = COL_COLD.mix(COL_HOT, tm);

  float spd = sqrt(GM/(rxz+0.1f))*ORB_VSCL;
  Vec3 tDir = new Vec3(-pos.z,0,pos.x).normalized();
  Vec3 vw   = tDir.scale(spd);

  float beta  = vw.dot(rayDir.negate());
  float vn    = vw.mag();
  float gamma = 1f/sqrt(max(1e-10f, 1f-vn*vn));
  float delta = 1f/(gamma*(1f-beta));

  float brightness  = tf * pow(delta, DOPP_STR);
  // Warm-biased Doppler: approaching side gets brighter & warmer gold,
  // receding side dims but stays orange — no blue shift ever.
  Vec3  colorShift  = new Vec3(pow(delta, 1.00f),   // red:   full boost
                               pow(delta, 0.55f),   // green: moderate
                               pow(delta, 0.08f));  // blue:  barely moves
  float shadow      = 1f - EQ_SS*sstep(EQ_SW, 0f, abs(pos.y));

  return base.compMul(colorShift).scale(brightness*shadow);
}

// ── Henyey–Greenstein phase function ────────────────────────
float hgPhase(float cosT, float g) {
  float g2 = g*g;
  return (1f-g2) / pow(1f+g2-2f*g*cosT, 1.5f);
}

// ── Volume scattering from both suns ────────────────────────
Vec3 getScattering(Vec3 pos, Vec3 rayDir) {
  Vec3  dn  = (pos.y>0) ? new Vec3(0,1,0) : new Vec3(0,-1,0);
  Vec3  ld1 = SUN1_POS.sub(pos).normalized();
  float d1  = SUN1_POS.sub(pos).magSq();
  float ph1 = hgPhase(ld1.dot(rayDir.negate()), HG_G);
  float s1  = mixF(1f-SHAD_STR, 1f, clamp01(ld1.dot(dn)));
  Vec3  sc1 = SUN1_COL.scale(ph1*s1/(d1+1f));

  Vec3  ld2 = SUN2_POS.sub(pos).normalized();
  float d2  = SUN2_POS.sub(pos).magSq();
  float ph2 = hgPhase(ld2.dot(rayDir.negate()), HG_G);
  float s2  = mixF(1f-SHAD_STR, 1f, clamp01(ld2.dot(dn)));
  Vec3  sc2 = SUN2_COL.scale(ph2*s2/(d2+1f));

  return sc1.add(sc2).scale(SCAT_STR);
}

// ── Glow corona rays ────────────────────────────────────────
float glowRays(Vec3 rp, Vec3 sunPos) {
  Vec3  v  = rp.sub(sunPos);
  float r  = v.mag();
  float inc = acos(clamp01(v.y/(r+1e-6f)));
  float az  = atan2(v.x, v.z);
  Vec3  nc  = new Vec3(r*0.1f, inc, az).scale(SUN_RYST);
  return pow(fbmRidged(nc.scale(SUN_RYSC)), SUN_RYCON);
}

Vec3 addSunGlow(Vec3 rp, Vec3 rd, Vec3 sunPos, Vec3 sunCol, float trans) {
  Vec3  oc     = rp.sub(sunPos);
  float tClose = -oc.dot(rd);
  if (tClose <= -SUN_R*5f) return new Vec3(0,0,0);
  float dSq = oc.add(rd.scale(tClose)).magSq();
  float sg  = exp(-dSq*SUN_GLFL);
  float gf  = sg * glowRays(rp, sunPos);
  Vec3  fc  = sunCol.compMul(new Vec3(0.5f,0.6f,1f)).mix(sunCol, sstep(0f,0.8f,sg));
  return fc.scale(gf*SUN_GLST*trans);
}

// ── Volumetric march along one ray segment ───────────────────
// Returns float[4]: r,g,b, transmittance_out
float[] marchSegment(Vec3 start, Vec3 end, float transIn, Vec3 rayDir) {
  float cx=0,cy=0,cz=0, trans=transIn;
  Vec3  seg    = end.sub(start);
  float segLen = seg.mag();
  if (segLen<1e-4f) return new float[]{0,0,0,trans};

  float step = segLen/VOL_SUB;
  Vec3  sDir = seg.scale(1f/segLen);

  for (int s=0; s<VOL_SUB; s++) {
    if (trans<1e-3f) break;
    Vec3  p = start.add(sDir.scale((s+0.5f)*step));
    float d = sampleWorldDensity(p) * DENS_MUL;
    if (d>1e-3f) {
      d = pow(d, DENS_POW);
      Vec3 total = getDiskEmission(p,rayDir).scale(EMIT_STR).add(getScattering(p,rayDir));
      float stepT = exp(-d*step*ABSORB_C);
      float w = d*trans*step;
      cx += total.x*w;
      cy += total.y*w;
      cz += total.z*w;
      trans *= stepT;
    }
  }
  return new float[]{cx,cy,cz,trans};
}

// ── Full ray trace ───────────────────────────────────────────
Vec3 traceRay(Vec3 origin, Vec3 dir) {
  Vec3  pos  = origin;
  Vec3  vel  = dir.normalized();
  float cr=0,cg=0,cb=0;
  float trans= 1f;
  float dt   = DT_INIT;
  int   hit  = 0, step = 0;

  while (step<MAX_STEPS && hit==0 && trans>1e-3f) {
    float r = pos.mag();

    if (r <= HORIZON_R+0.001f) {
      hit = 1;                                                              // event horizon

    } else if (pos.sub(SUN1_POS).magSq() < SUN_R*SUN_R) {
      hit = 1;
      Vec3 ss = getSunSurface(pos,SUN1_COL).scale(trans*SUN_CBRT);
      cr+=ss.x; cg+=ss.y; cb+=ss.z;

    } else if (pos.sub(SUN2_POS).magSq() < SUN_R*SUN_R) {
      hit = 1;
      Vec3 ss = getSunSurface(pos,SUN2_COL).scale(trans*SUN_CBRT);
      cr+=ss.x; cg+=ss.y; cb+=ss.z;

    } else if (r > FAR_FIELD) {
      hit = 1;
      Vec3 bg = getBackground(vel).scale(trans);
      cr+=bg.x; cg+=bg.y; cb+=bg.z;

    } else {
      Vec3 g1 = addSunGlow(pos,vel,SUN1_POS,SUN1_COL,trans);
      Vec3 g2 = addSunGlow(pos,vel,SUN2_POS,SUN2_COL,trans);
      cr+=g1.x+g2.x; cg+=g1.y+g2.y; cb+=g1.z+g2.z;

      float[] d = dopri5(pos,vel,dt);
      Vec3 posN = new Vec3(d[0],d[1],d[2]);
      Vec3 velN = new Vec3(d[3],d[4],d[5]);
      float err = d[6];

      float[] vol = marchSegment(pos,posN,trans,dir);
      cr+=vol[0]; cg+=vol[1]; cb+=vol[2];
      trans=vol[3];

      if (err<=TOLERANCE) {
        pos  = posN;
        vel  = velN.normalized();
        step++;
      }
      float ratio = TOLERANCE/(err+1e-12f);
      dt = max(DT_MIN, min(DT_MAX, SAFETY*dt*pow(ratio, 1f/6f)));
    }
  }
  if (hit==0) {
    Vec3 bg = getBackground(vel).scale(trans);
    cr+=bg.x; cg+=bg.y; cb+=bg.z;
  }
  return new Vec3(cr,cg,cb);
}

// ── Multithreaded frame render ───────────────────────────────
void renderFrame(Vec3 camPos, float[][] cam2world, float fov) {
  final int aaN = (AA_SAMPLES <= 1) ? 1 : (int)sqrt((float)AA_SAMPLES);
  final int aaCount = aaN * aaN;
  CountDownLatch latch = new CountDownLatch(H);
  for (int row=0; row<H; row++) {
    final int ry = row;
    pool.execute(() -> {
      for (int i=0; i<W; i++) {
        Vec3 col = new Vec3(0,0,0);
        for (int sy=0; sy<aaN; sy++) {
          for (int sx=0; sx<aaN; sx++) {
            float jx = ((sx + 0.5f) / aaN) - 0.5f;
            float jy = ((sy + 0.5f) / aaN) - 0.5f;
            float u = ((i + jx) - W*0.5f) / H;
            float v = ((ry + jy) - H*0.5f) / H;
            Vec3 localDir = new Vec3(u, v, fov).normalized();
            Vec3 rayDir   = matMul(cam2world, localDir);
            col = col.add(traceRay(camPos, rayDir));
          }
        }
        col = col.scale(1f / aaCount);

        float uPost = (i  - W*0.5f) / H;
        float vPost = (ry - H*0.5f) / H;
        col = applyPost(col.scale(0.5f), uPost, vPost);
        col = toneACES(col);
        int r = (int)(clamp01(pow(max(0f,col.x), 1f/2.2f))*255);
        int g = (int)(clamp01(pow(max(0f,col.y), 1f/2.2f))*255);
        int b = (int)(clamp01(pow(max(0f,col.z), 1f/2.2f))*255);
        pixBuf[ry*W+i] = 0xFF000000|(r<<16)|(g<<8)|b;
      }
      latch.countDown();
    });
  }
  try { latch.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
}
