function! vebugger#jdb#start(entryClass,args)
	let l:debugger=vebugger#std#startDebugger(shellescape(vebugger#util#getToolFullPath('jdb',get(a:args,'version'),'jdb'))
				\.(has_key(a:args,'classpath') && !has_key(a:args,'attach') ? ' -classpath '.fnameescape(a:args.classpath) : '')
				\.(has_key(a:args,'attach') ? ' -attach '.shellescape(a:args.attach) : ''))
	let l:debugger.state.jdb={}
	if has_key(a:args,'srcpath')
		let l:debugger.state.jdb.srcpath=a:args.srcpath
	else
		let l:debugger.state.jdb.srcpath='.'
	endif
	let l:debugger.state.jdb.filesToClassesMap={}

	if !has_key(a:args,'attach')
		call l:debugger.writeLine('stop on '.a:entryClass.'.main')
		call l:debugger.writeLine('run  '.a:entryClass.' '.vebugger#util#commandLineArgsForProgram(a:args))
	else
		call l:debugger.writeLine('run')
	endif
	call l:debugger.writeLine('monitor where')
	if !has('win32') && !has_key(a:args,'attach')
		call vebugger#std#openShellBuffer(l:debugger)
	endif

	call l:debugger.addReadHandler(function('vebugger#jdb#_readProgramOutput'))
	call l:debugger.addReadHandler(function('vebugger#jdb#_readWhere'))
	call l:debugger.addReadHandler(function('vebugger#jdb#_readException'))
	call l:debugger.addReadHandler(function('vebugger#jdb#_readEvaluatedExpressions'))

	call l:debugger.setWriteHandler('std','flow',function('vebugger#jdb#_writeFlow'))
	call l:debugger.setWriteHandler('std','breakpoints',function('vebugger#jdb#_writeBreakpoints'))
	call l:debugger.setWriteHandler('std','evaluateExpressions',function('vebugger#jdb#_requestEvaluateExpression'))
	call l:debugger.setWriteHandler('std','executeStatements',function('vebugger#jdb#_executeStatements'))

	call l:debugger.generateWriteActionsFromTemplate()

	call l:debugger.std_addAllBreakpointActions(g:vebugger_breakpoints)

	return l:debugger
endfunction

function! vebugger#jdb#attach(address, ...)
	let l:args = a:0 ? a:{1} : {}
	let l:args.attach = a:address
	call vebugger#jdb#start('', l:args)
endfunction

function! vebugger#jdb#_readProgramOutput(pipeName,line,readResult,debugger) dict
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

function! s:getTagContainingString(tag, str)
  let l:tags = taglist(a:tag)
  if (len(l:tags) > 0)
    for l:tag in l:tags
      if (filereadable(l:tag.filename) && match(readfile(l:tag.filename), a:str) >= 0)
        return l:tag
      endif
    endfor
  endif
  return {}
endfunction

function! s:findFolderFromStackTrace(src,nameFromStackTrace,frameNumber)
  " Remove method name.
  let l:canonicalClassName = strpart(a:nameFromStackTrace, 0, strridx(a:nameFromStackTrace, "."))
  " Remove package name.
  let l:simpleClassName = strridx(l:canonicalClassName, ".") >= 0 ? strpart(l:canonicalClassName, strridx(l:canonicalClassName, ".") + 1) : l:canonicalClassName
  " Remove class name.
  let l:package = strridx(l:canonicalClassName, ".") >= 0 ? strpart(l:canonicalClassName, 0, strridx(l:canonicalClassName, ".")) : ""

  " We don't really use callstack, so we use tags only for the current location.
  " Otherwise it makes everything too slow.
  if exists('g:vebugger_use_tags') && g:vebugger_use_tags && a:frameNumber == 1
    " Now first try to find a tag for the class from the required package.
    let l:classTag = s:getTagContainingString(l:simpleClassName, l:package)
    if (has_key(l:classTag, "filename"))
      return fnamemodify(l:classTag.filename, ":h")
    endif
  endif

  " If no such tag was found, try to find it using the src path.
  for l:path in vebugger#util#listify(a:src)
    for l:dirname in split(a:nameFromStackTrace,'\.')
      let l:nextPath=l:path.'/'.fnameescape(l:dirname)
      if empty(glob(l:nextPath))
        return l:path
      endif
      let l:path=l:nextPath
    endfor
  endfor
	return l:path
endfunction

function! vebugger#jdb#_readWhere(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\v\s*\[(\d+)]\s*(\S+)\s*\(([^:]*):(\d*)\)')
		if 4<len(l:matches)
			let l:frameNumber=str2nr(l:matches[1])
			let l:file=s:findFolderFromStackTrace(a:debugger.state.jdb.srcpath,l:matches[2],l:frameNumber).'/'.l:matches[3]
			let l:file=fnamemodify(l:file,':p')
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

function! vebugger#jdb#_readException(pipeName,line,readResult,debugger)
	if 'out'==a:pipeName
		let l:matches=matchlist(a:line,'\vException occurred:\s+(\S+)')
		if 1<len(l:matches)
			let a:readResult.std.exception={
						\'message':(l:matches[1])}
		endif
	endif
endfunction

function! vebugger#jdb#_writeFlow(writeAction,debugger)
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
    " trailing ; is optional to make it work for groovy as well
		let l:matches=matchlist(l:line,'\vpackage\s+(%(\w|\.)+)\s*;?')
		if 1<len(l:matches)
			return l:matches[1].'.'.l:className
		endif
	endfor
	return l:className
endfunction

function! vebugger#jdb#_writeBreakpoints(writeAction,debugger)
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

function! vebugger#jdb#_requestEvaluateExpression(writeAction,debugger)
	for l:evalAction in a:writeAction
		call a:debugger.writeLine('eval '.l:evalAction.expression)
	endfor
endfunction

function! vebugger#jdb#_executeStatements(writeAction,debugger)
	for l:evalAction in a:writeAction
		if has_key(l:evalAction,'statement')
			"Use eval to run the statement - it works!
			call a:debugger.writeLine('eval '.l:evalAction.statement)
		endif
	endfor
endfunction

function! vebugger#jdb#_readEvaluatedExpressions(pipeName,line,readResult,debugger)
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
