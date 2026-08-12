cmake_minimum_required(VERSION 3.20)
project(processing2hologram_native LANGUAGES CXX)

set(PROCESSING_JAVA_HOME "" CACHE PATH "JDK bundled with Processing")
if(NOT PROCESSING_JAVA_HOME)
  message(FATAL_ERROR "Set PROCESSING_JAVA_HOME to a JDK directory")
endif()

add_library(processing2hologram SHARED processing2hologram.cpp)
target_compile_features(processing2hologram PRIVATE cxx_std_20)
target_include_directories(processing2hologram PRIVATE
  "${PROCESSING_JAVA_HOME}/include"
  "${PROCESSING_JAVA_HOME}/include/win32"
)
target_compile_definitions(processing2hologram PRIVATE UNICODE _UNICODE)
target_link_libraries(processing2hologram PRIVATE user32 opengl32)

if(MSVC)
  target_compile_options(processing2hologram PRIVATE /W4 /permissive- /EHsc)
  target_link_options(processing2hologram PRIVATE "/MAP:${CMAKE_CURRENT_BINARY_DIR}/processing2hologram.map")
endif()
