param(
  [string]$ProcessingHome = 'C:\Program Files\Processing',
  [string]$MacNative = '',
  [switch]$SkipNative,
  [switch]$SkipTests,
  [switch]$RunGraphicsTest
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProcessingApp = Join-Path $ProcessingHome 'app'
$ProcessingJava = Join-Path $ProcessingApp 'resources\jdk'
$ProcessingCoreDirectory = Join-Path $ProcessingApp 'resources\core\library'
$ProcessingCoreJar = Get-ChildItem -LiteralPath $ProcessingCoreDirectory -Filter 'core-*.jar' |
  Sort-Object Name -Descending |
  Select-Object -First 1

if (-not $ProcessingCoreJar) {
  throw "Processing core JAR was not found below $ProcessingCoreDirectory"
}

$Javac = Join-Path $ProcessingJava 'bin\javac.exe'
$Java = Join-Path $ProcessingJava 'bin\java.exe'
$Jar = Join-Path $ProcessingJava 'bin\jar.exe'
$BuildRoot = Join-Path $ProjectRoot 'build'
$ClassDirectory = Join-Path $BuildRoot 'classes'
$TestClassDirectory = Join-Path $BuildRoot 'test-classes'
$ResourceDirectory = Join-Path $BuildRoot 'resources'
$NativeBuildDirectory = Join-Path $BuildRoot 'native-windows'
$ReleaseKind = if ($MacNative) { 'universal' } else { 'windows' }
$DistributionRoot = Join-Path (Join-Path (Join-Path $BuildRoot 'releases') $ReleaseKind) 'Processing2Hologram'
$DistributionLibrary = Join-Path $DistributionRoot 'library'
$DistributionExamples = Join-Path $DistributionRoot 'examples'
$LibraryJar = Join-Path $DistributionLibrary 'Processing2Hologram.jar'

$ExpectedBuildRoot = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot 'build'))
if ([System.IO.Path]::GetFullPath($BuildRoot) -ne $ExpectedBuildRoot) {
  throw "Refusing to clean unexpected build directory: $BuildRoot"
}
if ($MacNative -and -not (Test-Path -LiteralPath $MacNative -PathType Leaf)) {
  throw "macOS native library was not found: $MacNative"
}
foreach ($Directory in @($ClassDirectory, $TestClassDirectory, $ResourceDirectory, $DistributionRoot)) {
  if (Test-Path -LiteralPath $Directory) {
    Remove-Item -LiteralPath $Directory -Recurse -Force
  }
}

New-Item -ItemType Directory -Force -Path $ClassDirectory, $TestClassDirectory, $ResourceDirectory,
  $DistributionLibrary, $DistributionExamples | Out-Null

if (-not $SkipNative) {
  cmake -S (Join-Path $ProjectRoot 'native\windows') -B $NativeBuildDirectory -A x64 `
    "-DPROCESSING_JAVA_HOME=$ProcessingJava"
  if ($LASTEXITCODE -ne 0) { throw 'Native CMake configuration failed' }
  cmake --build $NativeBuildDirectory --config Release
  if ($LASTEXITCODE -ne 0) { throw 'Native compilation failed' }
}
$NativeOutput = Join-Path $NativeBuildDirectory 'Release\processing2hologram.dll'
if (-not (Test-Path -LiteralPath $NativeOutput)) {
  throw 'Native DLL is missing. Run build.ps1 once without -SkipNative.'
}
$NativeResourceDirectory = Join-Path $ResourceDirectory 'native\windows-amd64'
New-Item -ItemType Directory -Force -Path $NativeResourceDirectory | Out-Null
Copy-Item -LiteralPath $NativeOutput -Destination $NativeResourceDirectory -Force
if ($MacNative) {
  $MacResourceDirectory = Join-Path $ResourceDirectory 'native\macos-universal'
  New-Item -ItemType Directory -Force -Path $MacResourceDirectory | Out-Null
  Copy-Item -LiteralPath $MacNative `
    -Destination (Join-Path $MacResourceDirectory 'libprocessing2hologram.dylib') -Force
}

$MainSources = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'src\main\java') -Filter '*.java' -Recurse |
  Select-Object -ExpandProperty FullName
& $Javac -encoding UTF-8 -source 17 -target 17 -classpath $ProcessingCoreJar.FullName `
  -d $ClassDirectory $MainSources
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed' }

if (-not $SkipTests) {
  $TestSources = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'src\test\java') -Filter '*.java' -Recurse |
    Select-Object -ExpandProperty FullName
  & $Javac -encoding UTF-8 -source 17 -target 17 `
    -classpath "$($ProcessingCoreJar.FullName);$ClassDirectory" -d $TestClassDirectory $TestSources
  if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed' }
  & $Java -ea -classpath "$($ProcessingCoreJar.FullName);$ClassDirectory;$TestClassDirectory" `
    processing2hologram.CameraMathTest
  if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
}

if (Test-Path -LiteralPath $LibraryJar) { Remove-Item -LiteralPath $LibraryJar -Force }
& $Jar --create --file $LibraryJar -C $ClassDirectory . -C $ResourceDirectory .
if ($LASTEXITCODE -ne 0) { throw 'JAR packaging failed' }

Copy-Item -LiteralPath (Join-Path $ProjectRoot 'library.properties') -Destination $DistributionRoot -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'README.md') -Destination $DistributionRoot -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'LICENSE') -Destination $DistributionRoot -Force
Copy-Item -Path (Join-Path $ProjectRoot 'examples\*') -Destination $DistributionExamples -Recurse -Force

if ($RunGraphicsTest) {
  if ($SkipTests) { throw '-RunGraphicsTest cannot be combined with -SkipTests' }
  & $Java -classpath "$TestClassDirectory;$LibraryJar;$ProcessingCoreDirectory\*" `
    processing2hologram.OfflineRenderSmokeTest
  if ($LASTEXITCODE -ne 0) { throw 'Offline Processing OpenGL test failed' }
}

Write-Host "Built $ReleaseKind Processing library: $DistributionRoot"
