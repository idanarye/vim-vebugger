

command! -nargs=0 VBGrepeat call vebugger#repeatLastUserAction()

command! -nargs=1 VBGrawWrite call vebugger#userAction('writeLine', <q-args>)
command! -nargs=0 VBGkill call vebugger#killDebugger()

command! -nargs=0 VBGstepIn call vebugger#userAction('setWriteActionAndPerform', 'std', 'flow', 'stepin')
command! -nargs=0 VBGstepOver call vebugger#userAction('setWriteActionAndPerform', 'std', 'flow', 'stepover')
command! -nargs=0 VBGstepOut call vebugger#userAction('setWriteActionAndPerform', 'std', 'flow', 'stepout')
command! -nargs=0 VBGcontinue call vebugger#userAction('setWriteActionAndPerform', 'std', 'flow', 'continue')

command! -nargs=0 VBGtoggleTerminalBuffer call vebugger#userAction('toggleTerminalBuffer')
command! -nargs=+ -complete=file VBGtoggleBreakpoint call vebugger#std#toggleBreakpoint(<f-args>)
command! -nargs=0 VBGtoggleBreakpointThisLine call vebugger#std#toggleBreakpoint(expand('%:p:.'),line('.'))
command! -nargs=0 VBGclearBreakpoints call vebugger#std#clearBreakpoints()

command! -nargs=1 VBGeval call vebugger#userAction('std_eval', <q-args>)
command! -nargs=0 VBGevalWordUnderCursor call vebugger#userAction('std_eval', expand('<cword>'))
command! -nargs=1 VBGexecute call vebugger#userAction('std_execute', <q-args>)

command! -range -nargs=0 VBGevalSelectedText call vebugger#userAction('std_eval', vebugger#util#get_visual_selection())
command! -range -nargs=0 VBGexecuteSelectedText call vebugger#userAction('std_execute', vebugger#util#get_visual_selection())
command! -range -nargs=0 VBGrawWriteSelectedText call vebugger#userAction('writeLine', vebugger#util#get_visual_selection())

command! -nargs=+ -complete=file VBGstartGDB call vebugger#gdb#start([<f-args>][0],{'args':[<f-args>][1:]})
function! s:attachGDB(...)
	if 1 == a:0
		let l:processId=vebugger#util#selectProcessOfFile(a:1)
		if 0 < l:processId
			call vebugger#gdb#start(a:1, {'pid': l:processId})
		endif
	elseif 2 == a:0
		if a:2 =~ '\v^\d+$'
			call vebugger#gdb#start(a:1,{'pid': str2nr(a:2)})
		else
			call vebugger#gdb#start(a:1, {'con': a:2})
		endif
	else
		throw "Can't call VBGattachGDB with ".a:0." arguments"
	endif
endfunction
command! -nargs=+ -complete=file VBGattachGDB call s:attachGDB(<f-args>)
command! -nargs=+ -complete=file VBGstartLLDB call vebugger#lldb#start([<f-args>][0],{'args':[<f-args>][1:]})
function! s:attachLLDB(...)
	if 1 == a:0
		let l:processId=vebugger#util#selectProcessOfFile(a:1)
		if 0 < l:processId
			call vebugger#lldb#start(a:1, {'pid': l:processId})
		endif
	elseif 2 == a:0
		if a:2 =~ '\v^\d+$'
			call vebugger#lldb#start(a:1,{'pid': str2nr(a:2)})
		else
			call vebugger#lldb#start(a:1, {'con': a:2})
		endif
	else
		throw "Can't call VBGattachLLDB with ".a:0." arguments"
	endif
endfunction
command! -nargs=+ -complete=file VBGattachLLDB call s:attachLLDB(<f-args>)
command! -nargs=+ -complete=file VBGstartRDebug call vebugger#rdebug#start([<f-args>][0],{'args':[<f-args>][1:]})
command! -nargs=+ -complete=file VBGstartNInspect call vebugger#ninspect#start([<f-args>][0],{'args':[<f-args>][1:]})
command! -nargs=+ -complete=file VBGstartPDB call vebugger#pdb#start([<f-args>][0],{'args':[<f-args>][1:]})
command! -nargs=+ -complete=file VBGstartPDB2 call vebugger#pdb#start([<f-args>][0],{'args':[<f-args>][1:],'version':'2'})
command! -nargs=+ -complete=file VBGstartPDB3 call vebugger#pdb#start([<f-args>][0],{'args':[<f-args>][1:],'version':'3'})
command! -nargs=+ -complete=file VBGstartGDBForD call vebugger#gdb#start([<f-args>][0],{'args':[<f-args>][1:],'entry':'_Dmain'})

if exists('g:vebugger_leader')
	if !empty(g:vebugger_leader)
		for s:mapping in items({
					\'i':'VBGstepIn',
					\'o':'VBGstepOver',
					\'O':'VBGstepOut',
					\'c':'VBGcontinue',
					\'t':'VBGtoggleTerminalBuffer',
					\'b':'VBGtoggleBreakpointThisLine',
					\'B':'VBGclearBreakpoints',
					\'e':'VBGevalWordUnderCursor',
					\'E':'exe "VBGeval ".input("VBG-Eval> ")',
					\'x':'exe "VBGexecute ".getline(".")',
					\'X':'exe "VBGexecute ".input("VBG-Exec> ")',
					\'R':'exe "VBGrawWrite ".input("VBG> ")'})
			exe 'nnoremap '.g:vebugger_leader.s:mapping[0].' :'.s:mapping[1].'<Cr>'
		endfor
		for s:mapping in items({
					\'e':'VBGevalSelectedText',
					\'x':'VBGexecuteSelectedText',
					\'r':'VBGrawWriteSelectedText'})
			exe 'vnoremap '.g:vebugger_leader.s:mapping[0].' :'.s:mapping[1].'<Cr>'
		endfor
	endif
endif
