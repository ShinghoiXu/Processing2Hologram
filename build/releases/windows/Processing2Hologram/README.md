# Processing2Hologram

Processing2Hologram is a Processing 4 library for showing `P3D` scenes on
Looking Glass displays. Draw a scene with familiar Processing commands; the
library renders the required views, assembles the quilt, and sends it to Looking
Glass Bridge.

If no display is connected, the same sketch still runs with a normal center-view
preview and a full quilt preview. The first validated hardware target is Looking
Glass Portrait, while connected devices use the quilt layout and view cone
reported by Bridge rather than Portrait-specific values.

## Requirements

- Windows 10 or 11 x64, or macOS 12 or later
- Processing 4.4.6 or later
- Looking Glass Bridge 2.6 or later
- A Looking Glass connected in desktop mode for live holographic output
- A sketch using the `P3D` renderer

## Install

Prebuilt packages are checked into `build/releases`. Open the directory for your
operating system, then copy the complete `Processing2Hologram` directory into
your Processing Sketchbook's `libraries` directory. For example, macOS users can
install `build/releases/macos/Processing2Hologram` directly after cloning or
downloading this repository—no compiler is required.

Restart Processing after installing or replacing the library.

To build an installable copy from this repository, see
[Hacking on the library](#hacking-on-the-library). Install the complete
`Processing2Hologram` directory from the platform-specific release output.

After restarting Processing, open:

```text
File > Examples > Contributed Libraries > Processing2Hologram > Cube
```

Make sure Looking Glass Bridge is running before starting the sketch if you want
live output on a display.

## Your first holographic sketch

```java
import processing2hologram.*;

LookingGlass hologram;
float angle;

void setup() {
  size(900, 700, P3D);
  hologram = new LookingGlass(this);
}

void draw() {
  angle += 0.012;                 // update once per animation frame
  hologram.render(this::drawScene);
  image(hologram.preview(), 0, 0, width, height);
}

void drawScene(PGraphics pg) {
  pg.background(15, 18, 28);
  pg.lights();
  pg.pushMatrix();
  pg.translate(pg.width * 0.5, pg.height * 0.5);
  pg.rotateY(angle);
  pg.box(150);
  pg.popMatrix();
}
```

The Processing window shows the center view. When a supported display and Bridge
are available, `render()` also sends the quilt to that display. You can show the
full quilt for debugging with:

```java
image(hologram.quilt(), 0, 0, width, height);
```

Check connection state and print a useful message with:

```java
println(hologram.isConnected());
println(hologram.status());
```

## Writing the scene callback

`drawScene()` is called once for every view in the quilt—normally 48 times on a
Portrait. Every call must draw the same moment in the scene from the camera that
the library has prepared.

Update changing state once in `draw()`, outside the callback:

- animation values
- physics and particle simulation
- input-derived object state
- random or noise seeds that change the scene

Use the callback only to draw:

- backgrounds, lights, materials, and shaders
- matrix transforms and Processing primitives
- `PShape` models and textures

Do not call `camera()`, `perspective()`, or `frustum()` on the callback's
`PGraphics`. Those calls replace the holographic view transform.

## Camera and depth

The library derives all views from one center camera. Configure it through
`hologram.camera()`:

```java
hologram.camera()
    .lookAt(210, 280, 800, 210, 280, 0)
    .fov(40)
    .clip(1, 10000)
    .depthScale(1.0);
```

`depthScale(0)` produces a flat image. `depthScale(1)` uses the connected
display's reported view cone. Values up to `2` exaggerate parallax, but excessive
depth can be uncomfortable and may expose gaps near the edge of the view cone.

`hologram.zoom(value)` applies a final Bridge-side zoom. A value of `1` preserves
the rendered framing.

## Displays and offline use

`new LookingGlass(this)` selects the first display reported by Bridge. If more
than one Looking Glass is connected, pass a Bridge display index:

```java
hologram = new LookingGlass(this, displayIndex);
```

For a connected device, the library asks Bridge for its name, serial number,
view cone, maximum texture size, and recommended quilt dimensions and grid. The
device's optical calibration is handled by Bridge during presentation; sketches
do not need to provide `pitch`, `slope`, or optical-center values.

If Bridge is unavailable or no display is connected, the sketch remains usable
in preview-only mode. It falls back to the standard Portrait quilt layout:
3360 x 3360, 8 x 6 views, aspect 0.75. Call `status()` to see why live output is
unavailable.

To save the current quilt with Looking Glass filename metadata:

```java
hologram.saveQuilt("my-scene");
```

## API at a glance

- `new LookingGlass(PApplet)` connects to the first display
- `new LookingGlass(PApplet, displayIndex)` selects a Bridge display
- `render(SceneRenderer)` renders and presents one scene snapshot
- `camera()` returns the center-camera configuration
- `preview()` returns the center-nearest view
- `quilt()` returns the complete quilt
- `zoom(value)` sets Bridge-side final zoom
- `saveQuilt(baseName)` saves a correctly tagged quilt PNG
- `device()` returns connected-device information, or `null` offline
- `quiltSettings()` returns the active quilt dimensions and grid
- `isConnected()` reports whether live presentation is active
- `status()` describes the current connection or failure
- `close()` releases Bridge and Processing graphics resources; Processing also
  calls it automatically during disposal

## Troubleshooting

If the Processing preview works but the Looking Glass is blank or white:

1. Read `hologram.status()`. It should begin with `Connected to`, not report
   preview-only mode.
2. Confirm Looking Glass Bridge is running and the device is enabled as a desktop
   display. For Portrait, its desktop resolution should be 1536 x 2048.
3. Replace the complete installed library directory with the one from
   `build/releases/macos` or `build/releases/windows`, then restart Processing.
   Processing keeps the old JAR and native library loaded until restart.
4. Use version 0.1.1 or later. Version 0.1.0 could produce a white Bridge window
   on Windows because it submitted from JOGL's context.

If the sketch reports that the recommended quilt exceeds the maximum texture
size, the connected device's quilt is larger than the texture supported by the
current Bridge/GPU path. The sketch will continue in preview-only mode.

For a custom Bridge installation, set the native library's absolute path with
`LOOKING_GLASS_BRIDGE_DLL` on Windows or `LOOKING_GLASS_BRIDGE_LIBRARY` on macOS.

## Current limitations

- Live output is available on Windows x64 and macOS. The macOS adapter and Bridge
  discovery are verified on Apple silicon; presentation with attached hardware
  still needs broader validation.
- The main sketch renderer must be `P3D`.
- Complex scenes can be expensive because the callback is rendered once per view.
- A previously flattened color `PGraphics` cannot be converted back into correct
  multiview geometry. The library needs the scene-drawing callback.

## Hacking on the library

This section is for contributors and anyone who wants to build or modify the
Java/native implementation.

### Build from source

On Windows, run from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

On macOS, with Processing installed in `/Applications`, run:

```bash
./build.sh
```

For a non-default Processing location, use:

```bash
./build.sh --processing-home /path/to/Processing.app
```

You may instead set `PROCESSING_HOME`. Both scripts use Processing's bundled JDK
and `core.jar` and do not download dependencies. The Windows build uses CMake and
the Visual Studio 2022 C++ toolchain; the macOS build uses Apple Clang.

The build compiles the Java sources, platform JNI adapter, camera/quilt checks,
and a Processing-ready distribution containing the native library. The main JAR
keeps the standard `Processing2Hologram.jar` name required by the library folder;
the parent release directory identifies its platform:

```text
build/releases/macos/Processing2Hologram
build/releases/windows/Processing2Hologram
```

Files under `build/releases` are intentionally tracked by Git so users can
install a published package without building it. Other contents of `build`
remain ignored. After changing Java or native code, rebuild on each supported
platform and commit the resulting platform release directory along with the
source changes.

The macOS package contains a universal `arm64` + `x86_64` dylib. The Windows
package contains the x64 DLL. Java bytecode is portable, but these default JARs
are platform-specific because each embeds only its own native library.

### Build one cross-platform JAR

A single JAR can contain both native libraries. Build the native binary on each
operating system, transfer one binary to the other machine, then inject it while
building the final package.

On macOS, after copying in a Windows DLL:

```bash
./build.sh --windows-native /path/to/processing2hologram.dll
```

On Windows, after copying in the universal macOS dylib produced by `build.sh`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 `
  -MacNative .\libprocessing2hologram.dylib
```

Either command writes the combined distribution to:

```text
build/releases/universal/Processing2Hologram
```

Its `library/Processing2Hologram.jar` contains the Windows x64 DLL and the
universal macOS dylib. The runtime selects the correct one automatically. Do not
place separate macOS and Windows JARs together in the same Processing library;
they contain duplicate Java classes.

### Verification

The normal build runs the non-graphical checks. To additionally open a hidden
Processing OpenGL surface and verify the rendered Portrait quilt, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 -RunGraphicsTest
```

or on macOS:

```bash
./build.sh --run-graphics-test
```

The optional Windows hardware diagnostic is:

```powershell
& 'C:\Program Files\Processing\app\resources\jdk\bin\java.exe' `
  -cp 'build\releases\windows\Processing2Hologram\library\Processing2Hologram.jar' `
  processing2hologram.BridgeDiagnostics
```

It is safe to run without hardware. With a display connected, it prints the
selected device and its Bridge-recommended quilt settings.

### Implementation notes

The Java renderer creates parallel horizontal cameras with asymmetric frusta,
renders the scene into a quilt, and submits the OpenGL texture through a small
JNI adapter. Bridge performs the final device-calibrated optical pass.

On Windows, that pass runs in a private double-buffered WGL context sharing
Processing's quilt texture, and Bridge window messages are processed on
Processing's animation thread. On macOS, the adapter uses Bridge's OpenGL
texture-sharing API and submits Retina-aware physical texture dimensions.

If texture sharing fails, live presentation is disabled for the rest of the
session while the local preview remains available. The interop code is kept
small because Processing's public OpenGL surface does not promise a stable
texture-sharing contract across Processing/JOGL versions.

## References

- [Processing render techniques](https://processing.org/tutorials/rendering/)
- [Processing library template](https://processing.github.io/processing-library-template/)
- [Looking Glass Bridge native API](https://lfdocs.lookingglassfactory.com/software/looking-glass-bridge-sdk/native-function-reference)
- [Looking Glass quilt format](https://lookingglassfactory.com/tutorial/what-is-a-quilt)

## License

MIT. See [LICENSE](LICENSE).
