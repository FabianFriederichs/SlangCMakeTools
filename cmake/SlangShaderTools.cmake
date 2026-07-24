include_guard(GLOBAL)
include(CMakeParseArguments)

if(CMAKE_VERSION VERSION_LESS 3.30)
    message(FATAL_ERROR "SlangShaderTools requires CMake 3.30 or newer.")
endif()

# Appends values to a list while preserving order and removing duplicates.
function(_slang_list_append_unique list_variable)
    set(result "${${list_variable}}")
    foreach(value IN LISTS ARGN)
        list(FIND result "${value}" value_index)
        if(value_index EQUAL -1)
            list(APPEND result "${value}")
        endif()
    endforeach()
    set(${list_variable} "${result}" PARENT_SCOPE)
endfunction()

# Appends values to a target property using normal CMake usage scopes.
function(_slang_target_property_insert target_name property_name)
    cmake_parse_arguments(ARG "" "" "PRIVATE;PUBLIC;INTERFACE" ${ARGN})

    get_target_property(private_values ${target_name} ${property_name})
    if(private_values STREQUAL "private_values-NOTFOUND")
        set(private_values "")
    endif()
    get_target_property(interface_values
        ${target_name}
        INTERFACE_${property_name}
    )
    if(interface_values STREQUAL "interface_values-NOTFOUND")
        set(interface_values "")
    endif()

    _slang_list_append_unique(private_values
        ${ARG_PRIVATE}
        ${ARG_PUBLIC}
    )
    _slang_list_append_unique(interface_values
        ${ARG_PUBLIC}
        ${ARG_INTERFACE}
    )

    set_target_properties(${target_name} PROPERTIES
        ${property_name} "${private_values}"
        INTERFACE_${property_name} "${interface_values}"
    )
endfunction()

# Resolves the standalone compiler. SLANGC_EXECUTABLE is the package's native
# override; SLANG_EXECUTABLE is accepted from Slang's installed CMake package.
function(_slang_resolve_compiler output_variable)
    if(SLANGC_EXECUTABLE)
        set(compiler "${SLANGC_EXECUTABLE}")
    elseif(SLANG_EXECUTABLE)
        set(compiler "${SLANG_EXECUTABLE}")
    else()
        find_program(compiler NAMES slangc)
    endif()

    if(NOT compiler)
        message(FATAL_ERROR
            "Could not find slangc. Set SLANGC_EXECUTABLE, provide "
            "SLANG_EXECUTABLE through find_package(slang), or add slangc to PATH."
        )
    endif()

    set(${output_variable} "${compiler}" PARENT_SCOPE)
endfunction()

# -------- CMake Slang Shader Compilation Helper --------
# Helper that adds transitive properties for Slang shader compilation.
function(slang_ensure_properties target)
    get_target_property(_tcp ${target} TRANSITIVE_COMPILE_PROPERTIES)
    if(_tcp STREQUAL "_tcp-NOTFOUND" OR _tcp STREQUAL "")
        set(_tcp "")
    endif()
    _slang_list_append_unique(_tcp
        SLANG_INCLUDE_DIRECTORIES
        SLANG_MODULE_DIRECTORIES
        SLANG_BINARY_MODULE_FILES
        SLANG_DEPENDENCIES
        SLANG_COMPILE_OPTIONS
        SLANG_CAPABILITIES
    )
    set_target_properties(${target}
        PROPERTIES
            TRANSITIVE_COMPILE_PROPERTIES "${_tcp}"
            SLANG_INCLUDE_DIRECTORIES ""
            SLANG_MODULE_DIRECTORIES ""
            SLANG_BINARY_MODULE_FILES ""
            SLANG_DEPENDENCIES ""
            SLANG_COMPILE_OPTIONS ""
            SLANG_CAPABILITIES ""
            INTERFACE_SLANG_INCLUDE_DIRECTORIES ""
            INTERFACE_SLANG_MODULE_DIRECTORIES ""
            INTERFACE_SLANG_BINARY_MODULE_FILES ""
            INTERFACE_SLANG_DEPENDENCIES ""
            INTERFACE_SLANG_COMPILE_OPTIONS ""
            INTERFACE_SLANG_CAPABILITIES ""
    )
endfunction()

# Appends binary module artifacts to a target's SLANG_BINARY_MODULE_FILES
# property. Consumers add these files to their custom-command dependencies.
function(slang_target_binary_module_files target_name)
    set(options "")
    set(one_value_params "")
    set(multi_value_params PRIVATE PUBLIC INTERFACE)
    cmake_parse_arguments(SL "${options}" "${one_value_params}" "${multi_value_params}" ${ARGN})
    _slang_target_property_insert(${target_name}
        SLANG_BINARY_MODULE_FILES
            PRIVATE ${SL_PRIVATE}
            PUBLIC ${SL_PUBLIC}
            INTERFACE ${SL_INTERFACE}
    )
endfunction()

# Appends include directories to a target's SLANG_INCLUDE_DIRECTORIES property.
function(slang_target_include_directories target_name)
    set(options "")
    set(one_value_params "")
    set(multi_value_params PRIVATE PUBLIC INTERFACE)
    cmake_parse_arguments(SL "${options}" "${one_value_params}" "${multi_value_params}" ${ARGN})
    # Append include directories
    _slang_target_property_insert(${target_name}
        SLANG_INCLUDE_DIRECTORIES
            PRIVATE ${SL_PRIVATE}
            PUBLIC ${SL_PUBLIC}
            INTERFACE ${SL_INTERFACE}
    )
endfunction()

# Appends include directories to a target's SLANG_MODULE_DIRECTORIES property.
function(slang_target_module_directories target_name)
    set(options "")
    set(one_value_params "")
    set(multi_value_params PRIVATE PUBLIC INTERFACE)
    cmake_parse_arguments(SL "${options}" "${one_value_params}" "${multi_value_params}" ${ARGN})
    # Append include directories
    _slang_target_property_insert(${target_name}
        SLANG_MODULE_DIRECTORIES
            PRIVATE ${SL_PRIVATE}
            PUBLIC ${SL_PUBLIC}
            INTERFACE ${SL_INTERFACE}
    )
endfunction()

# Adds Slang usage dependencies to an INTERFACE target.
#
# PUBLIC and INTERFACE dependencies are added to the CMake link interface so their
# usage requirements propagate normally. PRIVATE dependencies cannot be represented
# by target_link_libraries() on an INTERFACE library, so they are recorded only in
# the target-local Slang property. Build ordering for the custom compilation command
# is established separately with slang_add_build_dependencies().
function(slang_target_link_dependencies target_name)
    set(options "")
    set(one_value_params "")
    set(multi_value_params PRIVATE PUBLIC INTERFACE)
    cmake_parse_arguments(SL "${options}" "${one_value_params}" "${multi_value_params}" ${ARGN})
    foreach(dependency IN LISTS SL_PRIVATE SL_PUBLIC SL_INTERFACE)
        if(NOT TARGET ${dependency})
            message(FATAL_ERROR
                "slang_target_link_dependencies(${target_name} ...): "
                "'${dependency}' is not a CMake target."
            )
        endif()
    endforeach()

    # Slang targets are INTERFACE libraries, so only their public interface can
    # participate in CMake's link-usage graph.
    target_link_libraries(${target_name}
        INTERFACE
            ${SL_INTERFACE} ${SL_PUBLIC}
    )

    # Record the same scopes in the Slang dependency properties. This keeps the
    # semantic dependency graph available to Slang-specific helper functions.
    _slang_target_property_insert(${target_name}
        SLANG_DEPENDENCIES
            PRIVATE ${SL_PRIVATE}
            PUBLIC ${SL_PUBLIC}
            INTERFACE ${SL_INTERFACE}
    )
