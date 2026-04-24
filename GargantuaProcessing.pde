import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

// ── Quality preset ───────────────────────────────────────────
// 1 = fast   (320×180,  VOL=12,  steps=100,  ~3-4 fps)
// 2 = medium (480×270,  VOL=20,  steps=130,  ~1.5-2 fps)
// 3 = high   (640×360,  VOL=32,  steps=170,  ~0.6-1 fps)  ← default
// 4 = ultra  (640×360,  VOL=48,  steps=220,  ~0.3-0.5 fps)
// 5 = cinematic (1280×720, VOL=72, steps=320, AA=4x, very slow)
final int QUALITY = 3;

// ── Render / display resolution ──────────────────────────────
final int   DW = (QUALITY >= 5) ? 1280 : 640;
final int   DH = (QUALITY >= 5) ? 720  : 360;
final int   W  = (QUALITY == 1) ? 320 : (QUALITY == 2) ? 480 : (QUALITY >= 5) ? 1280 : 640;
final int   H  = (QUALITY == 1) ? 180 : (QUALITY == 2) ? 270 : (QUALITY >= 5) ? 720  : 360;
final float ASPECT = (float)W / H;   // always 16:9

// ── Black-hole physics ───────────────────────────────────────
final float GM       = 0.5f;
final float RS       = 2.0f * GM;
final float HORIZON_R= RS;
final float DISK_IN  = RS * 2.5f;
final float DISK_OUT = RS * 12.0f;
final float DISK_THICK = (DISK_OUT - DISK_IN) * 0.005f;
final float FAR_FIELD  = 75.0f;
final float SUN_R      = 3.0f;

final Vec3 SUN1_POS = new Vec3( 60f,  10f, -25f);
final Vec3 SUN1_COL = new Vec3( 1.0f,  0.82f,  0.50f);  // warm gold
final Vec3 SUN2_POS = new Vec3(-50f, -15f,  35f);
final Vec3 SUN2_COL = new Vec3( 1.0f,  0.72f,  0.38f);  // warm amber (was blue — removed)

// Sun surface noise
final float SUN_NSC1=2.0f, SUN_NSC2=8.0f, SUN_NCON=10.0f;
final float SUN_BBST=2.0f, SUN_CBRT=10.0f;
final float SUN_GLST=0.1f, SUN_GLFL=0.2f;
final float SUN_RYSC=0.9f, SUN_RYST=500.0f, SUN_RYCON=9.0f;

// ── Adaptive integrator ──────────────────────────────────────
final int   MAX_STEPS = (QUALITY==1) ? 100 : (QUALITY==2) ? 130 : (QUALITY==3) ? 170 : (QUALITY==4) ? 220 : 320;
final float TOLERANCE = 1e-5f;
final float DT_INIT   = 0.5f;
final float DT_MIN    = 1e-4f;
final float DT_MAX    = 1.0f;
final float SAFETY    = 0.9f;
final int   AA_SAMPLES = (QUALITY >= 5) ? 4 : 1;

// ── Hi-res A3 export ─────────────────────────────────────────
// Set to true and specify a target time to auto-capture at that moment.
// A3 landscape = 1188×840 at 72dpi → 4× = 4752×3360 pixels.
// Since aspect is 16:9: 4752×2673 (keeps 16:9 ratio at ~4× of 1188×669)
final boolean AUTO_CAPTURE    = true;
final float   CAPTURE_TIME    = 40.381f;   // seconds — your desired frame
final float   CAPTURE_TOLERANCE = 0.5f;     // ±0.5s window
boolean       capturedAlready = false;

// Hi-res render dimensions (A3 at 4× = 4752 wide, 16:9 aspect)
final int HIRES_W = 4752;
final int HIRES_H = 2673;   // 4752 / (16/9) ≈ 2673

// ── Post-processing ──────────────────────────────────────────
final float BLOOM_TH  = 0.1f,  BLOOM_STR = 0.55f;  // ↑ neon bloom
final float FLARE_STR = 2.5f;                        // ↑ anamorphic streak
final float VIG_STR   = 0.4f,  GRAIN_INT = 0.015f;

