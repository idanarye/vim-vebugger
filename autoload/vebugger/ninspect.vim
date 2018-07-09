function! vebugger#ninspect#attach(connection, args)
	let l:debugger=vebugger#std#startDebugger(shellescape(vebugger#util#getToolFullPath('node',get(a:args,'version'),'node'))
				\.' inspect '.a:connection)
	let l:debugger.state.ninspect={}
	"let l:debugger.state.std.config.externalFileStop_flowCommand='stepover' "skip external modules


	call l:debugger.writeLine("$stdout=$stderr")
	let l:debugger.pipes.err.annotation = "err&prg\t\t"
	if !has('win32')
		call vebugger#std#openShellBuffer(l:debugger)
	endif

	call l:debugger.addReadHandler(function('vebugger#ninspect#_readProgramOutput'))
	call l:debugger.addReadHandler(function('vebugger#ninspect#_readWhere'))
	" call l:debugger.addReadHandler(function('vebugger#ninspect#_readEvaluatedExpressions'))
	call l:debugger.addReadHandler(function('vebugger#ninspect#_readFinish'))

	call l:debugger.setWriteHandler('std','flow',function('vebugger#ninspect#_writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('vebugger#ninspect#_writeBreakpoints'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('vebugger#ninspect#_requestEvaluateExpression'))
	" call l:debugger.setWriteHandler('std','executeStatements',function('vebugger#ninspect#_executeStatements'))
	" call l:debugger.setWriteHandler('std','removeAfterDisplayed',function('vebugger#ninspect#_removeAfterDisplayed'))
	
    call l:debugger.setWriteHandler('std','closeDebugger',function('vebugger#ninspect#_closeDebugger'))

	call l:debugger.generateWriteActionsFromTemplate()

	call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

    " Don't stop at the beginning
    " call l:debugger.writeLine('cont')

	return l:debugger
endfunction

function! vebugger#ninspect#start(entryFile,args)
	let l:debugger=vebugger#std#startDebugger(shellescape(vebugger#util#getToolFullPath('node',get(a:args,'version'),'node'))
				\.' inspect '.a:entryFile.' '.vebugger#util#commandLineArgsForProgram(a:args))
	let l:debugger.state.ninspect={}
	"let l:debugger.state.std.config.externalFileStop_flowCommand='stepover' "skip external modules


	call l:debugger.writeLine("$stdout=$stderr")
	let l:debugger.pipes.err.annotation = "err&prg\t\t"
	if !has('win32')
		call vebugger#std#openShellBuffer(l:debugger)
	endif

	call l:debugger.addReadHandler(function('vebugger#ninspect#_readProgramOutput'))
	call l:debugger.addReadHandler(function('vebugger#ninspect#_readWhere'))
	" call l:debugger.addReadHandler(function('vebugger#ninspect#_readEvaluatedExpressions'))
	call l:debugger.addReadHandler(function('vebugger#ninspect#_readFinish'))

	call l:debugger.setWriteHandler('std','flow',function('vebugger#ninspect#_writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('vebugger#ninspect#_writeBreakpoints'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('vebugger#ninspect#_requestEvaluateExpression'))
	" call l:debugger.setWriteHandler('std','executeStatements',function('vebugger#ninspect#_executeStatements'))
	" call l:debugger.setWriteHandler('std','removeAfterDisplayed',function('vebugger#ninspect#_removeAfterDisplayed'))
	
    call l:debugger.setWriteHandler('std','closeDebugger',function('vebugger#ninspect#_closeDebugger'))

	call l:debugger.generateWriteActionsFromTemplate()

	call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

    " Don't stop at the beginning
    " call l:debugger.writeLine('cont')

	return l:debugger
endfunction

function! vebugger#ninspect#_readProgramOutput(pipeName,line,readResult,debugger)
	if 'err'==a:pipeName
		let a:readResult.std.programOutput={'line':a:line}
    else
        "let l:donematch=matchlist(a:line,'\vdebug\>.............\<\sWaiting\sfor\sthe\sdebugger\sto\sdisconnect...')
        "if 1<len(l:donematch)
        "    let self.programOutputMode=0
        "    let a:readResult.std.programFinish={'finish':1}
        "else 
        "    if get(self,'programOutputMode')
                let l:matches=matchlist(a:line,'\v(^........debug\>.............|^........|^)\<\s(.*)$')
                if 3<len(l:matches)
                    let a:readResult.std.programOutput={'line':l:matches[2]}
                endif
        "    else 
        "        let l:startmatch=matchlist(a:line,'\vdebug\>')
        "        if 1<len(l:startmatch)
        "            call a:debugger.writeLine('cont') " Start by continuing
        "            let self.programOutputMode=1
        "        endif
        "    endif
        "endif
	endif
endfunction

function! vebugger#ninspect#_readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\vin\s(.*):(\d+)$')
        
        " if get(self,'programOutputMode')
        "     echom 'test'.self.programOutputMode
        " else
        "     echom 'test2'
        " endif

		if 3<len(l:matches)
			let l:file=l:matches[1]
            let l:line=str2nr(l:matches[2])
            let a:readResult.std.location={
                        \'file':(l:file),
                        \'line':(l:line)}
		endif
	endif
endfunction

function! vebugger#ninspect#_readFinish(pipeName,line,readResult,debugger)
    let l:matches=matchlist(a:line,'\vdebug\>.............\<\sWaiting\sfor\sthe\sdebugger\sto\sdisconnect...')
	if 1<len(l:matches)
		let a:readResult.std.programFinish={'finish':1}
    endif
endfunction

function! vebugger#ninspect#_closeDebugger(writeAction,debugger)
	call a:debugger.writeLine('kill')
	sign unplace 1
    call vebugger#killDebugger()
endfunction

function! vebugger#ninspect#_writeFlow(writeAction,debugger)
	if 'stepin'==a:writeAction
		call a:debugger.writeLine('step')
	elseif 'stepover'==a:writeAction
		call a:debugger.writeLine('next')
	elseif 'stepout'==a:writeAction
		call a:debugger.writeLine('out')
	elseif 'continue'==a:writeAction
		call a:debugger.writeLine('cont')
	endif
endfunction

function! vebugger#ninspect#_writeBreakpoints(writeAction,debugger)
	for l:breakpoint in a:writeAction
		if 'add'==(l:breakpoint.action)
			call a:debugger.writeLine('sb('''.fnameescape(l:breakpoint.file).''','.l:breakpoint.line.')')
		elseif 'remove'==l:breakpoint.action
			call a:debugger.writeLine('cb('''.fnameescape(l:breakpoint.file).''','.l:breakpoint.line.')')
		endif
	endfor
endfunction

function! vebugger#ninspect#_requestEvaluateExpression(writeAction,debugger)
	for l:evalAction in a:writeAction
		call a:debugger.std_addLineToShellBuffer('Eval: '.l:evalAction.expression)
		call a:debugger.writeLine('exec console.log(JSON.stringify('.l:evalAction.expression.', null, 2))')
		"call a:debugger.writeLine('exec JSON.stringify('.l:evalAction.expression.', null, 2)')
	endfor
endfunction

function! vebugger#ninspect#_executeStatements(writeAction,debugger)
	for l:evalAction in a:writeAction
		if has_key(l:evalAction,'statement')
			call a:debugger.std_addLineToShellBuffer('Execute: '.l:evalAction.expression)
			call a:debugger.writeLine(l:evalAction.statement)
		endif
	endfor
endfunction

function! vebugger#ninspect#_readEvaluatedExpressions(pipeName,line,readResult,debugger)
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

" function! vebugger#ninspect#_removeAfterDisplayed(writeAction,debugger)
" 	for l:removeAction in a:writeAction
" 		if has_key(l:removeAction,'id')
" 			call a:debugger.writeLine('undisplay '.l:removeAction.id)
" 		endif
" 	endfor
" endfunction

" function! s:unescapeString(str)
" 	let l:result=a:str
" 	let l:result=substitute(l:result,'\\"','"','g')
" 	let l:result=substitute(l:result,'\\t',"\t",'g')
" 	return l:result
" endfunction
