'use client';

import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { cn } from '@/lib/cn';
import { useTheme } from '@/components/theme/ThemeProvider';

type ContactFlockingBackgroundProps = {
  className?: string;
};

type BoidState = {
  position: THREE.Vector3;
  velocity: THREE.Vector3;
  acceleration: THREE.Vector3;
  hue: number;
  baseScale: number;
  phase: number;
  maxSpeed: number;
  maxForce: number;
};

const MAX_INSTANCE_COUNT = 760;
const BOUNDS = { width: 620, height: 520, depth: 620 };
const CENTER = new THREE.Vector3(0, -82, 0);

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function getTargetBoidLimit(
  width: number,
  height: number,
  reducedMotion: boolean,
  isMobile: boolean,
) {
  const area = Math.max(1, width * height);
  const areaFactor = clamp(area / (1280 * 720), 0.7, 1.45);
  const dpr = clamp(window.devicePixelRatio || 1, 1, 2.2);
  const dprFactor = dpr > 1.8 ? 0.86 : dpr > 1.45 ? 0.92 : 1;
  const cores = navigator.hardwareConcurrency ?? 6;
  const coreFactor = cores <= 4 ? 0.82 : cores >= 10 ? 1.12 : 1;
  const reducedFactor = reducedMotion ? 0.56 : 1;
  const base = isMobile ? 500 : 620;
  const raw = Math.round(base * areaFactor * dprFactor * coreFactor * reducedFactor);
  return isMobile ? clamp(raw, 360, 600) : clamp(raw, 360, 980);
}

function createSpawnPosition() {
  const radiusBase = Math.max(BOUNDS.width, BOUNDS.depth) * 0.92;
  const radius = radiusBase + Math.random() * radiusBase * 0.42;
  const theta = Math.random() * Math.PI * 2;
  const y = CENTER.y + (Math.random() - 0.5) * BOUNDS.height * 1.45;
  return new THREE.Vector3(
    CENTER.x + Math.cos(theta) * radius,
    y,
    CENTER.z + Math.sin(theta) * radius,
  );
}

function createInitialVelocity() {
  const randomDir = new THREE.Vector3(
    Math.random() - 0.5,
    Math.random() - 0.5,
    Math.random() - 0.5,
  );
  if (randomDir.lengthSq() < 0.0001) {
    randomDir.set(1, 0, 0);
  }
  randomDir.normalize();
  return randomDir;
}

function addBoid(
  boids: BoidState[],
  instancedMesh: THREE.InstancedMesh,
  boidLimit: number,
  flockMaxSpeed: number,
  flockMaxForce: number,
  lightTheme: boolean,
) {
  if (boids.length >= boidLimit || boids.length >= MAX_INSTANCE_COUNT) return;
  const spawnPosition = createSpawnPosition();
  const boid: BoidState = {
    position: spawnPosition,
    velocity: createInitialVelocity(),
    acceleration: new THREE.Vector3(),
    hue: Math.random(),
    baseScale: 1.1 + Math.random() * 4.3,
    phase: Math.random() * Math.PI * 2,
    maxSpeed: flockMaxSpeed * (0.82 + Math.random() * 0.38),
    maxForce: flockMaxForce * (0.74 + Math.random() * 0.62),
  };
  boids.push(boid);

  const color = new THREE.Color().setHSL(
    boid.hue,
    lightTheme ? 0.72 : 0.94,
    lightTheme ? 0.38 : 0.63,
  );
  instancedMesh.setColorAt(boids.length - 1, color);
  if (instancedMesh.instanceColor) {
    instancedMesh.instanceColor.needsUpdate = true;
  }
}

