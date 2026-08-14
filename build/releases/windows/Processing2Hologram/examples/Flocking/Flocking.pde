import processing2hologram.*;

final int BOID_COUNT = 128;

final float CAMERA_FOV = 42;
final float CAMERA_NEAR_CLIP = 1;
final float CAMERA_FAR_CLIP = 4000;

final float DEPTH_PLANE_DISTANCE = 300;
final float DEPTH_REPULSION_ZONE = 60;
final float DEPTH_ATTRACTION = 0.0011;
final float DEPTH_REPULSION = 0.005;
final float DEPTH_DAMPING = 0.0006;
final float BOID_VISUAL_RADIUS = 24;
final float SPAWN_OUTSIDE_PADDING = 18;

final float DESIRED_SEPARATION = 32;
final float NEIGHBOR_DISTANCE = 76;
final float POINTER_RADIUS = 300;

LookingGlass hologram;
Boid[] flock = new Boid[BOID_COUNT];

int lastFrameMillis;
int lastPointerMillis = -10000;
float simulationTime;
boolean paused;

PVector cameraEye = new PVector(0, -35, 875);
PVector cameraTarget = new PVector(0, 0, 0);
PVector cameraForward = new PVector();
PVector cameraRight = new PVector();
PVector cameraUp = new PVector();
PVector pointerWorld = new PVector();
float cameraFocusDistance;

