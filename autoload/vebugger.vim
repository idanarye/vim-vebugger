"Read and return all new lines from a Vebugger pipe object.
function! s:readNewLinesFromPipe(pipeObject)
	"read
	let l:text=a:pipeObject.pipe.read(1000,0)
	while 0<len(l:text)
		let a:pipeObject.buffer.=l:text
		let l:text=a:pipeObject.pipe.read(1000,0)
	endwhile

	"parse
	let l:lastNewline=strridx(a:pipeObject.buffer,"\n")
	if 0<=l:lastNewline
		let l:outLines=split(strpart(a:pipeObject.buffer,0,l:lastNewline),'\r\n\|\n\|\r')
		let a:pipeObject.buffer=strpart(a:pipeObject.buffer,l:lastNewline+1)
		return l:outLines
	endif

	return []
endfunction

let s:f_debugger={}

"Terminate the debugger
function! s:f_debugger.kill() dict
	if self.shell.is_valid
		call self.addLineToTerminal('','== DEBUGGER TERMINATED ==')
	endif
	let &updatetime=self.prevUpdateTime
	call self.shell.kill(15)
	if exists('s:debugger')
		for l:closeHandler in s:debugger.closeHandlers
			call l:closeHandler.handle(self)
		endfor
	endif
endfunction

"Write a line to the debugger's interactive shell
function! s:f_debugger.writeLine(line) dict
	call self.shell.stdin.write(a:line."\n")
endfunction

"Check for new lines from the debugger's interactive shell and handle them
function! s:f_debugger.invokeReading() dict
	let l:newLines={}
	for l:k in keys(self.pipes)
		let l:nl=s:readNewLinesFromPipe(self.pipes[l:k])
		if 0<len(l:nl)
			let l:newLines[l:k]=l:nl
		endif
	endfor
	for l:k in keys(l:newLines)
		for l:line in l:newLines[l:k]
			call self.handleLine(l:k,l:line)
		endfor
	endfor

	let l:checkpid=self.shell.checkpid()
	if 'exit'==l:checkpid[0]
				\|| 'error'==l:checkpid[0]
		call self.kill()
	endif
	call feedkeys("f\e") " Make sure the CursorHold event is refired even if the user does nothing
endfunction

"Handle a single line from the debugger's interactive shell
function! s:f_debugger.handleLine(pipeName,line) dict
	call self.addLineToTerminal(a:pipeName,a:line)

	let l:readResult=deepcopy(self.readResultTemplate,1)

	for l:readHandler in self.readHandlers
		call l:readHandler.handle(a:pipeName,a:line,l:readResult,self)
	endfor

	for l:thinkHandler in self.thinkHandlers
		call l:thinkHandler.handle(l:readResult,self)
	endfor

	call self.performWriteActions()
endfunction

"Perform all write actions
function! s:f_debugger.performWriteActions() dict
	for l:namespace in keys(self.writeActions)
		let l:handlers=get(self.writeHandlers,l:namespace)
		if !empty(l:handlers)
			for l:writeAction in items(self.writeActions[l:namespace])
				if !empty(l:writeAction[1])
					if has_key(l:handlers,l:writeAction[0])
						call l:handlers[l:writeAction[0]].handle(l:writeAction[1],self)
					endif
				endif
			endfor
		endif
	endfor
	call self.generateWriteActionsFromTemplate()
endfunction

"Show the terminal buffer that gets it's content from the debugger's
"interactive shell
function! s:f_debugger.showTerminalBuffer() dict
	if has_key(self,'terminalBuffer')
		if -1<bufwinnr(self.terminalBuffer)
			return
		endif
	endif
	new
	setlocal buftype=nofile
	setlocal bufhidden=wipe
	let self.terminalBuffer=bufnr('')
	silent file Vebugger:Ternimal
	wincmd p
endfunction

"Close the terminal buffer
function! s:f_debugger.closeTerminalBuffer() dict
	if has_key(self,'terminalBuffer')
		if -1<bufwinnr(self.terminalBuffer)
			let l:bufwin=bufwinnr(self.terminalBuffer)
			exe l:bufwin.'wincmd w'
			wincmd c
			wincmd p
		endif
	endif
endfunction

"Check if the terminal buffer associated with this debugger is currently open
function! s:f_debugger.isTerminalBufferOpen() dict
	if has_key(self,'terminalBuffer')
		if -1<bufwinnr(self.terminalBuffer)
			return 1
		endif
	endif
	return 0
endfunction

"Turn on and off the terminal buffer associated with this debugger
function! s:f_debugger.toggleTerminalBuffer() dict
	if self.isTerminalBufferOpen()
		call self.closeTerminalBuffer()
	else
		call self.showTerminalBuffer()
	endif
endfunction

"Write a line to the terminal buffer. This function does not process the line
function! s:f_debugger.addLineToTerminal(pipeName,line) dict
	if has_key(self,'terminalBuffer')
		let l:bufwin=bufwinnr(self.terminalBuffer)
		if -1<l:bufwin
			exe l:bufwin.'wincmd w'
			if has_key(self,'pipes')
						\&&has_key(self.pipes,a:pipeName)
						\&&has_key(self.pipes[a:pipeName],'annotation')
				call append (line('$'),(self.pipes[a:pipeName].annotation).(a:line))
			else
				call append (line('$'),a:line)
			endif
			normal G
			wincmd p
		endif
	endif
endfunction

"Add an handler to a handler list
function! s:addHandler(list,handler)
	if type(a:handler) == type({})
		call add(a:list,a:handler)
	elseif type(a:handler) == type(function('tr'))
		call add(a:list,{'handle':a:handler})
	endif
