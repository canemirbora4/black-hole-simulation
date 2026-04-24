// ============================================================
// Vec3 — immutable 3D vector + math helpers
// ============================================================
class Vec3 {
  final float x, y, z;

  Vec3(float x, float y, float z) { this.x=x; this.y=y; this.z=z; }

  Vec3 add(Vec3 o)             { return new Vec3(x+o.x, y+o.y, z+o.z); }
  Vec3 sub(Vec3 o)             { return new Vec3(x-o.x, y-o.y, z-o.z); }
  Vec3 scale(float s)          { return new Vec3(x*s, y*s, z*s); }
  Vec3 addScaled(Vec3 o,float s){ return new Vec3(x+o.x*s, y+o.y*s, z+o.z*s); }
  Vec3 compMul(Vec3 o)         { return new Vec3(x*o.x, y*o.y, z*o.z); }
  Vec3 negate()                { return new Vec3(-x,-y,-z); }

  float dot(Vec3 o)  { return x*o.x + y*o.y + z*o.z; }
  float magSq()      { return x*x + y*y + z*z; }
  float mag()        { return sqrt(x*x+y*y+z*z); }
  float xzMag()      { return sqrt(x*x+z*z); }

  Vec3 cross(Vec3 o) {
    return new Vec3(y*o.z-z*o.y, z*o.x-x*o.z, x*o.y-y*o.x);
  }

  Vec3 normalized() {
    float m = mag();
    if (m < 1e-10f) return new Vec3(0,0,0);
    float inv = 1f/m;
    return new Vec3(x*inv, y*inv, z*inv);
  }

  Vec3 mix(Vec3 o, float t) {
    float it = 1f-t;
    return new Vec3(x*it+o.x*t, y*it+o.y*t, z*it+o.z*t);
  }
}

// ── Matrix × vector  (m is row-major 3×3) ───────────────────
Vec3 matMul(float[][] m, Vec3 v) {
  return new Vec3(
    m[0][0]*v.x + m[0][1]*v.y + m[0][2]*v.z,
    m[1][0]*v.x + m[1][1]*v.y + m[1][2]*v.z,
    m[2][0]*v.x + m[2][1]*v.y + m[2][2]*v.z
  );
}

// ── Scalar helpers ───────────────────────────────────────────
float clamp01(float v)               { return v<0?0:(v>1?1:v); }
float clampF(float v,float a,float b){ return v<a?a:(v>b?b:v); }
float mixF(float a,float b,float t)  { return a+(b-a)*t; }

// smoothstep: safe against edge0==edge1
float sstep(float e0, float e1, float x) {
  float d = e1-e0;
  if (abs(d)<1e-10f) return x>=e1?1f:0f;
  float t = clamp01((x-e0)/d);
  return t*t*(3f-2f*t);
}

// fract: x – floor(x)
float frac(float x) { return x-(float)Math.floor(x); }
float flF(float x)  { return (float)Math.floor(x); }
