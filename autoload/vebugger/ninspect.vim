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
	call l:debugger.addReadHandler(function('vebugger#ninspect#_readEvaluatedExpressions'))
	call l:debugger.addReadHandler(function('vebugger#ninspect#_readFinish'))

	call l:debugger.setWriteHandler('std','flow',function('vebugger#ninspect#_writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('vebugger#ninspect#_writeBreakpoints'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('vebugger#ninspect#_requestEvaluateExpression'))
	" call l:debugger.setWriteHandler('std','executeStatements',function('vebugger#ninspect#_executeStatements'))
	" call l:debugger.setWriteHandler('std','removeAfterDisplayed',function('vebugger#ninspect#_removeAfterDisplayed'))
	
    call l:debugger.setWriteHandler('std','closeDebugger',function('vebugger#ninspect#_closeDebugger'))

	call l:debugger.generateWriteActionsFromTemplate()

	" call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

    " Don't stop at the beginning
    " call l:debugger.writeLine('cont')

    let s:programOutputMode=0
    let s:programEvalMode=0
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
    call l:debugger.addReadHandler(function('vebugger#ninspect#_readEvaluatedExpressions'))
	call l:debugger.addReadHandler(function('vebugger#ninspect#_readFinish'))

	call l:debugger.setWriteHandler('std','flow',function('vebugger#ninspect#_writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('vebugger#ninspect#_writeBreakpoints'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('vebugger#ninspect#_requestEvaluateExpression'))
	" call l:debugger.setWriteHandler('std','executeStatements',function('vebugger#ninspect#_executeStatements'))
	" call l:debugger.setWriteHandler('std','removeAfterDisplayed',function('vebugger#ninspect#_removeAfterDisplayed'))
	
    call l:debugger.setWriteHandler('std','closeDebugger',function('vebugger#ninspect#_closeDebugger'))

	call l:debugger.generateWriteActionsFromTemplate()

    " call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)
    " Don't stop at the beginning
    " call l:debugger.writeLine('cont')
    let s:programOutputMode=0
    let s:programEvalMode=0
	return l:debugger
endfunction

function! vebugger#ninspect#_readProgramOutput(pipeName,line,readResult,debugger)
    " echom a:line
	if 'err'==a:pipeName
		let a:readResult.std.programOutput={'line':a:line}
    else
        let l:donematch=matchlist(a:line,'\vdebug\>.............\<\sWaiting\sfor\sthe\sdebugger\sto\sdisconnect...')
        if 1<len(l:donematch)
            let s:programOutputMode=0
        else 
            if s:programOutputMode
                let l:matches=matchlist(a:line,'\v(^........debug\>.............|^........|^)\<\s(.*)$')
                if 3<len(l:matches)
                    let a:readResult.std.programOutput={'line':l:matches[2]}
                endif
            else 
                let l:startmatch=matchlist(a:line,'\vfunction')
                if 1<len(l:startmatch)
                    call a:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)
                    call a:debugger.writeLine('cont') " Start by continuing
                    let s:programOutputMode=1
                endif
            endif
        endif
	endif
endfunction

function! vebugger#ninspect#_readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName 
        if s:programOutputMode
            let l:matches=matchlist(a:line,'\vin\s(.*):(\d+)$')

            if 3<len(l:matches)
                let l:file=l:matches[1]
                let l:line=str2nr(l:matches[2])
                let a:readResult.std.location={
                            \'file':(l:file),
                            \'line':(l:line)}
            endif
        endif
	endif
endfunction

function! vebugger#ninspect#_readFinish(pipeName,line,readResult,debugger)
    let l:matches=matchlist(a:line,'\vdebug\>.............\<\sWaiting\sfor\sthe\sdebugger\sto\sdisconnect...|Error:\sThis\ssocket\shas\sbeen\sended\sby\sthe\sother\sparty')
	if 1<len(l:matches)
        let s:programOutputMode=0
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
        if get(g:,'vebugger_ninspect_eval_out_to_console', 0) 
            call a:debugger.std_addLineToShellBuffer('Eval: '.l:evalAction.expression)
        endif
		"call a:debugger.writeLine('exec console.log(JSON.stringify('.l:evalAction.expression.', null, 2))')
        if get(g:,'vebugger_ninspect_eval_out_to_console', 0) 
            call a:debugger.writeLine('exec (function(){var glbCacheForEval123abf = [];let ret = JSON.stringify('.l:evalAction.expression.', function(key,value){if(typeof value===''object''&&value!==null){if(glbCacheForEval123abf.indexOf(value)!==-1){try{return JSON.parse(JSON.stringify(value))}catch(error){return}}glbCacheForEval123abf.push(value)}return value}, 2);console.log(ret);return ret;})()')
        else 
            call a:debugger.writeLine('exec (function(){var glbCacheForEval123abf = [];let ret = JSON.stringify('.l:evalAction.expression.', function(key,value){if(typeof value===''object''&&value!==null){if(glbCacheForEval123abf.indexOf(value)!==-1){try{return JSON.parse(JSON.stringify(value))}catch(error){return}}glbCacheForEval123abf.push(value)}return value}, 2);return ret;})()')
        endif
		"call a:debugger.writeLine('exec JSON.stringify('.l:evalAction.expression.', null, 2)')
        let s:programEvalMode=1
        let s:programEvalModeExpression=''.l:evalAction.expression
	endfor
endfunction

function! vebugger#ninspect#_executeStatements(writeAction,debugger)
	for l:evalAction in a:writeAction
		if has_key(l:evalAction,'statement')
			call a:debugger.std_addLineToShellBuffer('Execute: '.l:evalAction.expression)
			call a:debugger.writeLine(l:evalAction.statement)
            let s:programEvalMode=1
            let s:programEvalModeExpression=''.l:evalAction.statement
		endif
	endfor
endfunction

function! vebugger#ninspect#_readEvaluatedExpressions(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		if s:programEvalMode
            let s:programEvalMode=s:programEvalMode+1
        endif
		if s:programEvalMode>3
            let s:programEvalMode=0
			let l:expression=s:programEvalModeExpression
			let l:value=a:line
			let a:readResult.std.evaluatedExpression={
						\'expression':(l:expression),
						\'value':(l:value)}
		endif
	endif
endfunction

function! s:unescapeString(str)
	let l:result=a:str
	let l:result=substitute(l:result,'\\n','\r','g')
	let l:result=substitute(l:result, '\e\[[0-9;]\+[mK]', '', 'g')
	return l:result
endfunction