endfunction

"Set a named handler in a handler dictionary
function! s:setHandler(dict,namespace,name,handler)
	if !has_key(a:dict,a:namespace)
		let a:dict[a:namespace]={}
	endif
	if type(a:handler) == type({})
		let a:dict[a:namespace][a:name]=a:handler
	elseif type(a:handler) == type(function('tr'))
		let a:dict[a:namespace][a:name]={'handle':a:handler}
	endif
endfunction

"Add a read handler. Read handlers process output from the debugger's
"interactive shell and modify read result objects with structured information
"parsed from those lines
function! s:f_debugger.addReadHandler(handler) dict
	call s:addHandler(self.readHandlers,a:handler)
endfunction

"Add a think handler. Think handlers are debugger agnostic - they look at
"read result objects and decide what to do with them.
function! s:f_debugger.addThinkHandler(handler) dict
	call s:addHandler(self.thinkHandlers,a:handler)
endfunction

"Set a write handler. Write handlers get write action objects and convert them
"to debugger specific commands. A write action can only handle a write action
"of the namespace and name it is registered for, to prevent the same write
"action handled by multiple write handlers.
function! s:f_debugger.setWriteHandler(namespace,name,handler) dict
	call s:setHandler(self.writeHandlers,a:namespace,a:name,a:handler)
endfunction

"Add a close handler. Close handlers are called when the debugger is closed to
"tidy things up.
function! s:f_debugger.addCloseHandler(handler) dict
	call s:addHandler(self.closeHandlers,a:handler)
endfunction

"Create an empty write action that follows the write actions template. That
"action will later be filled by think handlers or from outside.
function! s:f_debugger.generateWriteActionsFromTemplate() dict
	let self.writeActions=deepcopy(self.writeActionsTemplate)
endfunction

"Set a write action of a specific namespace and name, for write actions that
"do not support a list
function! s:f_debugger.setWriteAction(namespace,name,value) dict
	let self.writeActions[a:namespace][a:name]=a:value
endfunction

"Add a write action of a specific namespace and name, for write actions that supports a list
function! s:f_debugger.addWriteAction(namespace,name,value) dict
	call add(self.writeActions[a:namespace][a:name],a:value)
endfunction

"Create a bare debugger object from a raw shell line
function! vebugger#createDebugger(command)

	let l:debugger=deepcopy(s:f_debugger)

	let l:debugger.shell=vimproc#ptyopen(a:command,3)

	let l:debugger.outBuffer=''
	let l:debugger.errBuffer=''

	let l:debugger.pipes={
				\'out':{'pipe':(l:debugger.shell.stdout),'buffer':''},
				\'err':{'pipe':(l:debugger.shell.stderr),'buffer':'','annotation':"err:\t\t"}}

	let l:debugger.readResultTemplate={}
	let l:debugger.state={}
	let l:debugger.writeActionsTemplate={}

	let l:debugger.readHandlers=[]
	let l:debugger.thinkHandlers=[]
	let l:debugger.writeHandlers={}
	let l:debugger.closeHandlers=[]

	let l:debugger.prevUpdateTime=&updatetime

	set updatetime=500
	return l:debugger
endfunction


"Create a debugger and set it as the currently active debugger
function! vebugger#startDebugger(command)
	call vebugger#killDebugger()

	let s:debugger=vebugger#createDebugger(a:command)

	augroup vebugger_shell
		autocmd!
		autocmd CursorHold * call s:debugger.invokeReading()
	augroup END

	return s:debugger
endfunction

"Terminate the currently active debugger
function! vebugger#killDebugger()
	augroup vebugger_shell
		autocmd!
	augroup END
	if exists('s:debugger')
		call s:debugger.closeTerminalBuffer()
		call s:debugger.kill()
		unlet s:debugger
	endif
endfunction

"Write a line to the currently active debugger
function! vebugger#writeLine(line)
	if exists('s:debugger')
		call s:debugger.writeLine(a:line)
	endif
endfunction

"Invoke reading for the currently active debugger
function! vebugger#invokeReading()
	if exists('s:debugger')
		call s:debugger.invokeReading()
	endif
endfunction

"Toggle the terminal buffer for the currently active debugger
function! vebugger#toggleTerminalBuffer()
	if exists('s:debugger')
		call s:debugger.toggleTerminalBuffer()
	endif
endfunction

"Fetch the currently active debugger object
function! vebugger#getActiveDebugger()
	if exists('s:debugger')
		return s:debugger
	else
		return {}
	endif
endfunction

"Set a write action for the currently active debugger
function! vebugger#setWriteAction(namespace,name,value)
	if exists('s:debugger')
		call s:debugger.setWriteAction(a:namespace,a:name,a:value)
	endif
endfunction

"Add a write action to the currently active debugger
function! vebugger#addWriteAction(namespace,name,value)
	if exists('s:debugger')
		call s:debugger.addWriteAction(a:namespace,a:name,a:value)
	endif
endfunction

"Force performing all the write of the currently active debugger
function! vebugger#performWriteActions()
	if exists('s:debugger')
		call s:debugger.performWriteActions()
	endif
endfunction

"Set a write action for the currently active debugger and perform it
function! vebugger#setWriteActionAndPerform(namespace,name,value)
	call vebugger#setWriteAction(a:namespace,a:name,a:value)
	call vebugger#performWriteActions()
endfunction

"Add a write action to the currently active debugger and perform it
function! vebugger#addWriteActionAndPerform(namespace,name,value)
	call vebugger#addWriteAction(a:namespace,a:name,a:value)
	call vebugger#performWriteActions()
endfunction
