function! vebugger#gdb#start(binaryFile,args)
	let l:debugger=vebugger#std#startDebugger(shellescape(vebugger#util#getToolFullPath('gdb',get(a:args,'version'),'gdb'))
				\.' -i mi --silent '.fnameescape(a:binaryFile))
	let l:debugger.pipes.out.bufferer = function('vebugger#gdb#readMILinesFromPipe')
	let l:debugger.state.gdb={}


	let l:debugger.pipes.err.annotation = "err&prg\t\t"
	call l:debugger.writeLine("set width 0")
	call l:debugger.writeLine("set print pretty off")
	call l:debugger.writeLine("set print array off")
	call l:debugger.writeLine("define hook-stop\nwhere\nend")

	if get(a:args,'pid') "Attach to process
		call l:debugger.writeLine('attach '.string(a:args.pid))
	elseif has_key(a:args,'con') "Attach to gdbserver
		call l:debugger.writeLine('target remote '.a:args.con)
	else
		call l:debugger.writeLine('set args '.vebugger#util#commandLineArgsForProgram(a:args).' 1>&2')
		if !has('win32')
			call vebugger#std#openShellBuffer(l:debugger)
		endif

		if has_key(a:args,'entry')
			call l:debugger.writeLine('tbreak '.a:args.entry)
			call l:debugger.writeLine('run')
		else
			call l:debugger.writeLine('start')
		endif
	end


	call l:debugger.addReadHandler(function('vebugger#gdb#_readProgramOutput'))
	call l:debugger.addReadHandler(function('vebugger#gdb#_readWhere'))
	call l:debugger.addReadHandler(function('vebugger#gdb#_readFinish'))
	call l:debugger.addReadHandler(function('vebugger#gdb#_readEvaluatedExpressions'))

	call l:debugger.setWriteHandler('std','flow',function('vebugger#gdb#_writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('vebugger#gdb#_writeBreakpoints'))
	call l:debugger.setWriteHandler('std','closeDebugger',function('vebugger#gdb#_closeDebugger'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('vebugger#gdb#_requestEvaluateExpression'))
	call l:debugger.setWriteHandler('std','executeStatements',function('vebugger#gdb#_executeStatements'))

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

function! vebugger#gdb#readMILinesFromPipe() dict
	if !has_key(self, 'tildeBuffer')
		let self.tildeBuffer = ''
	endif
	let l:result = []

	while 1
		let l:newLinePos = stridx(self.buffer, "\n")
		if l:newLinePos < 0
			break
		endif
		let l:firstChar = self.buffer[0]
		if l:firstChar == '~'
			while self.buffer[0] == '~'
				let l:newLinePos = stridx(self.buffer, "\n")
				let l:line = self.buffer[0 : l:newLinePos]
				let l:line = l:line[2 : strridx(l:line, '"') - 1]
				let self.buffer = strpart(self.buffer, l:newLinePos + 1)
				"let self.tildeBuffer .= l:line
				let l:line = substitute(l:line, '\\n', "\n", "g")
				let l:line = substitute(l:line, '\\t', "\t", "g")
				let l:line = substitute(l:line, '\\"', '"', "g")
				let self.tildeBuffer .= l:line
			endwhile
			let l:lastTildeNewLine = strridx(self.tildeBuffer, "\n")
			if 0 <= l:lastTildeNewLine
				let l:newTildeLines = split(self.tildeBuffer[: l:lastTildeNewLine - 1], '\n')
				call map(l:newTildeLines, '"~".v:val')
				let self.tildeBuffer = strpart(self.tildeBuffer, l:lastTildeNewLine + 1)
				call extend(l:result, l:newTildeLines)
			endif
			continue
		else
			if !empty(self.tildeBuffer)
				call extend(l:result, split(self.tildeBuffer, '\n'))
				let self.tildeBuffer = ''
			endif
		endif
		let l:line = self.buffer[0 : l:newLinePos]
		if l:firstChar == '&'
			let l:line = l:line[2 : strridx(l:line, '"') - 1]
			let l:line = substitute(l:line, '\\n', "\n", "g")
			let l:line = substitute(l:line, '\\t', "\t", "g")
			let l:line = substitute(l:line, '\\"', '"', "g")
			let l:line = '&'.l:line
		endif

		let l:line = substitute(l:line, '\v[\n\r]+$', '', "")
		call add(l:result, l:line)
		let self.buffer = strpart(self.buffer, l:newLinePos + 1)
	endwhile

	return l:result
endfunction

function! vebugger#gdb#_readProgramOutput(pipeName,line,readResult,debugger)
	if 'err'==a:pipeName
				\&&a:line!~'\v^[=~*&^]'
				\&&a:line!~'\V(gdb)'
		let a:readResult.std.programOutput={'line':a:line}
	endif
endfunction

function! vebugger#gdb#_readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\v^\*stopped.*fullname\=\"([^"]+)\",line\=\"(\d+)"')
		if 2<len(l:matches)
			let l:file=has('win32') ? substitute(l:matches[1], '\\\\', '\\', 'g') : l:matches[1]
			let l:file=vebugger#util#WinShellSlash(l:file)
			let l:file=fnamemodify(l:file,':p')
			let a:readResult.std.location={
						\'file':(l:file),
						\'line':str2nr(l:matches[2])}
		endif
	endif
endfunction

function! vebugger#gdb#_readFinish(pipeName,line,readResult,debugger)
	if a:line=~'\c\V*stopped\.\*exited\[ -]normally'
		let a:readResult.std.programFinish={'finish':1}
	endif
endfunction

function! vebugger#gdb#_writeFlow(writeAction,debugger)
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

function! vebugger#gdb#_closeDebugger(writeAction,debugger)
	call a:debugger.writeLine('quit')
endfunction

function! vebugger#gdb#_writeBreakpoints(writeAction,debugger)
	for l:breakpoint in a:writeAction
		if 'add'==(l:breakpoint.action)
			call a:debugger.writeLine('break '.fnameescape(l:breakpoint.file).':'.l:breakpoint.line)
		elseif 'remove'==l:breakpoint.action
			call a:debugger.writeLine('clear '.fnameescape(l:breakpoint.file).':'.l:breakpoint.line)
		endif
	endfor
endfunction

function! vebugger#gdb#_requestEvaluateExpression(writeAction,debugger)
	for l:evalAction in a:writeAction
		call a:debugger.writeLine('print '.l:evalAction.expression)
	endfor
endfunction

function! vebugger#gdb#_executeStatements(writeAction,debugger)
	for l:evalAction in a:writeAction
		if has_key(l:evalAction,'statement')
			"Use eval to run the statement - but first we need to remove the ;
			call a:debugger.writeLine('print '.substitute(l:evalAction.statement,'\v;\s*$','',''))
		endif
	endfor
endfunction

function! vebugger#gdb#_readEvaluatedExpressions(pipeName,line,readResult,debugger) dict
	if 'out' == a:pipeName
		if has_key(self, 'nextExpressionToBePrinted')
			let l:matches=matchlist(a:line,'\v^\~\$(\d+) \= (.*)$')
			if 2<len(l:matches)
				let l:expression=l:matches[1]
				let l:value=l:matches[2]
				let a:readResult.std.evaluatedExpression={
							\'expression':self.nextExpressionToBePrinted,
							\'value':(s:unescapeString(l:value))}
			endif
			call remove(self,'nextExpressionToBePrinted')
		else
			let l:matches=matchlist(a:line,'\v^\&print (.+)$')
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
