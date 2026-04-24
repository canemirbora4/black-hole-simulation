<img width="4752" height="2673" alt="gargantua_A3_20260410_215409" src="https://github.com/user-attachments/assets/01d9ca71-9648-4a1e-8d29-3698a6f69958" />


# Gargantua IMBH — Generative Black Hole Renderer

A physically-inspired **Intermediate Mass Black Hole (IMBH)** simulator and real-time ray-tracer written in **Processing 4**. Inspired by **Gargantua** from *Interstellar*, it combines Schwarzschild-like geodesic light bending, a cylindrical **fluid-simulated accretion disk**, and a cinematic **post-processing** pipeline — all running on the CPU with multi-threaded row-based rendering.

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Setup & Run](#setup--run)
- [Quality Presets](#quality-presets)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Auto A3 Capture](#auto-a3-capture)
- [File Structure](#file-structure)
- [How It Works](#how-it-works)
- [Performance Tips](#performance-tips)
- [License](#license)

---

## Features

- **Geodesic ray marching** with an adaptive step-size integrator — produces gravitational lensing and an Einstein ring around the event horizon.
- **Volumetric accretion disk** driven by a Navier–Stokes–style fluid simulation on a cylindrical (r, θ, y) grid: advection, Jacobi pressure projection, dissipation, orbital velocity field.
- **Doppler beaming + gravitational redshift** approximation — one side of the disk appears brighter and hotter, the other dimmer.
- **Two procedural suns** with surface noise, ray streaks and limb darkening.
- **Post-processing stack** — bloom, anamorphic lens flare, vignette, film grain, ACES tone mapping, gamma correction.
- **Multi-core rendering** — row-based parallelism via `ExecutorService`.
- **Hi-res A3 export** — renders the current frame at **4752×2673** pixels, print-ready.
- **Automatic frame capture** — auto-triggers a hi-res render at a preset simulation time (e.g. `t = 40.381s`).

---

## Requirements

- **Processing 4.x** — <https://processing.org/download>
- Java mode (the default). No external libraries required.
- Recommended hardware: 6+ CPU cores and 8 GB+ RAM. Hi-res A3 renders may take a few minutes depending on CPU.

---

## Setup & Run

1. Clone this repository:
   ```bash
   git clone https://github.com/<your-username>/<repo-name>.git
   ```
2. Open **Processing 4**.
3. Double-click `GargantuaProcessing.pde` — Processing will load all `.pde` tabs (FluidSim, RayTracer, PostProcess, Utils, Vec3) automatically.
4. Press **Run** (▶).

A window opens and the camera slowly orbits the black hole while the accretion disk evolves in real time. Window title shows live FPS and simulation time.

---

## Quality Presets

Change the `QUALITY` constant at [GargantuaProcessing.pde:10](GargantuaProcessing.pde#L10) to trade off fidelity and speed:

| Level | Resolution | VOL_SUB | MAX_STEPS | Approx. FPS |
|:-----:|:----------:|:-------:|:---------:|:-----------:|
| 1 — fast       | 320 × 180   | 12 | 100 | 3–4 |
| 2 — medium     | 480 × 270   | 20 | 130 | 1.5–2 |
| 3 — high ★     | 640 × 360   | 32 | 170 | 0.6–1 |
| 4 — ultra      | 640 × 360   | 48 | 220 | 0.3–0.5 |
| 5 — cinematic  | 1280 × 720  | 72 | 320 | very slow (4× AA) |

★ Default. Tip: iterate on composition at `QUALITY = 1` or `2`, then bump to `3`–`5` for the final capture.

---

## Keyboard Shortcuts

| Key | Action |
|:---:|:-------|
| `S` | Save a PNG screenshot at window resolution (`gargantua_YYYYMMDD_HHMMSS.png`). |
| `H` | Render the current frame at **A3 (4752×2673)** and save to disk. |
| `Q` / `ESC` | Quit — shuts down the thread pool cleanly. |

---

## Auto A3 Capture

See [GargantuaProcessing.pde:53-56](GargantuaProcessing.pde#L53-L56):

```java
final boolean AUTO_CAPTURE      = true;
final float   CAPTURE_TIME      = 40.381f;  // seconds
final float   CAPTURE_TOLERANCE = 0.5f;
```

When `AUTO_CAPTURE` is enabled, the sketch automatically performs a hi-res render and writes it to disk the moment the simulation clock hits `CAPTURE_TIME`. Perfect for a "grab exactly this frame" workflow.

---

## File Structure

| File | Purpose |
|:-----|:--------|
| [GargantuaProcessing.pde](GargantuaProcessing.pde) | Main sketch — `setup()`, `draw()`, camera animation, hi-res export, global constants. |
| [RayTracer.pde](RayTracer.pde) | Geodesic ray marching, black hole metric, disk/sun shading, volumetric integration. |
| [FluidSim.pde](FluidSim.pde) | Cylindrical fluid simulation (advect, diverge, Jacobi project, dissipation). |
| [PostProcess.pde](PostProcess.pde) | Bloom, anamorphic flare, vignette, grain, ACES tone map. |
| [Utils.pde](Utils.pde) | Noise helpers, matrix math, procedural starfield background. |
| [Vec3.pde](Vec3.pde) | 3D vector class — add, scale, dot/cross, normalize. |
| [sketch.properties](sketch.properties) | Tells Processing which file is the main sketch. |

---

## How It Works

1. **Camera orbit** — [cameraAtTime()](GargantuaProcessing.pde#L315) eases radius, polar angle and FOV over time for a smooth cinematic push-in.
2. **Per-frame fluid step** — `simulationStep()` advects the density field, enforces incompressibility via Jacobi pressure iterations, and adds an orbital velocity field plus gravity.
3. **Ray marching** — every pixel shoots a ray that's integrated with adaptive steps under the black hole's gravitational influence. Steps shrink near the horizon (`RS`) for accuracy.
4. **Disk shading** — a temperature gradient from a hot inner ring (`COL_HOT`) to a cool outer rim (`COL_COLD`) is multiplied with the density field; emission, absorption and single-scattering terms are integrated along each ray.
5. **Post** — linear HDR → bloom + flare → vignette/grain → ACES tone map → gamma 2.2 → 8-bit sRGB.

---

## Performance Tips

- On Retina/HiDPI Macs, `pixelDensity(1)` is critical — without it the pixel buffer is 4× larger than expected and the image tiles incorrectly. It's already set; don't remove it.
- Window size doesn't affect cost: the real render runs in a `W × H` buffer and is scaled up to `DW × DH` on display.
- When rendering hi-res A3, close other heavy applications — a single frame will saturate every core.
- For fast preview runs, use `QUALITY = 1`, dial in `CAPTURE_TIME`, then rerun at `QUALITY = 3+` for the final output.

---

## License

Free for personal and academic use. For commercial use or redistribution, please get in touch first.

---

*Built with Processing 4 · Inspired by Kip Thorne and the Double Negative team's work on Interstellar (2014).*
