#
# Copyright (C) 2021 Swift Navigation Inc.
# Contact: Swift Navigation <dev@swift-nav.com>
#
# This source is subject to the license found in the file 'LICENSE' which must
# be be distributed together with this source. All other rights reserved.
#
# THIS CODE AND INFORMATION IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND,
# EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A PARTICULAR PURPOSE.
#

#
# A module to create custom targets to format source and header files in a git repo
#
# The function swift_setup_clang_format will create several targets which will
# use clang-format to format source code according to a configuration file. 2 types
# of targets will be created, one for formatting all files in the repository and the
# other for formatting only the files which differ from master. The list of files to
# format is generated by git itself using a GLOB pattern.
#
# The default pattern will include the following file types
#  *.c *.h *.cpp *.cc *.hpp
#
# A project may provide a custom file matching pattern to override the default
#
# swift_setup_clang_format(PATTERNS '*.c')
#
# will format ONLY *.c files. It is possible to provide a path in the pattern
#
# swift_setup_clang_format(PATTERNS 'src/*.c' 'include/*.h')
#
# will format only *.c files under ${PROJECT_SOURCE_DIR}/src and *.h files under
# ${PROJECT_SOURCE_DIR}/include
#
# The created targets have the names
#
# - clang-format-all-${PROJECT_NAME} - formats all files in the repo
# - clang-format-diff-${PROJECT_NAME} - formats only changed files
#
# In addition if the current project is at the top level of the working tree 2 more
# targets will be created
#
# - clang-format-all
# - clang-format-diff
#
# which are aliases for the namespaced targets. If every project in a working
# directory uses this module to create auto-formatting targets there will never be
# a name clash
#
# The parameter SCRIPT can be used to specify a custom formatting command instead
# of calling clang-format directly. This should be executable and will be called
# with a single argument of either 'all' or 'diff' according to the target
#
# clang-format-all-${PROJECT_NAME} will run `<script> all`
# clang-format-diff-${PROJECT_NAME} will run `<script> diff`
#
# If a script is not specified explicitly this function will first search for an
# appropriate script. It must live in ${CMAKE_CURRENT_SOURCE_DIR}/scripts and be
# named either clang-format.sh or clang-format.bash. If found the custom targets
# will run this script with the same parameters as above
#
# If not script is found or specified default formatting commands will be run.
# This function will find an appropriate clang-format program and run it against
# the file list provided by git.
#
# The list of program names can be overriden by passing the CLANG_FORMAT_NAMES
# parameter with a list of names to search for
#
# All commands will be run from the source directory which calls this function.
# It is highly recommended to include this module and call swift_setup_clang_format
# from the top level CMakeLists.txt, using in a subdirectory may not work as
# intended.
#
# In addition this function sets up a cmake option which can be used to control
# whether the targets are created either on the command line or by a super project.
# The option has the name
#
# ${PROJECT_NAME}_ENABLE_CLANG_FORMAT
#
# The default value is ON for top level projects, and OFF for any others.
#
# Running
#
# cmake -D<project>_ENABLE_CLANG_FORMAT=OFF ..
#
# will explicitly disable these targets from the command line at configure time
#

# Helper function to actually create the targets, not to be used outside this file
function(create_clang_format_targets)
  set(argOption "")
  set(argSingle "TOP_LEVEL")
  set(argMulti "ALL_COMMAND" "DIFF_COMMAND")

  cmake_parse_arguments(x "${argOption}" "${argSingle}" "${argMulti}" ${ARGN})

  add_custom_target(clang-format-all-${PROJECT_NAME}
      COMMAND ${x_ALL_COMMAND}
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  )
  add_custom_target(clang-format-diff-${PROJECT_NAME}
      COMMAND ${x_DIFF_COMMAND}
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  )

  # Top level projects will create the targets clang-format-all and
  # clang-format-diff with the same commands as the namespaced targets
  # above. However, cmake doesn't support aliases for non-library targets
  # so we have to create them fully.
  if(x_TOP_LEVEL)
    add_custom_target(clang-format-all
        COMMAND ${x_ALL_COMMAND}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    )
    add_custom_target(clang-format-diff
        COMMAND ${x_DIFF_COMMAND}
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    )
    add_custom_target(clang-format-all-check
        COMMAND git diff --exit-code
        DEPENDS clang-format-all
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    )
    add_custom_target(clang-format-diff-check
        COMMAND git diff --exit-code
        DEPENDS clang-format-diff
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    )
  endif()
endfunction()

macro(early_exit level msg)
  message(${level} "${msg}")
  if(x_REQUIRED)
    message(FATAL_ERROR "clang-format support is REQUIRED for ${PROJECT_NAME}")
  endif()
  return()
endmacro()

