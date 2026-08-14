import processing2hologram.*;

final int BOID_COUNT = 128;

final float BOUNDS_X = 270;
final float BOUNDS_Y = 350;
final float BOUNDS_Z = 300;
final float CAMERA_FOV = 42;

final float DESIRED_SEPARATION = 32;
final float NEIGHBOR_DISTANCE = 76;
final float POINTER_RADIUS = 300;

LookingGlass hologram;
Boid[] flock = new Boid[BOID_COUNT];

int lastFrameMillis;
int lastPointerMillis = -10000;
float simulationTime;
float lookX;
float lookY;
boolean paused;

PVector cameraEye = new PVector();
PVector cameraTarget = new PVector();
PVector pointerWorld = new PVector();

void setup() {
  // One Portrait quilt view is 420 x 560. fitWindowToPreview() adapts this
  // window if a connected Looking Glass reports a different aspect ratio.
  size(420, 560, P3D);
  surface.setTitle("Processing2Hologram - Interactive Flocking");

  hologram = new LookingGlass(this);
  hologram.camera()
      .fov(CAMERA_FOV)
      .clip(1, 4000)
      .depthScale(1.05);

  resetFlock();
  lastFrameMillis = millis();
}

void draw() {
  if (frameCount == 1) fitWindowToPreview();

  int now = millis();
  float simulationSteps = constrain((now - lastFrameMillis) / (1000.0 / 60.0), 0.1, 2.4);
  lastFrameMillis = now;

  boolean pointerActive = now - lastPointerMillis < 1100;
  if (mousePressed) {
    pointerActive = true;
    lastPointerMillis = now;
  }

  updateCamera(pointerActive);
  updatePointerWorld();

  if (!paused) {
    simulationTime += simulationSteps / 60.0;
    updateFlock(simulationSteps, pointerActive);
  }

  // The simulation above advances once. drawFlock() only renders the immutable
  // snapshot, because LookingGlass calls it once for every quilt view.
  hologram.render(this::drawFlock);

  background(5, 9, 16);
  image(hologram.preview(), 0, 0, width, height);
  drawOverlay(pointerActive);
}

void updateCamera(boolean pointerActive) {
  float boundedMouseX = constrain(mouseX, 0, width);
  float boundedMouseY = constrain(mouseY, 0, height);
  float targetLookX = pointerActive
      ? map(boundedMouseX, 0, max(1, width), -42, 42)
      : 0;
  float targetLookY = pointerActive
      ? map(boundedMouseY, 0, max(1, height), -32, 32)
      : 0;
  lookX = lerp(lookX, targetLookX, 0.065);
  lookY = lerp(lookY, targetLookY, 0.065);

  float orbit = simulationTime * 0.08;
  cameraTarget.set(lookX, lookY, 0);
  cameraEye.set(
      sin(orbit) * 90 + lookX * 0.16,
      -35 + lookY * 0.12,
      820 + cos(orbit) * 55
  );

  hologram.camera().lookAt(
      cameraEye.x, cameraEye.y, cameraEye.z,
      cameraTarget.x, cameraTarget.y, cameraTarget.z
  );
}

// Convert the mouse position into a point on the camera's focus plane. This
// keeps interaction aligned with the preview even while the camera drifts.
void updatePointerWorld() {
  PVector forward = PVector.sub(cameraTarget, cameraEye);
  float focusDistance = forward.mag();
  forward.normalize();

  PVector right = forward.cross(new PVector(0, 1, 0));
  if (right.magSq() < 0.0001) right.set(1, 0, 0);
  right.normalize();

  PVector cameraUp = right.cross(forward);
  cameraUp.normalize();

  float nx = map(constrain(mouseX, 0, width), 0, max(1, width), -1, 1);
  float ny = map(constrain(mouseY, 0, height), 0, max(1, height), -1, 1);
  float halfHeight = tan(radians(CAMERA_FOV * 0.5)) * focusDistance;
  float halfWidth = halfHeight * hologram.quiltSettings().viewAspect();

  pointerWorld.set(cameraTarget);
  pointerWorld.add(PVector.mult(right, nx * halfWidth));
  pointerWorld.add(PVector.mult(cameraUp, ny * halfHeight));
}

