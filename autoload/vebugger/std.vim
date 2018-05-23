let g:vebugger_breakpoints=[]

"Initialize the default pipe bufferers
function! vebugger#std#setStandardBufferers(debugger)
    for l:pipe in values(a:debugger.pipes)
        let l:pipe.bufferer = function('vebugger#std#readNewLinesFromPipe')
    endfor
endfunction

"Initialize the std part of the debugger's state
function! vebugger#std#setStandardState(debugger)
    let a:debugger.state.std={
                \'config':{
                \   'externalFileStop_flowCommand':''},
                \'location':{},
                \'callstack':[],
                \'evaluateExpressions':[]}
endfunction

"Initialize the std part of the debugger's read result template
function! vebugger#std#setStandardReadResultTemplate(debugger)
    let a:debugger.readResultTemplate.std={
                \'programOutput':{},
                \'location':{},
                \'callstack':{},
                \'evaluatedExpression':{},
                \'programFinish':{},
                \'exception':{}}
endfunction

"Initialize the std part of the debugger's write actions template
function! vebugger#std#setStandardWriteactionsTemplate(debugger)
    let a:debugger.writeActionsTemplate.std={
                \'flow':'',
                \'breakpoints':[],
                \'evaluateExpressions':[],
                \'executeStatements':[],
                \'removeAfterDisplayed':[],
                \'closeDebugger':''}
endfunction

"Adds the std_ functions to the debugger object
function! vebugger#std#addStandardFunctions(debugger)
    for l:k in keys(s:standardFunctions)
        let a:debugger['std_'.l:k]=s:standardFunctions[l:k]
    endfor
endfunction

"Add the standard think handlers to the debugger
function! vebugger#std#addStandardThinkHandlers(debugger)
    for l:ThinkHandler in values(s:standardThinkHandlers)
        call a:debugger.addThinkHandler(l:ThinkHandler)
    endfor
endfunction

"Add the standard close handlers to the debugger
function! vebugger#std#addStandardCloseHandlers(debugger)
    for l:CloseHandler in values(s:standardCloseHandlers)
        call a:debugger.addCloseHandler(l:CloseHandler)
    endfor
endfunction

"Performs the standard initialization of the debugger object
function! vebugger#std#standardInit(debugger)
    call vebugger#std#setStandardBufferers(a:debugger)
    call vebugger#std#setStandardState(a:debugger)
    call vebugger#std#setStandardReadResultTemplate(a:debugger)
    call vebugger#std#setStandardWriteactionsTemplate(a:debugger)
    call vebugger#std#addStandardFunctions(a:debugger)
    call vebugger#std#addStandardThinkHandlers(a:debugger)
    call vebugger#std#addStandardCloseHandlers(a:debugger)
endfunction

"Start a debugger with the std settings
function! vebugger#std#startDebugger(command)
    let l:debugger=vebugger#startDebugger(a:command)

    call vebugger#std#standardInit(l:debugger)

    return l:debugger
endfunction


"Read and return all new lines from a Vebugger pipe object.
function! vebugger#std#readNewLinesFromPipe() dict
    let l:lastNewline = strridx(self.buffer, "\n")
    if 0 <= l:lastNewline
        let l:outLines = split(strpart(self.buffer, 0, l:lastNewline), '\r\n\|\n\|\r')
        let self.buffer = strpart(self.buffer, l:lastNewline + 1)
        return l:outLines
    endif

    return []
endfunction


"Opens the shell buffer for a debugger. The shell buffer displays the output
"of the debugged program, and when it's closed the debugger gets terminated.
"Shell buffers should not be used when attaching a debugger to a running
"process.
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
    autocmd BufDelete <buffer> if exists('b:debugger') | call b:debugger.kill() | endif
    setlocal buftype=nofile
    setlocal filetype=VebuggerShell
    setlocal bufhidden=wipe
    let a:debugger.shellBuffer=bufnr('')
    silent file Vebugger:Shell
    wincmd p
endfunction

"Closes the shell buffer
function! vebugger#std#closeShellBuffer(debugger)
    if has_key(a:debugger,'shellBuffer')
        if -1<bufwinnr(a:debugger.shellBuffer)
            let l:bufwin=bufwinnr(a:debugger.shellBuffer)
            exe l:bufwin.'wincmd w'
            wincmd c
            wincmd p
        endif
    endif
