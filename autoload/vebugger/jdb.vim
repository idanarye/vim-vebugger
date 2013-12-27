
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
			if '1'==l:matches[1] " check that this is the innermost stackframe
				let l:file=s:findFolderFromStackTrace(a:debugger.state.std.srcpath,l:matches[2]).'/'.l:matches[3]
				let l:file=fnamemodify(l:file,':~:.')
				let a:readResult.std.location={
							\'file':(l:file),
							\'line':(l:matches[4])}
			endif
		endif
	end
endfunction
