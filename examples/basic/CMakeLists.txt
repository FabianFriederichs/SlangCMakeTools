cmake_minimum_required(VERSION 3.30)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    project(slang_cmake_targets_basic_example LANGUAGES NONE)
    list(APPEND CMAKE_MODULE_PATH
        "${CMAKE_CURRENT_SOURCE_DIR}/../../cmake"
    )
endif()

include(SlangShaderTools)

# Fixed project-wide flags are combined with the active configuration's
# SLANG_FLAGS_<UPPERCASE_CONFIG> value for every module and shader compilation.
string(APPEND SLANG_FLAGS " -matrix-layout-row-major")

set(EXAMPLE_CORE_MODE SOURCE CACHE STRING "SOURCE or BINARY")
set_property(CACHE EXAMPLE_CORE_MODE PROPERTY STRINGS SOURCE BINARY)

add_slang_module(
    example_core
    MODE "${EXAMPLE_CORE_MODE}"
    BINARY_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/modules"
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/include/example/core.slang"
    PUBLIC_INCLUDE_DIRS
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/include"
)

add_slang_shader(
    example_shader
    "${CMAKE_CURRENT_BINARY_DIR}/shaders"
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/example.slang"
    DEPENDENCIES
        example_core
    PROFILE spirv_1_5
)

# Target-scoped options are unconditional unless they contain a generator
# expression. PRIVATE affects only this shader; PUBLIC and INTERFACE options on
# module targets can propagate to consumers.
slang_target_compile_options(example_shader
    PRIVATE
        -DEXAMPLE_SHADER=1
)
