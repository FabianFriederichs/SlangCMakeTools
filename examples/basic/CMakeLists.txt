cmake_minimum_required(VERSION 3.30)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    project(slang_cmake_targets_basic_example LANGUAGES NONE)
    list(APPEND CMAKE_MODULE_PATH
        "${CMAKE_CURRENT_SOURCE_DIR}/../../cmake"
    )
endif()

include(SlangShaderTools)

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
