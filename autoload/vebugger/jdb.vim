function! vebugger#jdb#start(entryClass,args)
	let l:debugger=vebugger#std#startDebugger(shellescape(vebugger#util#getToolFullPath('jdb',get(a:args,'version'),'jdb'))
				\.(has_key(a:args,'classpath') ? ' -classpath '.fnameescape(a:args.classpath) : ''))
	let l:debugger.state.jdb={}
	if has_key(a:args,'srcpath')
		let l:debugger.state.jdb.srcpath=a:args.srcpath
	else
		let l:debugger.state.jdb.srcpath='.'
	endif
	let l:debugger.state.jdb.filesToClassesMap={}

	call l:debugger.writeLine('stop on '.a:entryClass.'.main')
	call l:debugger.writeLine('run  '.a:entryClass.' '.vebugger#util#commandLineArgsForProgram(a:args))
	call l:debugger.writeLine('monitor where')
	if !has('win32')
		call vebugger#std#openShellBuffer(l:debugger)
	endif

	call l:debugger.addReadHandler(function('s:readProgramOutput'))
	call l:debugger.addReadHandler(function('s:readWhere'))
	call l:debugger.addReadHandler(function('s:readException'))
	call l:debugger.addReadHandler(function('s:readEvaluatedExpressions'))

	call l:debugger.setWriteHandler('std','flow',function('s:writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('s:writeBreakpoints'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('s:requestEvaluateExpression'))
	call l:debugger.setWriteHandler('std','executeStatements',function('s:executeStatements'))

	call l:debugger.generateWriteActionsFromTemplate()

	call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

	return l:debugger
endfunction

function! s:readProgramOutput(pipeName,line,readResult,debugger) dict
	if 'out'==a:pipeName
		if a:line=~'\v^\> \>'
					\||a:line=='> '
					\||a:line=~'\v^Step completed'
					\||a:line=~'\v^Breakpoint hit'
					\||a:line=~'\v^\> Deferring breakpoint'
					\||a:line=='Nothing suspended.'
					\||a:line=~'\v^\> run  ' "Signs that the output finished
			let self.programOutputMode=0
		elseif a:line=~'\v(step|step up|next|cont)$' "Next line should be output
			let self.programOutputMode=1
		elseif a:line=~'\v^\> [^>]' "Start of output
			let a:readResult.std.programOutput={'line':substitute(a:line,'\v^\> ','','')}
			let self.programOutputMode=1
		elseif get(self,'programOutputMode')
			let a:readResult.std.programOutput={'line':a:line}
		endif
	else
		let a:readResult.std.programOutput={'line':a:line}
	endif
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

function! s:readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\v\s*\[(\d+)]\s*(\S+)\s*\(([^:]*):(\d*)\)')
		if 4<len(l:matches)
			let l:file=s:findFolderFromStackTrace(a:debugger.state.jdb.srcpath,l:matches[2]).'/'.l:matches[3]
			let l:file=fnamemodify(l:file,':~:.')
			let l:frameNumber=str2nr(l:matches[1])
			if 1==l:frameNumber " first stackframe is the current location
				let a:readResult.std.location={
							\'file':(l:file),
							\'line':str2nr(l:matches[4])}
			endif
			let a:readResult.std.callstack={
						\'clearOld':('1'==l:frameNumber),
						\'add':'after',
						\'file':(l:file),
						\'line':str2nr(l:matches[4])}
		endif
	endif
endfunction

function! s:readException(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\vException occurred:\s+(\S+)')
		if 1<len(l:matches)
			let a:readResult.std.exception={
						\'message':(l:matches[1])}
		endif
	endif
endfunction

function! s:writeFlow(writeAction,debugger)
	if 'stepin'==a:writeAction
		call a:debugger.writeLine('step')
	elseif 'stepover'==a:writeAction
		call a:debugger.writeLine('next')
	elseif 'stepout'==a:writeAction
		call a:debugger.writeLine('step up')
	elseif 'continue'==a:writeAction
		call a:debugger.writeLine('cont')
	endif
endfunction

function! s:getClassNameFromFile(filename)
	let l:className=fnamemodify(a:filename,':t:r') " Get only the name of the file, without path or extension
	for l:line in readfile(a:filename)
		let l:matches=matchlist(l:line,'\vpackage\s+(%(\w|\.)+)\s*;')
		if 1<len(l:matches)
			return l:matches[1].'.'.l:className
		endif
	endfor
	return l:className
endfunction

function! s:writeBreakpoints(writeAction,debugger)
	for l:breakpoint in a:writeAction
		let l:class=''
		if has_key(a:debugger.state.jdb.filesToClassesMap,l:breakpoint.file)
			let l:class=a:debugger.state.jdb.filesToClassesMap[l:breakpoint.file]
		else
			let l:class=s:getClassNameFromFile(l:breakpoint.file)
			let a:debugger.state.jdb.filesToClassesMap[l:breakpoint.file]=l:class
		endif

		if 'add'==(l:breakpoint.action)
			call a:debugger.writeLine('stop at '.l:class.':'.l:breakpoint.line)
		elseif 'remove'==l:breakpoint.action
			call a:debugger.writeLine('clear '.l:class.':'.l:breakpoint.line)
		endif
	endfor
endfunction

function! s:requestEvaluateExpression(writeAction,debugger)
	for l:evalAction in a:writeAction
		call a:debugger.writeLine('eval '.l:evalAction.expression)
	endfor
endfunction

function! s:executeStatements(writeAction,debugger)
	for l:evalAction in a:writeAction
		if has_key(l:evalAction,'statement')
			"Use eval to run the statement - it works!
			call a:debugger.writeLine('eval '.l:evalAction.statement)
		endif
	endfor
endfunction

function! s:readEvaluatedExpressions(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\v^%(\s*%(%(%(\w|\.)+)\[\d+\] )+)? ([^=]+) \= (.*)$')
		if 3<len(l:matches)
			let l:expression=l:matches[1]
			let l:value=l:matches[2]
			let a:readResult.std.evaluatedExpression={
						\'expression':(l:expression),
						\'value':(l:value)}
		endif
	endif
endfunction
