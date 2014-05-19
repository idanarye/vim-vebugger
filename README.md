INTRODUCTION
============

Vebugger is yet another debugger frontend plugin for Vim, created because I
wasn't happy with the other debugger plugins I found. Vebugger currently
supports:

 * Tracking the currently executed command in the source code
 * Debugger flow commands - step-in, set-over, set-out and continue
 * Breakpoints management
 * Evaluating expressions in the current executed scope
 * Messing with the program's state(changing values, calling functions)

Vebugger is built as a generic framework for building frontends for
interactive shell debugger, and comes with implementations for:

 * GDB - doesn't need introdcution...
 * JDB - a Java debugger
 * PDB - a Python module for debugging Python scripts
 * RDebug - a Ruby command line option for debugging Ruby scripts

Other implementations can be added with ease, and I will accept pull requests
that add such implementations as long as they use Vim's |license|.

Vebugger is built under the following assumptions:

 * While command line debuggers share enough in common to make the creation
   of such a framework as Vebugger possible, the differences between them are
   too great to be expressed with regular expression. To support them all at
   least some code has to be written.
 * Unlike IDE users, Vim users tend to understand the tools the operate behind
   the scenes. While Vebugger automates the common features, it allows you to
   "open the hood" and interact with the debugger's shell directly so you could
   utilize the full power of your debugger.
 * I have no intention to aim for the lowest common denominator. If one
   debugger has a cool feature I want to support, I'll implement it even if the
   other debuggers don't have it.

Vebugger is developed under Linux. I'll try it under Windows once I feel like
setting a Windows development environment, and fix what needs to be fixed to
make it work there. I have neither plans nor means to support OSX, but I will
accept pull requests that add OSX support.

REQUIREMENTS
============

Vebugger requires the vimproc plugin, obtainable from:
https://github.com/Shougo/vimproc.vim.  Notice that vimproc needs to be built -
there are instructions in the GitHub page.

In order for Vebugger to use a debugger, that debugger must be installed and
it's executable must be in the PATH. In case of RDebug and PDB, which are used
from the Ruby and Python modules, the interpreter(`ruby` or `python`) is the
one that must be installed and in the path.

USAGE
=====

Run `help vebugger-launching` from Vim to learn how to launch the debugger.

Run `help vebugger-usage` from Vim to learn how to operate the debugger.