// ── Fluid grid (cylindrical: r, θ, y) ───────────────────────
final int   GRID_R  = (QUALITY >= 5) ? 48 : 32;
final int   GRID_T  = (QUALITY >= 5) ? 96 : 64;
final int   GRID_Y  = (QUALITY >= 5) ? 12 : 8;
final float CYL_RMN = DISK_IN;
final float CYL_RMX = DISK_OUT;
final float CYL_HH  = DISK_THICK * 5.0f;
final float DR      = (CYL_RMX - CYL_RMN) / GRID_R;
final float DTHETA  = TWO_PI / GRID_T;
final float DY_GRID = (2f * CYL_HH) / GRID_Y;

// ── Volumetric rendering ─────────────────────────────────────
final int   VOL_SUB  = (QUALITY==1) ? 12 : (QUALITY==2) ? 20 : (QUALITY==3) ? 32 : (QUALITY==4) ? 48 : 72;
final float EMIT_STR = 3000.0f;   // ↑ neon brightness
final float ABSORB_C = 50.0f;
final float DENS_MUL = 1.5f;
final float DENS_POW = 3.0f;
final float SCAT_STR = 60.0f;    // ↑ scattered glow
final float HG_G     = 0.4f;
final float SHAD_STR = 0.8f;
final Vec3  COL_HOT  = new Vec3(1.0f, 0.90f, 0.68f);  // cream-gold inner ring
final Vec3  COL_COLD = new Vec3(0.72f, 0.28f, 0.08f); // deep rust-orange outer
final float DOPP_STR = 6.0f;     // moderate — brightness contrast, no blue push

// ── Disk structure noise ─────────────────────────────────────
final float WARP_SC  = 1.5f,  WARP_STR2 = 1.2f;
final float FIL_SC   = 1.8f,  FIL_CON   = 4.0f;
final float TAN_STR  = 25.0f;
final float CLMP_SC  = 0.5f,  CLMP_STR  = 0.6f;
final float VERT_SC  = 2.0f,  VERT_STR  = 0.6f;
final float DISK_NS  = 3.0f;
final float EQ_SW    = 0.1f,  EQ_SS     = 0.9f;

// ── Fluid simulation ─────────────────────────────────────────
final float DT_SIM  = 0.005f;
final float ADV_STR = 1e-5f;
final float MAX_VEL = 2.0f * DR / DT_SIM;
final int   JAC_ITER= (QUALITY >= 5) ? 12 : 8;
final float DISSIP  = 0.03f;
final float ORB_AST = 0.03f;
final float ORB_VSCL= 1.0f;
final float GRAV_STR= 1.0f;

// ── Camera animation ─────────────────────────────────────────
final float ORB_PERIOD= 120.0f;
final float ANIM_DUR  = 60.0f;
final float CAM_R_ST  = 50.0f,    CAM_R_EN   = 18.0f;
final float CAM_TH_ST = HALF_PI-0.4f, CAM_TH_EN  = HALF_PI+0.2f;
final float CAM_FOV_ST= 1.0f,     CAM_FOV_EN = 1.3f;

// ── Global state ─────────────────────────────────────────────
float[][][] density, densityNew;
float[][][] pressure, divergence;
float[][][] vR, vT, vY;
float[][][] vRNew, vTNew, vYNew;

// skyPix / skyW / skyH kept as stubs so Utils.pde still compiles
// (getBackground no longer uses them — procedural stars instead)
int[]   skyPix = new int[0];
int     skyW = 0, skyH = 0;

int[]   pixBuf;          // W×H render buffer
PImage  renderImg;       // displayed at DW×DH

ExecutorService pool;

// ============================================================
//  settings() — must contain size() and pixelDensity()
//  pixelDensity(1) is CRITICAL on Retina/HiDPI Macs:
//  without it, pixels[] is 4× larger than expected and the
//  image appears mirrored/tiled in only a quarter of the window.
// ============================================================
void settings() {
  size(DW, DH);
  pixelDensity(1);   // ← fixes the Retina double-image bug
}