export function ContactFlockingBackground({ className }: ContactFlockingBackgroundProps) {
  const mountRef = useRef<HTMLDivElement | null>(null);
  const { resolvedTheme } = useTheme();

  useEffect(() => {
    const mount = mountRef.current;
    if (!mount) return;

    let disposed = false;
    let raf = 0;
    let resizeObserver: ResizeObserver | null = null;
    let targetBoidLimit = 300;
    let spawnAccumulator = 0;
    let orbitAngle = 0;

    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const isMobile =
      window.matchMedia('(max-width: 768px)').matches ||
      window.matchMedia('(pointer: coarse)').matches;

    const scene = new THREE.Scene();
    const lightTheme = resolvedTheme === 'light';
    scene.fog = new THREE.Fog(lightTheme ? 0xd6dee7 : 0x090f1b, 350, 1400);

    const camera = new THREE.PerspectiveCamera(46, 1, 0.1, 2200);
    const orbitRadius = 240;
    const cameraHeight = 128;

    const renderer = new THREE.WebGLRenderer({
      alpha: true,
      antialias: !reducedMotion,
      powerPreference: 'high-performance',
    });
    renderer.setPixelRatio(clamp(window.devicePixelRatio || 1, 1, isMobile ? 1.35 : 1.8));
    renderer.setClearColor(lightTheme ? 0xe8ecf1 : 0x090f1b, lightTheme ? 0.72 : 0.84);
    renderer.domElement.style.position = 'absolute';
    renderer.domElement.style.inset = '0';
    renderer.domElement.style.width = '100%';
    renderer.domElement.style.height = '100%';
    renderer.domElement.style.display = 'block';
    mount.appendChild(renderer.domElement);

    const boidGeometry = new THREE.ConeGeometry(2.2, 8.2, 4, 1, true);
    boidGeometry.rotateX(Math.PI / 2);

    const boidMaterial = new THREE.MeshBasicMaterial({
      wireframe: true,
      transparent: true,
      opacity: reducedMotion ? 0.64 : 0.88,
      depthWrite: false,
      toneMapped: false,
      blending: lightTheme ? THREE.NormalBlending : THREE.AdditiveBlending,
    });

    const boidMesh = new THREE.InstancedMesh(boidGeometry, boidMaterial, MAX_INSTANCE_COUNT);
    boidMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    boidMesh.frustumCulled = false;
    scene.add(boidMesh);

    const boids: BoidState[] = [];
    const forward = new THREE.Vector3(0, 0, 1);
    const pointerNdc = new THREE.Vector2();
    const targetPointerNdc = new THREE.Vector2();
    const lookOffset = new THREE.Vector2();
    const targetLookOffset = new THREE.Vector2();
    const pointerWorld = new THREE.Vector3();
    const lookTarget = new THREE.Vector3();
    const plane = new THREE.Plane(new THREE.Vector3(0, 0, 1), 0);
    const raycaster = new THREE.Raycaster();
    const dummy = new THREE.Object3D();

    const sepForce = new THREE.Vector3();
    const aliForce = new THREE.Vector3();
    const cohForce = new THREE.Vector3();
    const diff = new THREE.Vector3();
    const toPointer = new THREE.Vector3();
    const steer = new THREE.Vector3();
    const desired = new THREE.Vector3();
    const cohesionCenter = new THREE.Vector3();
    const velocityDirection = new THREE.Vector3();
    const wanderForce = new THREE.Vector3();
    const boundsForce = new THREE.Vector3();

    let pointerInside = false;
    let pointerRecentAt = 0;

    const maxSpeed = reducedMotion ? 1.9 : 2.8;
    const maxForce = reducedMotion ? 0.03 : 0.044;
    const desiredSeparation = 25;
    const neighborDistance = 50;
    const pointerInfluenceRadius = 300;
    const boundaryStrength = reducedMotion ? 0.0046 : 0.0062;
    const boundaryMargin = 0.86;

    const onPointerPosition = (clientX: number, clientY: number) => {
      const rect = mount.getBoundingClientRect();
      const inside =
        clientX >= rect.left &&
        clientX <= rect.right &&
        clientY >= rect.top &&
        clientY <= rect.bottom;

      if (!inside) {
        pointerInside = false;
        return;
      }

      const nx = ((clientX - rect.left) / rect.width) * 2 - 1;
      const ny = ((clientY - rect.top) / rect.height) * 2 - 1;
      targetPointerNdc.set(clamp(nx, -1, 1), clamp(-ny, -1, 1));
      pointerInside = true;
      pointerRecentAt = performance.now();
    };

    const onWindowPointerMove = (event: PointerEvent) => {
      onPointerPosition(event.clientX, event.clientY);
    };

    const onTouchMove = (event: TouchEvent) => {
      const touch = event.touches[0];
      if (!touch) return;
      onPointerPosition(touch.clientX, touch.clientY);
    };

    const onWindowPointerLeave = () => {
      pointerInside = false;
    };

    const updateSizeAndDensity = () => {
      const width = Math.max(1, mount.clientWidth);
      const height = Math.max(1, mount.clientHeight);
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      targetBoidLimit = getTargetBoidLimit(width, height, reducedMotion, isMobile);

      if (boids.length > targetBoidLimit) {
        boids.length = targetBoidLimit;
      }
    };

    updateSizeAndDensity();

    const initialBoidCount = Math.max(132, Math.floor(targetBoidLimit * 0.55));
    for (let i = 0; i < initialBoidCount; i += 1) {
      addBoid(boids, boidMesh, targetBoidLimit, maxSpeed, maxForce, lightTheme);
    }
    boidMesh.count = boids.length;

    window.addEventListener('pointermove', onWindowPointerMove, { passive: true });
    window.addEventListener('pointerdown', onWindowPointerMove, { passive: true });
    window.addEventListener('pointerleave', onWindowPointerLeave);
    window.addEventListener('touchmove', onTouchMove, { passive: true });
    window.addEventListener('touchstart', onTouchMove, { passive: true });
    resizeObserver = new ResizeObserver(updateSizeAndDensity);
    resizeObserver.observe(mount);

    const clock = new THREE.Clock();
    clock.start();
    let elapsedTime = 0;

    const animate = () => {
      if (disposed) return;
      raf = window.requestAnimationFrame(animate);

      const delta = Math.min(clock.getDelta(), 0.045);
      elapsedTime += delta;
      const elapsed = elapsedTime;
      const simSteps = delta * 60;

      const pointerRecentlyActive = pointerInside || performance.now() - pointerRecentAt < 900;
      if (!pointerRecentlyActive) {
        targetPointerNdc.multiplyScalar(0.96);
      }
      pointerNdc.lerp(targetPointerNdc, reducedMotion ? 0.08 : 0.12);

      targetLookOffset.set(pointerNdc.x * 24, pointerNdc.y * 18);
      lookOffset.lerp(targetLookOffset, 0.07);

      orbitAngle += delta * (reducedMotion ? 0.09 : 0.13);
      camera.position.set(
        Math.sin(orbitAngle) * orbitRadius + lookOffset.x * 0.26,
        cameraHeight + lookOffset.y * 0.55,
        Math.cos(orbitAngle) * orbitRadius,
      );
      lookTarget.set(CENTER.x + lookOffset.x, CENTER.y + 100 + lookOffset.y * 0.64, CENTER.z);
      camera.lookAt(lookTarget);

      raycaster.setFromCamera(pointerNdc, camera);
      if (!raycaster.ray.intersectPlane(plane, pointerWorld)) {
        pointerWorld.set(pointerNdc.x * BOUNDS.width * 0.4, pointerNdc.y * BOUNDS.height * 0.35, 0);
      }

      spawnAccumulator += simSteps;
      const spawnRateStep = reducedMotion ? 7.2 : 3.1;
      while (spawnAccumulator >= spawnRateStep && boids.length < targetBoidLimit) {
        addBoid(boids, boidMesh, targetBoidLimit, maxSpeed, maxForce, lightTheme);
        spawnAccumulator -= spawnRateStep;
      }
      boidMesh.count = boids.length;

      const pointerForceScale = pointerRecentlyActive ? 0.078 : 0;

      for (let i = 0; i < boids.length; i += 1) {
        const boid = boids[i];
        if (boid === undefined) continue;
        sepForce.set(0, 0, 0);
        aliForce.set(0, 0, 0);
        cohForce.set(0, 0, 0);
        cohesionCenter.set(0, 0, 0);
        let sepCount = 0;
        let aliCount = 0;
        let cohCount = 0;

        for (let j = 0; j < boids.length; j += 1) {
          if (i === j) continue;
          const other = boids[j];
          if (other === undefined) continue;
          diff.subVectors(boid.position, other.position);
          const distSq = diff.lengthSq();
          if (distSq <= 0) continue;

          const dist = Math.sqrt(distSq);
          if (dist < desiredSeparation) {
            diff.multiplyScalar(1 / distSq);
            sepForce.add(diff);
            sepCount += 1;
          }
          if (dist < neighborDistance) {
            aliForce.add(other.velocity);
            cohesionCenter.add(other.position);
            aliCount += 1;
            cohCount += 1;
          }
        }

        boid.acceleration.set(0, 0, 0);

        if (sepCount > 0) {
          sepForce.multiplyScalar(1 / sepCount);
          if (sepForce.lengthSq() > 0) {
            sepForce.setLength(boid.maxSpeed);
            sepForce.sub(boid.velocity);
            sepForce.clampLength(0, boid.maxForce);
          }
          sepForce.multiplyScalar(1.5);
          boid.acceleration.add(sepForce);
        }

        if (aliCount > 0) {
          aliForce.multiplyScalar(1 / aliCount);
          if (aliForce.lengthSq() > 0) {
            aliForce.setLength(boid.maxSpeed);
            aliForce.sub(boid.velocity);
            aliForce.clampLength(0, boid.maxForce);
          }
          aliForce.multiplyScalar(1.0);
          boid.acceleration.add(aliForce);
        }

        if (cohCount > 0) {
          cohesionCenter.multiplyScalar(1 / cohCount);
          desired.subVectors(cohesionCenter, boid.position);
          if (desired.lengthSq() > 0) {
            desired.setLength(boid.maxSpeed);
            steer.subVectors(desired, boid.velocity);
            steer.clampLength(0, boid.maxForce);
            cohForce.copy(steer);
            cohForce.multiplyScalar(1.0);
            boid.acceleration.add(cohForce);
          }
        }

        wanderForce.set(
          Math.sin(elapsed * 0.63 + boid.phase * 1.7),
          Math.cos(elapsed * 0.57 + boid.phase * 1.25),
          Math.sin(elapsed * 0.49 + boid.phase * 2.1),
        );
        wanderForce.multiplyScalar(reducedMotion ? 0.0016 : 0.0025);
        boid.acceleration.add(wanderForce);

        boundsForce.set(0, 0, 0);
        const maxX = BOUNDS.width * boundaryMargin;
        const maxY = BOUNDS.height * boundaryMargin;
        const maxZ = BOUNDS.depth * boundaryMargin;
        if (boid.position.x > maxX) boundsForce.x -= (boid.position.x - maxX) / BOUNDS.width;
        else if (boid.position.x < -maxX) boundsForce.x += (-maxX - boid.position.x) / BOUNDS.width;
        if (boid.position.y > CENTER.y + maxY)
          boundsForce.y -= (boid.position.y - (CENTER.y + maxY)) / BOUNDS.height;
        else if (boid.position.y < CENTER.y - maxY)
          boundsForce.y += (CENTER.y - maxY - boid.position.y) / BOUNDS.height;
        if (boid.position.z > maxZ) boundsForce.z -= (boid.position.z - maxZ) / BOUNDS.depth;
        else if (boid.position.z < -maxZ) boundsForce.z += (-maxZ - boid.position.z) / BOUNDS.depth;
        if (boundsForce.lengthSq() > 0) {
          boundsForce.multiplyScalar(boundaryStrength);
          boid.acceleration.add(boundsForce);
        }

        if (pointerForceScale > 0.00001) {
          toPointer.subVectors(pointerWorld, boid.position);
          const pointerDistance = toPointer.length();
          if (pointerDistance > 0.001 && pointerDistance < pointerInfluenceRadius) {
            const falloff = 1 - pointerDistance / pointerInfluenceRadius;
            toPointer.multiplyScalar(1 / pointerDistance);
            boid.acceleration.addScaledVector(toPointer, pointerForceScale * (0.3 + 0.7 * falloff));
          }
        }

        boid.velocity.addScaledVector(boid.acceleration, simSteps);
        boid.velocity.clampLength(0, boid.maxSpeed);
        boid.position.addScaledVector(boid.velocity, simSteps);
      }

      for (let i = 0; i < boids.length; i += 1) {
        const boid = boids[i];
        if (boid === undefined) continue;
        velocityDirection.copy(boid.velocity);
        if (velocityDirection.lengthSq() < 0.0001) {
          velocityDirection.copy(forward);
        } else {
          velocityDirection.normalize();
        }

        dummy.position.copy(boid.position);
        dummy.quaternion.setFromUnitVectors(forward, velocityDirection);
        const pulse = 0.5 + 0.5 * Math.sin(elapsed * 1.8 + boid.phase);
        const scale = 0.1 + boid.baseScale * (0.15 + pulse * 0.85);
        dummy.scale.setScalar(scale);
        dummy.updateMatrix();
        boidMesh.setMatrixAt(i, dummy.matrix);
      }

      boidMesh.instanceMatrix.needsUpdate = true;
      renderer.render(scene, camera);
    };

    animate();

    return () => {
      disposed = true;
      cancelAnimationFrame(raf);
      resizeObserver?.disconnect();
      window.removeEventListener('pointermove', onWindowPointerMove);
      window.removeEventListener('pointerdown', onWindowPointerMove);
      window.removeEventListener('pointerleave', onWindowPointerLeave);
      window.removeEventListener('touchmove', onTouchMove);
      window.removeEventListener('touchstart', onTouchMove);
      boidGeometry.dispose();
      boidMaterial.dispose();
      boidMesh.dispose();
      renderer.dispose();
      if (renderer.domElement.parentNode === mount) {
        mount.removeChild(renderer.domElement);
      }
    };
  }, [resolvedTheme]);

  return (
    <div
      ref={mountRef}
      aria-hidden="true"
      className={cn('contact-scene-bg h-full w-full', className)}
    />
  );
}
