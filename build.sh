#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
processing_home="${PROCESSING_HOME:-/Applications/Processing.app}"
skip_tests=false
skip_native=false
run_graphics_test=false
windows_native=""

usage() {
  printf '%s\n' \
    'Usage: ./build.sh [--processing-home PATH] [--windows-native DLL] [--skip-native] [--skip-tests] [--run-graphics-test]' \
    '' \
    'Builds the macOS Processing library with a universal arm64+x86_64 dylib.' \
    'Pass --windows-native to include an existing Windows x64 DLL in a universal JAR.'
}

while (($# > 0)); do
  case "$1" in
    --processing-home)
      if (($# < 2)); then
        printf 'Missing value for --processing-home\n' >&2
        exit 2
      fi
      processing_home="$2"
      shift 2
      ;;
    --windows-native)
      if (($# < 2)); then
        printf 'Missing value for --windows-native\n' >&2
        exit 2
      fi
      windows_native="$2"
      shift 2
      ;;
    --skip-tests)
      skip_tests=true
      shift
      ;;
    --skip-native)
      skip_native=true
      shift
      ;;
    --run-graphics-test)
      run_graphics_test=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$run_graphics_test" == true && "$skip_tests" == true ]]; then
  printf '%s\n' '--run-graphics-test cannot be combined with --skip-tests' >&2
  exit 2
fi
if [[ -n "$windows_native" && ! -f "$windows_native" ]]; then
  printf 'Windows native library was not found: %s\n' "$windows_native" >&2
  exit 1
fi

if [[ -d "$processing_home/Contents/app" ]]; then
  processing_app="$processing_home/Contents/app"
elif [[ -d "$processing_home/app" ]]; then
  processing_app="$processing_home/app"
else
  printf 'Processing app directory was not found below %s\n' "$processing_home" >&2
  exit 1
fi

processing_java="$processing_app/resources/jdk"
processing_core_directory="$processing_app/resources/core/library"
core_jars=("$processing_core_directory"/core-*.jar)
if ((${#core_jars[@]} == 0)) || [[ ! -f "${core_jars[0]}" ]]; then
  printf 'Processing core JAR was not found below %s\n' "$processing_core_directory" >&2
  exit 1
fi
processing_core_jar="${core_jars[0]}"

javac="$processing_java/bin/javac"
java="$processing_java/bin/java"
jar="$processing_java/bin/jar"
for tool in "$javac" "$java" "$jar"; do
  if [[ ! -x "$tool" ]]; then
    printf 'Required Processing JDK tool is missing: %s\n' "$tool" >&2
    exit 1
  fi
done

build_root="$project_root/build"
class_directory="$build_root/classes"
test_class_directory="$build_root/test-classes"
resource_directory="$build_root/resources"
native_build_directory="$build_root/native-macos-universal"
release_kind="macos"
if [[ -n "$windows_native" ]]; then
  release_kind="universal"
fi
distribution_root="$build_root/releases/$release_kind/Processing2Hologram"
distribution_library="$distribution_root/library"
distribution_examples="$distribution_root/examples"
library_jar="$distribution_library/Processing2Hologram.jar"

for directory in \
  "$class_directory" "$test_class_directory" "$resource_directory" "$distribution_root"; do
  if [[ -e "$directory" ]]; then
    rm -rf -- "$directory"
  fi
done
mkdir -p \
  "$class_directory" "$test_class_directory" "$resource_directory" \
  "$distribution_library" "$distribution_examples"

native_output="$native_build_directory/libprocessing2hologram.dylib"
if [[ "$skip_native" == false ]]; then
  mkdir -p "$native_build_directory"
  clang++ -x objective-c++ -arch arm64 -arch x86_64 \
    -std=c++20 -O2 -Wall -Wextra -Wpedantic -dynamiclib \
    -I "$processing_java/include" -I "$processing_java/include/darwin" \
    "$project_root/native/macos/processing2hologram.cpp" \
    -framework AppKit -framework OpenGL -o "$native_output"
fi
if [[ ! -f "$native_output" ]]; then
  printf 'Native macOS library is missing. Run build.sh once without --skip-native.\n' >&2
  exit 1
fi
if ! lipo "$native_output" -verify_arch arm64 x86_64; then
  printf 'Native macOS library is not universal. Rebuild without --skip-native.\n' >&2
  exit 1
fi
native_resource_directory="$resource_directory/native/macos-universal"
mkdir -p "$native_resource_directory"
cp "$native_output" "$native_resource_directory/"
if [[ -n "$windows_native" ]]; then
  windows_resource_directory="$resource_directory/native/windows-amd64"
  mkdir -p "$windows_resource_directory"
  cp "$windows_native" "$windows_resource_directory/processing2hologram.dll"
fi

main_sources=()
while IFS= read -r -d '' source; do
  main_sources+=("$source")
done < <(find "$project_root/src/main/java" -name '*.java' -type f -print0)
"$javac" -encoding UTF-8 -source 17 -target 17 \
  -classpath "$processing_core_jar" -d "$class_directory" "${main_sources[@]}"

if [[ "$skip_tests" == false ]]; then
  test_sources=()
  while IFS= read -r -d '' source; do
    test_sources+=("$source")
  done < <(find "$project_root/src/test/java" -name '*.java' -type f -print0)
  "$javac" -encoding UTF-8 -source 17 -target 17 \
    -classpath "$processing_core_jar:$class_directory" \
    -d "$test_class_directory" "${test_sources[@]}"
  "$java" -ea -classpath "$processing_core_jar:$class_directory:$test_class_directory" \
    processing2hologram.CameraMathTest
fi

"$jar" --create --file "$library_jar" \
  -C "$class_directory" . -C "$resource_directory" .
cp "$project_root/library.properties" "$distribution_root/"
cp "$project_root/README.md" "$distribution_root/"
cp "$project_root/LICENSE" "$distribution_root/"
cp -R "$project_root/examples/." "$distribution_examples/"

if [[ "$run_graphics_test" == true ]]; then
  "$java" -classpath "$test_class_directory:$library_jar:$processing_core_directory/*" \
    processing2hologram.OfflineRenderSmokeTest
fi

printf 'Built %s Processing library: %s\n' "$release_kind" "$distribution_root"
