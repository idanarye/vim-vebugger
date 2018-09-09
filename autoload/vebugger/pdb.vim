function! vebugger#pdb#start(entryFile,args)
	let l:debuggerExe=vebugger#util#getToolFullPath('python',get(a:args,'version'),{
				\' ':'python',
				\'2':'python2',
				\'3':'python3'})
	let l:debugger=vebugger#std#startDebugger(shellescape(l:debuggerExe)
				\.' -m pdb '.a:entryFile.' '.vebugger#util#commandLineArgsForProgram(a:args))

	let l:debugger.state.pdb={}

	if !has('win32')
		call vebugger#std#openShellBuffer(l:debugger)
	endif

	call l:debugger.addReadHandler(function('vebugger#pdb#_readProgramOutput'))
	call l:debugger.addReadHandler(function('vebugger#pdb#_readWhere'))
	call l:debugger.addReadHandler(function('vebugger#pdb#_readFinish'))
	call l:debugger.addReadHandler(function('vebugger#pdb#_readEvaluatedExpressions'))

	call l:debugger.setWriteHandler('std','flow',function('vebugger#pdb#_writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('vebugger#pdb#_writeBreakpoints'))
	call l:debugger.setWriteHandler('std','closeDebugger',function('vebugger#pdb#_closeDebugger'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('vebugger#pdb#_requestEvaluateExpression'))
	call l:debugger.setWriteHandler('std','executeStatements',function('vebugger#pdb#_executeStatements'))
	call l:debugger.setWriteHandler('std','removeAfterDisplayed',function('vebugger#pdb#_removeAfterDisplayed'))

	call l:debugger.generateWriteActionsFromTemplate()

	call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

	return l:debugger
endfunction

function! vebugger#pdb#_readProgramOutput(pipeName,line,readResult,debugger) dict
	if 'out'==a:pipeName
		if a:line=~"\\V\<C-[>[C" " After executing commands this seems to get appended...
			let self.programOutputMode=1
			return
		endif
		if a:line=~'\v^\>'
					\||a:line=~'\V\^(Pdb)' "We don't want to print this particular line...
					\||a:line=='--Return--'
					\||a:line=='The program finished and will be restarted'
			let self.programOutputMode=0
		endif
		if get(self,'programOutputMode')
			let a:readResult.std.programOutput={'line':a:line}
		endif
		if a:line=~'\v^\(Pdb\) (n|s|r|cont)'
			let self.programOutputMode=1
		endif
	else
		let a:readResult.std.programOutput={'line':a:line}
	endif
endfunction

function! vebugger#pdb#_readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\v^\> (.+)\((\d+)\).*\(\)%(-\>.*)?$')

		if 2<len(l:matches)
			let l:file=vebugger#util#WinShellSlash(l:matches[1])
			if !empty(glob(l:file))
				let l:line=str2nr(l:matches[2])
				let a:readResult.std.location={
							\'file':(l:file),
							\'line':(l:line)}
			endif
		endif
	endif
endfunction

function! vebugger#pdb#_readFinish(pipeName,line,readResult,debugger)
	if a:line=='The program finished and will be restarted'
		let a:readResult.std.programFinish={'finish':1}
	endif
endfunction

function! vebugger#pdb#_writeFlow(writeAction,debugger)
	if 'stepin'==a:writeAction
		call a:debugger.writeLine('step')
	elseif 'stepover'==a:writeAction
		call a:debugger.writeLine('next')
	elseif 'stepout'==a:writeAction
		call a:debugger.writeLine('return')
	elseif 'continue'==a:writeAction
		call a:debugger.writeLine('continue')
	endif
endfunction

function! vebugger#pdb#_closeDebugger(writeAction,debugger)
	call a:debugger.writeLine('quit')
endfunction

function! vebugger#pdb#_writeBreakpoints(writeAction,debugger)
	for l:breakpoint in a:writeAction
		if 'add'==(l:breakpoint.action)
			call a:debugger.writeLine('break '.fnameescape(fnamemodify(l:breakpoint.file,':p')).':'.l:breakpoint.line)
		elseif 'remove'==l:breakpoint.action
			call a:debugger.writeLine('clear '.fnameescape(fnamemodify(l:breakpoint.file,':p')).':'.l:breakpoint.line)
		endif
	endfor
endfunction

function! vebugger#pdb#_requestEvaluateExpression(writeAction,debugger)
	for l:evalAction in a:writeAction
		call a:debugger.writeLine('p '.l:evalAction.expression)
	endfor
endfunction

function! vebugger#pdb#_executeStatements(writeAction,debugger)
	for l:evalAction in a:writeAction
		if has_key(l:evalAction,'statement')
			call a:debugger.writeLine('!'.l:evalAction.statement)
		endif
	endfor
endfunction

function! vebugger#pdb#_readEvaluatedExpressions(pipeName,line,readResult,debugger) dict
	if 'out'==a:pipeName
		if has_key(self,'expression') "Reading the actual value to print
			let l:value=a:line
			let a:readResult.std.evaluatedExpression={
						\'expression':(self.expression),
						\'value':(l:value)}
			"Reset the state
			unlet self.expression
		else "Check if the next line is the eval result
			let l:matches=matchlist(a:line,'\v^\(Pdb\) p (.*)$')
			if 1<len(l:matches)
				let self.expression=l:matches[1]
			endif
		endif
	endif
endfunction

function! vebugger#pdb#_removeAfterDisplayed(writeAction,debugger)
	for l:removeAction in a:writeAction
		if has_key(l:removeAction,'id')
			"call a:debugger.writeLine('undisplay '.l:removeAction.id)
		endif
	endfor
endfunction