void updateFlock(float step, boolean pointerActive) {
  float separationSq = DESIRED_SEPARATION * DESIRED_SEPARATION;
  float neighborSq = NEIGHBOR_DISTANCE * NEIGHBOR_DISTANCE;
  float pointerRadiusSq = POINTER_RADIUS * POINTER_RADIUS;

  for (int i = 0; i < flock.length; i++) {
    Boid boid = flock[i];

    float sepX = 0;
    float sepY = 0;
    float sepZ = 0;
    float alignX = 0;
    float alignY = 0;
    float alignZ = 0;
    float centerX = 0;
    float centerY = 0;
    float centerZ = 0;
    int separationCount = 0;
    int neighborCount = 0;

    for (int j = 0; j < flock.length; j++) {
      if (i == j) continue;
      Boid other = flock[j];

      float dx = boid.position.x - other.position.x;
      float dy = boid.position.y - other.position.y;
      float dz = boid.position.z - other.position.z;
      float distanceSq = dx * dx + dy * dy + dz * dz;
      if (distanceSq < 0.0001) continue;

      if (distanceSq < separationSq) {
        sepX += dx / distanceSq;
        sepY += dy / distanceSq;
        sepZ += dz / distanceSq;
        separationCount++;
      }

      if (distanceSq < neighborSq) {
        alignX += other.velocity.x;
        alignY += other.velocity.y;
        alignZ += other.velocity.z;
        centerX += other.position.x;
        centerY += other.position.y;
        centerZ += other.position.z;
        neighborCount++;
      }
    }

    boid.acceleration.set(0, 0, 0);

    if (separationCount > 0) {
      addSteering(
          boid,
          sepX / separationCount,
          sepY / separationCount,
          sepZ / separationCount,
          1.55
      );
    }

    if (neighborCount > 0) {
      addSteering(
          boid,
          alignX / neighborCount,
          alignY / neighborCount,
          alignZ / neighborCount,
          1.0
      );
      addSteering(
          boid,
          centerX / neighborCount - boid.position.x,
          centerY / neighborCount - boid.position.y,
          centerZ / neighborCount - boid.position.z,
          0.92
      );
    }

    // A different phase for every boid prevents the flock from becoming rigid.
    boid.acceleration.x += sin(simulationTime * 0.63 + boid.phase * 1.7) * 0.0030;
    boid.acceleration.y += cos(simulationTime * 0.57 + boid.phase * 1.25) * 0.0030;
    boid.acceleration.z += sin(simulationTime * 0.49 + boid.phase * 2.1) * 0.0030;

    addBoundaryForce(boid);

    if (pointerActive) {
      float dx = pointerWorld.x - boid.position.x;
      float dy = pointerWorld.y - boid.position.y;
      float dz = pointerWorld.z - boid.position.z;
      float distanceSq = dx * dx + dy * dy + dz * dz;

      if (distanceSq > 0.0001 && distanceSq < pointerRadiusSq) {
        float distance = sqrt(distanceSq);
        float falloff = 1.0 - distance / POINTER_RADIUS;
        // Moving the pointer attracts. Holding the mouse pushes the flock away.
        float strength = mousePressed ? -0.135 : 0.078;
        strength *= 0.3 + 0.7 * falloff;
        boid.acceleration.x += dx / distance * strength;
        boid.acceleration.y += dy / distance * strength;
        boid.acceleration.z += dz / distance * strength;
      }
    }

    boid.velocity.x += boid.acceleration.x * step;
    boid.velocity.y += boid.acceleration.y * step;
    boid.velocity.z += boid.acceleration.z * step;
    limit(boid.velocity, boid.maxSpeed);

    boid.position.x += boid.velocity.x * step;
    boid.position.y += boid.velocity.y * step;
    boid.position.z += boid.velocity.z * step;

    keepRecoverable(boid);
  }
}

