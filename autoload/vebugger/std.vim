let g:vebugger_breakpoints=[]

function! vebugger#std#setStandardState(debugger)
	let a:debugger.state.std={
				\'config':{
				\	'externalFileStop_flowCommand':''},
				\'location':{},
				\'callstack':[],
				\'evaluateExpressions':[]}
endfunction

function! vebugger#std#setStandardReadResultTemplate(debugger)
	let a:debugger.readResultTemplate.std={
				\'programOutput':{},
				\'location':{},
				\'callstack':{},
				\'evaluatedExpression':{},
				\'programFinish':{},
				\'exception':{}}
endfunction

function! vebugger#std#setStandardWriteactionsTemplate(debugger)
	let a:debugger.writeActionsTemplate.std={
				\'flow':'',
				\'breakpoints':[],
				\'evaluateExpressions':[],
				\'executeStatements':[],
				\'removeAfterDisplayed':[],
				\'closeDebugger':''}
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


function! vebugger#std#openShellBuffer(debugger)
	if has_key(a:debugger,'shellBuffer')
		if -1<bufwinnr(a:debugger.shellBuffer)
			return
		endif
	endif
	let l:oldBuffer=bufnr('Vebugger:Shell')
	if -1<l:oldBuffer
		let a:debugger.shellBuffer=l:oldBuffer
		call a:debugger.std_addLineToShellBuffer('')
		call a:debugger.std_addLineToShellBuffer('==================')
		call a:debugger.std_addLineToShellBuffer('')
		return
	endif
	8 new
	let b:debugger=a:debugger
	autocmd BufDelete <buffer> call b:debugger.kill()
	setlocal buftype=nofile
	setlocal bufhidden=wipe
	let a:debugger.shellBuffer=bufnr('')
	silent file Vebugger:Shell
	wincmd p
endfunction

let s:standardFunctions={}
function! s:standardFunctions.addLineToShellBuffer(line) dict
	if has_key(self,'shellBuffer')
		let l:bufwin=bufwinnr(self.shellBuffer)
		if -1<l:bufwin
			exe l:bufwin.'wincmd w'
			call append (line('$'),a:line)
			normal G
			wincmd p
		endif
	endif
endfunction

function! s:standardFunctions.addAllBreakpointActions(breakpoints) dict
	for l:breakpoint in a:breakpoints
		call self.addWriteAction('std','breakpoints',{
					\'action':'add',
					\'file':(l:breakpoint.file),
					\'line':(l:breakpoint.line)})
	endfor
endfunction

function! s:standardFunctions.eval(expression) dict
	if -1==index(self.state.std.evaluateExpressions,a:expression)
		call add(self.state.std.evaluateExpressions,a:expression)
	endif
	call self.addWriteAction('std','evaluateExpressions',{
				\'expression':(a:expression)})
	call self.performWriteActions()
endfunction

"Executes a statement in the debugged program
function! s:standardFunctions.execute(statement) dict
	call self.addWriteAction('std','executeStatements',{
				\'statement':(a:statement)})
	call self.performWriteActions()
endfunction

let s:standardThinkHandlers={}
function! s:standardThinkHandlers.addProgramOutputToShell(readResult,debugger) dict
	let l:programOutput=a:readResult.std.programOutput
	if !empty(l:programOutput)
		call a:debugger.std_addLineToShellBuffer(l:programOutput.line)
	endif
endfunction

function! s:standardThinkHandlers.moveToCurrentLine(readResult,debugger) dict
	if !empty(a:readResult.std.location)
		if !empty(a:debugger.state.std.config.externalFileStop_flowCommand) " Do we need to worry about stopping at external files?
			if 0!=stridx(tolower(fnamemodify(a:readResult.std.location.file,':p')),tolower(getcwd()))
				call a:debugger.setWriteAction('std','flow',a:debugger.state.std.config.externalFileStop_flowCommand)
				return
			endif
		endif
		if a:debugger.state.std.location!=a:readResult.std.location
			if has_key(a:debugger.state.std.location,'file')
				exe 'sign unplace 1 file='.fnameescape(fnamemodify(a:debugger.state.std.location.file,':p'))
			endif
			let a:debugger.state.std.location=deepcopy(a:readResult.std.location)
			if !bufexists(a:readResult.std.location.file)
				exe 'new '.(a:readResult.std.location.file)
			endif
			call vebugger#std#updateMarksForFile(a:debugger.state,a:readResult.std.location.file)
			exe 'sign jump 1 file='.fnameescape(fnamemodify(a:readResult.std.location.file,':p'))
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

