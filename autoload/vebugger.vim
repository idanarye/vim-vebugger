"Read bytes from pipe to buffer
function! s:fillBufferFromPipe(pipeObject)
    let l:text = a:pipeObject.pipe.read(1024, 0)
    let l:totalBytesRead = 0
    while 0 < len(l:text)
        let l:totalBytesRead += len(l:text)
        let a:pipeObject.buffer .= l:text
        let l:text = a:pipeObject.pipe.read(1024, 0)
    endwhile
    return l:totalBytesRead
endfunction

let s:f_debugger={}

"Terminate the debugger
function! s:f_debugger.kill() dict
    if has('nvim')
        try
            call jobclose(self.jobid)
            call self.addLineToTerminal('== DEBUGGER TERMINATED ==')
        catch /E900/
        endtry
    else
        call job_stop(self.jobid)
    endif
    if exists('s:debugger')
        for l:closeHandler in s:debugger.closeHandlers
            call l:closeHandler.handle(self)
        endfor
    endif
endfunction

"Write a line to the debugger's interactive shell
function! s:f_debugger.writeLine(line) dict
    if type(a:line) == type([])
        let l:lines = a:line
    else
        let l:lines = split(a:line, '\r\n\|\n\|\r')
    endif
    call add(l:lines, '')
    if has('nvim')
        try
            call jobsend(self.jobid, l:lines)
        catch /E900/
        endtry
    else
        call ch_sendraw(self.jobid, join(l:lines, "\n"))
    endif
endfunction

if has('nvim')
    function! s:f_debugger.on_stdout(jobid, data, event) abort dict
        let self.buffer .= join(a:data, "\n")

        for l:line in self.bufferer()
            call self.handleLine(l:line)
        endfor
    endfunction
else " Vim8 jobs
    function! s:f_debugger.out_cb(hannel, msg) abort dict
        let self.buffer .= a:msg

        for l:line in self.bufferer()
            call self.handleLine(l:line)
        endfor
    endfunction
endif

"Handle a single line from the debugger's interactive shell
function! s:f_debugger.handleLine(line) dict
    call self.addLineToTerminal(a:line)

    let l:readResult=deepcopy(self.readResultTemplate,1)

    for l:readHandler in self.readHandlers
        call l:readHandler.handle(a:line, l:readResult,self)
    endfor

    for l:thinkHandler in self.thinkHandlers
        call l:thinkHandler.handle(l:readResult, self)
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
    silent file Vebugger:Terminal
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
function! s:f_debugger.addLineToTerminal(line) dict
    if has_key(self, 'terminalBuffer')
        let l:bufwin = bufwinnr(self.terminalBuffer)
        if -1<l:bufwin
            exe l:bufwin.'wincmd w'
            call append (line('$') ,a:line)
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
        call add(a:list,{'handle': a:handler})
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

"Set a write action and perform it
function! s:f_debugger.setWriteActionAndPerform(namespace, name, value) dict
    call self.setWriteAction(a:namespace, a:name, a:value)
    call self.performWriteActions()
endfunction

"Add a write action of a specific namespace and name, for write actions that supports a list
function! s:f_debugger.addWriteAction(namespace,name,value) dict
    call add(self.writeActions[a:namespace][a:name],a:value)
endfunction

"Add a write action and perform it
function! s:f_debugger.addWriteActionAndPerform(namespace, name, value) dict
    call self.addWriteAction(a:namespace, a:name, a:value)
    call self.performWriteActions()
endfunction

"Create a bare debugger object from a raw shell line
function! vebugger#createDebugger(command)
    let l:debugger=deepcopy(s:f_debugger)

    let l:debugger.buffer = ''
    let l:debugger.writeActions = {}
    if has('nvim')
        let l:debugger.pty = 1
        let l:debugger.jobid = jobstart(a:command, l:debugger)
    else
        let l:options = {}
        let l:options.out_cb = function(l:debugger.out_cb, [], l:debugger)
        let l:options.out_mode = 'raw'
        let l:options.err_io = 'out'
        let l:options.err_mode = 'raw'

        let l:debugger.jobid = job_start(a:command, l:options)
    endif

    let l:debugger.readResultTemplate={}
    let l:debugger.state={}
    let l:debugger.writeActionsTemplate={}

    let l:debugger.readHandlers=[]
    let l:debugger.thinkHandlers=[]
    let l:debugger.writeHandlers={}
    let l:debugger.closeHandlers=[]

    return l:debugger
endfunction

"Create a debugger and set it as the currently active debugger
function! vebugger#startDebugger(command)
    call vebugger#killDebugger()

    let s:debugger=vebugger#createDebugger(a:command)

    return s:debugger
endfunction

"Terminate the currently active debugger
function! vebugger#killDebugger()
    if exists('s:debugger')
        call vebugger#std#closeShellBuffer(s:debugger)
        call s:debugger.closeTerminalBuffer()
        call s:debugger.kill()
        unlet s:debugger
    endif
endfunction

"Perform an action on the actvie debugger, and register that action
function! vebugger#userAction(action, ...)
    if exists('s:debugger')
        if has_key(s:debugger, a:action)
            let s:debugger.lastUserAction = {
                        \'action': a:action,
                        \'args': a:000}

            try
                doautocmd User Vebugger_PreUserAction
            finally
                call call(s:debugger[a:action], a:000, s:debugger)
                doautocmd User Vebugger_PostUserAction
            endtry
        else
            throw 'Current debugger does not support action '.a:action
        endif
    endif
endfunction

augroup vebugger_hooks
    autocmd!
    "Make a blank action hook to prevent 'No matching autocommands" warning
    autocmd User Vebugger_* echo
augroup END

"Repeat the last action performed on the active debugger
function! vebugger#repeatLastUserAction()
    if exists('s:debugger')
        if has_key(s:debugger, 'lastUserAction')
            let l:lastUserAction = s:debugger.lastUserAction
            call call(s:debugger[l:lastUserAction.action], l:lastUserAction.args, s:debugger)
        endif
    endif
endfunction

"Write a line to the currently active debugger
function! vebugger#writeLine(line)
    if exists('s:debugger')
        call s:debugger.writeLine(a:line)
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