endfunction()

# Adds build-order dependencies to the custom target that owns a Slang compiler
# invocation. This is deliberately separate from target_link_libraries(): link
# usage requirements do not make a custom command wait for another custom target.
function(slang_add_build_dependencies build_target)
    foreach(dependency IN LISTS ARGN)
        if(NOT TARGET ${dependency})
            message(FATAL_ERROR
                "slang_add_build_dependencies(${build_target} ...): "
                "'${dependency}' is not a CMake target."
            )
        endif()
    endforeach()

    if(ARGN)
        add_dependencies(${build_target} ${ARGN})
    endif()
endfunction()

# Collects the binary artifacts exported by a set of Slang module targets,
# including artifacts propagated through their public/interface dependencies.
function(slang_collect_binary_module_files output_variable)
    set(pending_dependencies ${ARGN})
    set(visited_dependencies "")
    set(binary_module_files "")

    while(pending_dependencies)
        list(POP_FRONT pending_dependencies dependency)
        list(FIND visited_dependencies "${dependency}" dependency_index)
        if(NOT dependency_index EQUAL -1)
            continue()
        endif()
        list(APPEND visited_dependencies "${dependency}")

        if(NOT TARGET ${dependency})
            message(FATAL_ERROR
                "slang_collect_binary_module_files: '${dependency}' is not a CMake target."
            )
        endif()

        get_target_property(dependency_binary_files
            ${dependency}
            INTERFACE_SLANG_BINARY_MODULE_FILES
        )
        if(dependency_binary_files
           AND NOT dependency_binary_files STREQUAL "dependency_binary_files-NOTFOUND")
            list(APPEND binary_module_files ${dependency_binary_files})
        endif()

        get_target_property(transitive_dependencies
            ${dependency}
            INTERFACE_SLANG_DEPENDENCIES
        )
        if(transitive_dependencies
           AND NOT transitive_dependencies STREQUAL "transitive_dependencies-NOTFOUND")
            list(APPEND pending_dependencies ${transitive_dependencies})
        endif()
    endwhile()

    if(binary_module_files)
        list(REMOVE_DUPLICATES binary_module_files)
    endif()
    set(${output_variable} "${binary_module_files}" PARENT_SCOPE)
endfunction()

# Appends compile options to a target's SLANG_COMPILE_OPTIONS property.
function(slang_target_compile_options target_name)
    set(options "")
    set(one_value_params "")
    set(multi_value_params PRIVATE PUBLIC INTERFACE)
    cmake_parse_arguments(SL "${options}" "${one_value_params}" "${multi_value_params}" ${ARGN})
    # Append compile options
    _slang_target_property_insert(${target_name}
        SLANG_COMPILE_OPTIONS
            PRIVATE ${SL_PRIVATE}
            PUBLIC ${SL_PUBLIC}
            INTERFACE ${SL_INTERFACE}
    )
endfunction()

# Appends capabilities to a target's SLANG_CAPABILITIES property.
function(slang_target_capabilities target_name)
    set(options "")
    set(one_value_params "")
    set(multi_value_params PRIVATE PUBLIC INTERFACE)
    cmake_parse_arguments(SL "${options}" "${one_value_params}" "${multi_value_params}" ${ARGN})
    # Append capabilities
    _slang_target_property_insert(${target_name}
        SLANG_CAPABILITIES
            PRIVATE ${SL_PRIVATE}
            PUBLIC ${SL_PUBLIC}
            INTERFACE ${SL_INTERFACE}
    )
endfunction()

# Infers a qualified Slang import name from a source file and its search roots.
# For example, <root>/example/core.slang becomes example.core.
# Generator-expression roots cannot be evaluated while
# configuring and are therefore ignored.
function(slang_infer_import_name output_variable source_file)
    get_filename_component(source_file_abs
        "${source_file}"
        ABSOLUTE
        BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
    )
    cmake_path(NORMAL_PATH source_file_abs)

    set(import_name_candidates "")
    foreach(search_root IN LISTS ARGN)
        if(search_root MATCHES "\\$<")
            continue()
        endif()

        get_filename_component(search_root_abs
            "${search_root}"
            ABSOLUTE
            BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}"
        )
        cmake_path(NORMAL_PATH search_root_abs)
        file(RELATIVE_PATH relative_source_path
            "${search_root_abs}"
            "${source_file_abs}"
        )
        string(REPLACE "\\" "/" relative_source_path "${relative_source_path}")

        if(IS_ABSOLUTE "${relative_source_path}"
           OR relative_source_path STREQUAL ".."
           OR relative_source_path MATCHES "^\\.\\./")
            continue()
        endif()

        string(REGEX REPLACE "\\.[^./]+$" "" import_path "${relative_source_path}")
        string(REPLACE "/" "." import_name_candidate "${import_path}")
        list(APPEND import_name_candidates "${import_name_candidate}")
    endforeach()

    if(import_name_candidates)
        list(REMOVE_DUPLICATES import_name_candidates)
    endif()
    list(LENGTH import_name_candidates import_name_candidate_count)

    if(import_name_candidate_count EQUAL 0)
        message(FATAL_ERROR
            "Could not infer a Slang import name for '${source_file}'. "
            "Declare an include/module directory containing the source, or "
            "provide IMPORT_NAME explicitly."
        )
    elseif(import_name_candidate_count GREATER 1)
        list(JOIN import_name_candidates "', '" formatted_import_names)
        message(FATAL_ERROR
            "The Slang import name for '${source_file}' is ambiguous. "
            "The declared search roots produce '${formatted_import_names}'. "
            "Provide IMPORT_NAME explicitly."
        )
    endif()

    list(GET import_name_candidates 0 inferred_import_name)
    set(${output_variable} "${inferred_import_name}" PARENT_SCOPE)
endfunction()

