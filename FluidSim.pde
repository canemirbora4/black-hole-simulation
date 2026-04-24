// ============================================================
// Fluid simulation on a cylindrical grid (r, θ, y)
// ============================================================

// ── Coordinate conversions ───────────────────────────────────
Vec3 gridToWorld(int i, int j, int k) {
  float r  = CYL_RMN + (i+0.5f)*DR;
  float th = (j+0.5f)*DTHETA - PI;
  float y  = -CYL_HH + (k+0.5f)*DY_GRID;
  return new Vec3(r*cos(th), y, r*sin(th));
}

Vec3 worldToGrid(Vec3 p) {
  float r  = p.xzMag();
  float th = atan2(p.z, p.x);
  float ri = (r  - CYL_RMN) / DR       - 0.5f;
  float ti = (th + PI)       / DTHETA   - 0.5f;
  float yi = (p.y + CYL_HH)  / DY_GRID  - 0.5f;
  return new Vec3(ri, ti, yi);
}

// ── Trilinear sample of a scalar field ──────────────────────
float sampleGrid(float[][][] field, Vec3 pg) {
  int ii = (int)Math.floor(pg.x);
  int jj = (int)Math.floor(pg.y);
  int kk = (int)Math.floor(pg.z);
  float fx = pg.x-ii, fy = pg.y-jj, fz = pg.z-kk;
  ii = max(0,min(ii,GRID_R-2));
  kk = max(0,min(kk,GRID_Y-2));
  int j0 = ((jj%GRID_T)+GRID_T)%GRID_T;
  int j1 = ((jj+1)%GRID_T+GRID_T)%GRID_T;
  float v00 = mixF(field[ii][j0][kk],   field[ii+1][j0][kk],   fx);
  float v10 = mixF(field[ii][j1][kk],   field[ii+1][j1][kk],   fx);
  float v01 = mixF(field[ii][j0][kk+1], field[ii+1][j0][kk+1], fx);
  float v11 = mixF(field[ii][j1][kk+1], field[ii+1][j1][kk+1], fx);
  return mixF(mixF(v00,v10,fy), mixF(v01,v11,fy), fz);
}

// ── Semi-Lagrangian backtracing ──────────────────────────────
Vec3 backtrace(int i, int j, int k) {
  float r   = CYL_RMN + (i+0.5f)*DR;
  float dta = DT_SIM * ADV_STR;
  float dr  = vR[i][j][k] * dta;
  float dth = (vT[i][j][k] / (r+1e-6f)) * dta;
  float dy  = vY[i][j][k] * dta;
  return new Vec3(i - dr/DR, j - dth/DTHETA, k - dy/DY_GRID);
}

// ── Advection ────────────────────────────────────────────────
void advectDensity() {
  for (int i=0;i<GRID_R;i++) for (int j=0;j<GRID_T;j++) for (int k=0;k<GRID_Y;k++) {
    densityNew[i][j][k] = sampleGrid(density, backtrace(i,j,k));
  }
}

void advectVelocity() {
  for (int i=0;i<GRID_R;i++) for (int j=0;j<GRID_T;j++) for (int k=0;k<GRID_Y;k++) {
    Vec3 prev = backtrace(i,j,k);
    vRNew[i][j][k] = mixF(sampleGrid(vR,prev), 0f, DISSIP);
    vTNew[i][j][k] = mixF(sampleGrid(vT,prev), 0f, DISSIP);
    vYNew[i][j][k] = mixF(sampleGrid(vY,prev), 0f, DISSIP);
  }
}

