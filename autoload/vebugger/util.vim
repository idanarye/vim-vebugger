
"Returns the visually selected text
function! vebugger#util#get_visual_selection()
    "Shamefully stolen from http://stackoverflow.com/a/6271254/794380
    " Why is this not a built-in Vim script function?!
    let [lnum1, col1] = getpos("'<")[1:2]
    let [lnum2, col2] = getpos("'>")[1:2]
    let lines = getline(lnum1, lnum2)
    let lines[-1] = lines[-1][: col2 - (&selection == 'inclusive' ? 1 : 2)]
    let lines[0] = lines[0][col1 - 1:]
    return join(lines, "\n")
endfunction

"Prompts the user with a filtered list of process, and returns the process id
"the user selects
function! vebugger#util#selectProcessOfFile(ofFile)
    let l:fileName=fnamemodify(a:ofFile,':t')
    if has('win32')
        "Get the process data in CSV format
        let l:resultLines=split(vimproc#system('tasklist /FO csv /FI "IMAGENAME eq '.l:fileName.'"'),'\r\n\|\n\|\r')

        if l:resultLines[0]=~'\V\^INFO:'
            throw 'No matching process found'
        endif
        "Parse(sort of) the CSV:
        let l:resultLinesParsed=map(l:resultLines,'eval("[".v:val."]")')
        let l:resultLinesParsed[0][2]='Session'
        "Format for output
        let l:linesForPrinting=map(copy(l:resultLinesParsed),'v:val[1]."\t".v:val[2]."\t\t".v:val[0]')
    else
        let l:resultLines=split(vimproc#system('ps -o pid,user,comm,start,state,tt -C '.fnameescape(l:fileName)),'\r\n\|\n\|\r')
        let l:linesForPrinting=copy(l:resultLines)
    endif

    if len(l:linesForPrinting)<=1
        throw 'No matching process found'
    endif
    if &lines<len(l:linesForPrinting)
        throw 'Too many matching processes found'
    endif

    "Add numbers to the lines
    for l:i in range(1,len(l:linesForPrinting)-1)
        let l:linesForPrinting[l:i]=repeat(' ',3-len(l:i)).l:i.') '.(l:linesForPrinting[l:i])
    endfor
    "Indent the title line(since it doesn't have a number)
    let l:linesForPrinting[0]='     '.l:linesForPrinting[0]

    "Get the selection
    let l:chosenId=inputlist(l:linesForPrinting)
    if l:chosenId<1
                \|| len(l:resultLines)<=l:chosenId
        return 0
    endif

    if has('win32')
        return str2nr(l:resultLinesParsed[l:chosenId][1])
    else
        let l:chosenLine=l:resultLines[l:chosenId]
        let g:chosenLine = l:chosenLine
        return str2nr(matchstr(l:chosenLine,'\v^\s*\zs(\d+)\ze\s*'))
    endif
endfunction

"Escape args(from a debugger's extra arguments) as a command line arguments
"string
function! vebugger#util#commandLineArgsForProgram(debuggerArgs)
    if has_key(a:debuggerArgs,'args')
        if type(a:debuggerArgs.args)==type([])
            return join(map(a:debuggerArgs.args,'s:argEscape(v:val)'),' ')
        elseif type(a:debuggerArgs.args)==type('')
            return a:debuggerArgs.args
        else
            return string(a:debuggerArgs.args)
        endif
    endif
endfunction

"Escape a single argument for the command line
function! s:argEscape(arg)
    if has('win32')
        return shellescape(a:arg)
    else
        return '"'.escape(a:arg,'"').'"'
    end
endfunction

"Return a tool's(usually debugger) full path, or revert to default if that
"path is not defined
function! vebugger#util#getToolFullPath(toolName,version,default)
    let l:optionName='vebugger_path_'.a:toolName
    if !empty(a:version)
        let l:optionName=l:optionName.'_'.a:version
    endif
    if exists('g:'.l:optionName)
        return g:[l:optionName]
    else
        if type({})==type(a:default)
            if !empty(a:version) && has_key(a:default,a:version)
                return a:default[a:version]
            else
                return a:default[' ']
            endif
        else
            return a:default
        endif
    endif
endfunction

"Checks if the path is an absolute path
function! vebugger#util#isPathAbsolute(path)
    if has('win32')
        return a:path=~':' || a:path[0]=='%' "Absolute paths in Windows contain : or start with an environment variable
    else
        return a:path[0]=~'\v^[/~$]' "Absolute paths in Linux start with ~(home),/(root dir) or $(environment variable)
    endif
endfunction

function! vebugger#util#WinShellSlash(path)
    if has('win32') && &shellslash
        return substitute(a:path, '\\', '/', 'g')
    else
        return a:path
    endif
endfunction

function! vebugger#util#listify(stringOrList)
    if type(a:stringOrList) == type([])
        return copy(a:stringOrList) " so it could safely be modified by map&filter
    else
        return [a:stringOrList]
    endif
endfunction

" Return the resul of a:command in English, even if language messages set
" others.
function! vebugger#util#EnglishExecute(command) abort
    let l:lang = matchstr(execute('language messages'), '"\zs.*\ze"')
    if l:lang !~ 'en'
        language messages en_US.utf8
    endif
    let l:result = execute(a:command)
    if l:lang !~ 'en'
        language messages l:lang
    endif
    return l:result
endfunction

function! s:listSigns(filter) abort
    let l:result = []
    for l:line in split(vebugger#util#EnglishExecute('sign place '.a:filter), '\n')
    let l:match = matchlist(l:line, '\C\v^\s+line\=(\d+)\s+id\=(\d+)\s+name\=(.+)$')
    if !empty(l:match)
        call add(l:result, {
            \ 'line': str2nr(l:match[1]),
            \ 'id': str2nr(l:match[2]),
            \ 'name': l:match[3],
            \ })
    endif
    endfor
    return l:result
endfunction

function! vebugger#util#listSignsInBuffer(bufnr) abort
    return s:listSigns('buffer='.a:bufnr)
endfunction

function! vebugger#util#listSignsInFile(filename) abort
    return s:listSigns('file='.a:filename)
endfunction