endfunction

let s:standardFunctions={}

"Write a line to the shell buffer
function! s:standardFunctions.addLineToShellBuffer(line) dict
    if has_key(self,'shellBuffer')
        let l:bufwin=bufwinnr(self.shellBuffer)
        if -1<l:bufwin
            exe 'noautocmd '.l:bufwin.'wincmd w'
            call append (line('$'),a:line)
            normal G
            noautocmd wincmd p
        endif
    endif
endfunction

"Set the write actions to add all breakpoints registered in Vebugger
function! s:standardFunctions.addAllBreakpointActions(breakpoints) dict
    for l:breakpoint in a:breakpoints
        call self.addWriteAction('std','breakpoints',{
                    \'action':'add',
                    \'file':(l:breakpoint.file),
                    \'line':(l:breakpoint.line)})
    endfor
endfunction

"Make the debugger evaluate an expression
function! s:standardFunctions.eval(expression) dict
    if -1==index(self.state.std.evaluateExpressions,a:expression)
        call add(self.state.std.evaluateExpressions,a:expression)
    endif
    call self.addWriteAction('std','evaluateExpressions',{
                \'expression':(a:expression)})
    call self.performWriteActions()
endfunction

"Execute a statement in the debugged program
function! s:standardFunctions.execute(statement) dict
    call self.addWriteAction('std','executeStatements',{
                \'statement':(a:statement)})
    call self.performWriteActions()
endfunction


let s:standardThinkHandlers={}

"Update the shell buffer with program output
function! s:standardThinkHandlers.addProgramOutputToShell(readResult,debugger) dict
    let l:programOutput=a:readResult.std.programOutput
    if !empty(l:programOutput)
        call a:debugger.std_addLineToShellBuffer(l:programOutput.line)
    endif
endfunction

"Make Vim jump to the currently executed line
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
            if -1 == bufwinnr(a:readResult.std.location.file)
                exe get(g:, 'vebugger_view_source_cmd', 'new').' '.(a:readResult.std.location.file)
            endif
            call vebugger#std#updateMarksForFile(a:debugger.state,a:readResult.std.location.file)
            exe 'sign jump 1 file='.fnameescape(fnamemodify(a:readResult.std.location.file,':p'))
        endif
    endif
endfunction

"Update the call stack
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

"Helper print function; when using vim timers feedkeys ensures that messages
"can be confirmend by the user.
function! s:printWithFeedKeys(evaluatedExpression)
    if empty(get(a:evaluatedExpression,'expression'))
        let l:echo = a:evaluatedExpression.value
    else
        let l:echo = a:evaluatedExpression.expression.': '.a:evaluatedExpression.value
    endif
    let l:echoLines = split(l:echo, '\r\n\|\n\|\r')
    if len(l:echoLines) == 1
        call add(l:echoLines, '')
    endif

    if has('timers')
        " Convert to an expression we can use with feedkeys.
        " string(l:echo) won't do because it uses single-quotes which
        " do not escape newlines
        let l:echoJoinExpr = 'join('.string(l:echoLines).', "\n")'

        let l:echoKeys = ':echo '.l:echoJoinExpr."\<Cr>"
        if mode() == 'n'
            " Call echo normaly
            call feedkeys(l:echoKeys)
        elseif mode() == 'i'
            " Execute command in insert mode
            call feedkeys("\<C-o>".l:echoKeys)
        endif
        " NOTE: Other modes are not supported
    else
        " Without timer support, feedkeys won't work and we have
        " to echo directly
        echo join(l:echoLines, "\n")
    endif
endfunction

"Print an expression that it's evaluation was previously requested
function! s:standardThinkHandlers.printEvaluatedExpression(readResult,debugger) dict
    let l:evaluatedExpression=a:readResult.std.evaluatedExpression
    if !empty(l:evaluatedExpression)
        if !empty(get(l:evaluatedExpression,'expression'))
            let l:index=index(a:debugger.state.std.evaluateExpressions,l:evaluatedExpression.expression)
            if 0<=l:index
                call remove(a:debugger.state.std.evaluateExpressions,l:index)
            endif
        endif
        call s:printWithFeedKeys(l:evaluatedExpression)
        call a:debugger.addWriteAction('std','removeAfterDisplayed',a:readResult)
    endif
