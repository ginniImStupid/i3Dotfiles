#!/usr/bin/env bash

# Copyright (C) 2024  Blyte Scholar

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


#########################################################################
# Usage:                                                                #
# Place this script in your rofi scripts directory                      #
# (i.e. copy it to  ~/.config/rofi/scripts/waypass)                     #
# and make it executable. Then invoke it with the following command:    #
#                                                                       #
# rofi -show waypass                                                    #
#                                                                       #
# The custom keybindings 1 and 2 are used to cycle between user/pass    #
# and copying/autotyping. These default to Alt+1 and Alt+2 but can be   #
# set during the rofi invocation with the -kb-custom-1 and              #
# -kb-custom-2 switches.                                                #
#                                                                       #
# For example, to set Alt-a to toggle auto-typing and Alt-p to cycle    #
# between user/pass/both:                                               #
# rofi -show waypass -kb-custom-1 "Alt+p" -kb-custom-2 "Alt+a"          #
#                                                                       #
#                                                                       #
# Keybindings:                                                          #
#  kb-custom-1: cycle b/w username, password, and both                  #
#  kb-custom-2: toggle between copy to clipboard and auto-typing        #
#########################################################################


#########################################################################
# USER Configuration Variables					        #
# 								        #
# # Notification                                                        #
#   The icon can be the name of an icon or the full path to one.        #
# 								        #
# # Prompt							        #
#  The rofi prompt will be formed from $pre$content$post where $content #
#  is determined by which data is being acted on		        #
#  (username/password/both). In the case of both, the separator is      #
#  added between them.						        #
#########################################################################

SEND_NOTIFICATIONS=1
NOTIFICATION_ICON="dialog-password"
NOTIFICATION_APP_NAME="Password Store"

CLIPBOARD_PROMPT_PRE="Copy "
CLIPBOARD_PROMPT_POST=" to clipboard"
USERNAME_PROMPT="username"
PASSWORD_PROMPT="password"
AUTOTYPE_PROMPT_PRE="Autotype "
AUTOTYPE_PROMPT_POST=""
MULTIPLE_SEP_PROMPT=" and "

## Autotype Configuration
WAIT_BEFORE_TYPING=0.2

## Password Store Configuration
PASSWORD_STORE_DIR="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
PASSWORD_STORE_EXTENSIONS_DIR="${PASSWORD_STORE_EXTENSIONS_DIR:-$PASSWORD_STORE_DIR/.extensions}"
PASSWORD_STORE_SYSTEM_EXTENSIONS_DIR="/usr/lib/password-store/extensions"
PASSWORD_STORE_CLIP_TIME="${PASSWORD_STORE_CLIP_TIME:-5}"
PASS_EXTRA_ARGS=""
PASS="pass $PASS_EXTRA_ARGS"

DEBUG_MODE=0


#########################################################################
# Global Constants                                                      #
#########################################################################

## ROFI_RETV states
_ROFI_INIT=0
_ROFI_SELECTED=1
_ROFI_CUSTOM=2
# These signal custom hotkeys
_AUTOTYPE=10
_CYCLE_MODE=11

## Values signifying active mode
_MODE_PASSWORD=0
_MODE_USERNAME=1
_MODE_USERPASS=2
_MODE_MAX=3

_AUTOTYPE_ENABLED=1


#########################################################################
# Password Store Extensions                                             #
# The optional `pass attr` extension is required to check if a username #
# if present in a multiline file.                                       #
#########################################################################

_pass_attr=0
if [ -e "$PASSWORD_STORE_SYSTEM_EXTENSIONS_DIR/attr.bash" ]
then
    _pass_attr=1
elif [ -e "$PASSWORD_STORE_EXTENSIONS_DIR/attr.bash" ] &&
     [ "$PASSWORD_STORE_ENABLE_EXTENSIONS" = true ]
then
    _pass_attr=1
fi


#########################################################################
# Start of main script                                                  #
#########################################################################

main() {
    shopt -s nullglob globstar

    check_dependencies

    pass_file="$1"

    # Defaults to copying password to clipboard.
    _mode=$_MODE_PASSWORD
    _autotype=0


    _window_state=""

    # Hotkeys are used to cycle between modes.
    rofi_set_option use-hot-keys true

    # Typing in a custom entry should not be supported.
    rofi_set_option no-custom true

    # Restore saved data.
    #
    # rofi runs the script multiple times so this needed to persist
    # variables.
    eval "$ROFI_DATA"

    # Contains the return code of the previous rofi run. Used to
    # signify state of rofi/what action was taken including custom
    # hotkeys.
    case "$ROFI_RETV" in
	"$_ROFI_SELECTED")
	    # A password has been selected.
	    rofi_act_on_file "$pass_file" || die "Error reading from '$pass_file'"
	    exit 0
	    ;;
	"$_CYCLE_MODE")
	    # Cycle between available modes.
	    ((_mode = (_mode + 1) % _MODE_MAX))
	    ;;
	"$_AUTOTYPE")
	    # Toggle between copying and autotyping.
	    ((_autotype ^= 1))
	    if [ $_autotype -eq 1 ]
	    then
		lock_window > /dev/null
	    else
		restore_state > /dev/null
	    fi
	    ;;

    esac

    # Store variables for next iteration.
    rofi_store_data

    # Update the rofi prompt based on the current mode.
    rofi_update_prompt

    # Display all available password files in rofi.
    rofi_display_password_files

}

