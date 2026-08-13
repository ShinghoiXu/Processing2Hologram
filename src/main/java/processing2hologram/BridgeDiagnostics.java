package processing2hologram;

import processing2hologram.internal.NativeBridge;

/** Command-line diagnostic for the native Bridge installation and connected display. */
public final class BridgeDiagnostics {
  private BridgeDiagnostics() {}

  public static void main(String[] args) {
    if (!NativeBridge.isSupportedPlatform()) {
      System.out.println(
          "This build has no live-output backend for the current platform. Quilt preview remains available.");
      return;
    }
    if (!NativeBridge.isDisplayConnected()) {
      System.out.println("Looking Glass Bridge did not report a connected display.");
      return;
    }
    System.out.println("Looking Glass Bridge reports a connected display.");
    System.out.println("Open the Cube example for Bridge calibration and OpenGL interop diagnostics;");
    System.out.println("a command-line process cannot safely create a Bridge OpenGL window.");
  }
}
