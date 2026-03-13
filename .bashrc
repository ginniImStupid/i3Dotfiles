#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias steam="steam -system-composer & disown"
alias ff="fastfetch -c examples/13"
alias nv='nvim'

PS1="$(if [[ ${EUID} == 0 ]]; then echo '\[\033[01;31m\]\u@\h'; else echo '\[\033[01;32m\]\u@\h'; fi)\[\033[33m\] \D{%F %T}\[\033[01;34m\] \w\[\033[00m\]\n\$([[ \$? != 0 ]] && echo \"\")\\$ "
