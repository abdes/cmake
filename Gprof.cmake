#
# OVERVIEW
#
# There are various technical approaches to implement profiling for any program,
# some emulate an environment, run the program on it and collect data (ex:
# Valgrind), others invoke kernel level system calls to inspect the events from
# a running program (ex: perf or dtrace). With this module, we focus on
# what we call "Code Profiling", which is the technique of introducing code
# during the compilation/linking that helps aggregate details about a running
# program and dumped out to a file during the programs shutdown phase. Currently
# only GCC compilers are supported by Gprof.
#
# To enable any code profiling instrumentation/targets, the cmake option
# "CODE_PROFILING" needs to be set to "ON". Code that is to be profiled needs to
# be setup with the `target_code_profiling` function, without it, later on when
# the profile results come out, it won't be able to report on those library
# and/or executable functions.
#
# USAGE:
#
#   target_code_profiling(<target>)
#
# Call on this function to setup the library and/or executable for profiling.
# Internally the function simply adds some compiler/linker options to the
# target.
#
#   swift_add_gprof(<target>
#     [NAME name]
#     [WORKING_DIRECTORY working_directory]
#     [REPORT_DIRECTORY report_directory]
#     [PROGRAM_ARGS arg1 arg2 ...]
#     [GENERATE_REPORT]
#   )
#
# Call this function to create a new cmake target which invokes the
# executable created by the specified `target` argument. For instance, if there
# was a cmake target called `unit-tests` and I invoked the function as
# `swift_add_gprof(unit-tests)`, it would produce the following cmake
# targets:
#
#   - gprof-unit-tests
#   - do-all-gprof
#
# The first target runs the `unit-tests` target, and generates the profile
# results to the default report directory
#`${CMAKE_BINARY_DIR}/profiling/gprof-reports/unit-tests`. The result consists
# of gmon.* files where numbers in the file name correspond to the process ID
# of the running program. If you see multiple files, that's because the original
# target spawned off child processes. Rerunning this target will mean that any
# prior results will be cleared out.
#
# The second target runs the first target as well as any other target that
# might have called the `swift_add_gprof` function, this is just a handy target
# to have to avoid explicitly running each target individually.
#
# If the `unit-tests` target would depend on another cmake target which you are
# interested in, you would need to call `target_code_profiling` on that target
# to be able to see results for its code.
#
# There are a few options that are available to the function. GENERATE_REPORT is
# a simple flag to make sure that the generated gmon.* reports are translated
# into something which is readable for a user. Normally these reports are
# generated by `gprof` via the following command:
#
#   gprof <executable> <gmon file>
#
# The reason why this is not done by default is because the `executable`
# parameter needs to match the executable that launched process ID specified by
# gmon file. If in our example `unit-tests` spawned off processes that called
# an internal executable, the result folder would contain a number of gmon
# files. One would have to know which gmon file corresponds to the `unit-tests`
# executable and which one corresponds to the internal executable. Running
# `gprof` on an incorrect executable will generate incorrect results and
# will not error out. As such, when one enables GENERATE_REPORT, the function
# will run the `gprof` on each `gmon.*` file, assuming that it was called by
# the `unit-tests` executable, outputting the results to a `gmon.*.txt` file.
#
# The NAME option is there to specify the name used for the new target, this is
# quite useful if you'd like to create multiple profiling targets from a single
# cmake target executable. Continuing on with our `unit-tests` example, if the
# target was a Googletest executable, and we wanted to break the tests cases
# across different suites, we could do something like the following:
#
#   swift_add_gprof(unit-tests
#     NAME suite-1
#     PROGRAM_ARGS --gtest_filter=Suite1.*
#   )
#
#   swift_add_gprof(unit-tests
#     NAME suite-2
#     PROGRAM_ARGS --gtest_filter=Suite2.*
#   )
#
# This would create two targets (not including `do-all-gprof` in this
# list) `gprof-suite-1` and `gprof-suite-2`, each calling the
# `unit-tests` executable with different program arguments.
#
# WORKING_DIRECTORY enables a user to change the execution directory for the tool
# from the default folder `${CMAKE_CURRENT_BINARY_DIR}` to the given argument.
# For instance, if a user wants to utilize files located in a specific folder.
#
# REPORT_DIRECTORY enables a user to change the output directory for the tool
# from the default folder `${CMAKE_BINARY_DIR}/profiling/gprof-reports`.
# Example, using argument `/tmp`, outputs the results to `/tmp`.
#
# NOTES
#
# Be aware that enabling profiling for your targets can have an impact on other
# tools that ingest or work off of the library/executable. For instance if you
# attempt to run code that normally has profiling details on a Valgrind
# environment, it has the possibility of crashing.
#

