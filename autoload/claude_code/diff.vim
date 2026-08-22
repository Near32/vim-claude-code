" autoload/claude_code/diff.vim
" Diff preview for Claude Code edit suggestions.
" Shows a side-by-side diff tab when Claude proposes file changes.
" Maintainer: Claude Code Vim Plugin
" License: MIT

if exists('g:autoloaded_claude_code_diff')
  finish
endif
let g:autoloaded_claude_code_diff = 1

" ---------------------------------------------------------------------------
" State
" ---------------------------------------------------------------------------

let s:diff_tab = -1
let s:diff_bufs = []
let s:poll_timer = -1
let s:trigger_dir = ''
let s:target_file = ''
let s:target_display = ''
let s:proposed_file = ''
let s:orig_file = ''
let s:transcript = ''
let s:transcript_start = 0
let s:suggested_category = ''
let s:decision_file = ''
let s:decided = 0
" Tutor mode: the hook already answered 'deny' and Claude moved on, so Vim owns
" the write and reports back by typing into the terminal, not via a decision file.
let s:no_wait = 0
let s:plugin_root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h:h')
if has('win32')
  let s:plugin_root = substitute(s:plugin_root, '\\', '/', 'g')
endif

" ---------------------------------------------------------------------------
" Polling — file-based IPC for hook → Vim communication
" ---------------------------------------------------------------------------

function! claude_code#diff#start_polling() abort
  if s:poll_timer >= 0
    return
  endif
  " User-global dir shared with the hooks — independent of either side's cwd
  let s:trigger_dir = expand('~/.claude/vim-diff')
  call mkdir(s:trigger_dir, 'p')
  let s:poll_timer = timer_start(1000, function('s:check_trigger'), {'repeat': -1})
  call claude_code#util#debug('diff: polling started (' . s:trigger_dir . ')')
endfunction

function! claude_code#diff#stop_polling() abort
  if s:poll_timer >= 0
    call timer_stop(s:poll_timer)
    let s:poll_timer = -1
    call claude_code#util#debug('diff: polling stopped')
  endif
endfunction

function! s:check_trigger(timer_id) abort
  " One preview at a time; leave other sessions' triggers for their Vims
  if claude_code#diff#is_open()
    return
  endif
  " Default (0): single-Vim mode — claim whatever trigger shows up, no
  " matter which repo it's for. Set g:claude_code_diff_match_repo_root = 1
  " to restrict this Vim to triggers under its own repo/cwd instead, so
  " each of several concurrently-open Vims only handles its own repo.
  let l:match_root = claude_code#config#get('diff_match_repo_root')
  if l:match_root
    let l:git_root = claude_code#git#root()
    let l:base = empty(l:git_root) ? getcwd() : l:git_root
  endif
  for l:trigger in glob(s:trigger_dir . '/*-trigger.json', 1, 1)
    " Parsing and showing are caught separately: one 'try' around both meant
    " any failure inside show() was reported as a parse error, with the trigger
    " already deleted and no retry — which made a broken preview undiagnosable.
    " Deliberately NOT deleting an unparseable trigger: the hook writes the
    " JSON non-atomically, so a half-written file parses as garbage for an
    " instant. Skipping self-heals on the next tick; deleting would turn that
    " race into a permanently lost patch.
    try
      let l:data = json_decode(join(readfile(l:trigger), "\n"))
    catch
      call claude_code#util#error('claude-code: failed to parse diff trigger — ' . v:exception)
      continue
    endtry
    try
      if l:match_root && stridx(l:data.file_path, l:base . '/') != 0
        continue
      endif
      " Claude runs inside a Vim terminal, and the hook recorded which Vim —
      " so leave other Vims' patches alone. Every Vim with the plugin loaded
      " polls this same user-global dir, and before this check whichever timer
      " fired first won: a long-idle Vim could silently swallow a patch meant
      " for the active session. 0/absent means Claude is not running under Vim,
      " so any Vim may take it (previous behaviour).
      " MUST 'continue' without deleting — the owning Vim still has to find it.
      let l:owner = get(l:data, 'vim_pid', 0)
      if l:owner > 0 && l:owner != getpid()
        continue
      endif
      " ponytail: delete-on-claim is the lock; two Vims in one repo can race
      call delete(l:trigger)
      if filereadable(l:data.orig) && filereadable(l:data.proposed)
        " Bookkeeping for THIS trigger is set inside show(), after its
        " internal "close any existing diff" call — not here. Setting it
        " here first meant that internal close() (which auto-sends 'ask'
        " for anything left undecided) fired against the new trigger's own
        " decision file before the tab even existed, resolving it instantly
        " regardless of what you later pressed.
        call claude_code#diff#show(l:data.orig, l:data.proposed, l:data.display_name,
              \ get(l:data, 'file_path', ''), get(l:data, 'decision_file', ''),
              \ get(l:data, 'transcript', ''), get(l:data, 'suggested_category', ''))
        " Set after show(), whose internal close() must still resolve the
        " PREVIOUS trigger under the previous trigger's mode.
        let s:no_wait = get(l:data, 'no_wait', 0)
      endif
      return
    catch
      " The trigger was already claimed (deleted) above, so nothing retries —
      " this message is the only remaining evidence the patch existed. Caught
      " rather than allowed to propagate, because this runs from a timer.
      call claude_code#util#error('claude-code: failed to open diff preview for '
            \ . get(l:data, 'display_name', '(unknown)') . ' — ' . v:exception)
    endtry
  endfor