# Declares an importable Slang module and selects its representation.
#
# SOURCE mode exports its source search paths and does not create a compiled
# artifact. BINARY mode compiles the module to a qualified .slang-module path,
# exports the binary search root, and exposes the artifact to consumers.
# --------------------------------------------------------
# Usage:
#   add_slang_module(
#     <target_name>
#     SOURCES <files...>                            # REQUIRED: source files forming the module
#     [IMPORT_NAME <qualified.name>]                # Optional override; inferred from the primary source and its search root
#     [MODE SOURCE|BINARY]                          # Optional; defaults to SOURCE
#     [BINARY_OUTPUT_DIR <dir>]                     # Required only in BINARY mode
#     [ADDITIONAL_FILE_DEPENDENCIES <files...>]     # Non-Slang inputs not discoverable by slangc
#     [MODULE_NAME <name>]                          # Optional; defaults to first source file name (without extension)
#     [ROOT_OUTPUT_DIR <dir>]                       # Optional; base for reported relative binary paths
#     --------------------------------------------
#     [PUBLIC_INCLUDE_DIRS <dirs...>]               # Include search paths (-I ...), used by consumers and for this build
#     [PRIVATE_INCLUDE_DIRS <dirs...>]              # Include search paths (-I ...), used only by this build
#     [INTERFACE_INCLUDE_DIRS <dirs...>]            # Include search paths (-I ...), used by consumers only
#     --------------------------------------------
#     [PUBLIC_MODULE_DIRS <dirs...>]                # Module search paths (-I ...), used by consumers and for this build
#     [PRIVATE_MODULE_DIRS <dirs...>]               # Module search paths (-I ...), used only by this build
#     [INTERFACE_MODULE_DIRS <dirs...>]             # Module search paths (-I ...), used by consumers only
#     --------------------------------------------
#     [PUBLIC_DEPENDENCIES <targets...>]            # Other CMake targets this module target depends on
#     [PRIVATE_DEPENDENCIES <targets...>]           # Other CMake targets this module target depends on
#     [INTERFACE_DEPENDENCIES <targets...>]         # Other CMake targets this module target depends on
#     --------------------------------------------
#     [PRIVATE_COMPILE_OPTIONS <opts...>]           # Extra slangc options
#     [PUBLIC_COMPILE_OPTIONS <opts...>]            # Extra slangc options
#     [INTERFACE_COMPILE_OPTIONS <opts...>]         # Extra slangc options
#     --------------------------------------------
#     [PRIVATE_CAPABILITIES <caps...>]              # Extra -capability <cap> ..., usually you want at least SPV_KHR_vulkan_memory_model
#     [PUBLIC_CAPABILITIES <caps...>]               # Extra -capability <cap> ..., usually you want at least SPV_KHR_vulkan_memory_model
#     [INTERFACE_CAPABILITIES <caps...>]            # Extra -capability <cap> ..., usually you want at least SPV_KHR_vulkan_memory_model
#   )
#
# Both modes expose the selected representation through the same transitive
# usage properties, so consumers do not need to know the module mode.
#
# BINARY targets additionally expose SLANG_MODULE_OUTPUT_ROOT,
# SLANG_MODULE_OUTPUT_DIR, SLANG_MODULE_OUTPUT_FILE, their relative variants,
# and a SLANG_BUILD_TARGET_NAME. SOURCE targets have no artifact properties.
#
# Example: select a representation once at the module declaration.
#
#   set(MY_RENDER_MODULE_MODE SOURCE CACHE STRING
#       "Representation used for the my.render Slang module (SOURCE or BINARY)"
#   )
#   set_property(CACHE MY_RENDER_MODULE_MODE PROPERTY STRINGS SOURCE BINARY)
#
#   add_slang_module(
#       my_render_module
#       MODE "${MY_RENDER_MODULE_MODE}"
#       BINARY_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/modules"
#       SOURCES
#           "${CMAKE_CURRENT_SOURCE_DIR}/include/my/render.slang"
#       PUBLIC_INCLUDE_DIRS
#           "${CMAKE_CURRENT_SOURCE_DIR}/include"
#   )
#
# The declaration above infers `my.render` from the source path relative to the
# public include root:
#
#   <include root>/my/render.slang -> import my.render
#
# In SOURCE mode, slangc receives the include root and resolves that import to
# the .slang source. In BINARY mode, CMake emits:
#
#   <binary output root>/my/render.slang-module
#
# and exports the binary output root as a module search path. IMPORT_NAME remains
# available as an override when multiple search roots make inference ambiguous:
#
#   IMPORT_NAME my.render
#
# Consumers are independent of that choice:
#
#   add_slang_shader(
#       my_concrete_shader
#       "${CMAKE_CURRENT_BINARY_DIR}"
#       SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/shader.slang"
#       DEPENDENCIES my_render_module
#   )
#
# The shader source uses the same import in both modes:
#
#   import my.render;
#
# Keep the default SOURCE mode or select the precompiled representation when
# configuring the build:
#
#   cmake --preset default_debug -DMY_RENDER_MODULE_MODE=BINARY
#
# A source-only module can omit both MODE and BINARY_OUTPUT_DIR:
#
#   add_slang_module(
#       my_source_module
#       SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/include/my/source_module.slang"
#       PUBLIC_INCLUDE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/include"
#   )
function(add_slang_module target_name)
    set(options "")
    set(one_value_params
        IMPORT_NAME
        MODE
        BINARY_OUTPUT_DIR
        MODULE_NAME
        ROOT_OUTPUT_DIR
    )
    set(multi_value_params
        SOURCES
        ADDITIONAL_FILE_DEPENDENCIES
        PUBLIC_INCLUDE_DIRS     PRIVATE_INCLUDE_DIRS     INTERFACE_INCLUDE_DIRS
        PUBLIC_MODULE_DIRS      PRIVATE_MODULE_DIRS      INTERFACE_MODULE_DIRS
        PUBLIC_DEPENDENCIES     PRIVATE_DEPENDENCIES     INTERFACE_DEPENDENCIES
        PUBLIC_COMPILE_OPTIONS  PRIVATE_COMPILE_OPTIONS  INTERFACE_COMPILE_OPTIONS
        PUBLIC_CAPABILITIES     PRIVATE_CAPABILITIES     INTERFACE_CAPABILITIES
    )
    cmake_parse_arguments(PARSE_ARGV 1 MOD
        "${options}"
        "${one_value_params}"
        "${multi_value_params}"
    )

    # Accept the former positional output directory for compatibility. New
    # declarations should use BINARY_OUTPUT_DIR so SOURCE mode can omit it.
    if(MOD_UNPARSED_ARGUMENTS)
        list(LENGTH MOD_UNPARSED_ARGUMENTS unparsed_argument_count)
        if(unparsed_argument_count EQUAL 1 AND NOT MOD_BINARY_OUTPUT_DIR)
            list(GET MOD_UNPARSED_ARGUMENTS 0 MOD_BINARY_OUTPUT_DIR)
        else()
            message(FATAL_ERROR
                "add_slang_module(${target_name} ...): unexpected arguments: "
                "${MOD_UNPARSED_ARGUMENTS}"
            )
        endif()
    endif()

    if(NOT MOD_SOURCES)
        message(FATAL_ERROR
            "add_slang_module(${target_name} ...): SOURCES must be provided and non-empty."
        )
    endif()
    if(NOT MOD_MODE)
        set(MOD_MODE SOURCE)
    endif()
    string(TOUPPER "${MOD_MODE}" MOD_MODE)
    if(NOT MOD_MODE STREQUAL "SOURCE" AND NOT MOD_MODE STREQUAL "BINARY")
        message(FATAL_ERROR
            "add_slang_module(${target_name} ...): MODE must be SOURCE or BINARY, "
            "not '${MOD_MODE}'."
        )
    endif()
    if(MOD_MODE STREQUAL "BINARY" AND NOT MOD_BINARY_OUTPUT_DIR)
        message(FATAL_ERROR
            "add_slang_module(${target_name} ...): BINARY_OUTPUT_DIR must be "
            "provided when MODE is BINARY."
        )
    endif()

    if(NOT MOD_MODULE_NAME)
        list(GET MOD_SOURCES 0 first_source)
        get_filename_component(MOD_MODULE_NAME "${first_source}" NAME_WE)
    endif()
    if(NOT MOD_IMPORT_NAME)
        list(GET MOD_SOURCES 0 first_source)
        slang_infer_import_name(
            MOD_IMPORT_NAME
            "${first_source}"
            ${MOD_PUBLIC_INCLUDE_DIRS}
            ${MOD_PRIVATE_INCLUDE_DIRS}
            ${MOD_INTERFACE_INCLUDE_DIRS}
            ${MOD_PUBLIC_MODULE_DIRS}
            ${MOD_PRIVATE_MODULE_DIRS}
            ${MOD_INTERFACE_MODULE_DIRS}
        )
    endif()

    add_library(${target_name} INTERFACE)
    slang_ensure_properties(${target_name})
    set_target_properties(${target_name} PROPERTIES
        SLANG_MODULE_MODE "${MOD_MODE}"
        SLANG_MODULE_IMPORT_NAME "${MOD_IMPORT_NAME}"
    )

    # Imported modules remain necessary when a source module is compiled by its
    # consumer and when a binary module is linked into a final program. Therefore
    # all module dependencies participate in the exported usage graph. PUBLIC
    # dependencies retain their public scope; PRIVATE dependencies become
    # link-only implementation requirements of the selected representation.
    slang_target_link_dependencies(${target_name}
        PUBLIC ${MOD_PUBLIC_DEPENDENCIES}
        INTERFACE
            ${MOD_PRIVATE_DEPENDENCIES}
            ${MOD_INTERFACE_DEPENDENCIES}
    )

    if(MOD_MODE STREQUAL "SOURCE")
        # Source modules behave like header-only libraries: consumers perform the
        # compilation, so every directory, option, and capability needed to compile
        # the module must be part of its interface.
        slang_target_include_directories(${target_name}
            INTERFACE
                ${MOD_PUBLIC_INCLUDE_DIRS}
                ${MOD_PRIVATE_INCLUDE_DIRS}
                ${MOD_INTERFACE_INCLUDE_DIRS}
        )
        slang_target_module_directories(${target_name}
            INTERFACE
                ${MOD_PUBLIC_MODULE_DIRS}
                ${MOD_PRIVATE_MODULE_DIRS}
                ${MOD_INTERFACE_MODULE_DIRS}
        )
        slang_target_compile_options(${target_name}
            INTERFACE
                ${MOD_PUBLIC_COMPILE_OPTIONS}
                ${MOD_PRIVATE_COMPILE_OPTIONS}
                ${MOD_INTERFACE_COMPILE_OPTIONS}
        )
        slang_target_capabilities(${target_name}
            INTERFACE
                ${MOD_PUBLIC_CAPABILITIES}
                ${MOD_PRIVATE_CAPABILITIES}
                ${MOD_INTERFACE_CAPABILITIES}
        )
    else()
        # Binary consumers receive the binary module root, not this module's
        # source directories. Explicit INTERFACE directories remain available for
        # additional consumer-side inputs.
        slang_target_include_directories(${target_name}
            PRIVATE
                ${MOD_PUBLIC_INCLUDE_DIRS}
                ${MOD_PRIVATE_INCLUDE_DIRS}
            INTERFACE ${MOD_INTERFACE_INCLUDE_DIRS}
        )
        slang_target_module_directories(${target_name}
            PRIVATE ${MOD_PRIVATE_MODULE_DIRS}
            PUBLIC ${MOD_PUBLIC_MODULE_DIRS}
            INTERFACE
                ${MOD_INTERFACE_MODULE_DIRS}
                "${MOD_BINARY_OUTPUT_DIR}"
        )
        slang_target_compile_options(${target_name}
            PUBLIC ${MOD_PUBLIC_COMPILE_OPTIONS}
            PRIVATE ${MOD_PRIVATE_COMPILE_OPTIONS}
            INTERFACE ${MOD_INTERFACE_COMPILE_OPTIONS}
        )
        slang_target_capabilities(${target_name}
            PUBLIC ${MOD_PUBLIC_CAPABILITIES}
            PRIVATE ${MOD_PRIVATE_CAPABILITIES}
            INTERFACE ${MOD_INTERFACE_CAPABILITIES}
        )
    endif()

    slang_collect_binary_module_files(
        mod_compile_binary_dependency_files
        ${MOD_PUBLIC_DEPENDENCIES}
        ${MOD_PRIVATE_DEPENDENCIES}
    )
    slang_collect_binary_module_files(
        mod_interface_binary_dependency_files
        ${MOD_PUBLIC_DEPENDENCIES}
        ${MOD_PRIVATE_DEPENDENCIES}
        ${MOD_INTERFACE_DEPENDENCIES}
    )

    if(MOD_MODE STREQUAL "SOURCE")
        # A source module has no artifact of its own, but it must forward binary
        # artifacts used by its imported modules.
        slang_target_binary_module_files(${target_name}
            INTERFACE ${mod_interface_binary_dependency_files}
        )
        set_target_properties(${target_name} PROPERTIES
            SLANG_ARTIFACT_TYPE "SLANG_SOURCE_MODULE"
        )

        set(${target_name}_MODULE_OUTPUT_ROOT "" PARENT_SCOPE)
        set(${target_name}_MODULE_OUTPUT_DIR "" PARENT_SCOPE)
        set(${target_name}_MODULE_OUTPUT_RDIR "" PARENT_SCOPE)
        set(${target_name}_MODULE_OUTPUT_FILE "" PARENT_SCOPE)
        set(${target_name}_MODULE_OUTPUT_RFILE "" PARENT_SCOPE)
        return()
    endif()

    _slang_resolve_compiler(slangc_executable)

    string(REPLACE "." "/" module_relative_path "${MOD_IMPORT_NAME}")
    set(out_file "${MOD_BINARY_OUTPUT_DIR}/${module_relative_path}.slang-module")
    get_filename_component(module_output_dir "${out_file}" DIRECTORY)
    file(MAKE_DIRECTORY "${module_output_dir}")

    slang_target_binary_module_files(${target_name}
        INTERFACE
            "${out_file}"
            ${mod_interface_binary_dependency_files}
    )

    # Assemble the usage requirements for this binary module compilation.
    # Add include dirs from dependencies (TARGET_PROPERTY on INTERFACE_SLANG_INCLUDE_DIRECTORIES with generator expression from public and private dependencies)
    set(mod_include_dirs "$<$<BOOL:$<TARGET_PROPERTY:${target_name},SLANG_INCLUDE_DIRECTORIES>>:$<JOIN:$<TARGET_PROPERTY:${target_name},SLANG_INCLUDE_DIRECTORIES>,;>>")
    foreach(dep IN LISTS MOD_PUBLIC_DEPENDENCIES MOD_PRIVATE_DEPENDENCIES)
        list(APPEND mod_include_dirs "$<$<BOOL:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_INCLUDE_DIRECTORIES>>:$<JOIN:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_INCLUDE_DIRECTORIES>,;>>")
    endforeach()
    # Remove duplicates
    set(mod_include_dirs "$<REMOVE_DUPLICATES:${mod_include_dirs}>")
    # Add module dirs from dependencies (TARGET_PROPERTY on INTERFACE_SLANG_MODULE_DIRECTORIES with generator expression from public and private dependencies)
    set(mod_module_dirs "$<$<BOOL:$<TARGET_PROPERTY:${target_name},SLANG_MODULE_DIRECTORIES>>:$<JOIN:$<TARGET_PROPERTY:${target_name},SLANG_MODULE_DIRECTORIES>,;>>")
    foreach(dep IN LISTS MOD_PUBLIC_DEPENDENCIES MOD_PRIVATE_DEPENDENCIES)
        list(APPEND mod_module_dirs "$<$<BOOL:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_MODULE_DIRECTORIES>>:$<JOIN:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_MODULE_DIRECTORIES>,;>>")
    endforeach()
    # Remove duplicates
    set(mod_module_dirs "$<REMOVE_DUPLICATES:${mod_module_dirs}>")
    # Add compile options from dependencies (TARGET_PROPERTY on INTERFACE_SLANG_COMPILE_OPTIONS with generator expression from public and private dependencies)
    set(mod_compile_options "$<$<BOOL:$<TARGET_PROPERTY:${target_name},SLANG_COMPILE_OPTIONS>>:$<JOIN:$<TARGET_PROPERTY:${target_name},SLANG_COMPILE_OPTIONS>,;>>")
    foreach(dep IN LISTS MOD_PUBLIC_DEPENDENCIES MOD_PRIVATE_DEPENDENCIES)
        list(APPEND mod_compile_options "$<$<BOOL:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_COMPILE_OPTIONS>>:$<JOIN:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_COMPILE_OPTIONS>,;>>")
    endforeach()
    # Remove duplicates
    set(mod_compile_options "$<REMOVE_DUPLICATES:${mod_compile_options}>")
    # Add capabilities from dependencies (TARGET_PROPERTY on INTERFACE_SLANG_CAPABILITIES with generator expression from public and private dependencies)
    set(mod_capabilities "$<$<BOOL:$<TARGET_PROPERTY:${target_name},SLANG_CAPABILITIES>>:$<JOIN:$<TARGET_PROPERTY:${target_name},SLANG_CAPABILITIES>,;>>")
    foreach(dep IN LISTS MOD_PUBLIC_DEPENDENCIES MOD_PRIVATE_DEPENDENCIES)
        list(APPEND mod_capabilities "$<$<BOOL:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_CAPABILITIES>>:$<JOIN:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_CAPABILITIES>,;>>")
    endforeach()
    # Remove duplicates
    set(mod_capabilities "$<REMOVE_DUPLICATES:${mod_capabilities}>")

    # Slang writes the complete transitive source-import graph here. CMake feeds
    # it to the selected build tool, so imported files do not need to be listed
    # manually in ADDITIONAL_FILE_DEPENDENCIES.
    set(depfile "${out_file}.d")

    # ---- Custom command ----
    add_custom_command(
        OUTPUT "${out_file}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "[slangc] module ${MOD_MODULE_NAME} -> ${out_file}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Sources: ${MOD_SOURCES}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Dependencies: ${MOD_PUBLIC_DEPENDENCIES} ${MOD_PRIVATE_DEPENDENCIES}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Interface Dependencies: ${MOD_PUBLIC_DEPENDENCIES} ${MOD_INTERFACE_DEPENDENCIES}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Include Directories: ${mod_include_dirs}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Module Directories: ${mod_module_dirs}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Compile Options: ${mod_compile_options}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Capabilities: ${mod_capabilities}"
        COMMAND "${slangc_executable}"
            ${MOD_SOURCES}
            -module-name "${MOD_MODULE_NAME}"
            "$<$<BOOL:${mod_include_dirs}>:-I$<JOIN:${mod_include_dirs},;-I>>"
            "$<$<BOOL:${mod_module_dirs}>:-I$<JOIN:${mod_module_dirs},;-I>>"
            "$<$<BOOL:${mod_compile_options}>:$<JOIN:${mod_compile_options},;>>"
            "$<$<BOOL:${mod_capabilities}>:-capability;$<JOIN:${mod_capabilities},;-capability;>>"
            -depfile "${depfile}"
            -o "${out_file}"
        DEPENDS
            ${MOD_SOURCES}
            ${MOD_ADDITIONAL_FILE_DEPENDENCIES}
            ${mod_compile_binary_dependency_files}
            "${slangc_executable}"
        DEPFILE "${depfile}"
        COMMAND_EXPAND_LISTS
        VERBATIM
    )

    add_custom_target(${target_name}_out DEPENDS "${out_file}")

    # Make this compilation wait for dependencies used by this module. Source
    # changes are tracked independently and precisely through the depfile above.
    slang_add_build_dependencies(${target_name}_out
        ${MOD_PUBLIC_DEPENDENCIES}
        ${MOD_PRIVATE_DEPENDENCIES}
    )

    # Building the logical interface target builds its generated artifact.
    add_dependencies(${target_name} ${target_name}_out)

    # ---- Compute output paths: Relative and absolute output dir as well as relative and absolute output file path.
    # The relative paths are relative to ROOT_OUTPUT_DIR if provided, otherwise to CMAKE_CURRENT_BINARY_DIR.
    if(MOD_ROOT_OUTPUT_DIR)
        file(RELATIVE_PATH ${target_name}_MODULE_RDIR
            "${MOD_ROOT_OUTPUT_DIR}"
            "${module_output_dir}"
        )
    else()
        file(RELATIVE_PATH ${target_name}_MODULE_RDIR
            "${CMAKE_CURRENT_BINARY_DIR}"
            "${module_output_dir}"
        )
    endif()
    if(MOD_ROOT_OUTPUT_DIR)
        file(RELATIVE_PATH ${target_name}_MODULE_RFILE "${MOD_ROOT_OUTPUT_DIR}" "${out_file}")
    else()
        file(RELATIVE_PATH ${target_name}_MODULE_RFILE "${CMAKE_CURRENT_BINARY_DIR}" "${out_file}")
    endif()

    target_compile_definitions(${target_name} INTERFACE
        ${target_name}_MODULE_OUTPUT_ROOT="${MOD_BINARY_OUTPUT_DIR}"
        ${target_name}_MODULE_OUTPUT_DIR="${module_output_dir}"
        ${target_name}_MODULE_OUTPUT_RDIR="${${target_name}_MODULE_RDIR}"
        ${target_name}_MODULE_OUTPUT_FILE="${out_file}"
        ${target_name}_MODULE_OUTPUT_RFILE="${${target_name}_MODULE_RFILE}"
    )

    set(${target_name}_MODULE_OUTPUT_ROOT "${MOD_BINARY_OUTPUT_DIR}" PARENT_SCOPE)
    set(${target_name}_MODULE_OUTPUT_DIR "${module_output_dir}" PARENT_SCOPE)
    set(${target_name}_MODULE_OUTPUT_RDIR "${${target_name}_MODULE_RDIR}" PARENT_SCOPE)
    set(${target_name}_MODULE_OUTPUT_FILE "${out_file}" PARENT_SCOPE)
    set(${target_name}_MODULE_OUTPUT_RFILE "${${target_name}_MODULE_RFILE}" PARENT_SCOPE)

    set_target_properties(${target_name} PROPERTIES
        SLANG_MODULE_OUTPUT_ROOT "${MOD_BINARY_OUTPUT_DIR}"
        SLANG_MODULE_OUTPUT_DIR "${module_output_dir}"
        SLANG_MODULE_OUTPUT_RDIR "${${target_name}_MODULE_RDIR}"
        SLANG_MODULE_OUTPUT_FILE "${out_file}"
        SLANG_MODULE_OUTPUT_RFILE "${${target_name}_MODULE_RFILE}"
        SLANG_ARTIFACT_TYPE "SLANG_MODULE"
        SLANG_BUILD_TARGET_NAME "${target_name}_out"
    )
