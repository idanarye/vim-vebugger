
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
	let l:resultLines=split(vimproc#system('ps -o pid,user,comm,start,state,tt -C '.fnameescape(l:fileName)),'\r\n\|\n\|\r')
	if len(l:resultLines)<=1
		throw 'No matching process found'
	endif
	if &lines<len(l:resultLines)
		throw 'Too many matching processes found'
	endif
	let l:resultLines[0]='     '.l:resultLines[0]
	for l:i in range(1,len(l:resultLines)-1)
		let l:resultLines[l:i]=repeat(' ',3-len(l:i)).l:i.') '.(l:resultLines[l:i])
	endfor
	let l:chosenId=inputlist(l:resultLines)
	if l:chosenId<1
				\|| len(l:resultLines)<=l:chosenId
		return 0
	endif
	let l:chosenLine=l:resultLines[l:chosenId]
	return str2nr(matchlist(l:chosenLine,'\v^\s*\d+\)\s+(\d+)')[1])
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