void setup() {
  // One Portrait quilt view is 420 x 560. fitWindowToPreview() adapts this
  // window if a connected Looking Glass reports a different aspect ratio.
  size(420, 560, P3D);
  surface.setTitle("Processing2Hologram - Interactive Flocking");

  hologram = new LookingGlass(this);
  hologram.camera()
      .fov(CAMERA_FOV)
      .clip(CAMERA_NEAR_CLIP, CAMERA_FAR_CLIP)
      .depthScale(1.05)
      .lookAt(
          cameraEye.x, cameraEye.y, cameraEye.z,
          cameraTarget.x, cameraTarget.y, cameraTarget.z
      );

  updateCameraBasis();
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

void updateCameraBasis() {
  cameraForward.set(cameraTarget);
  cameraForward.sub(cameraEye);
  cameraFocusDistance = cameraForward.mag();
  cameraForward.normalize();

  cameraRight.set(cameraForward.cross(new PVector(0, 1, 0)));
  if (cameraRight.magSq() < 0.0001) cameraRight.set(1, 0, 0);
  cameraRight.normalize();

  cameraUp.set(cameraRight.cross(cameraForward));
  cameraUp.normalize();
}

// Convert the mouse position into a point on the fixed camera's focus plane.
void updatePointerWorld() {
  float nx = map(constrain(mouseX, 0, width), 0, max(1, width), -1, 1);
  float ny = map(constrain(mouseY, 0, height), 0, max(1, height), -1, 1);
  float halfHeight = tan(radians(CAMERA_FOV * 0.5)) * cameraFocusDistance;
  float halfWidth = halfHeight * hologram.quiltSettings().viewAspect();

  pointerWorld.set(cameraTarget);
  pointerWorld.add(PVector.mult(cameraRight, nx * halfWidth));
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

    if (!boid.hasEnteredView) {
      addIngressSteering(boid);
    }

    addDepthForces(boid);

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

    boolean fullyOutside = isCompletelyOutsideView(boid);
    if (!boid.hasEnteredView) {
      // A recycled boid is allowed to travel in from its off-screen spawn.
      if (!fullyOutside) boid.hasEnteredView = true;
    } else if (fullyOutside) {
      // Destroy exactly one departed boid and replace it just outside a random
      // edge, aimed roughly at the focal center so it enters without popping.
      flock[i] = new Boid(true);
    }
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

// Guide recycled boids into a slowly wandering region around screen center.
// Keeping this correction in the camera's XY plane avoids another depth pull.
void addIngressSteering(Boid boid) {
  float fromEyeX = boid.position.x - cameraEye.x;
  float fromEyeY = boid.position.y - cameraEye.y;
  float fromEyeZ = boid.position.z - cameraEye.z;
  float viewX = fromEyeX * cameraRight.x
      + fromEyeY * cameraRight.y
      + fromEyeZ * cameraRight.z;
  float viewY = fromEyeX * cameraUp.x
      + fromEyeY * cameraUp.y
      + fromEyeZ * cameraUp.z;
  float wanderX = boid.ingressOffsetX
      + sin(simulationTime * 0.71 + boid.phase * 1.3) * 42;
  float wanderY = boid.ingressOffsetY
      + cos(simulationTime * 0.63 + boid.phase * 1.7) * 52;
  float desiredViewX = wanderX - viewX;
  float desiredViewY = wanderY - viewY;
  float desiredLength = sqrt(
      desiredViewX * desiredViewX + desiredViewY * desiredViewY
  );
  if (desiredLength < 0.0001) return;

  float desiredScale = boid.maxSpeed / desiredLength;
  float velocityViewX = boid.velocity.x * cameraRight.x
      + boid.velocity.y * cameraRight.y
      + boid.velocity.z * cameraRight.z;
  float velocityViewY = boid.velocity.x * cameraUp.x
      + boid.velocity.y * cameraUp.y
      + boid.velocity.z * cameraUp.z;
  float steerX = desiredViewX * desiredScale - velocityViewX;
  float steerY = desiredViewY * desiredScale - velocityViewY;
  float steerLength = sqrt(steerX * steerX + steerY * steerY);
  if (steerLength > boid.maxForce) {
    float forceScale = boid.maxForce / steerLength;
    steerX *= forceScale;
    steerY *= forceScale;
  }

  float weight = 0.42;
  boid.acceleration.x += (cameraRight.x * steerX + cameraUp.x * steerY) * weight;
  boid.acceleration.y += (cameraRight.y * steerX + cameraUp.y * steerY) * weight;
  boid.acceleration.z += (cameraRight.z * steerX + cameraUp.z * steerY) * weight;
}

// A very weak spring and damping gently favor the focal plane. Two soft walls
// add a small quadratic repulsion near the front and back depth limits.
void addDepthForces(Boid boid) {
  float fromFocusX = boid.position.x - cameraTarget.x;
  float fromFocusY = boid.position.y - cameraTarget.y;
  float fromFocusZ = boid.position.z - cameraTarget.z;
  float depthOffset = fromFocusX * cameraForward.x
      + fromFocusY * cameraForward.y
      + fromFocusZ * cameraForward.z;
  float depthVelocity = boid.velocity.x * cameraForward.x
      + boid.velocity.y * cameraForward.y
      + boid.velocity.z * cameraForward.z;

  float depthForce = -depthOffset / DEPTH_PLANE_DISTANCE * DEPTH_ATTRACTION;
  depthForce -= depthVelocity * DEPTH_DAMPING;

  float repulsionStart = DEPTH_PLANE_DISTANCE - DEPTH_REPULSION_ZONE;
  float distanceFromCenter = abs(depthOffset);
  if (distanceFromCenter > repulsionStart) {
    float penetration = constrain(
        (distanceFromCenter - repulsionStart) / DEPTH_REPULSION_ZONE,
        0,
        2
    );
    float directionToCenter = depthOffset < 0 ? 1 : -1;
    depthForce += directionToCenter * penetration * penetration * DEPTH_REPULSION;
  }

  boid.acceleration.x += cameraForward.x * depthForce;
  boid.acceleration.y += cameraForward.y * depthForce;
  boid.acceleration.z += cameraForward.z * depthForce;
}

// Use the fixed center camera's actual view frustum. The visual-radius margin
// means recycling only happens after the entire wireframe has left the view.
boolean isCompletelyOutsideView(Boid boid) {
  float fromEyeX = boid.position.x - cameraEye.x;
  float fromEyeY = boid.position.y - cameraEye.y;
  float fromEyeZ = boid.position.z - cameraEye.z;
  float cameraDepth = fromEyeX * cameraForward.x
      + fromEyeY * cameraForward.y
      + fromEyeZ * cameraForward.z;

  if (cameraDepth + BOID_VISUAL_RADIUS < CAMERA_NEAR_CLIP) return true;
  if (cameraDepth - BOID_VISUAL_RADIUS > CAMERA_FAR_CLIP) return true;
  // A boid whose center crossed the eye plane can still have a visible tip.
  if (cameraDepth <= 0) return false;

  float viewX = fromEyeX * cameraRight.x
      + fromEyeY * cameraRight.y
      + fromEyeZ * cameraRight.z;
  float viewY = fromEyeX * cameraUp.x
      + fromEyeY * cameraUp.y
      + fromEyeZ * cameraUp.z;
  float halfHeight = tan(radians(CAMERA_FOV * 0.5)) * cameraDepth;
  float halfWidth = halfHeight * hologram.quiltSettings().viewAspect();

  return abs(viewX) > halfWidth + BOID_VISUAL_RADIUS
      || abs(viewY) > halfHeight + BOID_VISUAL_RADIUS;
}

void spawnBoidInView(Boid boid) {
  float depthOffset = random(
      -DEPTH_PLANE_DISTANCE * 0.72,
      DEPTH_PLANE_DISTANCE * 0.72
  );
  float cameraDepth = cameraFocusDistance + depthOffset;
  float halfHeight = tan(radians(CAMERA_FOV * 0.5)) * cameraDepth;
  float halfWidth = halfHeight * hologram.quiltSettings().viewAspect();
  float spawnX = random(
      -max(1, halfWidth - BOID_VISUAL_RADIUS) * 0.88,
      max(1, halfWidth - BOID_VISUAL_RADIUS) * 0.88
  );
  float spawnY = random(
      -max(1, halfHeight - BOID_VISUAL_RADIUS) * 0.88,
      max(1, halfHeight - BOID_VISUAL_RADIUS) * 0.88
  );

  setBoidViewPosition(boid, cameraDepth, spawnX, spawnY);
  giveBoidRandomVelocity(boid);
  boid.hasEnteredView = true;
}

void spawnBoidOutsideView(Boid boid) {
  float depthOffset = random(
      -DEPTH_PLANE_DISTANCE * 0.72,
      DEPTH_PLANE_DISTANCE * 0.72
  );
  float cameraDepth = cameraFocusDistance + depthOffset;
  float halfHeight = tan(radians(CAMERA_FOV * 0.5)) * cameraDepth;
  float halfWidth = halfHeight * hologram.quiltSettings().viewAspect();
  float outsideOffset = BOID_VISUAL_RADIUS + SPAWN_OUTSIDE_PADDING;
  float spawnX;
  float spawnY;

  if (random(1) < 0.5) {
    spawnX = random(1) < 0.5
        ? -halfWidth - outsideOffset
        : halfWidth + outsideOffset;
    spawnY = random(-halfHeight * 0.82, halfHeight * 0.82);
  } else {
    spawnX = random(-halfWidth * 0.82, halfWidth * 0.82);
    spawnY = random(1) < 0.5
        ? -halfHeight - outsideOffset
        : halfHeight + outsideOffset;
  }

  setBoidViewPosition(boid, cameraDepth, spawnX, spawnY);
  boid.ingressOffsetX = random(-halfWidth * 0.22, halfWidth * 0.22);
  boid.ingressOffsetY = random(-halfHeight * 0.22, halfHeight * 0.22);
  aimBoidAtFocalCenter(boid);
  boid.hasEnteredView = false;
}

void setBoidViewPosition(Boid boid, float cameraDepth, float viewX, float viewY) {
  boid.position.set(cameraEye);
  boid.position.x += cameraForward.x * cameraDepth
      + cameraRight.x * viewX + cameraUp.x * viewY;
  boid.position.y += cameraForward.y * cameraDepth
      + cameraRight.y * viewX + cameraUp.y * viewY;
  boid.position.z += cameraForward.z * cameraDepth
      + cameraRight.z * viewX + cameraUp.z * viewY;
}

void aimBoidAtFocalCenter(Boid boid) {
  float aimX = cameraTarget.x - boid.position.x;
  float aimY = cameraTarget.y - boid.position.y;
  float aimZ = cameraTarget.z - boid.position.z;
  float aimLength = sqrt(aimX * aimX + aimY * aimY + aimZ * aimZ);
  if (aimLength < 0.0001) {
    aimX = cameraForward.x;
    aimY = cameraForward.y;
    aimZ = cameraForward.z;
    aimLength = 1;
  }

  aimX /= aimLength;
  aimY /= aimLength;
  aimZ /= aimLength;
  float sidewaysJitter = random(-0.32, 0.32);
  float verticalJitter = random(-0.32, 0.32);
  float depthJitter = random(-0.12, 0.12);
  aimX += cameraRight.x * sidewaysJitter
      + cameraUp.x * verticalJitter + cameraForward.x * depthJitter;
  aimY += cameraRight.y * sidewaysJitter
      + cameraUp.y * verticalJitter + cameraForward.y * depthJitter;
  aimZ += cameraRight.z * sidewaysJitter
      + cameraUp.z * verticalJitter + cameraForward.z * depthJitter;
  float jitteredLength = sqrt(aimX * aimX + aimY * aimY + aimZ * aimZ);
  float speed = random(1.0, boid.maxSpeed);
  boid.velocity.set(
      aimX / jitteredLength * speed,
      aimY / jitteredLength * speed,
      aimZ / jitteredLength * speed
  );
  boid.acceleration.set(0, 0, 0);
}

void giveBoidRandomVelocity(Boid boid) {
  float velocityX;
  float velocityY;
  float velocityZ;
  float lengthSq;
  do {
    velocityX = random(-1, 1);
    velocityY = random(-1, 1);
    velocityZ = random(-1, 1);
    lengthSq = velocityX * velocityX + velocityY * velocityY + velocityZ * velocityZ;
  } while (lengthSq < 0.001);

  float speed = random(1.0, boid.maxSpeed) / sqrt(lengthSq);
  boid.velocity.set(velocityX * speed, velocityY * speed, velocityZ * speed);
  boid.acceleration.set(0, 0, 0);
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
    flock[i] = new Boid(false);
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

  PVector position = new PVector();
  PVector velocity = new PVector();
  PVector acceleration = new PVector();
  boolean hasEnteredView;
  float ingressOffsetX;
  float ingressOffsetY;

  Boid(boolean startOutsideView) {
    if (startOutsideView) {
      spawnBoidOutsideView(this);
    } else {
      spawnBoidInView(this);
    }
  }
}
