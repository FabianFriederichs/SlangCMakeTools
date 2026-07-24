# slang-cmake-targets

Target-oriented CMake integration for offline
[Slang](https://shader-slang.org/) shader compilation.

The module treats Slang modules and shader programs as CMake targets with
transitive usage requirements. It provides:

- automatic dependency tracking for imported source files through Slang
  depfiles;
- qualified import-name inference from source layout;
- per-module `SOURCE` or precompiled `BINARY` representation;
- transitive source, binary-module, option, and capability propagation;
- precise custom-command build ordering and incremental rebuilds;
- optional artifact staging helpers.

The project currently targets CMake 3.30 or newer and offline SPIR-V
compilation through `slangc`.

## Using the module

Make `cmake/SlangShaderTools.cmake` available through `CMAKE_MODULE_PATH`, then
include it:

```cmake
list(APPEND CMAKE_MODULE_PATH "/path/to/slang-cmake-targets/cmake")
include(SlangShaderTools)
```

`slangc` is resolved in this order:

1. `SLANGC_EXECUTABLE`;
2. `SLANG_EXECUTABLE`, as provided by Slang's installed CMake package;
3. `slangc` on `PATH`.

## Declaring a module

Source mode is the default and needs no output directory:

```cmake
add_slang_module(
    render_core
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/include/render/core.slang"
    PUBLIC_INCLUDE_DIRS
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/include"
)
```

The source location above infers the qualified import name `render.core`.

To make the representation configurable:

```cmake
set(RENDER_CORE_MODE SOURCE CACHE STRING "SOURCE or BINARY")
set_property(CACHE RENDER_CORE_MODE PROPERTY STRINGS SOURCE BINARY)

add_slang_module(
    render_core
    MODE "${RENDER_CORE_MODE}"
    BINARY_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/modules"
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/include/render/core.slang"
    PUBLIC_INCLUDE_DIRS
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/include"
)
```

In `BINARY` mode this produces:

```text
<binary output directory>/render/core.slang-module
```

`IMPORT_NAME` is available as an explicit override for ambiguous source
layouts.

## Declaring a shader program

```cmake
add_slang_shader(
    pathtracer_shader
    "${CMAKE_CURRENT_BINARY_DIR}/shaders"
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/pathtracer.slang"
    DEPENDENCIES
        render_core
    PROFILE spirv_1_6
    COMPILE_OPTIONS
        -matrix-layout-row-major
)
```

The shader source uses the same import in either module mode:

```slang
import render.core;
```

## Staging a shader

Compiled SPIR-V can be staged beside another target or in a runtime asset
directory:

```cmake
slang_shader_post_build_copy(
    pathtracer_shader
    "${CMAKE_CURRENT_BINARY_DIR}/runtime/shaders"
    my_application
)
```

The shader target also exposes `SLANG_SHADER_OUTPUT_FILE` and related target
properties for project-specific installation or packaging.

See `examples/basic` for a complete declaration.

## Testing

With `slangc` and Ninja available:

```bash
cmake --preset default
cmake --build --preset default
ctest --preset default
```

The integration suite covers all four combinations of a transitive two-module
`SOURCE`/`BINARY` graph. Test source roots, build roots, outputs, and staging
directories contain whitespace, and every case checks dependency invalidation
and a subsequent no-op build.