endfunction

" Write the decision the blocked PreToolUse hook is waiting on
function! s:send_decision(decision, reason) abort
  let s:decided = 1
  " Tutor mode: nothing is blocked on a decision file — type the outcome into
  " the Claude terminal instead. 'ask' means dismissed with q: stay silent.
  if s:no_wait
    if a:decision !=# 'ask'
      call claude_code#terminal_bridge#send('[vim-claude-code] ' . a:reason)
    endif
    return
  endif
  if !empty(s:decision_file)
    call writefile([json_encode({'decision': a:decision, 'reason': a:reason})],
          \ s:decision_file)
  endif
endfunction

" Called by vim --servername --remote-expr for instant response
function! claude_code#diff#handle_trigger() abort
  call s:check_trigger(0)
  return ''
endfunction

" ---------------------------------------------------------------------------
" Diff display
" ---------------------------------------------------------------------------

" Index in the transcript of the MOST RECENT genuine user prompt — scanned
" backwards from the end, so it lands on the request that triggered this patch,
" not the first prompt of the session. Tool results are also recorded with
" type "user", so those are skipped. Falls back to a 40-line tail if no prompt
" is identifiable.
function! claude_code#diff#prompt_start(transcript) abort
  if empty(a:transcript) || !filereadable(a:transcript)
    return 0
  endif
  let l:all = readfile(a:transcript)
  let l:i = len(l:all) - 1
  while l:i >= 0
    if l:all[l:i] =~# '"type"\s*:\s*"user"' && l:all[l:i] !~# 'tool_result\|tool_use_id'
      return l:i
    endif
    let l:i -= 1
  endwhile
  return max([0, len(l:all) - 40])
endfunction

