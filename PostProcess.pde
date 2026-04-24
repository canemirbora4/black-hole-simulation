// ============================================================
// Post-processing: bloom, vignette, grain, ACES tone mapping
// ============================================================
import java.util.concurrent.ThreadLocalRandom;

// ── ACES filmic tone mapping (per-channel) ───────────────────
Vec3 toneACES(Vec3 c) {
  final float A=2.51f, B=0.03f, C2=2.43f, D=0.59f, E=0.14f;
  float r = max(0f,min(1f,(c.x*(A*c.x+B))/(c.x*(C2*c.x+D)+E)));
  float g = max(0f,min(1f,(c.y*(A*c.y+B))/(c.y*(C2*c.y+D)+E)));
  float b = max(0f,min(1f,(c.z*(A*c.z+B))/(c.z*(C2*c.z+D)+E)));
  return new Vec3(r,g,b);
}

// ── Cinematic post-processing ────────────────────────────────
Vec3 applyPost(Vec3 col, float u, float v) {
  // Bloom
  float lum    = col.x*0.299f + col.y*0.587f + col.z*0.114f;
  float bfact  = BLOOM_STR * sstep(BLOOM_TH, BLOOM_TH+0.5f, lum);
  Vec3  bloom  = col.scale(bfact);

  // Anamorphic lens flare (horizontal streak)
  float fIntens = exp(-abs(v)*15f) * col.mag() * FLARE_STR;
  Vec3  flare  = new Vec3(0.3f,0.5f,1.0f).scale(fIntens);

  // Vignette
  float vig    = 1f - (u*u + v*v*(ASPECT*ASPECT)) * VIG_STR;

  // Film grain (thread-safe random)
  float grain  = ((float)ThreadLocalRandom.current().nextFloat()-0.5f)*GRAIN_INT;

  Vec3 out = col.add(bloom).add(flare).scale(max(0f,vig));
  return out.add(new Vec3(grain,grain,grain));
}
