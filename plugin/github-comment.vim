" github-comment: Make GitHub comments straight from within Vim
" Author:         mmozuras
" HomePage:       https://github.com/mmozuras/vim-github-comment
" Readme:         https://github.com/mmozuras/vim-github-comment/blob/master/README.md
" Version:        0.0.1

let s:tokenfile = expand('~/.github-comment')

if !executable('git')
  echohl ErrorMsg | echomsg "github-comment requires 'git'" | echohl None
  finish
endif

if !exists('g:github_user')
  echohl ErrorMsg | echomsg "github-comment requires 'g:github_user' to be set" | echohl None
  finish
endif

if !executable('curl')
  echohl ErrorMsg | echomsg "github-comment requires 'curl'" | echohl None
  finish
endif

com! -nargs=+ GHComment call GHComment(<q-args>)

function! GHComment(body)
  let auth = s:GetAuthHeader()
  if len(auth) == 0
    echohl ErrorMsg | echomsg "github-comment auth failed" | echohl None
    return
  endif

  let repo = s:GitHubRepository()
  let commit_sha = s:CommitShaForCurrentLine()
  let path = s:GetRelativePathOfBufferInRepository()
  let linenumber = line('.')
  let comment = a:body
  let save_view = winsaveview()

  execute s:CommentOnGitHub(auth, repo, commit_sha, path, linenumber, comment)

  call winrestview(save_view)
endfunction

function! s:CommentOnGitHub(auth, repo, commit_sha, path, linenumber, comment)
  let request_uri = 'https://api.github.com/repos/'.a:repo.'/commits/'.a:commit_sha.'/comments'

  let response = webapi#http#post(request_uri, webapi#json#encode({
                  \  "path" : a:path,
                  \  "line" : a:linenumber,
                  \  "body" : a:comment
                  \}), {
                  \   "Authorization": a:auth,
                  \   "Content-Type": "application/json",
                  \})
endfunction

function! s:GitHubRepository()
  let cmd = 'git ls-remote --get-url'
  let remote = system(cmd)

  let name = split(remote, 'git://github\.com/')[0]
  let name = split(name, 'git@github\.com:')[0]
  let name = split(name, '\.git')[0]

  return name
endfunction

function! s:CommitShaForCurrentLine()
  let linenumber=line('.')
  let path=expand('%:p')

  let cmd = 'git blame -L'.linenumber.','.linenumber.' --porcelain '.path
  let blame_text = system(cmd)

  return matchstr(blame_text, '\w\+')
endfunction

function! s:GetAuthHeader()
  let token = ""
  if filereadable(s:tokenfile)
    let token = join(readfile(s:tokenfile), "")
  endif
  if len(token) > 0
    return token
  endif

  let password = inputsecret("GitHub password for ".g:github_user.":")
  if len(password) > 0
    let authorization = s:Authorize(password)

    if has_key(authorization, 'token')
      let token = printf("token %s", authorization.token)
      execute s:WriteToken(token)
    endif
  endif

  return token
endfunction

function! s:WriteToken(token)
  call writefile([a:token], s:tokenfile)
  call system("chmod go= ".s:tokenfile)
endfunction

function! s:Authorize(password)
  let auth = printf("basic %s", webapi#base64#b64encode(g:github_user.":".a:password))
  let response = webapi#http#post('https://api.github.com/authorizations', webapi#json#encode({
                  \  "scopes"        : ["repo"],
                  \}), {
                  \  "Content-Type"  : "application/json",
                  \  "Authorization" : auth,
                  \})
  return webapi#json#decode(response.content)
endfunction

function! s:GetRelativePathOfBufferInRepository()
  let buffer_path = expand("%:p")
  let git_dir = s:GetGitTopDir()."/"

  return substitute(buffer_path, git_dir, "", "")
endfunction

function! s:GetGitTopDir()
  let buffer_path = expand("%:p")
  let buf = split(buffer_path, "/")

  while len(buf) > 0
    let path = "/".join(buf, "/")

    if empty(finddir(path."/.git"))
      call remove(buf, -1)
    else
      return path
    endif
  endwhile

  return ""
endfunction
