

command! -nargs=1 VBGrawWrite call vebugger#writeLine(<q-args>)

command! -nargs=1 -complete=file VBGstartGDB call vebugger#gdb#start(<q-args>,{})
command! -nargs=0 VBGkill call vebugger#killDebugger()

command! -nargs=0 VBGstepIn call vebugger#setWriteActionAndPerform('std','flow','stepin')
command! -nargs=0 VBGstepOver call vebugger#setWriteActionAndPerform('std','flow','stepover')
command! -nargs=0 VBGstepOut call vebugger#setWriteActionAndPerform('std','flow','stepout')
command! -nargs=0 VBGcontinue call vebugger#setWriteActionAndPerform('std','flow','continue')

command! -nargs=0 VBGtoggleTerminalBuffer call vebugger#toggleTerminalBuffer()
command! -nargs=+ VBGtoggleBreakpoint call vebugger#std#toggleBreakpoint(<f-args>)
command! -nargs=0 VBGtoggleBreakpointThisLine call vebugger#std#toggleBreakpoint(expand('%:~:.'),line('.'))
command! -nargs=0 VBGclearBreakpints call vebugger#std#clearBreakpoints()

command! -nargs=1 VBGeval call vebugger#std#eval(<q-args>)
command! -nargs=0 VBGevalWordUnderCursor call vebugger#std#eval(expand('<cword>'))

"Shamefully stolen from http://stackoverflow.com/a/6271254/794380
function! s:get_visual_selection()
	" Why is this not a built-in Vim script function?!
	let [lnum1, col1] = getpos("'<")[1:2]
	let [lnum2, col2] = getpos("'>")[1:2]
	let lines = getline(lnum1, lnum2)
	let lines[-1] = lines[-1][: col2 - (&selection == 'inclusive' ? 1 : 2)]
	let lines[0] = lines[0][col1 - 1:]
	return join(lines, "\n")
endfunction

command! -range -nargs=0 VBGevalSelectedText call vebugger#std#eval(s:get_visual_selection())


if exists('g:vebugger_leader')
	if !empty(g:vebugger_leader)
		for s:mapping in items({
					\'i':'VBGstepIn',
					\'o':'VBGstepOver',
					\'O':'VBGstepOut',
					\'c':'VBGcontinue',
					\'t':'VBGtoggleTerminalBuffer',
					\'b':'VBGtoggleBreakpointThisLine',
					\'e':'VBGevalWordUnderCursor'})
			exe 'nnoremap '.g:vebugger_leader.s:mapping[0].' :'.s:mapping[1].'<Cr>'
		endfor
		for s:mapping in items({
					\'e':'VBGevalSelectedText'})
			exe 'vnoremap '.g:vebugger_leader.s:mapping[0].' :'.s:mapping[1].'<Cr>'
		endfor
	endif
endif
