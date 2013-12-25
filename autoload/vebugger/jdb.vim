
function! vebugger#jdb#start(entryClass,args)
	let l:debugger=vebugger#std#startDebugger('jdb'.(
				\has_key(a:args,'classpath')
				\? ' -classpath '.fnameescape(a:args.classpath)
				\: ''))
	if has_key(a:args,'srcpath')
		let l:debugger.state.std.srcpath=a:args.srcpath
	endif
	call l:debugger.showLogBuffer()
	call l:debugger.writeLine('stop on '.a:entryClass.'.main')
	call l:debugger.writeLine('run '.a:entryClass)
	call l:debugger.writeLine('monitor where')

	call l:debugger.addReadHandler(function('s:readWhere'))

	return l:debugger
endfunction

function! s:readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\v\s*\[\d+\]\s*[^\s]+\s*\(([^:]*):(\d*)\)')
		if 3<=len(l:matches)
			let a:readResult.std.location={
						\'file':(a:debugger.std_relativeSrcPath(l:matches[1])),
						\'line':(l:matches[2])}
		endif
	end
endfunction