#########################################################################
# Utility Functions                                                     #
#########################################################################

die() {
   printf "%s\n" "$*" 1>&2
   rofi_set_option prompt Error
   rofi_set_option message "$*"
   exit 1
}

debug() {
    [ $DEBUG_MODE -eq 1 ] && printf "%s\n" "$*" 1>&2
}

check_dependencies() {
    for bin in pass notify-send wtype rofi
    do
	command -v "$bin" >/dev/null || die "No executable '$bin' found in PATH."
    done

}

#########################################################################
# Rofi-specific functions                                               #
#########################################################################

rofi_set_option() {
    printf '\0%s\x1f%s\n' "$1" "$2"
}

rofi_store_data() {
    save_state
    rofi_set_option data "_autotype=$_autotype; _mode=$_mode; _window_state=$_window_state"
    debug "Data stored: '$ROFI_DATA'"
}

rofi_update_prompt() {
    # Use the prompt for copying.
    if [ $_autotype -eq 0 ]; then
	if [ $_mode -eq $_MODE_USERNAME ]; then
	    copy_prompt="$USERNAME_PROMPT"
	else
	    # When username and password are selected, copy password.
	    copy_prompt="$PASSWORD_PROMPT"
	fi
	prompt="$CLIPBOARD_PROMPT_PRE$copy_prompt$CLIPBOARD_PROMPT_POST"
    else
	# Use the prompt for autotyping.
	prompt="$AUTOTYPE_PROMPT_PRE"
	if [ $_mode -gt $_MODE_PASSWORD ]
	then
	    prompt="$prompt$USERNAME_PROMPT"
	    [ $_mode -eq $_MODE_USERPASS ] && prompt="$prompt$MULTIPLE_SEP_PROMPT"
	fi

	if [ $_mode -eq $_MODE_PASSWORD ] || [ $_mode -eq $_MODE_USERPASS ]
	then
	    prompt="$prompt$PASSWORD_PROMPT"
	fi

	prompt="$prompt$AUTOTYPE_PROMPT_POST"
    fi
    rofi_set_option prompt "$prompt"
}

rofi_display_password_files() {
    # Requires `shopt -s nullglob globstar`.
    pass_files=( "$PASSWORD_STORE_DIR"/**/*.gpg )
    pass_files=( "${pass_files[@]#"$PASSWORD_STORE_DIR"/}" )
    pass_files=( "${pass_files[@]%.gpg}" )

    printf '%s\n' "${pass_files[@]}"
}

rofi_act_on_file() {
    pass_file="$1"

    # Type entry out.
    if [ $_autotype -eq $_AUTOTYPE_ENABLED ]; then
	autotype "$1"
    else
	# Copy entry to clipboard.
	if [ $_mode -eq $_MODE_USERNAME ]; then
	    echo "Getting username" 1>&2
	    pass_get_user "$pass_file" | CLIPBOARD_STATE=sensitive wl-copy
	else
	    $PASS show -c "$pass_file" >/dev/null
	fi

	coproc send_countdown_notification
    fi
}

#########################################################################
# Auto-type functions                                                   #
#########################################################################

# rofi runs this before exiting, so put it in a coprocess and sleep
# before typing.
_wtype() {
    coproc (
	sleep $WAIT_BEFORE_TYPING
	restore_state
	wtype "$1" >/dev/null 2>&1
	if [ -n "$2" ]; then
	    wtype -k Tab
	    sleep $WAIT_BEFORE_TYPING
	    wtype -d 50 "$2" >/dev/null 2>&1
	fi
    )
}

autotype() {
    pass_file="$1"
    username="$(pass_get_user "$pass_file")"
    password="$(pass_get_pass "$pass_file")"

    case $_mode in
	$_MODE_PASSWORD)
	    _wtype "$password"
	    ;;
	$_MODE_PASSWORD)
	    _wtype "$username"
	    ;;
	$_MODE_USERPASS)
	    _wtype "$username" "$password"
	    ;;
    esac

}

#########################################################################
# Password Store definitions.                                           #
#########################################################################

pass_get_pass() {
    $PASS show "$1" | head -n 1
}

