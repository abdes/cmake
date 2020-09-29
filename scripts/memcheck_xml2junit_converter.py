#!/usr/bin/env python
#
# OVERVIEW
#
# This script converts an xml file generated by the tool Valgrind Memcheck
# into JUnit xml format. JUnit is a testing framework supported by CI tools
# such as Jenkins to display test results.
#
# The script searches for all `error` elements in a Valgrind Memcheck xml
# file. If none is found, the xml file is converted to a passing test. All
# errors found are inserted as a `test case` element in the JUnit xml file.
# If the option `skip_tests` is defined, that replaces all `error` elements
# with `skipped` elements.
#
# USAGE
#
#   python memcheck_xml2junit_converter.py [OPTIONS]
#
# Run the script by supplying an input directory containing one or several xml
# files and an output directory where the converted files are collected.
#
# OPTIONS
# * -i, --input_directory:  Sets the folder path to where the script searches
#                           for xml files to convert. Subdirectories within the
#                           directory are also included.
# * -o, --output_directory: Defines the output folder where the converted JUnit
#                           xml files are collected.
# * -s, --skip_tests:       Error elements in a Valgrind Memcheck xml file are
#                           replaced by a skipped message type in the converted 
#                           JUnit xml file.
#
import xml.etree.ElementTree as ET
import sys, os, argparse

parser = argparse.ArgumentParser(description='Convert Valgrind Memcheck xml into JUnit xml format.')
optional = parser._action_groups.pop()
required = parser.add_argument_group('required arguments')
required.add_argument('-i','--input_directory',
                      help='Directory where Valgrind Memcheck xml files are located',
                      required=True)
required.add_argument('-o','--output_directory',
                      help='Directory where the converted JUnit xml files are collected',
                      required=True)
optional.add_argument('-s','--skip_tests',
                      help='Error elements in a Valgrind Memcheck xml file is replaced by a skipped message type in the converted JUnit xml file',
                      action='store_true')
parser._action_groups.append(optional)
args = parser.parse_args()

if not os.path.exists(args.output_directory):
  os.mkdir(args.output_directory)

for subdir, dirs, files in os.walk(args.input_directory):
  if os.path.basename(subdir) == os.path.basename(args.output_directory):
    continue
  for filename in files:
    if "xml" in filename:
      # read errors in valgrind memcheck xml
      input_filepath = os.path.join(subdir, filename)
      try:
        doc = ET.parse(input_filepath)
      except ET.ParseError:
        continue
      errors = doc.findall('.//error')

      # create output filename
      output_filename = os.path.join(args.output_directory, filename)
      if not output_filename.endswith('.xml'):
        output_filename += '.xml'

      test_type = "error"
      plural = "s"
      if args.skip_tests:
        test_type = "skipped"
        plural = ""

      out = open(output_filename,"w")
      out.write('<?xml version="1.0" encoding="UTF-8"?>\n')
      if len(errors) == 0:
        out.write('<testsuite name="valgrind" tests="1" '+test_type+''+plural+'="'+str(len(errors))+'">\n')
        out.write('    <testcase classname="valgrind-memcheck" name="'+str(filename)+'"/>\n')
      else:
        out.write('<testsuite name="valgrind" tests="'+str(len(errors))+'" '+test_type+''+plural+'="'+str(len(errors))+'">\n')
        errorcount=0
        for error in errors:
          errorcount += 1

          kind = error.find('kind')
          what = error.find('what')
          if what == None:
            what = error.find('xwhat/text')

          stack = error.find('stack')
          frames = stack.findall('frame')

          for frame in frames:
            fi = frame.find('file')
            li = frame.find('line')
            if fi != None and li != None:
              break

          if fi != None and li != None:
            out.write('    <testcase classname="valgrind-memcheck" name="'+str(filename)+' '+str(errorcount)+' ('+kind.text+', '+fi.text+':'+li.text+')">\n')
          else:
            out.write('    <testcase classname="valgrind-memcheck" name="'+str(filename)+' '+str(errorcount)+' ('+kind.text+')">\n')
          out.write('        <'+test_type+' type="'+kind.text+'">\n')
          out.write('  '+what.text+'\n\n')

          for frame in frames:
            ip = frame.find('ip')
            fn = frame.find('fn')
            fi = frame.find('file')
            li = frame.find('line')
	    if fn != None:
              bodytext = fn.text
            else:
              bodytext = "unknown function name"
            bodytext = bodytext.replace("&","&amp;")
            bodytext = bodytext.replace("<","&lt;")
            bodytext = bodytext.replace(">","&gt;")
            if fi != None and li != None:
              out.write('  '+ip.text+': '+bodytext+' ('+fi.text+':'+li.text+')\n')
            else:
              out.write('  '+ip.text+': '+bodytext+'\n')
          out.write('        </'+test_type+'>\n')
          out.write('    </testcase>\n')
      out.write('</testsuite>\n')
      out.close()