function! claude_code#diff#show(orig_file, proposed_file, display_name, ...) abort
  " Close any existing (previous, stale) diff first — must happen before
  " this trigger's own decision-file bookkeeping is set below, or this
  " call's internal "undecided -> ask" fallback fires against the NEW
  " trigger instead of whatever was left over from before.
  call claude_code#diff#close()

  " Real on-disk target, so 'gm' can write an edited version directly
  let s:target_file = a:0 >= 1 ? a:1 : ''
  " Decision file / provenance bookkeeping for THIS trigger — set only now,
  " after the stale-diff cleanup above.
  let s:decision_file = a:0 >= 2 ? a:2 : ''
  let s:transcript = a:0 >= 3 ? a:3 : ''
  " Where this patch's discussion begins: the user prompt that set Claude off.
  " Everything from there to accept-time is the full exchange — the request,
  " Claude's work, and (tutor mode) the Q&A while the patch sits open.
  let s:transcript_start = claude_code#diff#prompt_start(s:transcript)
  let s:suggested_category = a:0 >= 4 ? a:4 : ''
  let s:decided = 0
  " Repo-relative name, used for the '@' attachment reference back to Claude
  let s:target_display = a:display_name
  " Claude's pristine proposed content, to diff your edits against for the patch
  let s:proposed_file = a:proposed_file
  let s:orig_file = a:orig_file

  " Remember current tab so we can return if needed
  let l:prev_tab = tabpagenr()

  " --- New tab ---
  tabnew
  let s:diff_tab = tabpagenr()

  " --- Left window: CURRENT (original) ---
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  silent execute 'read ' . fnameescape(a:orig_file)
  silent 1delete _
  " Detect filetype from real filename for syntax highlighting
  execute 'doautocmd filetypedetect BufRead ' . fnameescape(a:display_name)
  setlocal nomodifiable readonly
  let &l:statusline = ' CURRENT: ' . a:display_name
  diffthis
  let l:orig_buf = bufnr('%')

  " --- Right window: PROPOSED ---
  rightbelow vsplit
  enew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  silent execute 'read ' . fnameescape(a:proposed_file)
  silent 1delete _
  execute 'doautocmd filetypedetect BufRead ' . fnameescape(a:display_name)
  " Leave PROPOSED editable so you can tweak it before applying with 'gm'
  setlocal modifiable noreadonly
  let &l:statusline = ' PROPOSED (editable): ' . a:display_name
  diffthis
  let l:prop_buf = bufnr('%')

  let s:diff_bufs = [l:orig_buf, l:prop_buf]

  " Preserve 'wrap' inside diff mode — Vim forces 'nowrap' on diff windows
  " unless 'diffopt' contains "followwrap". Older Vim builds (e.g. Debian's
  " patched 8.1) don't support this diffopt value at all and raise E474;
  " guard with try/catch so the diff view still opens (just without
  " 'wrap' preserved) instead of aborting the whole command.
  if &diffopt !~# 'followwrap'
    try
      set diffopt+=followwrap
    catch /E474/
    endtry
  endif

  " Show full file (open all folds) and soft-wrap long lines at word breaks
  windo setlocal foldenable foldmethod=diff foldlevel=999 foldcolumn=0 wrap linebreak breakindent

  " Equalize windows and jump to first change
  wincmd =
  normal! gg]c

  " Keymaps: q to close, ga to accept, gr to reject
  " Set via win_execute (not bare <buffer>, which binds to whichever buffer
  " is current in the current window regardless of l:buf) so both the ORIG
  " and PROPOSED windows get the mappings, not just whichever had focus.
  for l:buf in s:diff_bufs
    call setbufvar(l:buf, '&buflisted', 0)
    let l:winid = bufwinid(l:buf)
    if l:winid > 0
      call win_execute(l:winid, 'nnoremap <buffer> <silent> q :call claude_code#diff#close()<CR>')
      call win_execute(l:winid, 'nnoremap <buffer> <silent> ga :call claude_code#diff#accept()<CR>')
      call win_execute(l:winid, 'nnoremap <buffer> <silent> gr :call claude_code#diff#reject()<CR>')
      call win_execute(l:winid, 'nnoremap <buffer> <silent> gm :call claude_code#diff#apply_edited()<CR>')
    endif
  endfor

  if s:is_thesis_scope() && !get(g:, 'claude_code_allow_plain_accept', 0)
    echomsg 'claude-code: diff preview for ' . a:display_name . ' — edit PROPOSED then gm to apply | gr reject | q close (plain accept disabled)'
  else
    echomsg 'claude-code: diff preview for ' . a:display_name . ' — ga accept | gm apply edits | gr reject | q close'
  endif
endfunction

" ---------------------------------------------------------------------------
" Close diff
" ---------------------------------------------------------------------------