endfunction()

# Compiles a Slang compilation unit into a single SPIR-V module (.spv), or optionally compile a single entry point.
#
# Usage:
#   add_slang_shader(
#     <target_name>                                 # Name of the CMake target to create
#     <output_dir>                                  # Output directory for the compiled shader
#     SOURCES <files...>                            # REQUIRED: source files forming the compilation unit
#     [ROOT_OUTPUT_DIR <dir>]                       # Optional; root dir for compiled shader file (SPIR-V) resolution. A relative path to this dir is stored in the shader target.
#     [INCLUDE_DIRS <dirs...>]                      # Include search paths (-I ...)
#     [MODULE_DIRS <dirs...>]                       # Module search paths (-I ...)
#     [ADDITIONAL_FILE_DEPENDENCIES <files...>]     # Non-Slang inputs not discoverable by slangc
#     [DEPENDENCIES <targets...>]                   # Other CMake targets this shader target depends on
#     [COMPILE_OPTIONS <opts...>]                   # Extra slangc options
#     [CAPABILITIES <caps...>]                      # Extra -capability <cap> ..., usually you want at least SPV_KHR_vulkan_memory_model
#     [PROFILE <profile>]                           # e.g. spirv_1_5, spirv_1_6
#     [ENTRY_POINT <name>]                          # If set: compile only this entry point
#   )
#
# Targets created by this function use custom properties to configure include dirs, module dirs, dependencies, compile options, and capabilities for slangc:
# - SLANG_INCLUDE_DIRECTORIES : Include directories for slangc (-I ...)
# - SLANG_MODULE_DIRECTORIES  : Module search directories for slangc (-I ...)
# - SLANG_DEPENDENCIES        : Other CMake targets this target depends on
# - SLANG_COMPILE_OPTIONS     : Extra compile options for slangc
# - SLANG_CAPABILITIES        : Extra capabilities for slangc (-capability ...)
# The slang_target_* functions can be used to append to these properties.
#
# Targets created by this function are also attached properties to infer the output directory, output file path, and binary type (module vs shader) for use by consuming targets and post-build copy commands:
# - SLANG_SHADER_OUTPUT_DIR   : Absolute path to the output directory for the compiled shader
# - SLANG_SHADER_OUTPUT_RDIR : Output directory relative to ROOT_OUTPUT_DIR if provided, otherwise relative to CMAKE_CURRENT_BINARY_DIR
# - SLANG_SHADER_OUTPUT_FILE  : Absolute path to the compiled shader file (SPIR-V)
# - SLANG_SHADER_OUTPUT_RFILE : Compiled shader file path relative to ROOT_OUTPUT_DIR if provided, otherwise relative to CMAKE_CURRENT_BINARY_DIR
# - SLANG_ARTIFACT_TYPE : Set to "SLANG_SHADER_SPIRV" to identify this target as a slang shader target for use by consuming targets and post-build copy commands.
function(add_slang_shader target_name output_dir)
    set(options "")
    set(one_value_params PROFILE ENTRY_POINT ROOT_OUTPUT_DIR)
    set(multi_value_params SOURCES INCLUDE_DIRS MODULE_DIRS COMPILE_OPTIONS CAPABILITIES ADDITIONAL_FILE_DEPENDENCIES DEPENDENCIES)
    cmake_parse_arguments(SH "${options}" "${one_value_params}" "${multi_value_params}" ${ARGN})

    # ---- Validate arguments ----
    if(NOT SH_SOURCES)
        message(FATAL_ERROR "add_slang_shader(${target_name} ...): SOURCES must be provided and non-empty.")
    endif()

    _slang_resolve_compiler(slangc_executable)

    file(MAKE_DIRECTORY "${output_dir}")

    # ---- Output file naming ----
    if(SH_ENTRY_POINT)
        set(out_file "${output_dir}/${target_name}.${SH_ENTRY_POINT}.spv")
    else()
        set(out_file "${output_dir}/${target_name}.spv")
    endif()

    # ---- Profile ----
    if(SH_PROFILE)
        set(profile "${SH_PROFILE}")
    else()
        set(profile "spirv_1_5")
    endif()

    # ---- Entry point ----
    set(entry_point_options "")
    if(SH_ENTRY_POINT)
        list(APPEND entry_point_options "-entry" "${SH_ENTRY_POINT}")
    endif()

    # --- Interface Target for resolving dependencies ---
    # Add interface library to link against from other targets.
    add_library(${target_name} INTERFACE)
    slang_ensure_properties(${target_name})

    # ---- Handle Dependencies ----
    # Shader dependencies are private usage requirements: they configure this
    # compilation but do not leak through the shader target to host consumers.
    slang_target_link_dependencies(${target_name}
        PRIVATE ${SH_DEPENDENCIES}
    )
    slang_collect_binary_module_files(
        sh_binary_module_files
        ${SH_DEPENDENCIES}
    )

    # ---- Compile include dirs ----
    # Include dirs from this shader
    slang_target_include_directories(${target_name}
        PRIVATE   ${SH_INCLUDE_DIRS}
    )
    # Add include dirs from dependencies (TARGET_PROPERTY on INTERFACE_SLANG_INCLUDE_DIRECTORIES with generator expression from public and private dependencies)
    set(sh_include_dirs "$<$<BOOL:$<TARGET_PROPERTY:${target_name},SLANG_INCLUDE_DIRECTORIES>>:$<JOIN:$<TARGET_PROPERTY:${target_name},SLANG_INCLUDE_DIRECTORIES>,;>>")
    foreach(dep IN LISTS SH_DEPENDENCIES)
        list(APPEND sh_include_dirs "$<$<BOOL:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_INCLUDE_DIRECTORIES>>:$<JOIN:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_INCLUDE_DIRECTORIES>,;>>")
    endforeach()
    # Remove duplicates
    set(sh_include_dirs "$<REMOVE_DUPLICATES:${sh_include_dirs}>")
    # ---- Compile module dirs ----
    # Module dirs from this shader
    slang_target_module_directories(${target_name}
        PRIVATE   ${SH_MODULE_DIRS}
    )
    # Add module dirs from dependencies (TARGET_PROPERTY on INTERFACE_SLANG_MODULE_DIRECTORIES with generator expression from public and private dependencies)
    set(sh_module_dirs "$<$<BOOL:$<TARGET_PROPERTY:${target_name},SLANG_MODULE_DIRECTORIES>>:$<JOIN:$<TARGET_PROPERTY:${target_name},SLANG_MODULE_DIRECTORIES>,;>>")
    foreach(dep IN LISTS SH_DEPENDENCIES)
        list(APPEND sh_module_dirs "$<$<BOOL:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_MODULE_DIRECTORIES>>:$<JOIN:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_MODULE_DIRECTORIES>,;>>")
    endforeach()
    # Remove duplicates
    set(sh_module_dirs "$<REMOVE_DUPLICATES:${sh_module_dirs}>")
    # ---- Compile options ----
    # Compile options from this shader
    slang_target_compile_options(${target_name}
        PRIVATE   ${SH_COMPILE_OPTIONS}
    )
    # Add compile options from dependencies (TARGET_PROPERTY on INTERFACE_SLANG_COMPILE_OPTIONS with generator expression from public and private dependencies)
    set(sh_compile_options "$<$<BOOL:$<TARGET_PROPERTY:${target_name},SLANG_COMPILE_OPTIONS>>:$<JOIN:$<TARGET_PROPERTY:${target_name},SLANG_COMPILE_OPTIONS>,;>>")
    foreach(dep IN LISTS SH_DEPENDENCIES)
        list(APPEND sh_compile_options "$<$<BOOL:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_COMPILE_OPTIONS>>:$<JOIN:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_COMPILE_OPTIONS>,;>>")
    endforeach()
    # Remove duplicates
    set(sh_compile_options "$<REMOVE_DUPLICATES:${sh_compile_options}>")
    # ---- Capabilities ----
    # Capabilities from this module
    slang_target_capabilities(${target_name}
        PRIVATE   ${SH_CAPABILITIES}
    )
    # Add capabilities from dependencies (TARGET_PROPERTY on INTERFACE_SLANG_CAPABILITIES with generator expression from public and private dependencies)
    set(sh_capabilities "$<$<BOOL:$<TARGET_PROPERTY:${target_name},SLANG_CAPABILITIES>>:$<JOIN:$<TARGET_PROPERTY:${target_name},SLANG_CAPABILITIES>,;>>")
    foreach(dep IN LISTS SH_DEPENDENCIES)
        list(APPEND sh_capabilities "$<$<BOOL:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_CAPABILITIES>>:$<JOIN:$<TARGET_PROPERTY:${dep},INTERFACE_SLANG_CAPABILITIES>,;>>")
    endforeach()
    # Remove duplicates
    set(sh_capabilities "$<REMOVE_DUPLICATES:${sh_capabilities}>")

    # Slang writes the complete transitive source-import graph here. CMake feeds
    # it to the selected build tool, so imported files do not need to be listed
    # manually in ADDITIONAL_FILE_DEPENDENCIES.
    set(depfile "${out_file}.d")

    # ---- Custom command ----
    add_custom_command(
        OUTPUT "${out_file}"
        # Print target info
        COMMAND ${CMAKE_COMMAND} -E echo
            "[slangc] ${target_name} -> ${out_file}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Sources: ${SH_SOURCES}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Dependencies: ${SH_DEPENDENCIES}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Binary Module Files: ${sh_binary_module_files}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Include Directories: ${sh_include_dirs}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Module Directories: ${sh_module_dirs}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Compile Options: ${sh_compile_options}"
        COMMAND ${CMAKE_COMMAND} -E echo
            "  Capabilities: ${sh_capabilities}"
        COMMAND "${slangc_executable}"
            ${SH_SOURCES}
            -target spirv
            -profile "${profile}"
            -emit-spirv-directly
            -fvk-use-entrypoint-name
            ${entry_point_options}
            "$<$<BOOL:${sh_include_dirs}>:-I$<JOIN:${sh_include_dirs},;-I>>"
            "$<$<BOOL:${sh_module_dirs}>:-I$<JOIN:${sh_module_dirs},;-I>>"
            "$<$<BOOL:${sh_compile_options}>:$<JOIN:${sh_compile_options},;>>"
            "$<$<BOOL:${sh_capabilities}>:-capability;$<JOIN:${sh_capabilities},;-capability;>>"
            -depfile "${depfile}"
            -o "${out_file}"
        DEPENDS
            ${SH_SOURCES}
            ${SH_ADDITIONAL_FILE_DEPENDENCIES}
            ${sh_binary_module_files}
            "${slangc_executable}"
        DEPFILE "${depfile}"
        COMMAND_EXPAND_LISTS
        VERBATIM
    )

    add_custom_target(${target_name}_out DEPENDS "${out_file}")

    # Make this compilation wait for its declared Slang targets. File-level
    # invalidation is handled independently and precisely by the depfile above.
    slang_add_build_dependencies(${target_name}_out ${SH_DEPENDENCIES})

    # Building the logical interface target builds its generated artifact.
    add_dependencies(${target_name} ${target_name}_out)

    # ---- Compute ouput paths: Relative and absolute output dir als well as relative and absolute output file path.
    # The relative paths are relative to ROOT_OUTPUT_DIR if provided, otherwise to CMAKE_CURRENT_BINARY_DIR.
    # Output directories relative to ROOT_OUTPUT_DIR (or CMAKE_CURRENT_BINARY_DIR, if not provided)
    if(SH_ROOT_OUTPUT_DIR)
        file(RELATIVE_PATH ${target_name}_SHADER_RDIR "${SH_ROOT_OUTPUT_DIR}" "${output_dir}")
    else()
        file(RELATIVE_PATH ${target_name}_SHADER_RDIR "${CMAKE_CURRENT_BINARY_DIR}" "${output_dir}")
    endif()
    # Output file relative to ROOT_OUTPUT_DIR (or CMAKE_CURRENT_BINARY_DIR, if not provided)
    if(SH_ROOT_OUTPUT_DIR)
        file(RELATIVE_PATH ${target_name}_SHADER_RFILE "${SH_ROOT_OUTPUT_DIR}" "${out_file}")
    else()
        file(RELATIVE_PATH ${target_name}_SHADER_RFILE "${CMAKE_CURRENT_BINARY_DIR}" "${out_file}")
    endif()

    # Expose output file paths to the caller:
    # --- Absolute and relative output dir + absolute and relative output file path.
    target_compile_definitions(${target_name} INTERFACE
        ${target_name}_SHADER_OUTPUT_DIR="${output_dir}"
        ${target_name}_SHADER_OUTPUT_RDIR="${${target_name}_SHADER_RDIR}"
        ${target_name}_SHADER_OUTPUT_FILE="${out_file}"
        ${target_name}_SHADER_OUTPUT_RFILE="${${target_name}_SHADER_RFILE}"
    )

    # Expose output paths to the caller via PARENT_SCOPE variables as well.
    set(${target_name}_SHADER_OUTPUT_DIR "${output_dir}" PARENT_SCOPE)
    set(${target_name}_SHADER_OUTPUT_RDIR "${${target_name}_SHADER_RDIR}" PARENT_SCOPE)
    set(${target_name}_SHADER_OUTPUT_FILE "${out_file}" PARENT_SCOPE)
    set(${target_name}_SHADER_OUTPUT_RFILE "${${target_name}_SHADER_RFILE}" PARENT_SCOPE)

    # Also set them as target properties for easy access by other targets that depend on this shader.
    set_target_properties(${target_name} PROPERTIES
        SLANG_SHADER_OUTPUT_DIR "${output_dir}"
        SLANG_SHADER_OUTPUT_RDIR "${${target_name}_SHADER_RDIR}"
        SLANG_SHADER_OUTPUT_FILE "${out_file}"
        SLANG_SHADER_OUTPUT_RFILE "${${target_name}_SHADER_RFILE}"
    )

    # Mark the target as slang spirv shader for easy identification by other functions (e.g. for post-build copy).
    # Also attach the name of the actual build target as a property for easy access by post-build copy commands.
    set_target_properties(${target_name} PROPERTIES
        SLANG_ARTIFACT_TYPE "SLANG_SHADER_SPIRV"
        SLANG_BUILD_TARGET_NAME "${target_name}_out"
    )
