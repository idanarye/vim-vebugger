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

	"return
	return []
endfunction

function! s:createDebugger(command)
	let l:debugger={'shell':vimproc#popen3(a:command)}
	let l:debugger.outBuffer=''
	let l:debugger.errBuffer=''

	let l:debugger.pipes={
				\'out':{'pipe':(l:debugger.shell.stdout),'buffer':''},
				\'err':{'pipe':(l:debugger.shell.stderr),'buffer':''}}

	let l:debugger.readHandlers=[]
	let l:debugger.thinkHandlers=[]
	let l:debugger.writeHandlers={}

	let l:debugger.prevUpdateTime=&updatetime
	function l:debugger.kill() dict
		let &updatetime=self.prevUpdateTime
		call self.shell.kill(15)
	endfunction

	function l:debugger.writeLine(line) dict
		call self.shell.stdin.write(a:line."\n")
	endfunction


	function l:debugger.invokeReading() dict
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
	endfunction

	function l:debugger.handleLine(pipeName,line) dict
		call self.logLine(a:pipeName,a:line)
	endfunction

	function l:debugger.showLogBuffer() dict
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
	endfunction

	function l:debugger.logLine(pipeName,line) dict
		if has_key(self,'logBuffer')
			let l:bufwin=bufwinnr(self.logBuffer)
			if -1<l:bufwin
				let l:curwin=winnr()
				exe l:bufwin.'wincmd w'
				if 'out'==a:pipeName
					call append (line('$'),a:line)
				else
					call append (line('$'),a:pipeName.":\t\t".a:line)
				endif
				normal G
				exe l:curwin.'wincmd w'
			endif
		endif
	endfunction

	set updatetime=500
	return l:debugger
endfunction

" all the functions here are currently just for testing:

function! vebugger#startDebugger(command)
	call vebugger#killDebugger()

	let s:debugger=s:createDebugger(a:command)

	augroup vebuffer_shell
		autocmd!
		autocmd CursorHold * call s:debugger.invokeReading()
	augroup END
endfunction

function! vebugger#killDebugger()
	augroup vebuffer_shell
		autocmd!
	augroup END
	if exists('s:debugger')
		call s:debugger.shell.kill()
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