// ── External forces ──────────────────────────────────────────
void applyForces() {
  for (int i=0;i<GRID_R;i++) for (int j=0;j<GRID_T;j++) for (int k=0;k<GRID_Y;k++) {
    Vec3 pw  = gridToWorld(i,j,k);
    float r  = pw.xzMag();
    float th = atan2(pw.z, pw.x);
    float st = sin(th), ct = cos(th);

    // Orbital correction
    float idealSpd = sqrt(GM/(r+0.1f)) * ORB_VSCL;
    Vec3 tDir = new Vec3(-pw.z,0,pw.x).normalized();
    Vec3 idealVW = tDir.scale(idealSpd);
    Vec3 curVW   = new Vec3(vR[i][j][k]*ct - vT[i][j][k]*st,
                            vY[i][j][k],
                            vR[i][j][k]*st + vT[i][j][k]*ct);
    Vec3 correction = idealVW.sub(curVW).scale(ORB_AST);

    // Gravity
    Vec3 grav = new Vec3(0,0,0);
    float rsq = pw.magSq();
    if (rsq>0.1f) grav = pw.normalized().scale(-GRAV_STR*GM/rsq);

    Vec3 total = correction.add(grav);
    vR[i][j][k] += total.dot(new Vec3( ct,0,st)) * DT_SIM;
    vT[i][j][k] += total.dot(new Vec3(-st,0,ct)) * DT_SIM;
    vY[i][j][k] += total.y                        * DT_SIM;
  }
}

// ── Clamp velocity ───────────────────────────────────────────
void clampVelocity() {
  float maxSq = MAX_VEL*MAX_VEL;
  for (int i=0;i<GRID_R;i++) for (int j=0;j<GRID_T;j++) for (int k=0;k<GRID_Y;k++) {
    float vs = vR[i][j][k]*vR[i][j][k] + vT[i][j][k]*vT[i][j][k] + vY[i][j][k]*vY[i][j][k];
    if (vs>maxSq) {
      float sc = MAX_VEL/sqrt(vs);
      vR[i][j][k]*=sc; vT[i][j][k]*=sc; vY[i][j][k]*=sc;
    }
  }
}

// ── Divergence ───────────────────────────────────────────────
void computeDivergence() {
  float iDR=1f/DR, iDT=1f/DTHETA, iDY=1f/DY_GRID;
  for (int i=0;i<GRID_R;i++) for (int j=0;j<GRID_T;j++) for (int k=0;k<GRID_Y;k++) {
    if (i>0&&i<GRID_R-1&&k>0&&k<GRID_Y-1) {
      float ri = CYL_RMN+(i+0.5f)*DR;
      float rp = CYL_RMN+(i+1.5f)*DR, rm = CYL_RMN+(i-0.5f)*DR;
      int jp = (j+1)%GRID_T, jm = (j-1+GRID_T)%GRID_T;
      float dR  = (rp*vR[i+1][j][k]  - rm*vR[i-1][j][k] ) * 0.5f*iDR / ri;
      float dTH = (    vT[i][jp][k]  -      vT[i][jm][k]) * 0.5f*iDT / ri;
      float dY  = (    vY[i][j][k+1] -      vY[i][j][k-1]) * 0.5f*iDY;
      divergence[i][j][k] = dR+dTH+dY;
      pressure  [i][j][k] = 0f;
    } else {
      divergence[i][j][k] = 0f;
      pressure  [i][j][k] = 0f;
    }
  }
}

// ── Red–black Jacobi pressure solve ─────────────────────────
void solvePressure(int isRed) {
  for (int i=1;i<GRID_R-1;i++) for (int j=0;j<GRID_T;j++) for (int k=1;k<GRID_Y-1;k++) {
    if ((i+j+k)%2==isRed) {
      int jp=(j+1)%GRID_T, jm=(j-1+GRID_T)%GRID_T;
      float sum = pressure[i+1][j][k]+pressure[i-1][j][k]
                + pressure[i][jp][k]+pressure[i][jm][k]
                + pressure[i][j][k+1]+pressure[i][j][k-1];
      pressure[i][j][k] = (sum - divergence[i][j][k]) / 6f;
    }
  }
}

// ── Pressure projection ──────────────────────────────────────
void projectVelocity() {
  float iDR=1f/DR, iDT=1f/DTHETA, iDY=1f/DY_GRID;
  for (int i=1;i<GRID_R-1;i++) for (int j=0;j<GRID_T;j++) for (int k=1;k<GRID_Y-1;k++) {
    float r  = CYL_RMN+(i+0.5f)*DR;
    int jp=(j+1)%GRID_T, jm=(j-1+GRID_T)%GRID_T;
    vR[i][j][k] -= (pressure[i+1][j][k] - pressure[i-1][j][k]) * 0.5f*iDR;
    vT[i][j][k] -= (pressure[i][jp][k]  - pressure[i][jm][k] ) * 0.5f*iDT / r;
    vY[i][j][k] -= (pressure[i][j][k+1] - pressure[i][j][k-1]) * 0.5f*iDY;
  }
}

