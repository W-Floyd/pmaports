#!/usr/bin/env python3
"""Minimal SSREQ (Subsystem Request) QMI server, so the modem stops looking.

WHY THIS EXISTS
---------------
Our modem logs, during its own init:

    ssreq_svc_poll_client.c:139  ssid=100
    MPSS:Failed to connect to SSREQ server instance:16

SSREQ is hosted on the *application processor* by Qualcomm's closed
`pm-service` (peripheral-manager), which stock Android runs as
`vendor.per_mgr` and which nothing on our side provides. A working mainline
device has it -- erebion's Xperia 10 III lists `53 1 16 1` (service 53,
version 1, instance 16, node 1 = the AP) -- and fogona lists nothing for 53.
See investigations/wifi-modem.md §3.1.

Everything below is read out of the modem's own QMI IDL, in the vendor tree at
`modem_proc/qmimsgs/ssreq/` (arzekrasr/MPSS.HA.1.1), not guessed:

    SSREQ_QMI_SERVICE_INSTANCE_APSS_V01 = 0x10      -- instance 16 is "APSS"
    QMI_SSREQ_SYSTEM_SHUTDOWN_REQ_V01     0x0020
    QMI_SSREQ_SYSTEM_RESTART_REQ_V01      0x0021
    QMI_SSREQ_PERIPHERAL_RESTART_REQ_V01  0x0022
    struct qmi_idl_service_object = { 0x06, 0x01, 0x35, 14, ... }
                                                ^^^^ service id 53

The service id is the third field of the IDL service object. That reading is
calibrated, not assumed: `ssctl` gives 0x2B (43), `dms` 0x02 (2), `uim` 0x0B
(11) and `pdc` 0x24 (36) in the same slot, and all four match their known QMI
numbers.

WHAT THIS IS AND IS NOT
-----------------------
It is an experiment, not an implementation of peripheral-manager. The three
requests are shutdown, restart and peripheral-restart -- "please take a
subsystem down or bring it back" -- and a real server would drive remoteproc.
This one **answers success and does nothing**, because the question it exists
to answer is narrow: does the modem stop stalling when something is there?

**Most likely the modem never sends a request at all.** It is a *poll client*:
it waits for the service to appear in the registry so it can hold a client
handle. If that is all it wants, merely publishing is enough and no request
will ever arrive. That is why every received message is logged loudly -- if
anything does come in, it is news, and the msg_id tells us what.

Run it before the modem starts. The modem powers up around 33 s into boot on
this handset and polls early, so the systemd unit beside this file is ordered
the same aggressive way as the F3 capture. Log goes to the journal.

PROTOCOL NOTES, so the next person does not re-derive them
----------------------------------------------------------
* QRTR service registration is a *control message*, not a bind option: send a
  20-byte `struct qrtr_ctrl_pkt` with `cmd = QRTR_TYPE_NEW_SERVER (2)` to port
  `QRTR_PORT_CTRL (0xfffffffe)` on your own node.
* The `instance` field in that packet is **not** the instance -- it packs both:
  `(instance << 8) | version`. For SSREQ that is `(16 << 8) | 1 = 0x1001`.
  Send a bare 16 and `qrtr-lookup` reports version 16, instance 0, and the
  modem never finds you.
* Bind with node 0 / port 0 to get a port assigned, then `getsockname()` to
  learn the real node -- the control message has to be addressed to it.
* QMI service messages carry a 7-byte header `{u8 type, u16 txn, u16 msg_id,
  u16 len}`; a response is type 2 and must carry TLV `0x02`, the 4-byte
  `qmi_response_type_v01` of `{u16 result, u16 error}`.
"""
import os
import socket
import struct
import sys
import time

SERVICE = 53
VERSION = 1
INSTANCE = 16

QRTR_PORT_CTRL = 0xFFFFFFFE
# From enum qrtr_pkt_type. NEW_SERVER is 4, NOT 2 -- 2 is QRTR_TYPE_HELLO, and
# sending that to the control port introduces you as a new peer, whereupon the
# name server broadcasts every registered service at you. Twenty-byte control
# packets then arrive looking like malformed QMI, and a loop that answers them
# writes megabytes of nonsense back to the control port.
QRTR_TYPE_NEW_SERVER = 4
QRTR_TYPE_DEL_SERVER = 5

