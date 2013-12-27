function! vebugger#std#setStandardState(debugger)
	let a:debugger.state.std={
				\'srcpath':'.',
				\'location':{},
				\'callstack':[]}
endfunction

function! vebugger#std#setStandardReadResultTemplate(debugger)
	let a:debugger.readResultTemplate.std={
				\'location':{},
				\'callstack':{}}
endfunction

function! vebugger#std#setStandardWriteactionsTemplate(debugger)
	let a:debugger.writeActionsTemplate.std={
				\'flow':''}
endfunction

function! vebugger#std#addStandardFunctions(debugger)
	for l:k in keys(s:standardFunctions)
		let a:debugger['std_'.l:k]=s:standardFunctions[l:k]
	endfor
endfunction

function! vebugger#std#addStandardThinkHandlers(debugger)
	for l:ThinkHandler in values(s:standardThinkHandlers)
		call a:debugger.addThinkHandler(l:ThinkHandler)
	endfor
endfunction

function! vebugger#std#addStandardCloseHandlers(debugger)
	for l:CloseHandler in values(s:standardCloseHandlers)
		call a:debugger.addCloseHandler(l:CloseHandler)
	endfor
endfunction

function! vebugger#std#standardInit(debugger)
	call vebugger#std#setStandardState(a:debugger)
	call vebugger#std#setStandardReadResultTemplate(a:debugger)
	call vebugger#std#setStandardWriteactionsTemplate(a:debugger)
	call vebugger#std#addStandardFunctions(a:debugger)
	call vebugger#std#addStandardThinkHandlers(a:debugger)
	call vebugger#std#addStandardCloseHandlers(a:debugger)
endfunction

function! vebugger#std#startDebugger(command)
	let l:debugger=vebugger#startDebugger(a:command)

	call vebugger#std#standardInit(l:debugger)

	return l:debugger
endfunction



let s:standardFunctions={}
function s:standardFunctions.relativeSrcPath(filename) dict
	return fnamemodify(self.state.std.srcpath.'/'.a:filename,':~:.')
endfunction

let s:standardThinkHandlers={}
function! s:standardThinkHandlers.moveToCurrentLine(readResult,debugger) dict
	if !empty(a:readResult.std.location)
		if a:debugger.state.std.location!=a:readResult.std.location
			if has_key(a:debugger.state.std.location,'file')
				exe 'sign unplace 1 file='.fnameescape(a:debugger.state.std.location.file)
			endif
			let a:debugger.state.std.location=deepcopy(a:readResult.std.location)
			if !bufexists(a:readResult.std.location.file)
				exe 'new '.(a:readResult.std.location.file)
			endif
			call vebugger#std#updateMarksForFile(a:debugger.state,a:readResult.std.location.file)
			exe 'sign jump 1 file='.fnameescape(a:readResult.std.location.file)
		endif
	endif
endfunction

function! s:standardThinkHandlers.updateCallStack(readResult,debugger) dict
	let l:callstack=a:readResult.std.callstack
	if !empty(l:callstack)
		if get(l:callstack,'clearOld')
			let a:debugger.state.std.callstack=[]
		endif
		let l:frame={'file':(l:callstack.file),'line':(l:callstack.line)}
		if 'after'==get(l:callstack,'add')
			call add(a:debugger.state.std.callstack,l:frame)
		elseif 'before'==get(l:callstack,'add')
			call insert(a:debugger.state.std.callstack,l:frame)
		endif
	endif
endfunction

let s:standardCloseHandlers={}
function! s:standardCloseHandlers.removeCurrentMarker(debugger) dict
	sign unplace 1
endfunction

sign define vebugger_current text=->
function! vebugger#std#updateMarksForFile(state,filename)
	if bufexists(a:filename)
		exe 'sign unplace * file='.fnameescape(a:filename)
		if !empty(a:state.std.location)
			if a:state.std.location.file==a:filename
				exe 'sign place 1 name=vebugger_current line='.a:state.std.location.line.' file='.fnameescape(a:filename)
			endif
		endif
	endif
endfunction
