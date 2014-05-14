function! vebugger#rdebug#start(entryFile,args)
	let l:debugger=vebugger#std#startDebugger(
				\(has_key(a:args,'command')
				\? (a:args.command)
				\: 'ruby -rdebug')
				\.' '.a:entryFile)
	let l:debugger.state.rdebug={}
	call l:debugger.showLogBuffer()


	call l:debugger.addReadHandler(function('s:readWhere'))
	call l:debugger.addReadHandler(function('s:readEvaluatedExpressions'))

	call l:debugger.setWriteHandler('std','flow',function('s:writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('s:writeBreakpoints'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('s:requestEvaluateExpression'))
	call l:debugger.setWriteHandler('std','removeAfterDisplayed',function('s:removeAfterDisplayed'))

	call l:debugger.generateWriteActionsFromTemplate()

	call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

	VBGtoggleLogBuffer

	return l:debugger
endfunction

function! s:readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\v^([^:]+)\:(\d+)\:(.*)$')

		if 3<len(l:matches)
			let l:file=l:matches[1]
			if !empty(glob(l:file))
				let l:line=str2nr(l:matches[2])
				let a:readResult.std.location={
							\'file':(l:file),
							\'line':(l:line)}
			endif
		endif
	endif
endfunction

function! s:writeFlow(writeAction,debugger)
	if 'stepin'==a:writeAction
		call a:debugger.writeLine('step')
	elseif 'stepover'==a:writeAction
		call a:debugger.writeLine('next')
	elseif 'stepout'==a:writeAction
		"call a:debugger.writeLine('step up')
	elseif 'continue'==a:writeAction
		call a:debugger.writeLine('cont')
	endif
endfunction

function! s:writeBreakpoints(writeAction,debugger)
	for l:breakpoint in a:writeAction
		if 'add'==(l:breakpoint.action)
			call a:debugger.writeLine('break '.fnameescape(l:breakpoint.file).':'.l:breakpoint.line)
		elseif 'remove'==l:breakpoint.action
			call a:debugger.writeLine('delete '.fnameescape(l:breakpoint.file).':'.l:breakpoint.line)
		endif
	endfor
endfunction

function! s:requestEvaluateExpression(writeAction,debugger)
	for l:evalAction in a:writeAction
		call a:debugger.writeLine('display '.l:evalAction.expression)
	endfor
endfunction

function! s:readEvaluatedExpressions(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\v^(\d+)\: (.*) \= (.*)$')
		if 4<len(l:matches)
			let l:id=str2nr(l:matches[1])
			let l:expression=l:matches[2]
			let l:value=l:matches[3]
			let a:readResult.std.evaluatedExpression={
						\'id':(l:id),
						\'expression':(l:expression),
						\'value':(l:value)}
		endif
	endif
endfunction

function! s:removeAfterDisplayed(writeAction,debugger)
	for l:removeAction in a:writeAction
		if has_key(l:removeAction,'id')
			call a:debugger.writeLine('undisplay '.l:removeAction.id)
		endif
	endfor
endfunction
