package processing2hologram;

import processing2hologram.internal.NativeBridge;

/** Command-line diagnostic for the native Bridge installation and connected display. */
public final class BridgeDiagnostics {
  private BridgeDiagnostics() {}

  public static void main(String[] args) {
    if (!NativeBridge.isDisplayConnected()) {
      System.out.println("No Looking Glass display is currently connected. Bridge was not initialized.");
      return;
    }
    System.out.println("Windows reports a connected Looking Glass display.");
    System.out.println("Open the Cube example for Bridge calibration and OpenGL interop diagnostics;");
    System.out.println("a command-line process cannot safely create a Bridge OpenGL window.");
  }
}
