import processing2hologram.*;

final int GRID_COLUMNS = 41;
final int GRID_ROWS = 33;
final int GLOW_SEEDS = 15;

LookingGlass hologram;
float[][] waveHeight = new float[GRID_ROWS][GRID_COLUMNS];
float waveTime;
boolean paused;
boolean pointerActive;

void setup() {
  size(420, 560, P3D);
  surface.setTitle("Processing2Hologram - Wave Garden");

  hologram = new LookingGlass(this);
  hologram.camera()
      .lookAt(0, -300, 610, 0, 30, 0)
      .fov(42)
      .clip(1, 2600)
      .depthScale(1.05);
  updateWaves();
}

void draw() {
  if (frameCount == 1) fitWindowToPreview();
  if (!paused) {
    waveTime += 0.018;
    // Cache the animated mesh once; drawGarden() only reads this array.
    updateWaves();
  }

  hologram.render(this::drawGarden);

  background(3, 10, 18);
  image(hologram.preview(), 0, 0, width, height);
  drawHud("MOVE mouse to stir  |  SPACE pause", paused ? "paused" : "live wave mesh");
}

void updateWaves() {
  float pointerX = pointerActive
      ? map(constrain(mouseX, 0, max(1, width)), 0, max(1, width), -250, 250)
      : 0;
  float pointerZ = pointerActive
      ? map(constrain(mouseY, 0, max(1, height)), 0, max(1, height), -250, 250)
      : 0;

  for (int row = 0; row < GRID_ROWS; row++) {
    float z = map(row, 0, GRID_ROWS - 1, -250, 250);
    for (int column = 0; column < GRID_COLUMNS; column++) {
      float x = map(column, 0, GRID_COLUMNS - 1, -250, 250);
      float radius = sqrt(x * x + z * z);
      float pointerRadius = dist(x, z, pointerX, pointerZ);
      waveHeight[row][column] =
          35 * sin(radius * 0.046 - waveTime * 2.0)
          + 16 * sin(x * 0.032 + waveTime * 1.4) * cos(z * 0.027 - waveTime)
          + 24 * exp(-pointerRadius * 0.018) * sin(pointerRadius * 0.075 - waveTime * 3.0);
    }
  }
}

void drawGarden(PGraphics pg) {
  pg.colorMode(RGB, 255);
  pg.background(3, 10, 18);
  pg.ambientLight(18, 32, 42);
  pg.directionalLight(85, 165, 220, -0.25, 0.65, -1);
  pg.pointLight(255, 65, 185, 160, -180, 100);

  // Colored triangle strips form a lightweight animated surface.
  pg.noStroke();
  for (int row = 0; row < GRID_ROWS - 1; row++) {
    pg.beginShape(TRIANGLE_STRIP);
    for (int column = 0; column < GRID_COLUMNS; column++) {
      float x = map(column, 0, GRID_COLUMNS - 1, -250, 250);
      for (int offset = 0; offset <= 1; offset++) {
        int r = row + offset;
        float z = map(r, 0, GRID_ROWS - 1, -250, 250);
        float h = waveHeight[r][column];
        float tint = constrain(map(h, -75, 75, 0, 1), 0, 1);
        pg.fill(lerp(18, 235, tint), lerp(82, 58, tint), lerp(140, 220, tint), 225);
        pg.vertex(x, h, z);
      }
    }
    pg.endShape();
  }

  // A sparse wireframe reveals surface curvature and holographic parallax.
  pg.noFill();
  pg.stroke(92, 215, 255, 105);
  pg.strokeWeight(1);
  for (int row = 0; row < GRID_ROWS; row += 2) {
    pg.beginShape();
    for (int column = 0; column < GRID_COLUMNS; column++) {
      float x = map(column, 0, GRID_COLUMNS - 1, -250, 250);
      float z = map(row, 0, GRID_ROWS - 1, -250, 250);
      pg.vertex(x, waveHeight[row][column] - 1, z);
    }
    pg.endShape();
  }
  for (int column = 0; column < GRID_COLUMNS; column += 3) {
    pg.beginShape();
    for (int row = 0; row < GRID_ROWS; row++) {
      float x = map(column, 0, GRID_COLUMNS - 1, -250, 250);
      float z = map(row, 0, GRID_ROWS - 1, -250, 250);
      pg.vertex(x, waveHeight[row][column] - 1, z);
    }
    pg.endShape();
  }

  pg.noStroke();
  pg.sphereDetail(7);
  for (int i = 0; i < GLOW_SEEDS; i++) {
    int column = 2 + (i * 11) % (GRID_COLUMNS - 4);
    int row = 2 + (i * 7) % (GRID_ROWS - 4);
    float x = map(column, 0, GRID_COLUMNS - 1, -250, 250);
    float z = map(row, 0, GRID_ROWS - 1, -250, 250);
    float y = waveHeight[row][column] - 14 - 8 * sin(waveTime * 2 + i);
    pg.pushMatrix();
    pg.translate(x, y, z);
    pg.emissive(30, 145 + (i % 3) * 35, 210);
    pg.fill(90, 210, 255);
    pg.sphere(5 + (i % 4));
    pg.emissive(0, 0, 0);
    pg.popMatrix();
  }
}

void keyPressed() {
  if (key == ' ') paused = !paused;
}

void mouseMoved() {
  pointerActive = true;
}

void mouseDragged() {
  pointerActive = true;
}

void fitWindowToPreview() {
  PGraphics preview = hologram.preview();
  float scale = min(1, min(displayWidth * 0.8f / preview.width,
                           displayHeight * 0.8f / preview.height));
  int newHeight = max(128, round(preview.height * scale));
  int newWidth = max(128, round(newHeight * preview.width / (float) preview.height));
  if (newWidth != width || newHeight != height) surface.setSize(newWidth, newHeight);
}

void drawHud(String controls, String state) {
  noStroke();
  fill(0, 170);
  rect(10, height - 48, width - 20, 38, 7);
  fill(235);
  textSize(11);
  text(controls, 20, height - 30);
  fill(95, 220, 255);
  text(state + "  |  " + (hologram.isConnected() ? "display connected" : "preview only"),
       20, height - 16);
}
