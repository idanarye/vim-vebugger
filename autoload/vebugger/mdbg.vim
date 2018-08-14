function! vebugger#mdbg#searchAndAttach(binaryFile,srcpath)
    let l:processId=vebugger#util#selectProcessOfFile(a:binaryFile)
    if 0<l:processId
	call vebugger#mdbg#start(a:binaryFile,{'srcpath':a:srcpath,'pid':l:processId})
    endif
endfunction

function! vebugger#mdbg#start(binaryFile,args)
    let l:debugger=vebugger#std#startDebugger(shellescape(vebugger#util#getToolFullPath('mdbg',get(a:args,'version'),'Mdbg')))
    let l:debugger.state.mdbg={'breakpointNumbers':{}}
    let l:debugger.readResultTemplate.mdbg={'breakpointBound':{}}

    if has_key(a:args,'srcpath')
	let l:debugger.state.mdbg.srcpath=a:args.srcpath
    else
	let l:debugger.state.mdbg.srcpath='.'
    endif

    call l:debugger.writeLine('when StepComplete do where')
    call l:debugger.writeLine('when BreakpointHit do where')


    if get(a:args,'pid') "Attach to process
	call l:debugger.writeLine('attach '.string(a:args.pid))
    else
	if !get(a:args,'noConsole')
	    call l:debugger.writeLine('mode nc on')
	endif
	call l:debugger.writeLine('run "'.s:pathToMdbgStyle(fnamemodify(a:binaryFile, ':p')).'" '.vebugger#util#commandLineArgsForProgram(a:args))
	call l:debugger.writeLine('where')
    end
    call l:debugger.addReadHandler(function('vebugger#mdbg#_readProgramOutput'))
    call l:debugger.addReadHandler(function('vebugger#mdbg#_readWhere'))
    call l:debugger.addReadHandler(function('vebugger#mdbg#_readFinish'))
    call l:debugger.addReadHandler(function('vebugger#mdbg#_readEvaluatedExpressions'))
    call l:debugger.addReadHandler(function('vebugger#mdbg#_readBreakpointBound'))

    call l:debugger.addThinkHandler(function('s:breakpointAdded'))

    call l:debugger.setWriteHandler('std','flow',function('vebugger#mdbg#_writeFlow'))
    call l:debugger.setWriteHandler('std','breakpoints',function('vebugger#mdbg#_writeBreakpoints'))
    call l:debugger.setWriteHandler('std','closeDebugger',function('vebugger#mdbg#_closeDebugger'))
    call l:debugger.setWriteHandler('std','evaluateExpressions',function('vebugger#mdbg#_requestEvaluateExpression'))
    call l:debugger.setWriteHandler('std','executeStatements',function('vebugger#mdbg#_executeStatements'))

    call l:debugger.generateWriteActionsFromTemplate()

    call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

    return l:debugger
endfunction

function! s:pathToMdbgStyle(path)
    if has('win32unix')
	return substitute(system('cygpath -w '.shellescape(a:path)),'\n$','','')
    else
	return a:path
    endif
endfunction

function! s:pathToVimStyle(path)
    if has('win32unix')
	return substitute(system('cygpath -u '.shellescape(a:path)),'\n$','','')
    else
	return a:path
    endif
endfunction

function! s:findFilePath(src,fileName,methodName)
    let l:fileName = s:pathToVimStyle(a:fileName)
    if vebugger#util#isPathAbsolute(l:fileName)
	return fnamemodify(l:fileName,':p') "Return the normalized full path
    endif
    let l:path=fnamemodify(a:src,':p')
    let l:files=glob(l:path.'**/'.l:fileName,0,1)
    for l:dirname in split(a:methodName,'\.')
	if empty(l:files)
	    return ''
	endif
	if 1==len(l:files)
	    return l:files[0]
	endif
	let l:path=fnamemodify(l:path.l:dirname,':p')
	let l:files=filter(l:files,'-1<stridx(v:val,l:path)')
    endfor
    return ''
endfunction

function! vebugger#mdbg#_readProgramOutput(pipeName,line,readResult,debugger)
endfunction

function! vebugger#mdbg#_readWhere(pipeName,line,readResult,debugger)
    if 'out'==a:pipeName
	let l:matches=matchlist(a:line,'\v^\*(\d+)\.\s*([A-Za-z0-9_.+<>]+)\s*\((.+):(\d+)\)')
	if 3<len(l:matches)
	    let l:frameNumber=str2nr(l:matches[1])
	    let l:file=s:findFilePath(a:debugger.state.mdbg.srcpath,l:matches[3],l:matches[2])
	    let l:file=fnamemodify(l:file,':p')
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

function! vebugger#mdbg#_readFinish(pipeName,line,readResult,debugger)
    if a:line=~'\VSTOP: Process Exited\$'
	let a:readResult.std.programFinish={'finish':1}
    endif
endfunction

function! vebugger#mdbg#_writeFlow(writeAction,debugger)
    if 'stepin'==a:writeAction
	call a:debugger.writeLine('step')
    elseif 'stepover'==a:writeAction
	call a:debugger.writeLine('next')
    elseif 'stepout'==a:writeAction
	call a:debugger.writeLine('out')
    elseif 'continue'==a:writeAction
	call a:debugger.writeLine('go')
    endif
endfunction

function! vebugger#mdbg#_closeDebugger(writeAction,debugger)
    call a:debugger.writeLine('quit')
endfunction

function! vebugger#mdbg#_writeBreakpoints(writeAction,debugger)
    for l:breakpoint in a:writeAction
	let l:fullFileName=fnamemodify(l:breakpoint.file,':p')
	if 'add'==(l:breakpoint.action)
	    call a:debugger.writeLine('break '.s:pathToMdbgStyle(l:fullFileName).':'.l:breakpoint.line)
	    let a:debugger.state.mdbg.breakpointNumbers[s:pathToVimStyle(l:fullFileName).':'.l:breakpoint.line]={}
	elseif 'remove'==l:breakpoint.action
	    call a:debugger.writeLine('delete '.a:debugger.state.mdbg.breakpointNumbers[l:fullFileName.':'.l:breakpoint.line].number)
	    call remove(a:debugger.state.mdbg.breakpointNumbers,l:fullFileName.':'.l:breakpoint.line)
	endif
    endfor
endfunction

function! vebugger#mdbg#_readBreakpointBound(pipeName,line,readResult,debugger)
    if 'out'==a:pipeName
	let l:matches=matchlist(a:line,'\vBreakpoint \#(\d+) bound\s*\(line (\d+) in ([^)]+)\)')
	if 3<len(l:matches)
	    let a:readResult.mdbg.breakpointBound={
			\'fileNameTail':s:pathToVimStyle(l:matches[3]),
			\'line':l:matches[2],
			\'breakpointNumber':l:matches[1]}
	endif
    endif
endfunction

function! s:breakpointAdded(readResult,debugger)
    if !empty(a:readResult.mdbg.breakpointBound)
	let l:breakpointBound=a:readResult.mdbg.breakpointBound
	let l:lookFor=l:breakpointBound.fileNameTail.':'.l:breakpointBound.line
	let l:lookForRegex='\V'.escape(l:lookFor,'\').'\$'
	let l:matchingKeys=filter(keys(a:debugger.state.mdbg.breakpointNumbers),'v:val=~l:lookForRegex')
	for l:key in l:matchingKeys
	    if empty(a:debugger.state.mdbg.breakpointNumbers[l:key])
		let a:debugger.state.mdbg.breakpointNumbers[l:key]={'number':l:breakpointBound.breakpointNumber}
	    endif
	endfor
    endif
endfunction

function! vebugger#mdbg#_requestEvaluateExpression(writeAction,debugger)
    for l:evalAction in a:writeAction
	call a:debugger.writeLine('print '.l:evalAction.expression)
    endfor
endfunction

function! vebugger#mdbg#_executeStatements(writeAction,debugger)
    for l:evalAction in a:writeAction
	if has_key(l:evalAction,'statement')
	    call a:debugger.writeLine('set '.substitute(l:evalAction.statement,'\v;\s*$','',''))
	endif
    endfor
endfunction

function! vebugger#mdbg#_readEvaluatedExpressions(pipeName,line,readResult,debugger) dict
    if 'out'==a:pipeName
	let l:matches=matchlist(a:line,'\v\[[^\]]*\]\s*mdbg\>\s*([^=]+)\=(.*)$')
	if 2<len(l:matches)
	    let l:expression=l:matches[1]
	    let l:value=l:matches[2]
	    let a:readResult.std.evaluatedExpression={
			\'expression':l:expression,
			\'value':l:value}
	endif
    endif
endfunction
