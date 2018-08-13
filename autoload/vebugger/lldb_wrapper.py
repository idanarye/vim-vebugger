#!/usr/bin/env python2
# -*- coding: utf-8 -*-

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals


import collections
import os
import platform
import re
import subprocess
import sys


FilePosition = collections.namedtuple('FilePosition', ['filepath', 'linenumber'])


try:
    # Just try for LLDB in case PYTHONPATH is already correctly setup
    import lldb
except ImportError:
    lldb_python_dirs = []
    # lldb is not in the PYTHONPATH, try some defaults for the current platform
    platform_system = platform.system()
    if platform_system == 'Darwin':
        # On Darwin, try the currently selected Xcode directory
        try:
            xcode_dir = subprocess.check_output(['xcode-select', '--print-path'])
        except subprocess.CalledProcessError:
            xcode_dir = None
        if xcode_dir:
            lldb_python_dirs.append(
                os.path.realpath(
                    os.path.join(xcode_dir, '../SharedFrameworks/LLDB.framework/Versions/A/Resources/Python')
                )
            )
        lldb_python_dirs.append(
            '/Library/Developer/CommandLineTools/Library/PrivateFrameworks/LLDB.framework/Versions/A/Resources/Python'
        )
    for lldb_python_dir in lldb_python_dirs:
        if os.path.exists(lldb_python_dir):
            if lldb_python_dir not in sys.path:
                sys.path.append(lldb_python_dir)
                try:
                    import lldb
                except ImportError:
                    pass
                else:
                    break
    else:
        sys.stderr.write('Error: could not locate the "lldb" module, please set PYTHONPATH correctly\n')
        sys.exit(1)


class NoCustomCommandError(Exception):
    pass


class Debugger(object):
    class BreakpointManager(object):
        def __init__(self):
            self._next_breakpoint_id = 1
            self._location_to_id = {}

        def add_breakpoint(self, filename, linenumber):
            location = (filename, linenumber)
            breakpoint_id = self._next_breakpoint_id
            self._location_to_id[location] = breakpoint_id
            self._next_breakpoint_id += 1
            return breakpoint_id

        def remove_breakpoint(self, filename, linenumber):
            location = (filename, linenumber)
            breakpoint_id = self._location_to_id[location]
            del self._location_to_id[location]
            return breakpoint_id

    def __init__(self, executable):
        self._executable = executable
        self._debugger = lldb.SBDebugger.Create()
        self._debugger.SetAsync(False)
        self._command_interpreter = self._debugger.GetCommandInterpreter()
        error = lldb.SBError()
        self._target = self._debugger.CreateTarget(
            self._executable, None, None, True, error
        )
        self._process = None
        self._last_debugger_return_obj = None
        self._state_dict = None
        self._breakpoint_manager = self.BreakpointManager()
        self._custom_commands = ['br', 'clear']
        self._set_options()

    def _set_options(self):
        # -> first read lldbinit
        try:
            with open(os.path.expanduser('~/.lldbinit')) as f:
                for line in f:
                    self.run_command(line)
        except IOError:
            pass
        self.run_command('settings set frame-format frame #${frame.index}: ${frame.pc}{ ${module.file.basename}`${function.name}{${function.pc-offset}}}{ at:${line.file.fullpath}:${line.number}}\n')
        self.run_command('settings set auto-confirm 1')

    def run_command(self, commandline):
        if self._is_custom_command(commandline):
            self._run_custom_command(commandline)
        else:
            if isinstance(commandline, unicode):
                commandline = commandline.encode('utf-8')
            return_obj = lldb.SBCommandReturnObject()
            self._command_interpreter.HandleCommand(commandline, return_obj)
            if self._process is None or self._process.GetState() == lldb.eStateInvalid:
                self._process = self._command_interpreter.GetProcess()
            self._last_debugger_return_obj = return_obj

    def _is_custom_command(self, commandline):
        command = commandline.split()[0]
        return command in self._custom_commands

    def _run_custom_command(self, commandline):
        def br(arguments):
            filename, linenumber = arguments[0].split(':')
            linenumber = int(linenumber)
            self._breakpoint_manager.add_breakpoint(filename, linenumber)
            self.run_command('b {}'.format(*arguments))

        def clear(arguments):
            filename, linenumber = arguments[0].split(':')
            linenumber = int(linenumber)
            breakpoint_id = self._breakpoint_manager.remove_breakpoint(filename,
                                                                       linenumber)
            self.run_command('breakpoint delete {:d}'.format(breakpoint_id))

        if not self._is_custom_command(commandline):
            raise NoCustomCommandError
        parts = commandline.split()
        print('parts:', parts)
        command = parts[0]
        arguments = parts[1:]
        locals()[command](arguments)

    @property
    def debugger_output(self):
        if self._last_debugger_return_obj is not None:
            return_obj = self._last_debugger_return_obj
            self._last_debugger_return_obj = None
            return return_obj.GetOutput()
        else:
            return ''

    @property
    def where(self):
        def extract_where(backtrace):
            where = None
            pattern = re.compile('at:([^:]+):(\d+)')
            backtrace_lines = backtrace.split('\n')
            for line in backtrace_lines:
                match_obj = pattern.search(line)
                if match_obj:
                    filepath = match_obj.group(1)
                    linenumber = int(match_obj.group(2))
                    if os.access(filepath, os.R_OK):
                        where = FilePosition(filepath, linenumber)
                        break
            return where

        where = None
        self.run_command('bt')
        debugger_output = self.debugger_output
        if debugger_output is not None:
            where = extract_where(debugger_output)
        return where

    @property
    def program_stdout(self):
        stdout = []
        has_text = True
        while has_text:
            text = self._process.GetSTDOUT(1024)
            if text:
                stdout.append(text)
            else:
                has_text = False
        return ''.join(stdout)

    @property
    def program_stderr(self):
        stderr = []
        has_text = True
        while has_text:
            text = self._process.GetSTDERR(1024)
            if text:
                stderr.append(text)
            else:
                has_text = False
        return ''.join(stderr)

    @property
    def program_state(self):
        return self._state_id_to_name(self._process.GetState())

    def _state_id_to_name(self, state_id):
        if self._state_dict is None:
            self._state_dict = {}
            for key, value in lldb.__dict__.iteritems():
                if key.startswith('eState'):
                    self._state_dict[value] = key[6:]
        return self._state_dict[state_id]


def prefix_output(output, prefix):
    if output is None:
        output = ''
    lines = output.split('\n')
    lines = [prefix + line for line in lines]
    prefixed_output = '\n'.join(lines)
    return prefixed_output


def main():
    if len(sys.argv) < 2:
        sys.stderr.write('An executable is needed as an argument.\n')
        sys.exit(1)

    executable = sys.argv[1]
    debugger = Debugger(executable)

    try:
        while True:
            line = raw_input()
            # TODO: find a way to check directly if the debugger was terminated
            if line in ['exit', 'quit']:
                raise EOFError
            debugger.run_command(line)
            program_stdout = debugger.program_stdout
            if program_stdout:
                print(prefix_output(program_stdout, 'program_stdout: '))
            program_stderr = debugger.program_stderr
            if program_stderr:
                print(prefix_output(program_stderr, 'program_stderr: '))
            print(prefix_output(debugger.debugger_output, 'debugger_output: '))
            where = debugger.where
            if where:
                print(prefix_output('{:s}:{:d}'.format(where.filepath, where.linenumber), 'where: '))
            print(prefix_output(debugger.program_state, 'program_state: '))
    except EOFError:
        print('Exiting')


if __name__ == '__main__':
    main()
