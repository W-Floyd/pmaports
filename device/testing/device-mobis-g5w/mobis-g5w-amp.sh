#!/bin/sh
# The amp follows the session's sound. Its mute and volume are the micom's, so
# the default sink's state is mirrored onto them with stock's own frames
# (captured from the stock micomd's UART, sent through micomd's control socket,
# which refuses anything not on its allowed list):
#   mute: 0x020B set; the first unmute brings the amp up as stock does on a
#   source switch (set, mode Media, volume, then 0x0238 release), later ones
#   only release.
#   volume: the I2S card's "Master Playback Volume" (0-35, no register behind
#   it), which the sound server takes for hardware volume, so the samples stay
#   at full scale; each change becomes a 0x0203 frame at that level. Every
#   session starts at START, not at what the last one left: the amp's ceiling
#   is too loud to come back to unasked. So nothing is ever stored: each frame
#   carries bit 7, stock's "don't keep as the last volume", as stock sets for
#   a volume it won't return to (MicomAudioService.sendVolumeCommandToMicom).
#   Without it the micom writes its EEPROM on every step of the knob.
C=/run/micomd.ctl
SET=ff850201020b0003020170
MODE=ff850201020100030e0077
REL=ff85020102380003020042
# without the card's control (an older kernel), the lowest volume stock sent
FALLBACK=22
START=40%

send() { micomd -send "$C" "$1" >/dev/null 2>&1; }

level() {
	v=$(amixer -c 0 cget name='Master Playback Volume' 2>/dev/null |
		sed -n 's/^  : values=\([0-9]*\).*/\1/p')
	echo "${v:-$FALLBACK}"
}

# 0x0203, header 85 02 01 02, payload level | 0x80; the checksum works out to
# 0x7a XOR the payload.
volume_frame() {
	b=$(($1 | 0x80))
	printf 'ff85020102030002%02x%02x' $b $((0x7a ^ b))
}

# micomd's control socket and the sound server come up around login.
until [ -S "$C" ] && pactl info >/dev/null 2>&1; do sleep 1; done
pactl set-sink-volume @DEFAULT_SINK@ "$START"

state=
sent=
apply() {
	case "$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null)" in
	*yes)
		[ "$state" = muted ] && return
		send $SET
		state=muted
		;;
	*no)
		l=$(level)
		if [ -z "$state" ]; then
			send $SET
			send $MODE
			send "$(volume_frame "$l")"
			sent=$l
			# stock waits 0.2-1.3 s before the release
			sleep 0.3
		fi
		if [ "$state" != up ]; then
			send $REL
			state=up
		fi
		if [ "$l" != "$sent" ]; then
			send "$(volume_frame "$l")"
			sent=$l
		fi
		;;
	esac
}

apply
pactl subscribe | while read -r l; do
	case "$l" in
	*"on sink "* | *"on server"*) apply ;;
	esac
done
