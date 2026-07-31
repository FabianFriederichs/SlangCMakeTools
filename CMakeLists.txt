cmake_minimum_required(VERSION 3.30)

project(slang_cmake_targets VERSION 0.1.0 LANGUAGES NONE)

include(CTest)

option(
    SLANG_CMAKE_TARGETS_BUILD_EXAMPLES
    "Build the slang-cmake-targets examples"
    OFF
)

list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(SlangShaderTools)

if(SLANG_CMAKE_TARGETS_BUILD_EXAMPLES)
    add_subdirectory(examples/basic)
endif()

if(BUILD_TESTING)
    find_program(SLANG_CMAKE_TARGETS_SLANGC_EXECUTABLE NAMES slangc)
    find_program(SLANG_CMAKE_TARGETS_NINJA_EXECUTABLE NAMES ninja)

    if(NOT SLANG_CMAKE_TARGETS_SLANGC_EXECUTABLE)
        message(WARNING "slangc was not found; integration tests are disabled.")
    elseif(NOT SLANG_CMAKE_TARGETS_NINJA_EXECUTABLE)
        message(WARNING "Ninja was not found; integration tests are disabled.")
    else()
        foreach(core_mode IN ITEMS SOURCE BINARY)
            foreach(bridge_mode IN ITEMS SOURCE BINARY)
                string(TOLOWER
                    "${core_mode}_${bridge_mode}"
                    mode_pair
                )
                add_test(
                    NAME integration_${mode_pair}
                    COMMAND
                        "${CMAKE_COMMAND}"
                        "-DTEST_NAME=${mode_pair}"
                        "-DTEST_PROJECT_SOURCE=${CMAKE_CURRENT_SOURCE_DIR}/tests/project"
                        "-DTEST_WORK_ROOT=${CMAKE_CURRENT_BINARY_DIR}/integration tests"
                        "-DSLANG_SHADER_TOOLS_DIR=${CMAKE_CURRENT_SOURCE_DIR}/cmake"
                        "-DSLANGC_EXECUTABLE=${SLANG_CMAKE_TARGETS_SLANGC_EXECUTABLE}"
                        "-DNINJA_EXECUTABLE=${SLANG_CMAKE_TARGETS_NINJA_EXECUTABLE}"
                        "-DCORE_MODE=${core_mode}"
                        "-DBRIDGE_MODE=${bridge_mode}"
                        -P "${CMAKE_CURRENT_SOURCE_DIR}/tests/scripts/run_integration.cmake"
                )
            endforeach()
        endforeach()
    endif()
endif()

install(
    FILES cmake/SlangShaderTools.cmake
    DESTINATION "share/slang-cmake-targets/cmake"
)