endfunction

"Close the debugger when the program is finished but the debugger wasn't
"closed automatically
function! s:standardThinkHandlers.closeDebuggerWhenProgramFinishes(readResult,debugger) dict
    if !empty(a:readResult.std.programFinish)
        call a:debugger.setWriteAction('std','closeDebugger','close')
    endif
endfunction

"Print an exception message
function! s:standardThinkHandlers.printException(readResult,debugger) dict
    if !empty(a:readResult.std.exception)
        echohl WarningMsg
        echo a:readResult.std.exception.message."\n"
        echohl None
    endif
endfunction

let s:standardCloseHandlers={}
"Remove the currently executed line when a debugger is closed
function! s:standardCloseHandlers.removeCurrentMarker(debugger) dict
    let a:debugger.state.std.location={}
    sign unplace 1
endfunction

let s:breakpoint_text = get(g:, 'vebugger_breakpoint_text', '->')
let s:currentline_text = get(g:, 'vebugger_currentline_text', '**')

if hlexists("DebuggedLine")
  sign define vebugger_current linehl=DebuggedLine
else
  execute 'sign define vebugger_current text=' . s:currentline_text
endif

if hlexists('BreakPoint')
    execute 'sign define vebugger_breakpoint text=' . s:breakpoint_text . ' linehl=BreakPoint texthl=BreakPoint'
else
    execute 'sign define vebugger_breakpoint text=' . s:breakpoint_text . ' linehl=ColorColumn texthl=ColorColumn'
endif

"Update all the marks(currently executed line and breakpoints) for a file
function! vebugger#std#updateMarksForFile(state,filename)
    let l:filename=fnamemodify(a:filename,":p")
    let l:bufnr = bufnr(l:filename)
    if -1 < l:bufnr
        exe 'sign unplace 1 file='.fnameescape(fnamemodify(l:filename,':p'))
        for l:sign in vebugger#util#listSignsInBuffer(l:bufnr)
            if l:sign.name == 'vebugger_breakpoint'
                exe 'sign unplace 2 file='.fnameescape(fnamemodify(l:filename,':p'))
            endif
        endfor

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

"Toggle a breakpoint on and off
function! vebugger#std#toggleBreakpoint(file,line)
    let l:debugger=vebugger#getActiveDebugger()
    let l:debuggerState=empty(l:debugger)
                \? {}
                \: l:debugger.state
    for l:i in range(len(g:vebugger_breakpoints))
        let l:breakpoint=g:vebugger_breakpoints[l:i]
        if l:breakpoint.file==a:file && l:breakpoint.line==a:line
            call remove(g:vebugger_breakpoints,l:i)
            if !empty(l:debugger)
                call l:debugger.addWriteActionAndPerform('std','breakpoints',{
                            \'action':'remove',
                            \'file':(a:file),
                            \'line':(a:line)})
            endif
            call vebugger#std#updateMarksForFile(l:debuggerState,a:file)
            return
        endif
    endfor
    call add(g:vebugger_breakpoints,{'file':(a:file),'line':(a:line)})
    if !empty(l:debugger)
        call l:debugger.addWriteActionAndPerform('std','breakpoints',{
                    \'action':'add',
                    \'file':(a:file),
                    \'line':(a:line)})
    endif
    call vebugger#std#updateMarksForFile(l:debuggerState,a:file)
endfunction

"Clear all breakpoints
function! vebugger#std#clearBreakpoints()
    let l:debugger=vebugger#getActiveDebugger()
    let l:debuggerState=empty(l:debugger) ? {} : l:debugger.state
    let l:files=[]
    for l:breakpoint in g:vebugger_breakpoints
        if index(l:files,l:breakpoint.file)<0
            call add(l:files,l:breakpoint.file)
        endif
        if !empty(l:debugger)
            call l:debugger.addWriteAction('std','breakpoints',extend({'action':'remove'},l:breakpoint))
        endif
    endfor
    if !empty(l:debugger)
        call l:debugger.performWriteActions()
    endif
    let g:vebugger_breakpoints=[]
    for l:file in l:files
        call vebugger#std#updateMarksForFile(l:debuggerState,l:file)
    endfor
endfunction
