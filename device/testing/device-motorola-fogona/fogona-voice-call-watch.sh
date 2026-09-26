#!/bin/sh
# EXPERIMENT (voice PoC, /repo/investigations/call-audio.md): on an active
# call, keep the speaker backend running on the earpiece alone, route both
# handset mics into the capture backend, and attach stock's voice graphs
# through the kernel's q6apm-voice-poc debugfs file; undo it on hangup.
#
# The graphs and their calibration (qcom/sm6225/voice-*.bin) are built at
# boot from the handset's own ACDB by fogona-voice-graphs; without them
# "start" fails and the call stays silent.
ctl=/sys/kernel/debug/q6apm-voice/ctl
# voice_poc_rx_direct: voice RX without b0000045 (the working downlink)
modprobe q6apm_voice_poc voice_poc_rx_direct=1
log() { echo "voice-watch: $*" > /dev/kmsg; }

suspend_sinks() {
	for d in /run/user/*; do
		u=$(stat -c %U "$d")
		su -s /bin/sh "$u" -c "export XDG_RUNTIME_DIR=$d; for s in \$(pactl list sinks short 2>/dev/null | cut -f2 | grep alsa_output); do pactl suspend-sink \$s $1; done"
	done
}

# callaudiod switches the card back to HiFi on hangup, typically before this
# loop notices the call is gone. The new HiFi node then fails to open hw:0,0
# (EBUSY, our aplay still holds it), and WirePlumber drops it for good: no
# output until the profile changes again. Once the PCMs are released, going
# through "off" and back to the active profile recreates the node (setting
# the same profile again is not reliably enough).
reapply_profile() {
	for d in /run/user/*; do
		u=$(stat -c %U "$d")
		su -s /bin/sh "$u" -c "export XDG_RUNTIME_DIR=$d; c=alsa_card.platform-sound; p=\$(pactl list cards 2>/dev/null | sed -n 's/^[[:space:]]*Active Profile: //p' | head -n1); [ -n \"\$p\" ] && pactl set-card-profile \$c off && pactl set-card-profile \$c \"\$p\""
	done
}

# Both handset mics into TX_CODEC_DMA_TX_3 (MultiMedia2). Stock's
# handset-dmic-endfire, with the second mic on DEC1 instead of DEC2 (the
# backend runs channel mask 0x3): ch0 = AMIC1, bottom (ADC1, SWR_MIC0);
# ch1 = AMIC3, top (ADC2 INP3, SWR_MIC4).
mic_path() {
	for c in "MultiMedia2 Mixer TX_CODEC_DMA_TX_3=1" "TX DEC0 MUX=SWR_MIC" \
		 "TX SMIC MUX0=SWR_MIC0" "TX_AIF1_CAP Mixer DEC0=1" \
		 "ADC1_MIXER Switch=1" "ADC1 Switch=1" "ADC1 Volume=12" \
		 "TX DEC1 MUX=SWR_MIC" "TX SMIC MUX1=SWR_MIC4" \
		 "TX_AIF1_CAP Mixer DEC1=1" "ADC2 MUX=INP3" \
		 "ADC2_MIXER Switch=1" "ADC2 Switch=1" "ADC2 Volume=12"; do
		amixer -c0 -q cset name="${c%=*}" "${c##*=}"
	done
}

on=0
while true; do
	if mmcli -m any --voice-list-calls 2>/dev/null | grep -q "(active)"; then
		if [ $on = 0 ]; then
			suspend_sinks 1
			amixer -c0 -q sset "PRI_MI2S_RX Audio Mixer MultiMedia1" on
			amixer -c0 -q cset name="Speaker Switch" 0
			amixer -c0 -q cset name="Receiver Switch" 1
			aplay -q -D hw:0,0 -f S16_LE -r 48000 -c 2 /dev/zero &
			apid=$!
			# the mics: voice TX reads the capture backend's splitter
			mic_path
			arecord -q -D hw:0,1 -f S16_LE -r 48000 -c 2 /dev/null &
			rpid=$!
			sleep 0.5
			echo start > $ctl
			log "call active: start rc=$?"
			on=1
		fi
	elif [ $on = 1 ]; then
		echo stop > $ctl
		kill $apid $rpid 2>/dev/null
		wait $apid $rpid 2>/dev/null
		amixer -c0 -q cset name="Speaker Switch" 1
		suspend_sinks 0
		reapply_profile
		log "call gone: stop"
		on=0
	fi
	sleep 0.5
done
