cmake_minimum_required(VERSION 3.30)

foreach(required_variable IN ITEMS
    TEST_NAME
    TEST_PROJECT_SOURCE
    TEST_WORK_ROOT
    SLANG_SHADER_TOOLS_DIR
    SLANGC_EXECUTABLE
    NINJA_EXECUTABLE
    CORE_MODE
    BRIDGE_MODE
)
    if(NOT DEFINED ${required_variable})
        message(FATAL_ERROR "${required_variable} must be provided.")
    endif()
endforeach()

set(case_root "${TEST_WORK_ROOT}/${TEST_NAME}")
set(case_source "${case_root}/source tree")
set(case_build "${case_root}/build tree")

file(REMOVE_RECURSE "${case_root}")
file(MAKE_DIRECTORY "${case_source}")
file(COPY "${TEST_PROJECT_SOURCE}/" DESTINATION "${case_source}")

execute_process(
    COMMAND
        "${CMAKE_COMMAND}"
        -S "${case_source}"
        -B "${case_build}"
        -G Ninja
        "-DCMAKE_MAKE_PROGRAM=${NINJA_EXECUTABLE}"
        -DCMAKE_BUILD_TYPE=Debug
        "-DSLANG_SHADER_TOOLS_DIR=${SLANG_SHADER_TOOLS_DIR}"
        "-DSLANGC_EXECUTABLE=${SLANGC_EXECUTABLE}"
        "-DCORE_MODE=${CORE_MODE}"
        "-DBRIDGE_MODE=${BRIDGE_MODE}"
    RESULT_VARIABLE configure_result
    OUTPUT_VARIABLE configure_output
    ERROR_VARIABLE configure_error
)
if(NOT configure_result EQUAL 0)
    message(FATAL_ERROR
        "Configuration failed:\n${configure_output}\n${configure_error}"
    )
endif()

execute_process(
    COMMAND
        "${CMAKE_COMMAND}"
        --build "${case_build}"
        --target integration_consumer
    RESULT_VARIABLE initial_build_result
    OUTPUT_VARIABLE initial_build_output
    ERROR_VARIABLE initial_build_error
)
if(NOT initial_build_result EQUAL 0)
    message(FATAL_ERROR
        "Initial build failed:\n${initial_build_output}\n${initial_build_error}"
    )
endif()

foreach(expected_flag IN ITEMS
    TEST_GLOBAL_FLAG=1
    TEST_DEBUG_FLAG=1
    TEST_TARGET_FLAG=1
)
    if(NOT initial_build_output MATCHES "${expected_flag}")
        message(FATAL_ERROR
            "Expected Slang flag '${expected_flag}' was not used:\n"
            "${initial_build_output}"
        )
    endif()
endforeach()
if(initial_build_output MATCHES "TEST_RELEASE_FLAG=1")
    message(FATAL_ERROR
        "Release-only Slang flags were used by a Debug build:\n"
        "${initial_build_output}"
    )
endif()

file(READ "${case_build}/consumer path.txt" consumer_path)
string(STRIP "${consumer_path}" consumer_path)
foreach(expected_file IN ITEMS
    "${case_build}/compiled shaders/integration_shader.spv"
    "${case_build}/staged shaders/integration_shader.spv"
    "${consumer_path}"
)
    if(NOT EXISTS "${expected_file}")
        message(FATAL_ERROR "Expected output was not created: ${expected_file}")
    endif()
endforeach()

if(CORE_MODE STREQUAL "BINARY"
   AND NOT EXISTS "${case_build}/compiled modules/test/core.slang-module")
    message(FATAL_ERROR "The core binary module was not created.")
endif()
if(BRIDGE_MODE STREQUAL "BINARY"
   AND NOT EXISTS "${case_build}/compiled modules/test/bridge.slang-module")
    message(FATAL_ERROR "The bridge binary module was not created.")
endif()

file(TOUCH "${case_source}/shaders/include/test/detail.slang")
execute_process(
    COMMAND
        "${CMAKE_COMMAND}"
        --build "${case_build}"
        --target integration_consumer
    RESULT_VARIABLE rebuild_result
    OUTPUT_VARIABLE rebuild_output
    ERROR_VARIABLE rebuild_error
)
if(NOT rebuild_result EQUAL 0)
    message(FATAL_ERROR
        "Rebuild failed:\n${rebuild_output}\n${rebuild_error}"
    )
endif()

if(NOT rebuild_output MATCHES "\\[slangc\\] integration_shader")
    message(FATAL_ERROR
        "The dependent shader was not rebuilt after changing a transitive "
        "source:\n${rebuild_output}"
    )
endif()
if(CORE_MODE STREQUAL "BINARY"
   AND NOT rebuild_output MATCHES "\\[slangc\\] module core")
    message(FATAL_ERROR
        "The core binary module was not rebuilt:\n${rebuild_output}"
    )
endif()
if(BRIDGE_MODE STREQUAL "BINARY"
   AND NOT rebuild_output MATCHES "\\[slangc\\] module bridge")
    message(FATAL_ERROR
        "The bridge binary module was not rebuilt:\n${rebuild_output}"
    )
endif()

execute_process(
    COMMAND
        "${CMAKE_COMMAND}"
        --build "${case_build}"
        --target integration_consumer
    RESULT_VARIABLE noop_build_result
    OUTPUT_VARIABLE noop_build_output
    ERROR_VARIABLE noop_build_error
)
if(NOT noop_build_result EQUAL 0)
    message(FATAL_ERROR
        "No-op build failed:\n${noop_build_output}\n${noop_build_error}"
    )
endif()
if(NOT noop_build_output MATCHES "no work to do")
    message(FATAL_ERROR
        "The second rebuild was not a no-op:\n${noop_build_output}"
    )
endif()
