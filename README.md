# SlangCMakeTools

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
list(APPEND CMAKE_MODULE_PATH "/path/to/CMakeSlangTools/cmake")
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

## Configuring compile options

Use `COMPILE_OPTIONS` for flags that belong to one shader and should apply in
every build configuration:

```cmake
add_slang_shader(
    pathtracer_shader
    "${CMAKE_CURRENT_BINARY_DIR}/shaders"
    SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/shaders/pathtracer.slang"
    COMPILE_OPTIONS
        -matrix-layout-row-major
        -Werror
)
```

Options can also be appended after declaring a target:

```cmake
slang_target_compile_options(pathtracer_shader
    PRIVATE
        -matrix-layout-row-major
        -Werror
)
```

`PRIVATE` applies to the target itself, `PUBLIC` applies to the target and its
consumers, and `INTERFACE` applies only to consumers. Module declarations also
accept `PRIVATE_COMPILE_OPTIONS`, `PUBLIC_COMPILE_OPTIONS`, and
`INTERFACE_COMPILE_OPTIONS` directly.

For project-wide flags, `SLANG_FLAGS` is applied to every module and shader
compilation regardless of the build configuration. Configuration-specific
flags use `SLANG_FLAGS_<UPPERCASE_CONFIG>`. The built-in defaults are:

| Variable | Default |
| --- | --- |
| `SLANG_FLAGS` | empty |
| `SLANG_FLAGS_DEBUG` | `-O0 -g` |
| `SLANG_FLAGS_RELEASE` | `-O2 -g0` |
| `SLANG_FLAGS_RELWITHDEBINFO` | `-O2 -g` |
| `SLANG_FLAGS_MINSIZEREL` | `-O1 -g0` |

They can be set in a preset, on the configure command line, or before targets
are declared:

```bash
cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Debug \
    -DSLANG_FLAGS="-matrix-layout-row-major -Werror" \
    -DSLANG_FLAGS_DEBUG="-O0 -g"
```

```cmake
set(SLANG_FLAGS "-matrix-layout-row-major -Werror")
set(SLANG_FLAGS_DEBUG "-O0 -g")
```

Single-config generators discover custom configurations through
`CMAKE_BUILD_TYPE`; multi-config generators use `CMAKE_CONFIGURATION_TYPES`.
The actual selection is performed with `$<CONFIG:...>` generator expressions,
so each configuration receives only its own flags. A custom configuration can
provide a correspondingly named variable:

```cmake
set(CMAKE_BUILD_TYPE Profile)
set(SLANG_FLAGS_PROFILE "-O2 -g")
```

Flag variables are shell-style command strings. Quote the complete value when
passing multiple flags through `-D`.

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