// ── Copy helper ──────────────────────────────────────────────
void copyField(float[][][] src, float[][][] dst) {
  for (int i=0;i<GRID_R;i++)
    for (int j=0;j<GRID_T;j++)
      for (int k=0;k<GRID_Y;k++) dst[i][j][k]=src[i][j][k];
}

// ── Full simulation step ─────────────────────────────────────
void simulationStep() {
  advectVelocity();
  advectDensity();
  copyField(vRNew,vR); copyField(vTNew,vT); copyField(vYNew,vY);
  copyField(densityNew,density);
  applyForces();
  clampVelocity();
  computeDivergence();
  for (int it=0;it<JAC_ITER;it++) { solvePressure(1); solvePressure(0); }
  projectVelocity();
}

// ── Scene initialisation ─────────────────────────────────────
void initScene() {
  for (int i=0;i<GRID_R;i++) for (int j=0;j<GRID_T;j++) for (int k=0;k<GRID_Y;k++) {
    Vec3 pw  = gridToWorld(i,j,k);
    float rxz = pw.xzMag();

    // Vertical modulation
    float vm  = 1f+(fbmRidged(pw.scale(VERT_SC))-0.5f)*2f*VERT_STR;
    float mht = DISK_THICK*vm;
    float fy  = sstep(mht, mht*0.7f,  abs(pw.y));
    float fi  = sstep(DISK_IN,  DISK_IN *1.2f, rxz);
    float fo  = sstep(DISK_OUT, DISK_OUT*0.8f, rxz);
    float base = fy*fi*fo;

    // Domain warp
    Vec3 wc = pw.scale(WARP_SC);
    Vec3 wv = new Vec3(
      fbmRidged(wc.add(new Vec3(13.7f,13.7f,13.7f))),
      fbmRidged(wc.add(new Vec3(24.2f,24.2f,24.2f))),
      fbmRidged(wc.add(new Vec3(19.1f,19.1f,19.1f)))
    );
    Vec3 wp = pw.add(wv.sub(new Vec3(0.5f,0.5f,0.5f)).scale(2f*WARP_STR2));

    // Local frame
    float th = atan2(wp.z, wp.x);
    Vec3 rDir = new Vec3(cos(th),0,sin(th));
    Vec3 tDir = new Vec3(-sin(th),0,cos(th));
    Vec3 vDir = new Vec3(0,1,0);
    Vec3 lc   = new Vec3(wp.dot(rDir), wp.dot(tDir), wp.dot(vDir));

    // Filament + clump noise
    float fn = pow(fbmRidged(lc.compMul(new Vec3(1f,TAN_STR,1f)).scale(FIL_SC)), FIL_CON);
    float cn = fbmRidged(lc.scale(CLMP_SC));
    float combined = mixF(fn, cn, CLMP_STR);

    density[i][j][k] = max(0f, base*combined*DISK_NS);
  }
}

// ── Velocity initialisation ──────────────────────────────────
void initVelocity() {
  for (int i=0;i<GRID_R;i++) for (int j=0;j<GRID_T;j++) for (int k=0;k<GRID_Y;k++) {
    Vec3 pw = gridToWorld(i,j,k);
    float r = pw.xzMag();
    if (r>0.1f) {
      float spd = sqrt(GM/(r+0.1f))*ORB_VSCL;
      Vec3 tDir = new Vec3(-pw.z,0,pw.x).normalized();
      Vec3 vw   = tDir.scale(spd);
      float th  = atan2(pw.z,pw.x);
      float ct  = cos(th), st = sin(th);
      vR[i][j][k] =  vw.x*ct + vw.z*st;
      vT[i][j][k] = -vw.x*st + vw.z*ct;
      vY[i][j][k] = 0f;
    }
  }
}