function! claude_code#diff#close() abort
  if s:diff_tab <= 0
    return ''
  endif

  " Dismissed without a decision (q, or a forced close): release the blocked
  " hook so Claude falls back to its own confirmation prompt
  if !s:decided
    call s:send_decision('ask', '')
  endif
  let s:decision_file = ''

  " Find and close the diff tab
  try
    let l:current_tab = tabpagenr()
    " Only close if the tab still exists
    if s:diff_tab <= tabpagenr('$')
      execute 'tabclose ' . s:diff_tab
      " If we were on a later tab, adjust index
      if l:current_tab > s:diff_tab
        execute 'tabnext ' . (l:current_tab - 1)
      elseif l:current_tab < s:diff_tab
        execute 'tabnext ' . l:current_tab
      endif
    endif
  catch
    " Tab may already be closed
  endtry

  " Clean up buffer references
  for l:buf in s:diff_bufs
    try
      if bufexists(l:buf)
        execute 'bwipeout! ' . l:buf
      endif
    catch
    endtry
  endfor

  " Tutor mode: the hook exited long ago, so Vim is the last reader of its
  " temp files and nothing else will remove them. (In blocking mode the hook
  " still cleans up after its wait loop — vim-preview-diff.py:204.) Safe here
  " because every reader has already run: accept()/apply_edited() call
  " record_provenance() and build_patch() before they call close().
  if s:no_wait
    for l:f in [s:orig_file, s:proposed_file]
      if !empty(l:f)
        call delete(l:f)
      endif
    endfor
  endif
  " Cleared unconditionally so a second close() cannot act on stale paths
  let s:orig_file = ''
  let s:proposed_file = ''

  let s:diff_tab = -1
  let s:diff_bufs = []
  return ''
endfunction

" ---------------------------------------------------------------------------
" Accept / Reject — send response to Claude terminal and close diff
" ---------------------------------------------------------------------------

function! claude_code#diff#accept() abort
  if s:is_thesis_scope() && !get(g:, 'claude_code_allow_plain_accept', 0)
    echohl WarningMsg
    echo 'claude-code: plain accept disabled (Transparency of Authorship policy) — edit PROPOSED then gm, or gr to reject. Enable with :let g:claude_code_allow_plain_accept=1'
    echohl None
    return
  endif
  let l:cat = s:prompt_category()
  if empty(l:cat)
    echo ' — accept cancelled (no category)'
    return
  endif
  call s:record_provenance('accepted', readfile(s:proposed_file), l:cat)
  if s:no_wait
    " Claude's write was already denied by the hook, so apply it ourselves
    if empty(s:target_file)
      call claude_code#util#error('claude-code: no target file recorded — cannot accept')
      return
    endif
    call claude_code#diff#mkdir_for(s:target_file)
    call writefile(readfile(s:proposed_file), s:target_file)
    silent! checktime
    call s:send_decision('allow', 'User accepted your patch to ' . s:target_display
          \ . ' unmodified; Vim has written it to disk. Re-read the file if you need it.')
  else
    call s:send_decision('allow', 'User reviewed and accepted the change in the Vim diff preview.')
  endif
  call claude_code#diff#close()
endfunction

function! claude_code#diff#reject() abort
  call s:record_provenance('rejected', [], 'n/a (rejected)')
  call s:send_decision('deny', 'User reviewed and rejected the change in the Vim diff preview. Do not re-apply it; await further instructions.')
  call claude_code#diff#close()
endfunction

" Create the target's parent directory if it does not exist yet. Claude's own
" Write creates parents; when Vim performs the write instead (tutor mode, or
" 'gm' in preview mode) nothing else does, and writefile() fails with E482.
function! claude_code#diff#mkdir_for(path) abort
  let l:dir = fnamemodify(a:path, ':h')
  if !empty(l:dir) && !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
endfunction

" ---------------------------------------------------------------------------
" Apply edited version — write the (edited) PROPOSED buffer straight to disk,
" decline Claude's own write so it does not clobber it, then tell Claude what
" the file now contains.
" ---------------------------------------------------------------------------