function! s:standardThinkHandlers.printEvaluatedExpression(readResult,debugger) dict
	let l:evaluatedExpression=a:readResult.std.evaluatedExpression
	if !empty(l:evaluatedExpression)
		if empty(get(l:evaluatedExpression,'expression'))
			echo l:evaluatedExpression.value."\n"
		else
			let l:index=index(a:debugger.state.std.evaluateExpressions,l:evaluatedExpression.expression)
			if 0<=l:index
				call remove(a:debugger.state.std.evaluateExpressions,l:index)
				echo l:evaluatedExpression.expression.': '.l:evaluatedExpression.value."\n"
				let g:echo=l:evaluatedExpression.expression.': '.l:evaluatedExpression.value."\n"
			endif
		endif
		call a:debugger.addWriteAction('std','removeAfterDisplayed',a:readResult)
	endif
endfunction

function! s:standardThinkHandlers.closeDebuggerWhenProgramFinishes(readResult,debugger) dict
	if !empty(a:readResult.std.programFinish)
		call a:debugger.setWriteAction('std','closeDebugger','close')
	endif
endfunction

function! s:standardThinkHandlers.printException(readResult,debugger) dict
	if !empty(a:readResult.std.exception)
		echohl WarningMsg
		echo a:readResult.std.exception.message."\n"
		echohl None
	endif
endfunction

let s:standardCloseHandlers={}
function! s:standardCloseHandlers.removeCurrentMarker(debugger) dict
	let a:debugger.state.std.location={}
	sign unplace 1
endfunction

sign define vebugger_current text=->
sign define vebugger_breakpoint text=** linehl=ColorColumn
function! vebugger#std#updateMarksForFile(state,filename)
	let l:filename=fnamemodify(a:filename,":p")
	if bufexists(l:filename)
		exe 'sign unplace * file='.fnameescape(fnamemodify(l:filename,':p'))

		for l:breakpoint in g:vebugger_breakpoints
			if fnamemodify(l:breakpoint.file,':p')==fnamemodify(a:filename,':p')
				exe 'sign place 2 name=vebugger_breakpoint line='.l:breakpoint.line.' file='.fnameescape(fnamemodify(l:breakpoint.file,':p'))
			endif
		endfor

		if !empty(a:state)
			if !empty(a:state.std.location)
				if fnamemodify(a:state.std.location.file,':p')==fnamemodify(a:filename,':p')
					exe 'sign place 1 name=vebugger_current line='.a:state.std.location.line.' file='.fnameescape(fnamemodify(l:filename,':p'))
				endif
			endif
		endif
	endif
endfunction

function! vebugger#std#toggleBreakpoint(file,line)
	let l:debugger=vebugger#getActiveDebugger()
	let l:debuggerState=empty(l:debugger)
				\? {}
				\: l:debugger.state
	for l:i in range(len(g:vebugger_breakpoints))
		let l:breakpoint=g:vebugger_breakpoints[l:i]
		if l:breakpoint.file==a:file && l:breakpoint.line==a:line
			call remove(g:vebugger_breakpoints,l:i)
			call vebugger#addWriteActionAndPerform('std','breakpoints',{
						\'action':'remove',
						\'file':(a:file),
						\'line':(a:line)})
			call vebugger#std#updateMarksForFile(l:debuggerState,a:file)
			return
		endif
	endfor
	call add(g:vebugger_breakpoints,{'file':(a:file),'line':(a:line)})
	call vebugger#addWriteActionAndPerform('std','breakpoints',{
				\'action':'add',
				\'file':(a:file),
				\'line':(a:line)})
	call vebugger#std#updateMarksForFile(l:debuggerState,a:file)
endfunction

function! vebugger#std#clearBreakpoints()
	let l:debugger=vebugger#getActiveDebugger()
	let l:debuggerState=empty(l:debugger) ? {} : l:debugger.state
	let l:files=[]
	for l:breakpoint in g:vebugger_breakpoints
		if index(l:files,l:breakpoint.file)<0
			call add(l:files,l:breakpoint.file)
		endif
		call vebugger#addWriteAction('std','breakpoints',extend({'action':'remove'},l:breakpoint))
	endfor
	call vebugger#performWriteActions()
	let g:vebugger_breakpoints=[]
	for l:file in l:files
		call vebugger#std#updateMarksForFile(l:debuggerState,l:file)
	endfor
endfunction

function! vebugger#std#eval(expression)
	let l:debugger=vebugger#getActiveDebugger()
	if !empty(l:debugger) && !empty(l:debugger.std_eval)
		call l:debugger.std_eval(a:expression)
	endif
endfunction

function! vebugger#std#execute(statement)
	let l:debugger=vebugger#getActiveDebugger()
	if !empty(l:debugger) && !empty(l:debugger.std_eval)
		call l:debugger.std_execute(a:statement)
	endif
endfunction
