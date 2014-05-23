function! vebugger#gdb#searchAndAttach(binaryFile)
	let l:processId=vebugger#util#selectProcessOfFile(a:binaryFile)
	if 0<l:processId
		call vebugger#gdb#start(a:binaryFile,{'pid':l:processId})
	endif
endfunction

function! vebugger#gdb#start(binaryFile,args)
	let l:debugger=vebugger#std#startDebugger(shellescape(vebugger#util#getToolFullPath('gdb','gdb'))
				\.' -i mi --silent '.fnameescape(a:binaryFile))
	let l:debugger.state.gdb={}


	let l:debugger.pipes.err.annotation = "err&prg\t\t"
	call l:debugger.writeLine("set width 0")
	call l:debugger.writeLine("define hook-stop\nwhere\nend")

	if get(a:args,'pid') "Attach to process
		call l:debugger.writeLine('attach '.string(a:args.pid))
	else
		call l:debugger.writeLine('set args '.vebugger#util#commandLineArgsForProgram(a:args).' 1>&2')
		if !has('win32')
			call vebugger#std#openShellBuffer(l:debugger)
		endif
		call l:debugger.writeLine('start')
	end


	call l:debugger.addReadHandler(function('s:readProgramOutput'))
	call l:debugger.addReadHandler(function('s:readWhere'))
	call l:debugger.addReadHandler(function('s:readFinish'))
	call l:debugger.addReadHandler(function('s:readEvaluatedExpressions'))

	call l:debugger.setWriteHandler('std','flow',function('s:writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('s:writeBreakpoints'))
	call l:debugger.setWriteHandler('std','closeDebugger',function('s:closeDebugger'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('s:requestEvaluateExpression'))
	call l:debugger.setWriteHandler('std','executeStatements',function('s:executeStatements'))

	call l:debugger.generateWriteActionsFromTemplate()

	call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

	return l:debugger
endfunction

function! s:findFolderFromStackTrace(src,nameFromStackTrace)
	let l:path=a:src
	for l:dirname in split(a:nameFromStackTrace,'\.')
		let l:nextPath=l:path.'/'.fnameescape(l:dirname)
		if empty(glob(l:nextPath))
			return l:path
		endif
		let l:path=l:nextPath
	endfor
	return l:path
endfunction

function! s:readProgramOutput(pipeName,line,readResult,debugger)
	if 'err'==a:pipeName
				\&&a:line!~'\v^[=~*&^]'
				\&&a:line!~'\V(gdb)'
		let a:readResult.std.programOutput={'line':a:line}
	endif
endfunction

function! s:readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		"let l:matches=matchlist(a:line,'\v#(\d+)\s+(\S+)\s+\(.*\)\s+at\s+([^:]+):(\d+)')
		let l:matches=matchlist(a:line,'\v^\~"#(\d+)\s+(\S+)\s+\(.*\)\s+at\s+([^:]+):(\d+)')
		if 4<len(l:matches)
			let l:file=l:matches[3]
			let l:file=fnamemodify(l:file,':~:.')
			let l:frameNumber=str2nr(l:matches[1])
			if 0==l:frameNumber " first stackframe is the current location
				let a:readResult.std.location={
							\'file':(l:file),
							\'line':str2nr(l:matches[4])}
			endif
			let a:readResult.std.callstack={
						\'clearOld':('0'==l:frameNumber),
						\'add':'after',
						\'file':(l:file),
						\'line':str2nr(l:matches[4])}
		endif
	endif
endfunction

function! s:readFinish(pipeName,line,readResult,debugger)
	if a:line=~'\c\V\^~"[Inferior \.\*exited normally]'
		let a:readResult.std.programFinish={'finish':1}
	endif
endfunction

function! s:writeFlow(writeAction,debugger)
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

function! s:closeDebugger(writeAction,debugger)
	call a:debugger.writeLine('quit')
endfunction

function! s:writeBreakpoints(writeAction,debugger)
	for l:breakpoint in a:writeAction
		if 'add'==(l:breakpoint.action)
			call a:debugger.writeLine('break '.fnameescape(l:breakpoint.file).':'.l:breakpoint.line)
		elseif 'remove'==l:breakpoint.action
			call a:debugger.writeLine('clear '.fnameescape(l:breakpoint.file).':'.l:breakpoint.line)
		endif
	endfor
endfunction

function! s:requestEvaluateExpression(writeAction,debugger)
	for l:evalAction in a:writeAction
		call a:debugger.writeLine('print '.l:evalAction.expression)
	endfor
endfunction

function! s:executeStatements(writeAction,debugger)
	for l:evalAction in a:writeAction
		if has_key(l:evalAction,'statement')
			"Use eval to run the statement - but first we need to remove the ;
			call a:debugger.writeLine('print '.substitute(l:evalAction.statement,'\v;\s*$','',''))
		endif
	endfor
endfunction

function! s:readEvaluatedExpressions(pipeName,line,readResult,debugger) dict
	if 'out'==a:pipeName
		if has_key(self,'nextExpressionToBePrinted')
			let l:matches=matchlist(a:line,'\v^\~"\$(\d+) \= (.*)"$')
			if 2<len(l:matches)
				let l:expression=l:matches[1]
				let l:value=l:matches[2]
				let a:readResult.std.evaluatedExpression={
							\'expression':self.nextExpressionToBePrinted,
							\'value':(s:unescapeString(l:value))}
			endif
			call remove(self,'nextExpressionToBePrinted')
		else
			let l:matches=matchlist(a:line,'\v^\&"print (.{-})(\\r)?(\\n)?"$')
			if 1<len(l:matches)
				let self.nextExpressionToBePrinted=s:unescapeString(l:matches[1])
			endif
		endif
	endif
endfunction

function! s:unescapeString(str)
	let l:result=a:str
	let l:result=substitute(l:result,'\\"','"','g')
	let l:result=substitute(l:result,'\\t',"\t",'g')
	return l:result
endfunction
