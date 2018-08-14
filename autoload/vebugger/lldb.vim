let s:script_dir_path=expand('<sfile>:p:h')

function! vebugger#lldb#start(binaryFile,args)
	let l:debuggerExe=vebugger#util#getToolFullPath('python','lldb','python2')
	let l:debugger=vebugger#std#startDebugger(shellescape(l:debuggerExe)
				\.' '.s:script_dir_path.'/lldb_wrapper.py '.fnameescape(a:binaryFile))

	let l:debugger.state.lldb={}

	if get(a:args,'pid') "Attach to process
		call l:debugger.writeLine('process attach --pid '.string(a:args.pid))
	elseif has_key(a:args,'con') "Attach to lldbserver
		call l:debugger.writeLine('platform connect connect://'.a:args.con)
	else
		call l:debugger.writeLine('settings set target.run-args '.vebugger#util#commandLineArgsForProgram(a:args))
		if !has('win32')
			call vebugger#std#openShellBuffer(l:debugger)
		endif

        " TODO: remove 'and false'; add a temporary breakpoint to lldb
		if has_key(a:args,'entry') && 0
			" call l:debugger.writeLine('tbreak '.a:args.entry)
			" call l:debugger.writeLine('run')
		else
			call l:debugger.writeLine('breakpoint set --name main')
			call l:debugger.writeLine('process launch')
		endif
    endif


	call l:debugger.addReadHandler(function('vebugger#lldb#_readProgramOutput'))
	call l:debugger.addReadHandler(function('vebugger#lldb#_readWhere'))
	call l:debugger.addReadHandler(function('vebugger#lldb#_readFinish'))
	call l:debugger.addReadHandler(function('vebugger#lldb#_readEvaluatedExpressions'))

	call l:debugger.setWriteHandler('std','flow',function('vebugger#lldb#_writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('vebugger#lldb#_writeBreakpoints'))
	call l:debugger.setWriteHandler('std','closeDebugger',function('vebugger#lldb#_closeDebugger'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('vebugger#lldb#_requestEvaluateExpression'))
	call l:debugger.setWriteHandler('std','executeStatements',function('vebugger#lldb#_executeStatements'))

	call l:debugger.generateWriteActionsFromTemplate()

	call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

	return l:debugger
endfunction

function! vebugger#lldb#_readProgramOutput(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
				\&&(a:line=~'\v^program_stdout:'
				\||a:line=~'\v^program_stderr:')
		let a:readResult.std.programOutput={'line':strpart(a:line, 16)}
	endif
endfunction

function! vebugger#lldb#_readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
				\&&a:line=~'\v^where:'
		let l:matches=matchlist(a:line,'\v^where:\s([^:]+):(\d+)')
		if 2<len(l:matches)
			let l:file=l:matches[1]
			let l:file=fnamemodify(l:file,':p')
			let a:readResult.std.location={
						\'file':(l:file),
						\'line':str2nr(l:matches[2])}
		endif
	endif
endfunction

function! vebugger#lldb#_readFinish(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
				\&&a:line=~'\v^program_state:\sExited'
		let a:readResult.std.programFinish={'finish':1}
	endif
endfunction

function! vebugger#lldb#_writeFlow(writeAction,debugger)
	if 'stepin'==a:writeAction
		call a:debugger.writeLine('step')
	elseif 'stepover'==a:writeAction
		call a:debugger.writeLine('next')
	elseif 'stepout'==a:writeAction
		call a:debugger.writeLine('finish')
	elseif 'continue'==a:writeAction
		call a:debugger.writeLine('continue')
	endif
endfunction

function! vebugger#lldb#_closeDebugger(writeAction,debugger)
	call a:debugger.writeLine('quit')
endfunction

function! vebugger#lldb#_writeBreakpoints(writeAction,debugger)
	for l:breakpoint in a:writeAction
		if 'add'==(l:breakpoint.action)
			call a:debugger.writeLine('br '.fnameescape(l:breakpoint.file).':'.l:breakpoint.line)
		elseif 'remove'==l:breakpoint.action
			call a:debugger.writeLine('clear '.fnameescape(l:breakpoint.file).':'.l:breakpoint.line)
		endif
	endfor
endfunction

function! vebugger#lldb#_requestEvaluateExpression(writeAction,debugger)
	for l:evalAction in a:writeAction
		call a:debugger.writeLine('print '.l:evalAction.expression)
	endfor
endfunction

function! vebugger#lldb#_executeStatements(writeAction,debugger)
	for l:evalAction in a:writeAction
		if has_key(l:evalAction,'statement')
			"Use eval to run the statement - but first we need to remove the ;
			call a:debugger.writeLine('print '.substitute(l:evalAction.statement,'\v;\s*$','',''))
		endif
	endfor
endfunction

function! vebugger#lldb#_readEvaluatedExpressions(pipeName,line,readResult,debugger) dict
	if 'out' == a:pipeName
		if has_key(self, 'nextExpressionToBePrinted')
					\&&a:line=~'\v^debugger_output:'
			let l:matches=matchlist(a:line,'\v^[^\$]*\$(\d+) \= (.*)$')
			if 2<len(l:matches)
				let l:expression=l:matches[1]
				let l:value=l:matches[2]
				let a:readResult.std.evaluatedExpression={
							\'expression':self.nextExpressionToBePrinted,
							\'value':(l:value)}
			endif
			call remove(self,'nextExpressionToBePrinted')
		else
			let l:matches=matchlist(a:line,'\v^print (.+)$')
			if 1<len(l:matches)
				let self.nextExpressionToBePrinted=l:matches[1]
			endif
		endif
	endif
endfunction