// ============================================================
void setup() {
  frameRate(60);

  // ── Fluid fields ─────────────────────────────────────────
  density    = new float[GRID_R][GRID_T][GRID_Y];
  densityNew = new float[GRID_R][GRID_T][GRID_Y];
  pressure   = new float[GRID_R][GRID_T][GRID_Y];
  divergence = new float[GRID_R][GRID_T][GRID_Y];
  vR  = new float[GRID_R][GRID_T][GRID_Y];
  vT  = new float[GRID_R][GRID_T][GRID_Y];
  vY  = new float[GRID_R][GRID_T][GRID_Y];
  vRNew = new float[GRID_R][GRID_T][GRID_Y];
  vTNew = new float[GRID_R][GRID_T][GRID_Y];
  vYNew = new float[GRID_R][GRID_T][GRID_Y];

  pixBuf    = new int[W * H];
  renderImg = createImage(W, H, RGB);

  int cores = Runtime.getRuntime().availableProcessors();
  pool = Executors.newFixedThreadPool(cores);
  println("Gargantua  quality=" + QUALITY +
          "  render=" + W + "x" + H + "  display=" + DW + "x" + DH +
    "  steps=" + MAX_STEPS + "  vol=" + VOL_SUB + "  aa=" + AA_SAMPLES + "x" +
          "  threads=" + cores);

  initScene();
  initVelocity();
  println("Keys: S=screenshot, H=hi-res A3, Q or ESC=quit");
  if (AUTO_CAPTURE) println("Auto-capture armed at t=" + CAPTURE_TIME + "s (±" + CAPTURE_TOLERANCE + "s)");
  println("Ready.");
}

// ============================================================
void draw() {
  // Real-time animation clock — independent of FPS
  float t = millis() / 1000.0f;
  simulationStep();

  // ── Camera ───────────────────────────────────────────────
  float[] cam = cameraAtTime(t);
  Vec3 camPos = new Vec3(cam[0], cam[1], cam[2]);
  Vec3 camFwd = new Vec3(cam[3], cam[4], cam[5]);
  float fov   = cam[6];

  Vec3 right = camFwd.cross(new Vec3(0,1,0)).normalized();
  Vec3 camUp = right.cross(camFwd);

  // Column matrix [right | up | fwd]
  float[][] m = {
    { right.x, camUp.x, camFwd.x },
    { right.y, camUp.y, camFwd.y },
    { right.z, camUp.z, camFwd.z }
  };

  renderFrame(camPos, m, fov);

  // ── Upload render buffer → PImage, draw scaled to window ─
  renderImg.loadPixels();
  System.arraycopy(pixBuf, 0, renderImg.pixels, 0, W * H);
  renderImg.updatePixels();
  image(renderImg, 0, 0, DW, DH);

  surface.setTitle("Gargantua  |  t=" + nf(t,1,2) + "s  |  " + nf(frameRate,1,1) + " fps");

  // ── Auto-capture at target time ──────────────────────────
  if (AUTO_CAPTURE && !capturedAlready && abs(t - CAPTURE_TIME) < CAPTURE_TOLERANCE) {
    capturedAlready = true;
    println(">>> Auto-capture triggered at t=" + nf(t,1,3) + "s — rendering hi-res A3...");
    saveHiRes(t);
  }
}

// ============================================================
void keyPressed() {
  if (key == 's' || key == 'S') {
    String ts = nf(year(),4) + nf(month(),2) + nf(day(),2)
              + "_" + nf(hour(),2) + nf(minute(),2) + nf(second(),2);
    String fn = "gargantua_" + ts + ".png";
    save(fn);   // saves the current display size as PNG
    println("Screenshot saved → " + fn);
  }
  if (key == 'h' || key == 'H') {
    float t = millis() / 1000.0f;
    println(">>> Manual hi-res capture at t=" + nf(t,1,3) + "s — rendering A3...");
    saveHiRes(t);
  }
  if (key == ESC || key == 'q' || key == 'Q') {
    pool.shutdownNow();
    exit();
  }
}

