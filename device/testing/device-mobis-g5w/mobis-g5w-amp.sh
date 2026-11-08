#!/bin/sh
# The amp follows the session's sound: its mute is the micom's AV mute, so the
# default sink's mute is mirrored onto it, with stock's own frames (captured
# from the stock micomd's UART, sent through micomd's control socket): 0x020B
# set to mute; the first unmute brings the amp up as stock does on a source
# switch (set, mode Media, volume, then 0x0238 release); later ones only
# release. The amp volume stays fixed: volume is the sound server's.
C=/run/micomd.ctl
SET=ff850201020b0003020170
MODE=ff850201020100030e0077
# 0x16, the lowest volume the stock system was seen to send
VOL=ff85020102030002166c
REL=ff85020102380003020042

send() { micomd -send "$C" "$1" >/dev/null 2>&1; }

# micomd's control socket and the sound server come up around login.
until [ -S "$C" ] && pactl info >/dev/null 2>&1; do sleep 1; done

state=
apply() {
	case "$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null)" in
	*yes)
		[ "$state" = muted ] && return
		send $SET
		state=muted
		;;
	*no)
		[ "$state" = up ] && return
		if [ -z "$state" ]; then
			send $SET
			send $MODE
			send $VOL
			# stock waits 0.2-1.3 s before the release
			sleep 0.3
		fi
		send $REL
		state=up
		;;
	esac
}

apply
pactl subscribe | while read -r l; do
	case "$l" in
	*"on sink "* | *"on server"*) apply ;;
	esac
done
