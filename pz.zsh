# http://github.com/mattmc3/pz
# Copyright mattmc3, 2020-2021
# MIT license, https://opensource.org/licenses/MIT
#
# pz - Plugins for ZSH made easy-pz
#

# init settings
_zero=${(%):-%N}
() {
  if zstyle -T :pz: plugins-dir; then
    zstyle :pz: plugins-dir ${_zero:A:h:h}
  fi
  if zstyle -T :pz:clone: default-gitserver; then
    zstyle :pz:clone: default-gitserver 'github.com'
  fi
}
unset _zero

function _pz_help() {
  if (( $+functions[pz_extended_help] )); then
    pz_extended_help $@
  else
    echo "usage:"
    echo "  pz <command> [<flags...>] [<arguments...>]"
    echo "commands:"
    echo "  help, clone, list, prompt, pull, source"
  fi
}

function _pz_clone() {
  local pluginsdir; zstyle -s :pz: plugins-dir pluginsdir
  local gitserver; zstyle -s :pz:clone: default-gitserver gitserver

  local repo="$1"
  if [[ $repo != git://* &&
        $repo != https://* &&
        $repo != http://* &&
        $repo != ssh://* &&
        $repo != git@*:*/* ]]; then
    repo="https://${gitserver}/${repo%.git}.git"
  fi
  git -C "$pluginsdir" clone --recursive --depth 1 "$repo"
  [[ $! -eq 0 ]] || return 1
}

function _pz_list() {
  local pluginsdir; zstyle -s :pz: plugins-dir pluginsdir
  local gitserver; zstyle -s :pz:clone: default-gitserver gitserver

  local httpsgit="https://$gitserver"
  local flag_short_name=false
  if [[ "$1" == "-s" ]]; then
    flag_short_name=true
    shift
  fi

  for d in $pluginsdir/*(/N); do
    if [[ $flag_short_name == true ]]; then
      echo "${d:t}"
    else
      [[ -d $d/.git ]] || continue
      repo_url=$(git -C "$d" remote get-url origin)
      if [[ "$repo_url" == ${repo_url#$httpsgit/} ]]; then
        echo "$repo_url"
      else
        echo ${${repo_url#$httpsgit/}%.git}
      fi
    fi
  done
}

function _pz_prompt() {
  local pluginsdir; zstyle -s :pz: plugins-dir pluginsdir

  local flag_add_only=false
  if [[ "$1" == "-a" ]]; then
    flag_add_only=true
    shift
  fi
  local repo="$1"
  local plugin=${${repo##*/}%.git}
  [[ -d $pluginsdir/$plugin ]] || _pz_clone "$@"
  fpath+=$pluginsdir/$plugin
  if [[ $flag_add_only == false ]]; then
    autoload -U promptinit
    promptinit
    prompt "$plugin"
  fi
}

function _pz_pull() {
  local pluginsdir; zstyle -s :pz: plugins-dir pluginsdir

  local p update_plugins
  if [[ -n "$1" ]]; then
    update_plugins=(${${1##*/}%.git})
  else
    update_plugins=($(_pz_list -s))
  fi
  for p in $update_plugins; do
    echo "updating ${p:t}..."
    git -C "$pluginsdir/$p" pull --rebase --autostash
  done
}

function __pz_get_source_file() {
  local pluginsdir; zstyle -s :pz: plugins-dir pluginsdir

  local plugin=${${1##*/}%.git}
  local plugin_path="$pluginsdir/$plugin"
  [[ -d $plugin_path ]] || return 2

  local search_files
  if [[ -z "$2" ]]; then
    # if just a repo was specified, the search is more broad
    if [[ -f "$plugin_path/$plugin.plugin.zsh" ]]; then
      # let's do a performance shortcut for adherents to proper convention
      search_files=("$plugin_path/$plugin.plugin.zsh")
    else
      search_files=(
        # look for specific files first
        $plugin_path/$plugin.zsh(.N)
        $plugin_path/$plugin(.N)
        $plugin_path/$plugin.zsh-theme(.N)
        $plugin_path/init.zsh(.N)
        # then do more aggressive globbing
        $plugin_path/*.plugin.zsh(.N)
        $plugin_path/*.zsh(.N)
        $plugin_path/*.zsh-theme(.N)
        $plugin_path/*.sh(.N)
      )
    fi
  else
    # if a subplugin was specified, the search is more specific
    local subpath=${2%/*}
    local subplugin=${2##*/}
    search_files=(
        # look for specific files
        $plugin_path/$2(.N)
        $plugin_path/$subpath/$subplugin.plugin.zsh(.N)
        $plugin_path/$subpath/$subplugin.zsh(.N)
        $plugin_path/$subpath/$subplugin/$subplugin.plugin.zsh(.N)
        $plugin_path/$subpath/$subplugin/init.zsh(.N)
        $plugin_path/$subpath/$subplugin.zsh-theme(.N)
      )
  fi
  [[ ${#search_files[@]} -gt 0 ]] || return 1
  echo ${search_files[1]}
}

function _pz_source() {
  local source_file=$(__pz_get_source_file "$@")
  if [[ $? -eq 2 ]]; then
    _pz_clone $repo
    source_file=$(__pz_get_source_file "$@")
  fi
  [[ -n "$source_file" ]] || {
    echo "plugin not found $1 $2" >&2
    return 1
  }
  fpath+="${source_file:a:h}"
  source "$source_file"
}

function pz() {
  local pluginsdir; zstyle -s :pz: plugins-dir pluginsdir

  local cmd="$1"
  [[ -d "$pluginsdir" ]] || mkdir -p "$pluginsdir"

  if functions "_pz_${cmd}" > /dev/null ; then
    shift
    _pz_${cmd} "$@"
    return $?
  elif [[ -z $cmd ]]; then
    _pz_help
    return
  else
    echo "pz command not found: '${cmd}'" >&2 && return 1
  fi
}
