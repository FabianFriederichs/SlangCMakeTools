cmake_minimum_required(VERSION 3.30)

project(slang_cmake_targets_integration_test CXX)

foreach(required_variable IN ITEMS
    SLANG_SHADER_TOOLS_DIR
    CORE_MODE
    BRIDGE_MODE
)
    if(NOT DEFINED ${required_variable})
        message(FATAL_ERROR "${required_variable} must be provided.")
    endif()
endforeach()

list(APPEND CMAKE_MODULE_PATH "${SLANG_SHADER_TOOLS_DIR}")
include(SlangShaderTools)

# Exercise fixed global flags, configuration-specific flags, and exclusion of
# flags belonging to an inactive configuration.
set(SLANG_FLAGS "-DTEST_GLOBAL_FLAG=1")
set(SLANG_FLAGS_DEBUG "-DTEST_DEBUG_FLAG=1")
set(SLANG_FLAGS_RELEASE "-DTEST_RELEASE_FLAG=1")

set(module_output_dir "${CMAKE_CURRENT_BINARY_DIR}/compiled modules")

add_slang_module(
    test_core
    MODE "${CORE_MODE}"
    BINARY_OUTPUT_DIR "${module_output_dir}"
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/include/test/core.slang"
    PUBLIC_INCLUDE_DIRS
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/include"
)

add_slang_module(
    test_bridge
    MODE "${BRIDGE_MODE}"
    BINARY_OUTPUT_DIR "${module_output_dir}"
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/include/test/bridge.slang"
    PUBLIC_INCLUDE_DIRS
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/include"
    PUBLIC_DEPENDENCIES
        test_core
)

add_slang_shader(
    integration_shader
    "${CMAKE_CURRENT_BINARY_DIR}/compiled shaders"
    SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/shaders/integration shader.slang"
    DEPENDENCIES
        test_bridge
    COMPILE_OPTIONS
        -DTEST_TARGET_FLAG=1
)

add_executable(integration_consumer main.cpp)
target_link_libraries(integration_consumer PRIVATE integration_shader)
file(GENERATE
    OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/consumer path.txt"
    CONTENT "$<TARGET_FILE:integration_consumer>"
)

slang_shader_post_build_copy(
    integration_shader
    "${CMAKE_CURRENT_BINARY_DIR}/staged shaders"
    integration_consumer
)