QMI_REQUEST, QMI_RESPONSE = 0, 2
QMI_RESULT_SUCCESS, QMI_ERR_NONE = 0, 0
QMI_RESULT_FAILURE, QMI_ERR_NOT_SUPPORTED = 1, 0x0004

MSG_NAMES = {
    0x0020: "SYSTEM_SHUTDOWN",
    0x0021: "SYSTEM_RESTART",
    0x0022: "PERIPHERAL_RESTART",
}


def log(msg):
    print("ssreq-stub: %s" % msg, flush=True)


def ctrl_pkt(cmd, service, instance, node, port):
    """struct qrtr_ctrl_pkt: cmd, then the server{} arm of its union."""
    return struct.pack("<5I", cmd, service, instance, node, port)


def publish(sock, node, port):
    pkt = ctrl_pkt(QRTR_TYPE_NEW_SERVER, SERVICE,
                   (INSTANCE << 8) | VERSION, node, port)
    sock.sendto(pkt, (node, QRTR_PORT_CTRL))


def withdraw(sock, node, port):
    pkt = ctrl_pkt(QRTR_TYPE_DEL_SERVER, SERVICE,
                   (INSTANCE << 8) | VERSION, node, port)
    try:
        sock.sendto(pkt, (node, QRTR_PORT_CTRL))
    except OSError:
        pass


def respond(sock, addr, txn, msg_id, result, error):
    tlv = struct.pack("<BHHH", 0x02, 4, result, error)
    hdr = struct.pack("<BHHH", QMI_RESPONSE, txn, msg_id, len(tlv))
    sock.sendto(hdr + tlv, addr)


def main():
    sock = socket.socket(socket.AF_QIPCRTR, socket.SOCK_DGRAM, 0)

    # getsockname() BEFORE bind, to learn our own node -- binding node 0 is
    # EINVAL. libqrtr's qrtr_open() does exactly this, and it is easy to miss:
    # a naive bind((0, 0)) fails with "Invalid argument" and, inside a retry
    # loop, looks like qrtr simply not being up yet.
    local_node = sock.getsockname()[0]

    # qrtr may genuinely not be up yet when this runs this early in boot.
    last = None
    for _ in range(600):
        try:
            sock.bind((local_node, 0))
            break
        except OSError as e:
            last = e
            time.sleep(0.05)
    else:
        log("could not bind AF_QIPCRTR node %d after 30s: %r"
            % (local_node, last))
        return 1

    node, port = sock.getsockname()
    publish(sock, node, port)
    log("published service %d version %d instance %d on node %d port %d"
        % (SERVICE, VERSION, INSTANCE, node, port))
    log("waiting for the modem; it may never send anything, which is a result")

    try:
        while True:
            try:
                data, addr = sock.recvfrom(65536)
            except OSError as e:
                log("recv failed: %r" % (e,))
                time.sleep(0.2)
                continue
            # Control traffic (BYE, DEL_CLIENT, name-server chatter) arrives on
            # the same socket from the control port. It is not QMI -- never
            # parse it as such, and never answer it.
            if addr[1] == QRTR_PORT_CTRL:
                cmd = struct.unpack_from("<I", data, 0)[0] if len(data) >= 4 else -1
                log("ctrl cmd=%d from %s (ignored)" % (cmd, addr))
                continue
            if len(data) < 7:
                log("runt from %s: %s" % (addr, data.hex()))
                continue
            mtype, txn, msg_id, mlen = struct.unpack_from("<BHHH", data, 0)
            name = MSG_NAMES.get(msg_id, "UNKNOWN")
            log("<- %s msg_id=0x%04x (%s) txn=%d len=%d from %s: %s"
                % ("req" if mtype == QMI_REQUEST else "type%d" % mtype,
                   msg_id, name, txn, mlen, addr, data.hex()))
            if msg_id in MSG_NAMES:
                respond(sock, addr, txn, msg_id,
                        QMI_RESULT_SUCCESS, QMI_ERR_NONE)
                log("-> success for %s (stub: nothing was actually done)" % name)
            else:
                # Do not claim success for something undocumented.
                respond(sock, addr, txn, msg_id,
                        QMI_RESULT_FAILURE, QMI_ERR_NOT_SUPPORTED)
                log("-> NOT_SUPPORTED for msg_id 0x%04x" % msg_id)
    except KeyboardInterrupt:
        pass
    finally:
        withdraw(sock, node, port)
        log("withdrew service %d" % SERVICE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
