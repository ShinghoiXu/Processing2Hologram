import processing2hologram.*;

LookingGlass hologram;
float angle;

void setup() {
  // Portrait fallback: one quilt view is 420 x 560 (3:4). If a connected
  // device reports a different quilt, fitWindowToPreview() adapts the
  // window on the first frame.
  size(420, 560, P3D);
  hologram = new LookingGlass(this);

  // The library owns the per-view camera. The user describes only the center camera.
  hologram.camera()
      .fov(40)
      .depthScale(1.0);
}

void draw() {
  // Resize the window once the preview size is known (after setup).
  if (frameCount == 1) fitWindowToPreview();

  // Update animation exactly once. drawScene() is called 48 times per frame on Portrait.
  angle += 0.012;
  hologram.render(this::drawScene);

  background(18);
  image(hologram.preview(), 0, 0, width, height);

  drawStatus("Processing2Hologram - " + hologram.status());
}

// Match the window to the preview's aspect ratio so the image is never
// stretched. Falls back to the Portrait 3:4 window when offline.
void fitWindowToPreview() {
  PGraphics preview = hologram.preview();
  float scale = min(1, min(displayWidth * 0.8f / preview.width,
                           displayHeight * 0.8f / preview.height));
  int newHeight = max(128, round(preview.height * scale));
  int newWidth = max(128, round(newHeight * preview.width / (float) preview.height));
  if (newWidth != width || newHeight != height) {
    surface.setSize(newWidth, newHeight);
  }
}

// Wrap long status text into multiple lines instead of running past the edge.
void drawStatus(String message) {
  fill(255);
  float maxWidth = width - 32;
  String[] words = split(message, ' ');
  StringBuilder line = new StringBuilder();
  float y = height - 12;
  for (String word : words) {
    String candidate = line.length() == 0 ? word : line + " " + word;
    if (line.length() > 0 && textWidth(candidate) > maxWidth) {
      text(line.toString(), 16, y);
      y -= 14;
      line = new StringBuilder(word);
    } else {
      if (line.length() > 0) line.append(' ');
      line.append(word);
    }
  }
  if (line.length() > 0) text(line.toString(), 16, y);
}

void drawScene(PGraphics pg) {
  pg.background(15, 18, 28);
  pg.lights();

  pg.pushMatrix();
  pg.translate(pg.width * 0.5, pg.height * 0.5, 0);
  pg.rotateX(-0.35);
  pg.rotateY(angle);
  pg.noStroke();
  pg.fill(80, 175, 255);
  pg.box(150);
  pg.popMatrix();
}

