package processing2hologram.internal;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

/** Extracts the bundled JNI adapter without changing the process-wide native library path. */
final class NativeLibraryLoader {
  private static boolean loaded;

  private NativeLibraryLoader() {}

  static boolean isSupportedPlatform() {
    String os = System.getProperty("os.name", "").toLowerCase();
    String architecture = System.getProperty("os.arch", "").toLowerCase();
    boolean supportedArchitecture = architecture.equals("amd64")
        || architecture.equals("x86_64") || architecture.equals("aarch64")
        || architecture.equals("arm64");
    boolean windowsX64 = os.contains("win")
        && (architecture.equals("amd64") || architecture.equals("x86_64"));
    return windowsX64 || (os.contains("mac") && supportedArchitecture);
  }

  static synchronized void load() {
    if (loaded) return;
    if (!isSupportedPlatform()) {
      throw new UnsupportedOperationException(
          "Looking Glass live output requires Windows x64 or macOS; quilt preview is available");
    }

    String override = System.getProperty("processing2hologram.native");
    if (override != null && !override.isBlank()) {
      System.load(Path.of(override).toAbsolutePath().toString());
      loaded = true;
      return;
    }

    boolean macOS = System.getProperty("os.name", "").toLowerCase().contains("mac");
    String resource = macOS
        ? "/native/macos-universal/libprocessing2hologram.dylib"
        : "/native/windows-amd64/processing2hologram.dll";
    try (InputStream input = NativeLibraryLoader.class.getResourceAsStream(resource)) {
      if (input == null) {
        // Useful while developing from unpacked classes and for standard Processing native layouts.
        System.loadLibrary("processing2hologram");
      } else {
        Path directory = Files.createTempDirectory("processing2hologram-native-");
        Path library = directory.resolve(macOS
            ? "libprocessing2hologram.dylib" : "processing2hologram.dll");
        Files.copy(input, library, StandardCopyOption.REPLACE_EXISTING);
        library.toFile().deleteOnExit();
        directory.toFile().deleteOnExit();
        System.load(library.toAbsolutePath().toString());
      }
      loaded = true;
    } catch (IOException exception) {
      throw new UnsatisfiedLinkError("Could not extract Processing2Hologram native adapter: "
          + exception.getMessage());
    }
  }
}