pass_get_user() {
    pass_file="$1"
    pass_parent="$(dirname "$pass_file")"

    # Requires the 'pass attr' extension
    if [ "$_pass_attr" -eq 1 ]
    then
	pass_username="$($PASS attr "$pass_file" user)"
    fi

    # If the 'User' attribute exists in the password file, use that.
    if [ -n "$pass_username" ]
    then
	debug "Found username in '$pass_file'"
	printf '%s\n' "$pass_username"

    # Check for storing usernames as separate file in same directory.
    elif [ -e "$PASSWORD_STORE_DIR/$pass_parent/user.gpg" ]
    then
	debug "Using contents of '$PASSWORD_STORE_DIR/$pass_parent/user.gpg' as username."
	pass_get_pass "$pass_parent/user"
    elif [ -e "$PASSWORD_STORE_DIR/$pass_parent/username.gpg" ]
    then
	debug "Using contents of '$PASSWORD_STORE_DIR/$pass_parent/username.gpg' as username."
	pass_get_pass "$pass_parent/username"
    elif [ -e "$PASSWORD_STORE_DIR/$pass_parent/User.gpg" ]
    then
	debug "Using contents of '$PASSWORD_STORE_DIR/$pass_parent/User.gpg' as username."
	pass_get_pass "$pass_parent/user"
    elif [ -e "$PASSWORD_STORE_DIR/$pass_parent/Username.gpg" ]
    then
	debug "Using contents of '$PASSWORD_STORE_DIR/$pass_parent/Username.gpg' as username."
	pass_get_pass "$pass_parent/Username"

    # As last resort, use the name of the file. Has form 'USER@HOSTNAME:PORT'
    # with but the hostname and port as optional.
    else
	debug "Extracting username from basename of '$pass_file'"
	basename "$pass_file" | cut -d "@" -f 1
    fi
}

#########################################################################
# Generic window manager function definitions                           #
#                                                                       #
# Can be extended to support more window managers.                      #
#########################################################################

# Save any state information that the window manager might need.
save_state() {
    case "$XDG_CURRENT_DESKTOP" in
	"sway")
	    sway_save_state
	    ;;
    esac
}

# Restore any settings changed by this script to their original
# values.
restore_state() {
    case "$XDG_CURRENT_DESKTOP" in
	"sway")
	    sway_restore_state
	    ;;
    esac
}

# Implement some form of locking to prevent auto-typing sensitive
# information into the wrong window.
lock_window() {
    case "$XDG_CURRENT_DESKTOP" in
	"sway")
	    sway_lock_window
	    ;;
    esac
}

#########################################################################
# Sway-specific function definitions                                    #
#########################################################################

sway_save_state() {
    # Save information about the currently focused window only at
    # first run.
    if [ -z "$_window_state" ]
    then
	# This ugly bastard makes a shell eval'able string containing
	# the needed window information as `_var1=val1;_var2=val2`
	_sway_window_state="$(swaymsg -r -t get_tree | jq -r -c \
	'..|try select(.focused == true) |
	"_window_id=\(.id);_window_border=\(.border);_window_border_width=\(.current_border_width);"')"

	# Pass on the state. This will be placed in `ROFI_DATA`.
	_window_state="'$_sway_window_state'"
    else
	# Seems hacky, but it works.
	_window_state="'$_window_state'"
    fi
}

sway_restore_focus() {
    swaymsg "[con_id=$_window_id]" focus
}

sway_restore_state() {
    eval "$_window_state"
    sway_restore_focus

    swaymsg 'urgent disable'

    # I can't find a way to get this value from swaymsg, so assume yes.
    swaymsg 'focus_follows_mouse' yes

    # Return the border to it's original settings.
    swaymsg "border $_window_border $_window_border_width"
}

sway_lock_window() {
    sway_restore_focus
    swaymsg 'focus_follows_mouse no'
    swaymsg 'urgent enable'

    # It would be nice to also change the color. Maybe urgency?
    swaymsg 'border pixel 8'
}

notify() {
    [ $SEND_NOTIFICATIONS -eq 1 ] || return

    notify-send --app-name="$NOTIFICATION_APP_NAME" \
		--icon="$NOTIFICATION_ICON" "$@"
}

send_countdown_notification() {
    [ $SEND_NOTIFICATIONS -eq 1 ] || return

    _countdown_pct=100
    _countdown_sleep=0.5

    # Update once every half second.
    _steps=$(( PASSWORD_STORE_CLIP_TIME * 2 ))
    _step_size=$(echo "$_countdown_pct / $_steps" | bc -l)

    # Just to store the notification id.
    _notify_id="$(notify -p "...")"

    _time_left=$PASSWORD_STORE_CLIP_TIME

    while [ $_steps -gt 0 ]
    do

	[ $((_steps % 2)) -eq 1 ] && ((_time_left -= 1))

	notify -h "int:value:$_countdown_pct" \
	       -r "$_notify_id" \
	       "$NOTIFICATION_APP_NAME" \
	       "Clipboard will be cleared after $_time_left seconds..."

	sleep $_countdown_sleep
	_countdown_pct="$(echo "$_countdown_pct - $_step_size" | bc -l)"
	((_steps -= 1))

    done

    # A final notification lasting 3 seconds.
    notify -r "$_notify_id" \
	   -t 3000 \
	   "Clipboard entry cleared."
}


main "$@"