void addSteering(Boid boid, float desiredX, float desiredY, float desiredZ, float weight) {
  float desiredLength = sqrt(
      desiredX * desiredX + desiredY * desiredY + desiredZ * desiredZ
  );
  if (desiredLength < 0.0001) return;

  float desiredScale = boid.maxSpeed / desiredLength;
  float steerX = desiredX * desiredScale - boid.velocity.x;
  float steerY = desiredY * desiredScale - boid.velocity.y;
  float steerZ = desiredZ * desiredScale - boid.velocity.z;
  float steerLength = sqrt(steerX * steerX + steerY * steerY + steerZ * steerZ);

  if (steerLength > boid.maxForce) {
    float forceScale = boid.maxForce / steerLength;
    steerX *= forceScale;
    steerY *= forceScale;
    steerZ *= forceScale;
  }

  boid.acceleration.x += steerX * weight;
  boid.acceleration.y += steerY * weight;
  boid.acceleration.z += steerZ * weight;
}

void addBoundaryForce(Boid boid) {
  float marginX = BOUNDS_X * 0.82;
  float marginY = BOUNDS_Y * 0.82;
  float marginZ = BOUNDS_Z * 0.82;
  float strength = 0.018;

  if (boid.position.x > marginX) {
    boid.acceleration.x -= (boid.position.x - marginX) / BOUNDS_X * strength;
  } else if (boid.position.x < -marginX) {
    boid.acceleration.x += (-marginX - boid.position.x) / BOUNDS_X * strength;
  }

  if (boid.position.y > marginY) {
    boid.acceleration.y -= (boid.position.y - marginY) / BOUNDS_Y * strength;
  } else if (boid.position.y < -marginY) {
    boid.acceleration.y += (-marginY - boid.position.y) / BOUNDS_Y * strength;
  }

  if (boid.position.z > marginZ) {
    boid.acceleration.z -= (boid.position.z - marginZ) / BOUNDS_Z * strength;
  } else if (boid.position.z < -marginZ) {
    boid.acceleration.z += (-marginZ - boid.position.z) / BOUNDS_Z * strength;
  }
}

// A large frame hitch cannot strand a boid forever outside the soft boundary.
void keepRecoverable(Boid boid) {
  float outerX = BOUNDS_X * 1.35;
  float outerY = BOUNDS_Y * 1.35;
  float outerZ = BOUNDS_Z * 1.35;

  if (abs(boid.position.x) > outerX) {
    boid.position.x = constrain(boid.position.x, -outerX, outerX);
    boid.velocity.x *= -0.55;
  }
  if (abs(boid.position.y) > outerY) {
    boid.position.y = constrain(boid.position.y, -outerY, outerY);
    boid.velocity.y *= -0.55;
  }
  if (abs(boid.position.z) > outerZ) {
    boid.position.z = constrain(boid.position.z, -outerZ, outerZ);
    boid.velocity.z *= -0.55;
  }
}

void limit(PVector vector, float maximum) {
  float lengthSq = vector.magSq();
  if (lengthSq > maximum * maximum) {
    vector.mult(maximum / sqrt(lengthSq));
  }
}

void drawFlock(PGraphics pg) {
  pg.background(9, 15, 27);
  pg.colorMode(HSB, 360, 100, 100, 100);
  pg.noFill();
  pg.blendMode(ADD);
  pg.hint(DISABLE_DEPTH_MASK);

  for (Boid boid : flock) {
    pg.pushMatrix();
    pg.translate(boid.position.x, boid.position.y, boid.position.z);
    orientAlongVelocity(pg, boid.velocity);
    pg.rotateZ(boid.phase + simulationTime * 0.17);

    float pulse = 0.5 + 0.5 * sin(simulationTime * 1.8 + boid.phase);
    float scale = 0.38 + boid.baseScale * (0.22 + pulse * 0.78);
    pg.scale(scale);

    pg.stroke(boid.hue, 90, 100, 82);
    pg.strokeWeight(1.25 / max(0.55, scale));
    drawWireCone(pg);
    pg.popMatrix();
  }

  pg.hint(ENABLE_DEPTH_MASK);
  pg.blendMode(BLEND);
  pg.colorMode(RGB, 255);
}

void orientAlongVelocity(PGraphics pg, PVector velocity) {
  float speed = velocity.mag();
  if (speed < 0.0001) return;

  float dx = velocity.x / speed;
  float dy = velocity.y / speed;
  float dz = constrain(velocity.z / speed, -1, 1);
  float angle = acos(dz);

  // Cross product of local +Z and the desired direction.
  float axisX = -dy;
  float axisY = dx;
  float axisLength = sqrt(axisX * axisX + axisY * axisY);

  if (axisLength > 0.0001) {
    pg.rotate(angle, axisX / axisLength, axisY / axisLength, 0);
  } else if (dz < 0) {
    pg.rotateX(PI);
  }
}

