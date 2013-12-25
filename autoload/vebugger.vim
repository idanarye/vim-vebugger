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
		let l:outLines=split(strpart(a:pipeObject.buffer,0,l:lastNewline),'\n\|\r\|\r\n')
		let a:pipeObject.buffer=strpart(a:pipeObject.buffer,l:lastNewline+1)
		return l:outLines
	endif

	return []
endfunction

let s:f_debugger={}

function! s:f_debugger.kill() dict
	let &updatetime=self.prevUpdateTime
	call self.shell.kill(15)
	for l:closeHandler in s:debugger.closeHandlers
		call l:closeHandler.handle(self)
	endfor
endfunction

function! s:f_debugger.writeLine(line) dict
	call self.shell.stdin.write(a:line."\n")
endfunction

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
endfunction

function! s:f_debugger.handleLine(pipeName,line) dict
	call self.logLine(a:pipeName,a:line)

	let l:readResult=deepcopy(self.readResultTemplate,1)

	for l:readHandler in self.readHandlers
		call l:readHandler.handle(a:pipeName,a:line,l:readResult,self)
	endfor

	for l:thinkHandler in self.thinkHandlers
		call l:thinkHandler.handle(l:readResult,self.state,self)
	endfor
endfunction

function! s:f_debugger.showLogBuffer() dict
	if has_key(self,'logBuffer')
		if -1<bufwinnr(self.logBuffer)
			return
		endif
	endif
	new
	setlocal buftype=nofile
	setlocal bufhidden=wipe
	let self.logBuffer=bufnr('')
	file Vebugger\ Console
	wincmd p
endfunction

function! s:f_debugger.closeLogBuffer() dict
	if has_key(self,'logBuffer')
		if -1<bufwinnr(self.logBuffer)
			let l:bufwin=bufwinnr(self.logBuffer)
			exe l:bufwin.'wincmd w'
			wincmd c
			wincmd p
		endif
	endif
endfunction

function! s:f_debugger.logLine(pipeName,line) dict
	if has_key(self,'logBuffer')
		let l:bufwin=bufwinnr(self.logBuffer)
		if -1<l:bufwin
			exe l:bufwin.'wincmd w'
			if 'out'==a:pipeName
				call append (line('$'),a:line)
			else
				call append (line('$'),a:pipeName.":\t\t".a:line)
			endif
			normal G
			wincmd p
		endif
	endif
endfunction

function! s:addHandler(list,handler)
	if type(a:handler) == type({})
		call add(a:list,a:handler)
	elseif type(a:handler) == type(function('tr'))
		call add(a:list,{'handle':a:handler})
	endif
endfunction

function! s:f_debugger.addReadHandler(handler) dict
	call s:addHandler(self.readHandlers,a:handler)
endfunction

function! s:f_debugger.addThinkHandler(handler) dict
	call s:addHandler(self.thinkHandlers,a:handler)
endfunction

function! s:f_debugger.addCloseHandler(handler) dict
	call s:addHandler(self.closeHandlers,a:handler)
endfunction

function! vebugger#createDebugger(command)

	let l:debugger=deepcopy(s:f_debugger)

	let l:debugger.shell=vimproc#popen3(a:command)
	let l:debugger.outBuffer=''
	let l:debugger.errBuffer=''

	let l:debugger.pipes={
				\'out':{'pipe':(l:debugger.shell.stdout),'buffer':''},
				\'err':{'pipe':(l:debugger.shell.stderr),'buffer':''}}

	let l:debugger.readResultTemplate={}
	let l:debugger.state={}

	let l:debugger.readHandlers=[]
	let l:debugger.thinkHandlers=[]
	let l:debugger.writeHandlers={}
	let l:debugger.closeHandlers=[]

	let l:debugger.prevUpdateTime=&updatetime

	set updatetime=500
	return l:debugger
endfunction

" all the functions here are currently just for testing:

function! vebugger#startDebugger(command)
	call vebugger#killDebugger()

	let s:debugger=vebugger#createDebugger(a:command)

	augroup vebugger_shell
		autocmd!
		autocmd CursorHold * call s:debugger.invokeReading()
	augroup END

	return s:debugger
endfunction

function! vebugger#killDebugger()
	augroup vebugger_shell
		autocmd!
	augroup END
	if exists('s:debugger')
		call s:debugger.closeLogBuffer()
		call s:debugger.kill()
		unlet s:debugger
	endif
endfunction

function! vebugger#writeLine(line)
	if exists('s:debugger')
		call s:debugger.writeLine(a:line)
	endif
endfunction

function! vebugger#invokeReading()
	if exists('s:debugger')
		call s:debugger.invokeReading()
	endif
endfunction

function! vebugger#showLogBuffer()
	if exists('s:debugger')
		call s:debugger.showLogBuffer()
	endif
endfunction
