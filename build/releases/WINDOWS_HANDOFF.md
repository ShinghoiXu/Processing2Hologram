# Windows build and universal-package handoff

This file is for the agent or maintainer who continues the release work on a
Windows x64 machine.

## Current state

- The Java code and runtime loader support Windows x64 and macOS.
- `build/releases/macos/Processing2Hologram` is the checked-in, install-ready
  macOS package.
- Its `library/Processing2Hologram.jar` contains
  `native/macos-universal/libprocessing2hologram.dylib` as a Mach-O universal
  binary for both Apple silicon (`arm64`) and Intel (`x86_64`).
- The macOS package and attached Looking Glass Portrait have been tested.
- A Windows DLL and the final universal JAR have **not** been produced or tested
  in the current macOS environment. Do not mark them verified until the Windows
  build and hardware checks below pass.
- Git intentionally tracks everything below `build/releases`; compiler output
  elsewhere below `build` remains ignored.

Preserve unrelated working-tree changes. Do not clean or replace the complete
repository just to rebuild a release.

## Windows prerequisites

- Windows 10 or 11 x64
- Processing 4 installed at `C:\Program Files\Processing`, or pass its actual
  location with `-ProcessingHome`
- Visual Studio 2022 Desktop development with C++
- CMake available on `PATH`
- Looking Glass Bridge 2.6 or later for the live hardware test

The build uses Processing's bundled JDK and does not download dependencies.

## 1. Build the Windows-only package

From the repository root in PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

For a non-default Processing installation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 `
  -ProcessingHome 'D:\path\to\Processing'
```

Expected output:

```text
build/releases/windows/Processing2Hologram
```

The package JAR must contain this native resource:

```text
native/windows-amd64/processing2hologram.dll
```

## 2. Extract the checked-in macOS native library

The universal macOS dylib is already stored inside the tracked macOS JAR, so a
fresh clone does not need any ignored build files from the Mac. Run this from the
repository root in the same PowerShell session:

```powershell
$ProcessingHome = 'C:\Program Files\Processing'
$JarTool = Join-Path $ProcessingHome 'app\resources\jdk\bin\jar.exe'
$MacJar = Join-Path (Get-Location) `
  'build\releases\macos\Processing2Hologram\library\Processing2Hologram.jar'
$ExtractRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
  ('processing2hologram-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $ExtractRoot | Out-Null
Push-Location $ExtractRoot
& $JarTool --extract --file $MacJar `
  native/macos-universal/libprocessing2hologram.dylib
if ($LASTEXITCODE -ne 0) { throw 'Could not extract the macOS native library' }
Pop-Location
$MacNative = Join-Path $ExtractRoot `
  'native\macos-universal\libprocessing2hologram.dylib'
```

If Processing is elsewhere, update `$ProcessingHome` to the same directory used
for `-ProcessingHome`.

## 3. Build the combined universal package

The Windows-only build above has already compiled the DLL, so reuse it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1 `
  -SkipNative -MacNative $MacNative
```

If a custom Processing path is required, add `-ProcessingHome $ProcessingHome`.
Expected output:

```text
build/releases/universal/Processing2Hologram
```

There must be one JAR, not two platform JARs placed together. At runtime,
`NativeLibraryLoader` selects the resource for the current operating system.

## 4. Verify before committing the release files

Check the universal JAR entries:

```powershell
$UniversalJar = `
  'build\releases\universal\Processing2Hologram\library\Processing2Hologram.jar'
& $JarTool --list --file $UniversalJar | Select-String `
  'native/(windows-amd64/processing2hologram.dll|macos-universal/libprocessing2hologram.dylib)'
```

The command must print both native-resource paths. Also confirm:

1. The normal build reports `CameraMathTest: all checks passed`.
2. Copy `build/releases/windows/Processing2Hologram` into the Windows Processing
   sketchbook's `libraries` directory and restart Processing.
3. Run `examples/Cube/Cube.pde` with Looking Glass Bridge and a display attached.
4. Confirm `hologram.status()` reports a connection and that the cube appears on
   the Looking Glass, not only in the Processing preview window.
5. Replace the installed package with
   `build/releases/universal/Processing2Hologram`, restart Processing, and repeat
   the Windows hardware test.
6. Run `git status --short build/releases` and ensure the Windows and universal
   release directories are visible to Git. Commit those complete directories,
   including their JARs, `library.properties`, examples, license, and README.

Do not commit `build/classes`, `build/resources`, `build/native-windows`, Gradle
caches, IDE output, Bridge logs, or temporary extraction files.

