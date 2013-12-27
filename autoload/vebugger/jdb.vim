function! vebugger#jdb#start(entryClass,args)
	let l:debugger=vebugger#std#startDebugger('jdb'.(
				\has_key(a:args,'classpath')
				\? ' -classpath '.fnameescape(a:args.classpath)
				\: ''))
	if has_key(a:args,'srcpath')
		let l:debugger.state.std.srcpath=a:args.srcpath
	endif
	call l:debugger.writeLine('stop on '.a:entryClass.'.main')
	call l:debugger.writeLine('run '.a:entryClass)
	call l:debugger.writeLine('monitor where')

	call l:debugger.addReadHandler(function('s:readWhere'))

	call l:debugger.setWriteHandler('std','flow',function('s:writeFlow'))

	call l:debugger.generateWriteActionsFromTemplate()

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

function! s:readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\v\s*\[(\d+)]\s*(\S+)\s*\(([^:]*):(\d*)\)')
		if 4<len(l:matches)
			let l:file=s:findFolderFromStackTrace(a:debugger.state.std.srcpath,l:matches[2]).'/'.l:matches[3]
			let l:file=fnamemodify(l:file,':~:.')
			let l:frameNumber=str2nr(l:matches[1])
			if 1==l:frameNumber " first stackframe is the current location
				let a:readResult.std.location={
							\'file':(l:file),
							\'line':(l:matches[4])}
			endif
			let a:readResult.std.callstack={
						\'clearOld':('1'==l:frameNumber),
						\'add':'after',
						\'file':(l:file),
						\'line':(l:matches[4])}
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
