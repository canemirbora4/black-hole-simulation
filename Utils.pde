// ============================================================
// Noise + procedural background
// ============================================================

// ── Hash (matches Taichi hash31) ────────────────────────────
float hash31(Vec3 p) {
  float p3x = frac(p.x * 437.585453f);
  float p3y = frac(p.y * 223.13306f);
  float p3z = frac(p.z * 353.72935f);
  float d = p3x*(p3x+19.19f) + p3y*(p3y+19.19f) + p3z*(p3z+19.19f);
  p3x = frac(p3x+d);
  p3y = frac(p3y+d);
  p3z = frac(p3z+d);
  return frac((p3x+p3y)*p3z);
}

// ── 3-D value noise ─────────────────────────────────────────
float valueNoise3D(Vec3 p) {
  float ix = flF(p.x), iy = flF(p.y), iz = flF(p.z);
  float fx = frac(p.x), fy = frac(p.y), fz = frac(p.z);
  fx = fx*fx*(3f-2f*fx);
  fy = fy*fy*(3f-2f*fy);
  fz = fz*fz*(3f-2f*fz);

  Vec3 i000=new Vec3(ix,iy,iz),     i100=new Vec3(ix+1,iy,iz);
  Vec3 i010=new Vec3(ix,iy+1,iz),   i110=new Vec3(ix+1,iy+1,iz);
  Vec3 i001=new Vec3(ix,iy,iz+1),   i101=new Vec3(ix+1,iy,iz+1);
  Vec3 i011=new Vec3(ix,iy+1,iz+1), i111=new Vec3(ix+1,iy+1,iz+1);

  float v000=hash31(i000), v100=hash31(i100);
  float v010=hash31(i010), v110=hash31(i110);
  float v001=hash31(i001), v101=hash31(i101);
  float v011=hash31(i011), v111=hash31(i111);

  return mixF(
    mixF(mixF(v000,v100,fx), mixF(v010,v110,fx), fy),
    mixF(mixF(v001,v101,fx), mixF(v011,v111,fx), fy),
    fz);
}

// ── Ridged FBM (6 octaves) ───────────────────────────────────
float fbmRidged(Vec3 p) {
  float val=0f, amp=0.5f, freq=1f;
  for (int oct=0; oct<6; oct++) {
    float n = valueNoise3D(p.scale(freq));
    val += amp*(1f - abs(n-0.5f)*2f);
    amp  *= 0.5f;
    freq *= 2f;
  }
  return val;
}

// ── Procedural starfield (replaces skybox texture) ──────────
// Pure black void with sparse white/slightly-coloured stars.
Vec3 getBackground(Vec3 dir) {
  float phi   = acos(clamp01(dir.y));
  float theta = atan2(dir.z, dir.x);
  float u = (theta + PI) / TWO_PI;
  float v = 1f - phi / PI;

  // Each "cell" in a 1200×600 grid can contain at most one star.
  float cu = flF(u * 1200f);
  float cv = flF(v * 600f);
  float h1 = hash31(new Vec3(cu, cv,  7.31f));
  float h2 = hash31(new Vec3(cu, cv, 13.77f));
  float h3 = hash31(new Vec3(cu, cv, 29.53f));

  // Only ~0.6 % of cells light up
  float bright = (h1 > 0.994f) ? pow((h1 - 0.994f) * 166.7f, 1.8f) : 0f;

  // Subtle colour tint per star (mostly white, occasional blue/yellow)
  float cr = bright;
  float cg = bright * (0.88f + h2 * 0.12f);
  float cb = bright * (0.85f + h3 * 0.15f);

  return new Vec3(cr, cg, cb);
}