option(CODE_PROFILING "Builds targets with profiling instrumentation. Currently only works with GCC Compilers" OFF)

find_package(GProf)

if (CODE_PROFILING)
  if (NOT CMAKE_COMPILER_IS_GNUCXX)
    message(WARNING "Gprof is currently only available for GCC compiler")
  endif()
  if (NOT GProf_FOUND)
    message(WARNING "Gprof program is required to generate code profiling report")
  endif()
endif()

function(target_code_profiling target)
  if (NOT TARGET ${target})
    message(FATAL_ERROR "Specified target \"${target}\" does not exist")
  endif()

  if (NOT (CODE_PROFILING AND
           CMAKE_COMPILER_IS_GNUCXX))
    return()
  endif()

  target_compile_options(${target} PRIVATE -pg)
  target_link_libraries(${target} PRIVATE -pg)
endfunction()

function(swift_add_gprof target)
  target_code_profiling(${target})

  get_target_property(target_type ${target} TYPE)
  if (NOT target_type STREQUAL EXECUTABLE)
    message(FATAL_ERROR "Specified target \"${target}\" must be an executable type to register for profiling with Gprof")
  endif()

  if (NOT (GProf_FOUND AND
           ${PROJECT_NAME} STREQUAL ${CMAKE_PROJECT_NAME})
      OR CMAKE_CROSSCOMPILING)
    return()
  endif()

  set(argOption GENERATE_REPORT)
  set(argSingle NAME WORKING_DIRECTORY REPORT_DIRECTORY)
  set(argMulti PROGRAM_ARGS)

  cmake_parse_arguments(x "${argOption}" "${argSingle}" "${argMulti}" ${ARGN})

  if (x_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "Unparsed arguments ${x_UNPARSED_ARGUMENTS}")
  endif()

  set(target_name gprof-${target})
  set(report_folder ${target})
  if (x_NAME)
    set(target_name gprof-${x_NAME})
    set(report_folder ${x_NAME})
  endif()

  set(working_directory ${CMAKE_CURRENT_BINARY_DIR})
  if (x_WORKING_DIRECTORY)
    set(working_directory ${x_WORKING_DIRECTORY})
  endif()

  set(report_directory ${CMAKE_BINARY_DIR}/profiling/gprof-reports)
  if (x_REPORT_DIRECTORY)
    set(report_directory ${x_REPORT_DIRECTORY})
  endif()
  
  unset(post_commands)
  if (GProf_FOUND AND x_GENERATE_REPORT)
    list(APPEND post_commands COMMAND find ${report_directory}/${report_folder} -regex '.*gmon\.[0-9].*' -execdir ${GProf_EXECUTABLE} $<TARGET_FILE:${target}> {} > ${report_directory}/${report_folder}/gmon.txt + -quit)
  endif()

  add_custom_target(${target_name}
    COMMENT "Gprof is running for \"${target}\" (output: \"${report_directory}/${report_folder}\")"
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${report_directory}/${report_folder}
    COMMAND ${CMAKE_COMMAND} -E make_directory ${report_directory}/${report_folder}
    COMMAND ${CMAKE_COMMAND} -E env GMON_OUT_PREFIX=gmon $<TARGET_FILE:${target}> ${x_PROGRAM_ARGS}
    COMMAND mv ${working_directory}/gmon* ${report_directory}/${report_folder}
    ${post_commands}
    WORKING_DIRECTORY ${working_directory}
    DEPENDS ${target}
  )

  if (NOT TARGET do-all-gprof)
    add_custom_target(do-all-gprof)
  endif()
  add_dependencies(do-all-gprof ${target_name})
endfunction()