void drawWireCone(PGraphics pg) {
  float radius = 4.68;
  float baseZ = -7.02;
  float tipZ = 10.92;

  pg.beginShape(LINES);

  // Diamond-shaped base.
  pg.vertex(radius, 0, baseZ);
  pg.vertex(0, radius, baseZ);
  pg.vertex(0, radius, baseZ);
  pg.vertex(-radius, 0, baseZ);
  pg.vertex(-radius, 0, baseZ);
  pg.vertex(0, -radius, baseZ);
  pg.vertex(0, -radius, baseZ);
  pg.vertex(radius, 0, baseZ);

  // Four edges converge at the forward tip.
  pg.vertex(radius, 0, baseZ);
  pg.vertex(0, 0, tipZ);
  pg.vertex(0, radius, baseZ);
  pg.vertex(0, 0, tipZ);
  pg.vertex(-radius, 0, baseZ);
  pg.vertex(0, 0, tipZ);
  pg.vertex(0, -radius, baseZ);
  pg.vertex(0, 0, tipZ);

  pg.endShape();
}

void drawOverlay(boolean pointerActive) {
  hint(DISABLE_DEPTH_TEST);
  camera();
  noLights();

  noStroke();
  fill(4, 8, 16, 196);
  rect(12, 12, width - 24, 72, 10);

  fill(255);
  textAlign(LEFT, TOP);
  textSize(14);
  text("INTERACTIVE FLOCKING", 24, 23);

  fill(185, 205, 225);
  textSize(11);
  String interaction = mousePressed
      ? "Repelling flock - release to attract"
      : pointerActive
          ? "Attracting flock - hold mouse to repel"
          : "Move mouse to attract - hold to repel";
  text(interaction, 24, 46);
  text("SPACE pause/resume   R reset", 24, 63);

  fill(4, 8, 16, 174);
  rect(12, height - 36, width - 24, 24, 8);
  fill(150, 174, 198);
  text(
      hologram.isConnected() ? "Looking Glass connected" : "Portrait quilt preview (Bridge offline)",
      24,
      height - 30
  );

  hint(ENABLE_DEPTH_TEST);
}

void resetFlock() {
  for (int i = 0; i < flock.length; i++) {
    flock[i] = new Boid();
  }
}

void fitWindowToPreview() {
  PGraphics preview = hologram.preview();
  float scale = min(
      1,
      min(displayWidth * 0.8 / preview.width, displayHeight * 0.8 / preview.height)
  );
  int newHeight = max(128, round(preview.height * scale));
  int newWidth = max(128, round(newHeight * preview.width / (float) preview.height));
  if (newWidth != width || newHeight != height) {
    surface.setSize(newWidth, newHeight);
  }
}

void mouseMoved() {
  lastPointerMillis = millis();
}

void mouseDragged() {
  lastPointerMillis = millis();
}

void mousePressed() {
  lastPointerMillis = millis();
}

void keyPressed() {
  if (key == ' ') {
    paused = !paused;
  } else if (key == 'r' || key == 'R') {
    resetFlock();
  }
}

class Boid {
  float hue = random(360);
  float baseScale = random(0.78, 1.72);
  float phase = random(TWO_PI);
  float maxSpeed = random(2.15, 3.05);
  float maxForce = random(0.034, 0.058);

  PVector position = new PVector(
      random(-BOUNDS_X * 0.88, BOUNDS_X * 0.88),
      random(-BOUNDS_Y * 0.88, BOUNDS_Y * 0.88),
      random(-BOUNDS_Z * 0.88, BOUNDS_Z * 0.88)
  );
  PVector velocity = randomDirection();
  PVector acceleration = new PVector();

  PVector randomDirection() {
    PVector direction;
    do {
      direction = new PVector(random(-1, 1), random(-1, 1), random(-1, 1));
    } while (direction.magSq() < 0.001);
    direction.normalize();
    direction.mult(random(1.0, maxSpeed));
    return direction;
  }
}
