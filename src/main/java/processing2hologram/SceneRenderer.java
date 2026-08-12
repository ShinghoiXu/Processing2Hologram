package processing2hologram;

import processing.core.PGraphics;

/** Draws one immutable snapshot of a scene into a holographic view. */
@FunctionalInterface
public interface SceneRenderer {
  /**
   * Called once for every view in the quilt.
   *
   * <p>Do not advance animation, physics, random state, or other mutable scene
   * state here. Update that state once in the sketch's {@code draw()} method,
   * before calling {@link LookingGlass#render(SceneRenderer)}.</p>
   */
  void draw(PGraphics graphics);
}