function! claude_code#diff#apply_edited() abort
  if empty(s:target_file)
    call claude_code#util#error('claude-code: no target file recorded — cannot apply edited version')
    return
  endif
  if len(s:diff_bufs) < 2 || !bufexists(s:diff_bufs[1])
    call claude_code#util#error('claude-code: proposed buffer unavailable')
    return
  endif

  " Capture the (possibly edited) proposed content before the buffers are wiped
  let l:lines = getbufline(s:diff_bufs[1], 1, '$')

  " Unedited proposal cannot be applied via gm unless plain accept is enabled:
  " the policy requires the PGR's own judgement to be visible in the change
  " (thesis prose only — not PTAPP-governed code/tooling)
  if s:is_thesis_scope() && !get(g:, 'claude_code_allow_plain_accept', 0)
        \ && l:lines ==# readfile(s:proposed_file)
    echohl WarningMsg
    echo 'claude-code: PROPOSED is unedited — rephrase it in your own words (critical oversight), or gr to reject'
    echohl None
    return
  endif

  let l:cat = s:prompt_category()
  if empty(l:cat)
    echo ' — apply cancelled (no category)'
    return
  endif
  call s:record_provenance(l:lines ==# readfile(s:proposed_file) ? 'accepted' : 'modified', l:lines, l:cat)
  let l:target = s:target_file
  let l:display = s:target_display

  " Write our edited version directly to the real file
  try
    call claude_code#diff#mkdir_for(l:target)
    call writefile(l:lines, l:target)
  catch
    call claude_code#util#error('claude-code: failed to write ' . l:target . ' — ' . v:exception)
    return
  endtry
  silent! checktime

  " Build a unified patch of *our* edits (edited buffer vs Claude's proposal)
  let l:patch_ref = s:build_patch(s:proposed_file, l:lines, l:display)

  " Deny Claude's pending write (the file already holds the user's version)
  " and explain via the decision reason — reaches Claude in any terminal
  let l:reason = 'User applied their own edited version of your proposal directly to '
        \ . l:display . '. Do not re-apply your edit; re-read the file to see the current content.'
  if !empty(l:patch_ref)
    let l:reason .= ' Their edits relative to your proposal: ' . l:patch_ref
  endif
  call s:send_decision('deny', l:reason)
  call claude_code#diff#close()

  echomsg 'claude-code: applied your edited version to ' . l:target
endfunction

" Write a unified diff (proposed -> edited) to a temp file and return its
" absolute path (referenced in the deny reason). Empty on failure.
function! s:build_patch(proposed_file, edited_lines, display) abort
  if empty(a:proposed_file) || !filereadable(a:proposed_file) || !executable('diff')
    return ''
  endif
  let l:edited_file = s:trigger_dir . '/claude-vim-diff-edited'
  let l:patch_file = s:trigger_dir . '/user-edits-' . strftime('%Y%m%d-%H%M%S') . '.diff'
  try
    call writefile(a:edited_lines, l:edited_file)
    " -u unified; labels so the patch reads against the real filename
    let l:cmd = 'diff -u'
          \ . ' --label ' . shellescape('a/' . a:display)
          \ . ' --label ' . shellescape('b/' . a:display)
          \ . ' ' . shellescape(a:proposed_file)
          \ . ' ' . shellescape(l:edited_file)
    let l:out = systemlist(l:cmd)
    call delete(l:edited_file)
    if empty(l:out)
      return ''
    endif
    call writefile(l:out, l:patch_file)
    return l:patch_file
  catch
    return ''
  endtry
endfunction

" ---------------------------------------------------------------------------
" Provenance recording — AI_POLICY/provenance/<file>/<timestamp>/
" Evidence trail per Policy on Transparency of Authorship (Appendix 10 §38):
" Claude's original patch, the human-vetted accepted patch, the discussion
" excerpt, and a meta.yaml with the decision.
" ---------------------------------------------------------------------------

function! s:unified_diff(from_file, to_lines, label_a, label_b) abort
  if !executable('diff')
    return []
  endif
  let l:tmp = s:trigger_dir . '/claude-vim-prov-tmp'
  call writefile(a:to_lines, l:tmp)
  let l:out = systemlist('diff -u'
        \ . ' --label ' . shellescape(a:label_a)
        \ . ' --label ' . shellescape(a:label_b)
        \ . ' ' . shellescape(a:from_file)
        \ . ' ' . shellescape(l:tmp))
  call delete(l:tmp)
  return l:out
endfunction

" Thesis-submitted prose (PTAPP-governed) vs everything else (tooling/code,
" outside PTAPP scope per §2 — see AI_POLICY/README.md §3.4 ).
function! s:is_thesis_scope() abort
  return tolower(fnamemodify(s:target_display, ':e')) =~# '^\%(tex\|bib\)$'
endfunction

" Not PTAPP-governed (tooling/code, §2) — no forced classification, the
" accepted/modified/rejected decision already recorded is enough.
let s:code_category = 'code-tooling (not PTAPP-governed)' 

" Forced classification at accept time, grounded in Appendix 10.
" Returns the chosen category string, or '' if the user cancelled.
function! s:prompt_category() abort
  " Tutor mode is its own context: the patch is a teaching artefact (concepts,
  " exercises, feedback, scaffolding), not authored content or a prose fix.
  if s:no_wait
    return 'tutoring (AI-assisted learning exchange, not authored content)'
  endif
  if !s:is_thesis_scope()
    return s:code_category
  endif
  let l:opts = [
        \ '7.2-correction: word usage / typographical error fix (permitted, identify+correct)',
        \ '7.3.1-grammar-and-syntax: identified, not corrected; fix is my own wording (7.4 selection)',
        \ '7.3.2-clarity-of-expression: identified, not corrected; fix is my own wording (7.4 selection)',
        \ '7.3.3-voice-and-tone: identified, not corrected; fix is my own wording (7.4 selection)',
        \ '7.3.4-logical-sequencing: identified, not corrected; fix is my own wording (7.4 selection)',
        \ '7.3.5-ambiguity: identified, not corrected; fix is my own wording (7.4 selection)',
        \ '7.3.6-repetition: identified, not corrected; fix is my own wording (7.4 selection)',
        \ '9.1-integrated-check: equivalent to standard spell/grammar check (no acknowledgement needed)',
        \ '8.1-8.2-OUT-OF-SCOPE (a new version of my content, not a fix to a located defect): rewrite/summary/argument/code/figure content — should be REJECTED, not accepted',
        \ 'other: free-form entry',
        \ ]
  let l:header = 'claude-code: classify this change (Transparency of Authorship policy):'
  if !empty(s:suggested_category)
    let l:header .= ' [AI suggests: ' . s:suggested_category . ' — your call]'
  endif
  let l:choice = inputlist([l:header]
        \ + map(copy(l:opts), 'string(v:key + 1) . ". " . v:val'))
  if l:choice < 1 || l:choice > len(l:opts)
    return ''
  endif
  if l:choice == len(l:opts)
    let l:free = input('category (free-form): ')
    return empty(l:free) ? '' : l:free
  endif
  let l:picked = l:opts[l:choice - 1]
  " Accepting out-of-scope assistance is a policy breach — warn, allow override with a reason
  if l:picked =~# '^8\.1-8\.2-OUT-OF-SCOPE'
    let l:why = input('8.1-8.2 assistance must normally be rejected. Reason for accepting anyway (empty = cancel): ')
    return empty(l:why) ? '' : matchstr(l:picked, '^\S*') . ' OVERRIDE: ' . l:why
  endif
  return l:picked
endfunction

 

function! s:record_provenance(decision, accepted_lines, category) abort
  try
    let l:git_root = claude_code#git#root()
    let l:base = empty(l:git_root) ? getcwd() : l:git_root
    let l:stamp = strftime('%Y-%m-%dT%H-%M-%S')
    let l:slug = substitute(s:target_display, '[/\\]', '__', 'g')
    let l:dir = l:base . '/AI_POLICY/provenance/' . l:slug . '/' . l:stamp
    call mkdir(l:dir, 'p')

    call writefile(s:unified_diff(s:orig_file, readfile(s:proposed_file),
          \ 'a/' . s:target_display, 'b/' . s:target_display . ' (claude proposal)'),
          \ l:dir . '/original.patch')
    if a:decision !=# 'rejected'
      call writefile(s:unified_diff(s:orig_file, a:accepted_lines,
            \ 'a/' . s:target_display, 'b/' . s:target_display . ' (accepted)'),
            \ l:dir . '/accepted.patch')
    endif

    " Discussion excerpt: tail of the Claude Code transcript (JSONL)
    if !empty(s:transcript) && filereadable(s:transcript)
      let l:all = readfile(s:transcript)
      " From the user prompt that triggered this patch, through to now —
      " whole, however long it ran. In tutor mode the patch stays open while
      " you and Claude talk, and that entire exchange belongs in the record.
      call writefile(l:all[s:transcript_start :], l:dir . '/discussion.jsonl')
    endif

    call writefile([
          \ 'file: ' . s:target_display,
          \ 'timestamp: ' . l:stamp,
          \ 'decision: ' . a:decision,
          \ 'tool: Claude Code via vim-claude-code',
          \ 'operator: ' . expand('$USER'),
          \ 'category: ' . a:category,
          \ 'ai_suggested_category: ' . s:suggested_category,
          \ ], l:dir . '/meta.yaml')

    let l:log = l:base . '/AI_POLICY/provenance/LOG.md'
    let l:entry = '- ' . l:stamp . ' `' . s:target_display . '` — ' . a:decision
    call writefile(filereadable(l:log) ? readfile(l:log) + [l:entry] : [l:entry], l:log)
  catch
    call claude_code#util#error('claude-code: provenance recording failed — ' . v:exception)
  endtry
endfunction

" ---------------------------------------------------------------------------
" Status
" ---------------------------------------------------------------------------

function! claude_code#diff#is_open() abort
  return s:diff_tab > 0 && s:diff_tab <= tabpagenr('$')
endfunction

function! claude_code#diff#is_polling() abort
  return s:poll_timer >= 0
endfunction

" ---------------------------------------------------------------------------
" Hook management — install/uninstall PreToolUse & PostToolUse hooks
" ---------------------------------------------------------------------------

function! s:bin_dir() abort
  return s:plugin_root . '/bin'
endfunction

" a:1 (optional): 1 = tutor mode — hook returns immediately instead of blocking
" on Vim's decision, and the tutor skill is linked into the project.
function! claude_code#diff#install_hooks(...) abort
  let l:tutor = a:0 && a:1
  let l:bin = s:bin_dir()
  let l:preview_script = l:bin . '/vim-preview-diff.py'
  let l:close_script = l:bin . '/vim-close-diff.py'

  " Verify scripts exist
  if !filereadable(l:preview_script)
    call claude_code#util#error('claude-code: hook script not found: ' . l:preview_script)
    return
  endif
  if !filereadable(l:close_script)
    call claude_code#util#error('claude-code: hook script not found: ' . l:close_script)
    return
  endif

  " Determine settings path
  let l:git_root = claude_code#git#root()
  let l:base = empty(l:git_root) ? getcwd() : l:git_root
  let l:settings_dir = l:base . '/.claude'
  let l:settings_path = l:settings_dir . '/settings.local.json'

  " Read existing settings
  let l:data = {}
  if filereadable(l:settings_path)
    try
      let l:raw = join(readfile(l:settings_path), "\n")
      if !empty(l:raw)
        let l:data = json_decode(l:raw)
      endif
    catch
      call claude_code#util#error('claude-code: failed to parse ' . l:settings_path)
      return
    endtry
  endif

  " Ensure hooks structure exists
  if !has_key(l:data, 'hooks')
    let l:data.hooks = {}
  endif
  if !has_key(l:data.hooks, 'PreToolUse')
    let l:data.hooks.PreToolUse = []
  endif
  if !has_key(l:data.hooks, 'PostToolUse')
    let l:data.hooks.PostToolUse = []
  endif

  " Remove any existing vim-claude-code diff entries (avoid duplicates).
  " Matches BOTH scripts: the PostToolUse command is vim-close-diff.py, which
  " the old 'vim-preview-diff' marker never matched — so every install appended
  " another Post entry and removed none.
  let l:marker = '-diff.py'
  call s:remove_hook_entries(l:data.hooks.PreToolUse, l:marker)
  call s:remove_hook_entries(l:data.hooks.PostToolUse, l:marker)

  " Add our entries
  call add(l:data.hooks.PreToolUse, {
        \ 'matcher': 'Edit|Write|MultiEdit',
        \ 'hooks': [{'type': 'command',
        \            'command': l:preview_script . (l:tutor ? ' --no-wait' : ''),
        \            'timeout': 600}],
        \ })
  call add(l:data.hooks.PostToolUse, {
        \ 'matcher': 'Edit|Write|MultiEdit',
        \ 'hooks': [{'type': 'command', 'command': l:close_script}],
        \ })

  " Write settings
  call mkdir(l:settings_dir, 'p')
  call writefile([json_encode(l:data)], l:settings_path)

  " Tutor mode also needs the skill visible to Claude in this project.
  " g:claude_code_tutor_version selects which plugin-side skill dir is
  " linked ('v1' -> the original 'tutor'; anything else, including the
  " default, -> 'tutor-v2'); the project-side link name stays 'tutor'
  " either way so the skill name Claude resolves is unaffected.
  let l:version = claude_code#config#get('tutor_version')
  if l:tutor
    let l:skill_src = (l:version ==# 'v1') ? 'tutor' : 'tutor-v2'
    call mkdir(l:settings_dir . '/skills', 'p')
    call delete(l:settings_dir . '/skills/tutor', 'rf')
    call system('ln -sfn ' . shellescape(s:plugin_root . '/skills/' . l:skill_src)
          \ . ' ' . shellescape(l:settings_dir . '/skills/tutor'))
  endif

  " Start polling
  call claude_code#diff#start_polling()

  echomsg 'claude-code: ' . (l:tutor ? 'tutor (' . l:version . ')' : 'diff preview')
        \ . ' hooks installed -> ' . l:settings_path
endfunction

function! claude_code#diff#uninstall_hooks() abort
  " Determine settings path
  let l:git_root = claude_code#git#root()
  let l:base = empty(l:git_root) ? getcwd() : l:git_root
  let l:settings_path = l:base . '/.claude/settings.local.json'

  if !filereadable(l:settings_path)
    call claude_code#util#error('claude-code: no settings found at ' . l:settings_path)
    return
  endif

  let l:data = {}
  try
    let l:raw = join(readfile(l:settings_path), "\n")
    if !empty(l:raw)
      let l:data = json_decode(l:raw)
    endif
  catch
    call claude_code#util#error('claude-code: failed to parse ' . l:settings_path)
    return
  endtry

  if !has_key(l:data, 'hooks')
    echomsg 'claude-code: no hooks found in ' . l:settings_path
    return
  endif

  " Matches both scripts — see install_hooks(); uninstall previously left every
  " PostToolUse entry behind.
  let l:marker = '-diff.py'
  if has_key(l:data.hooks, 'PreToolUse')
    call s:remove_hook_entries(l:data.hooks.PreToolUse, l:marker)
  endif
  if has_key(l:data.hooks, 'PostToolUse')
    call s:remove_hook_entries(l:data.hooks.PostToolUse, l:marker)
  endif

  call writefile([json_encode(l:data)], l:settings_path)

  " Stop polling
  call claude_code#diff#stop_polling()

  echomsg 'claude-code: diff preview hooks removed from ' . l:settings_path
endfunction

" Remove entries whose command contains the marker string
function! s:remove_hook_entries(list, marker) abort
  let l:i = len(a:list) - 1
  while l:i >= 0
    let l:entry = a:list[l:i]
    if has_key(l:entry, 'hooks') && !empty(l:entry.hooks)
      let l:cmd = get(l:entry.hooks[0], 'command', '')
      if stridx(l:cmd, a:marker) >= 0
        call remove(a:list, l:i)
      endif
    endif
    let l:i -= 1
  endwhile
endfunction

" ---------------------------------------------------------------------------
" Doctor check for diff preview dependencies
" ---------------------------------------------------------------------------

function! claude_code#diff#check_deps() abort
  let l:results = []

  if executable('python3')
    if has('win32')
      let l:ver = systemlist('python3 --version')[0]
      if l:ver =~# '^Python 3\.'
        call add(l:results, '[OK]   python3 found (' . l:ver . ')')
      else
        call add(l:results, '[FAIL] python3 found but version is not 3.x (' . l:ver . ')')
      endif
    else
      call add(l:results, '[OK]   python3 found')
    endif
  else
    call add(l:results, '[FAIL] python3 not found — required for diff preview')
  endif



  if has('clientserver')
    call add(l:results, '[OK]   +clientserver support (instant diff, optional)')
  else
    call add(l:results, '[INFO] No +clientserver — using file-based polling (works fine)')
  endif

  return l:results
endfunction