endfunction()

# Attaches a post-build command to a shader program target that copies the compiled shader module to a specified directory.
#
# Usage:
#   slang_shader_post_build_copy(
#     <shader_target>                   # The shader target whose output should be copied. Must be of type SLANG_SHADER_SPIRV (i.e. created with add_slang_shader).
#     <destination_dir>                 # The directory to which the compiled shader module should be copied after build.
#     <dependent_target>                # The target to which the post-build command will be attached. This is usually the target that consumes the shader target as a dependency.
#     [RELATIVE_TO_TARGET_BINARY_DIR]   # If set, the destination path is interpreted relative to the binary directory of the dependent_target. Otherwise, it is interpreted as an absolute path.
#   )
function(slang_shader_post_build_copy shader_target destination_dir dependent_target)
    set(options "RELATIVE_TO_TARGET_BINARY_DIR")
    set(one_value_params "")
    set(multi_value_params "")
    cmake_parse_arguments(COPY "${options}" "${one_value_params}" "${multi_value_params}" ${ARGN})

    # Sanity checks
    if (NOT TARGET ${shader_target})
        message(FATAL_ERROR "slang_shader_post_build_copy: shader_target '${shader_target}' does not exist.")
    endif()
    if (NOT TARGET ${dependent_target})
        message(FATAL_ERROR "slang_shader_post_build_copy: dependent_target '${dependent_target}' does not exist.")
    endif()
    # Check if shader_target is actually a slang shader target by checking the SLANG_ARTIFACT_TYPE property.
    get_target_property(shader_type ${shader_target} SLANG_ARTIFACT_TYPE)
    if(NOT shader_type)
        message(FATAL_ERROR "slang_shader_post_build_copy: shader_target '${shader_target}' does not have SLANG_ARTIFACT_TYPE property. Make sure to use add_slang_shader to create the shader target.")
    endif()
    if (NOT shader_type STREQUAL "SLANG_SHADER_SPIRV")
        message(FATAL_ERROR "slang_shader_post_build_copy: shader_target '${shader_target}' is not of type 'SLANG_SHADER_SPIRV' (actual type: '${shader_type}'). Make sure to use add_slang_shader to create the shader target.")
    endif()

    # Get the output file property from the shader target
    get_target_property(shader_output_file ${shader_target} SLANG_SHADER_OUTPUT_FILE)
    if(NOT shader_output_file)
        message(FATAL_ERROR "slang_shader_post_build_copy: shader_target '${shader_target}' does not have SLANG_SHADER_OUTPUT_FILE property. Make sure to use add_slang_shader to create the shader target.")
    endif()

    # Compute actual destination directory.
    if(COPY_RELATIVE_TO_TARGET_BINARY_DIR)
        get_target_property(dependent_target_binary_dir ${dependent_target} BINARY_DIR)
        set(actual_destination_dir "${dependent_target_binary_dir}/${destination_dir}")
    else()
        set(actual_destination_dir "${destination_dir}")
    endif()

    # Create destination directory if it doesn't exist
    file(MAKE_DIRECTORY "${actual_destination_dir}")

    # Get build target name for the shader target, so that we can set up a dependency on it for the post-build copy command.
    get_target_property(shader_build_target ${shader_target} SLANG_BUILD_TARGET_NAME)
    if(NOT shader_build_target)
        message(FATAL_ERROR "slang_shader_post_build_copy: shader_target '${shader_target}' does not have SLANG_BUILD_TARGET_NAME property. Make sure to use add_slang_shader to create the shader target.")
    endif()

    # Get absolute path to the output file.
    get_filename_component(shader_output_file_abs "${shader_output_file}" ABSOLUTE)

    # Get shader file name for the copied file.
    get_filename_component(shader_filename "${shader_output_file_abs}" NAME)
    set(copied_shader_file "${actual_destination_dir}/${shader_filename}")
    set(copy_target "${shader_target}_copy_for_${dependent_target}")

    # Custom command that copies the compiled shader file to the destination directory. This command depends on the shader output file and the actual build target for the shader, to ensure it runs after the shader is compiled.
    add_custom_command(
        OUTPUT "${copied_shader_file}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${actual_destination_dir}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${shader_output_file_abs}"
            "${copied_shader_file}"
        DEPENDS
            "${shader_output_file_abs}"
            ${shader_build_target}
        COMMENT "Copying shader '${shader_target}' to '${copied_shader_file}'"
        VERBATIM
    )

    add_custom_target(${copy_target} DEPENDS "${copied_shader_file}")

    add_dependencies(${dependent_target} ${copy_target})