# External function to create clang-format-* targets. Call according to the
# documentation in the file header.
function(swift_setup_clang_format)
  set(argOption "REQUIRED")
  set(argSingle "SCRIPT")
  set(argMulti "CLANG_FORMAT_NAMES" "PATTERNS")

  cmake_parse_arguments(x "${argOption}" "${argSingle}" "${argMulti}" ${ARGN})

  if(x_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unparsed arguments ${x_UNPARSED_ARGUMENTS}")
  endif()

  # Global clang-format enable option, influences the default project specific enable option
  option(ENABLE_CLANG_FORMAT "Enable auto-formatting of code using clang-format globally" ON)
  if(NOT ENABLE_CLANG_FORMAT)
    early_exit(STATUS "auto-formatting is disabled globally")
  endif()

  if(${PROJECT_NAME} STREQUAL ${CMAKE_PROJECT_NAME})
    # This is the top level project, ie the CMakeLists.txt which cmake was run
    # on directly, not a submodule/subproject. We can do some special things now.
    # The option to enable clang formatting will be enabled by default only for
    # top level projects. Also the top level project will create an alias target
    # clang-format-all against the project specific target
    set(top_level_project ON)
  else()
    set(top_level_project OFF)
  endif()

  # Create a cmake option to enable formatting of this specific project
  option(${PROJECT_NAME}_ENABLE_CLANG_FORMAT "Enable auto-formatting of code using clang-format for project ${PROJECT_NAME}" ${top_level_project})

  if(NOT ${PROJECT_NAME}_ENABLE_CLANG_FORMAT)
    # Explicitly disabled
    early_exit(STATUS "${PROJECT_NAME} clang-format support is DISABLED")
  endif()

  # If a custom script has been specified always use that by default
  if(x_SCRIPT)
    if(EXISTS ${x_SCRIPT})
      message(STATUS "Initialising clang format targets for ${PROJECT_NAME} using existing script in ${x_SCRIPT}")
      create_clang_format_targets(
          TOP_LEVEL ${top_level_project}
          ALL_COMMAND ${x_SCRIPT} all
          DIFF_COMMAND ${x_SCRIPT} diff
      )
    else()
      message(FATAL_ERROR "Specified clang-format script ${x_SCRIPT} doesn't exist")
    endif()
    return()
  endif()

  # Search for a custom formatting script in some reasonable places
  set(custom_scripts "${CMAKE_CURRENT_SOURCE_DIR}/scripts/clang-format.sh" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/clang-format.bash")

  foreach(script ${custom_scripts})
    if(EXISTS ${script})
      # Found a custom formatting script
      message(STATUS "Initialising clang format target for ${PROJECT_NAME} using existing script in ${script}")
      create_clang_format_targets(
          TOP_LEVEL ${top_level_project}
          ALL_COMMAND ${script} all
          DIFF_COMMAND ${script} diff
      )
      return()
    endif()
  endforeach()

  # Did not find any script to use, generate a default formatting command to process all code files in the repo

  # First try to find clang-format
  if(NOT x_CLANG_FORMAT_NAMES)
    set(x_CLANG_FORMAT_NAMES
        clang-format11 clang-format-11
        clang-format60 clang-format-6.0
        clang-format40 clang-format-4.0
        clang-format39 clang-format-3.9
        clang-format38 clang-format-3.8
        clang-format37 clang-format-3.7
        clang-format36 clang-format-3.6
        clang-format35 clang-format-3.5
        clang-format34 clang-format-3.4
        clang-format
    )
  endif()
  find_program(CLANG_FORMAT NAMES ${x_CLANG_FORMAT_NAMES})

  if("${CLANG_FORMAT}" STREQUAL "CLANG_FORMAT-NOTFOUND")
    # clang-format not found, can't continue
    early_exit(WARNING "Could not find appropriate clang-format, targets disabled")
  endif()

  message(STATUS "Using ${CLANG_FORMAT}")
  set(${PROJECT_NAME}_CLANG_FORMAT ${CLANG_FORMAT} CACHE STRING "Absolute path to clang-format for ${PROJECT_NAME}")

  if(x_PATTERNS)
    set(patterns ${x_PATTERNS})
  else()
    # Format all source and header files in the repo, use a git command to build the file list
    set(patterns '*.[ch]' '*.cpp' '*.cc' '*.hpp')
  endif()

  create_clang_format_targets(
      TOP_LEVEL ${top_level_project}
      ALL_COMMAND git ls-files ${patterns} | xargs ${${PROJECT_NAME}_CLANG_FORMAT} -i
      DIFF_COMMAND git describe --tags --abbrev=0 --always
                   | xargs -I % git diff --diff-filter=ACMRTUXB --name-only --line-prefix=`git rev-parse --show-toplevel`/ % -- ${patterns}
                   | xargs ${${PROJECT_NAME}_CLANG_FORMAT} -i
  )
endfunction()