// ── Hi-res A3 render + save ──────────────────────────────────
void saveHiRes(float t) {
  println("  Hi-res: " + HIRES_W + "x" + HIRES_H + " (" + (HIRES_W*HIRES_H) + " pixels)");
  println("  Using VOL_SUB=" + VOL_SUB + " MAX_STEPS=" + MAX_STEPS);
  int startMs = millis();

  // Camera at the given time
  float[] cam = cameraAtTime(t);
  Vec3 camPos = new Vec3(cam[0], cam[1], cam[2]);
  Vec3 camFwd = new Vec3(cam[3], cam[4], cam[5]);
  float fov   = cam[6];

  Vec3 right = camFwd.cross(new Vec3(0,1,0)).normalized();
  Vec3 camUp = right.cross(camFwd);
  float[][] m = {
    { right.x, camUp.x, camFwd.x },
    { right.y, camUp.y, camFwd.y },
    { right.z, camUp.z, camFwd.z }
  };

  // Render into a separate pixel buffer
  final int hiW = HIRES_W;
  final int hiH = HIRES_H;
  final int[] hiPixBuf = new int[hiW * hiH];
  final float hiAspect = (float)hiW / hiH;

  // Progress tracking
  final java.util.concurrent.atomic.AtomicInteger rowsDone = new java.util.concurrent.atomic.AtomicInteger(0);

  // Use same thread pool, render row by row
  CountDownLatch latch = new CountDownLatch(hiH);
  for (int row = 0; row < hiH; row++) {
    final int ry = row;
    final Vec3 fCamPos = camPos;
    final float[][] fM = m;
    final float fFov = fov;
    pool.execute(() -> {
      for (int i = 0; i < hiW; i++) {
        float u = (i - hiW * 0.5f) / hiH;
        float v = (ry - hiH * 0.5f) / hiH;
        Vec3 localDir = new Vec3(u, v, fFov).normalized();
        Vec3 rayDir   = matMul(fM, localDir);
        Vec3 col = traceRay(fCamPos, rayDir);

        float uPost = u;
        float vPost = v;
        col = applyPost(col.scale(0.5f), uPost, vPost);
        col = toneACES(col);
        int r = (int)(clamp01(pow(max(0f, col.x), 1f/2.2f)) * 255);
        int g = (int)(clamp01(pow(max(0f, col.y), 1f/2.2f)) * 255);
        int b = (int)(clamp01(pow(max(0f, col.z), 1f/2.2f)) * 255);
        hiPixBuf[ry * hiW + i] = 0xFF000000 | (r << 16) | (g << 8) | b;
      }
      int done = rowsDone.incrementAndGet();
      if (done % 100 == 0 || done == hiH) {
        println("  Hi-res progress: " + done + "/" + hiH + " rows  (" + nf(100f*done/hiH,1,1) + "%)");
      }
      latch.countDown();
    });
  }
  try { latch.await(); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }

  // Save as PImage
  PImage hiImg = createImage(hiW, hiH, RGB);
  hiImg.loadPixels();
  System.arraycopy(hiPixBuf, 0, hiImg.pixels, 0, hiW * hiH);
  hiImg.updatePixels();

  String ts = nf(year(),4) + nf(month(),2) + nf(day(),2)
            + "_" + nf(hour(),2) + nf(minute(),2) + nf(second(),2);
  String fn = "gargantua_A3_" + ts + ".png";
  hiImg.save(fn);

  float elapsed = (millis() - startMs) / 1000.0f;
  println(">>> Hi-res A3 saved → " + fn + "  (" + nf(elapsed,1,1) + "s render time)");
}

// ── Camera path ────────────────────
float[] cameraAtTime(float t) {
  float phi  = (t / ORB_PERIOD) * TWO_PI + PI;
  float prog = min(t / ANIM_DUR, 1.0f);
  float ep   = 0.5f * (1f - cos(prog * PI));

  float r   = CAM_R_ST   + (CAM_R_EN   - CAM_R_ST)   * ep;
  float th  = CAM_TH_ST  + (CAM_TH_EN  - CAM_TH_ST)  * ep;
  float fov = CAM_FOV_ST + (CAM_FOV_EN - CAM_FOV_ST)  * ep;

  float cx = r * sin(th) * cos(phi);
  float cy = r * cos(th);
  float cz = r * sin(th) * sin(phi);
  float mg = sqrt(cx*cx + cy*cy + cz*cz);

  return new float[]{ cx, cy, cz, -cx/mg, -cy/mg, -cz/mg, fov };
}