endfunction()

# Attaches a post-build command to the shader module target that copies the compiled shader module to a specified directory.
#
# Usage:
#   slang_module_post_build_copy(
#     <module_target>                   # The module target whose output should be copied. Must be of type SLANG_MODULE (i.e. created with add_slang_module).
#     <destination_dir>                 # The directory to which the compiled shader module should be copied after build.
#     <dependent_target>                # The target to which the post-build command will be attached. This is usually the target that consumes the module target as a dependency.
#     [RELATIVE_TO_TARGET_BINARY_DIR]   # If set, the destination path is interpreted relative to the binary directory of the dependent_target. Otherwise, it is interpreted as an absolute path.
#   )
function(slang_module_post_build_copy module_target destination_dir dependent_target)
    set(options "RELATIVE_TO_TARGET_BINARY_DIR")
    set(one_value_params "")
    set(multi_value_params "")
    cmake_parse_arguments(COPY "${options}" "${one_value_params}" "${multi_value_params}" ${ARGN})

    # Sanity checks
    if (NOT TARGET ${module_target})
        message(FATAL_ERROR "slang_module_post_build_copy: module_target '${module_target}' does not exist.")
    endif()
    if (NOT TARGET ${dependent_target})
        message(FATAL_ERROR "slang_module_post_build_copy: dependent_target '${dependent_target}' does not exist.")
    endif()
    # Check if module_target is actually a slang module target by checking the SLANG_ARTIFACT_TYPE property.
    get_target_property(module_type ${module_target} SLANG_ARTIFACT_TYPE)
    if(NOT module_type)
        message(FATAL_ERROR "slang_module_post_build_copy: module_target '${module_target}' does not have SLANG_ARTIFACT_TYPE property. Make sure to use add_slang_module to create the module target.")
    endif()
    if (NOT module_type STREQUAL "SLANG_MODULE")
        message(FATAL_ERROR "slang_module_post_build_copy: module_target '${module_target}' is not of type 'SLANG_MODULE' (actual type: '${module_type}'). Make sure to use add_slang_module to create the module target.")
    endif()

    # Get the output file property from the module target
    get_target_property(module_output_file ${module_target} SLANG_MODULE_OUTPUT_FILE)
    if(NOT module_output_file)
        message(FATAL_ERROR "slang_module_post_build_copy: module_target '${module_target}' does not have SLANG_MODULE_OUTPUT_FILE property. Make sure to use add_slang_module to create the module target.")
    endif()

    # Compute actual destination directory.
    if(COPY_RELATIVE_TO_TARGET_BINARY_DIR)
        get_target_property(dependent_target_binary_dir ${dependent_target} BINARY_DIR)
        set(actual_destination_dir "${dependent_target_binary_dir}/${destination_dir}")
    else()
        set(actual_destination_dir "${destination_dir}")
    endif()

    # Create destination directory if it doesn't exist
    file(MAKE_DIRECTORY "${actual_destination_dir}")

    # Get build target name for the module target, so that we can set up a dependency on it for the post-build copy command.
    get_target_property(module_build_target ${module_target} SLANG_BUILD_TARGET_NAME)
    if(NOT module_build_target)
        message(FATAL_ERROR "slang_module_post_build_copy: module_target '${module_target}' does not have SLANG_BUILD_TARGET_NAME property. Make sure to use add_slang_module to create the module target.")
    endif()

    # Get absolute path to the output file.
    get_filename_component(module_output_file_abs "${module_output_file}" ABSOLUTE)

    # Get shader file name for the copied file.
    get_filename_component(module_filename "${module_output_file_abs}" NAME)
    set(copied_module_file "${actual_destination_dir}/${module_filename}")
    set(copy_target "${module_target}_copy_for_${dependent_target}")

    # Custom command that copies the compiled module file to the destination directory. This command depends on the module output file and the actual build target for the module, to ensure it runs after the module is compiled.
    add_custom_command(
        OUTPUT "${copied_module_file}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${actual_destination_dir}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${module_output_file_abs}"
            "${copied_module_file}"
        DEPENDS
            "${module_output_file_abs}"
            ${module_build_target}
        COMMENT "Copying module '${module_target}' to '${copied_module_file}'"
        VERBATIM
    )

    add_custom_target(${copy_target} DEPENDS "${copied_module_file}")

    add_dependencies(${dependent_target} ${copy_target})
endfunction()
