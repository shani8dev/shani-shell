#!/usr/bin/env python3
"""pam-session.py SERVICE USER PASSWORD - sign USER in through the real libpam the
way greetd does: pam_authenticate, pam_acct_mgmt, pam_setcred and
pam_open_session, answering every prompt with PASSWORD - then hold the session
open until a line arrives on stdin, and close it.

dev/keyring-test.sh drives the greeter's stack (/etc/pam.d/SERVICE) with it in a
systemd-booted container, so pam_systemd makes a real logind session and starts
the user's own systemd, and the session modules after it (pam_oo7) run as they
would after a real sign-in. Prints "open" once the session is open, "closed" at
the end, or "fail <step> <pam error>" and exits 1."""
import ctypes
import ctypes.util
import sys

PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON = 1, 2
PAM_ESTABLISH_CRED, PAM_DELETE_CRED = 0x2, 0x4


class PamMessage(ctypes.Structure):
    _fields_ = [("msg_style", ctypes.c_int), ("msg", ctypes.c_char_p)]


class PamResponse(ctypes.Structure):
    _fields_ = [("resp", ctypes.c_char_p), ("resp_retcode", ctypes.c_int)]


CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(PamMessage)),
                        ctypes.POINTER(ctypes.POINTER(PamResponse)), ctypes.c_void_p)


class PamConv(ctypes.Structure):
    _fields_ = [("conv", CONV), ("appdata_ptr", ctypes.c_void_p)]


def main() -> int:
    service, user, password = sys.argv[1], sys.argv[2], sys.argv[3]
    libc = ctypes.CDLL(ctypes.util.find_library("c"))
    libc.calloc.restype = ctypes.c_void_p
    libc.strdup.restype = ctypes.c_void_p
    pam = ctypes.CDLL(ctypes.util.find_library("pam"))
    pam.pam_strerror.restype = ctypes.c_char_p

    def conv(n, msgs, resp, _data):
        arr = ctypes.cast(libc.calloc(n, ctypes.sizeof(PamResponse)), ctypes.POINTER(PamResponse))
        for i in range(n):
            if msgs[i].contents.msg_style in (PAM_PROMPT_ECHO_OFF, PAM_PROMPT_ECHO_ON):
                arr[i].resp = ctypes.cast(libc.strdup(password.encode()), ctypes.c_char_p)
        resp[0] = arr
        return 0

    handle = ctypes.c_void_p()
    cb = CONV(conv)
    if pam.pam_start(service.encode(), user.encode(), ctypes.byref(PamConv(cb, None)), ctypes.byref(handle)) != 0:
        print("fail start"); return 1
    pam.pam_set_item(handle, 3, b"tty1")          # PAM_TTY, as a greeter's VT session has
    for step, call in (("authenticate", lambda: pam.pam_authenticate(handle, 0)),
                       ("acct_mgmt", lambda: pam.pam_acct_mgmt(handle, 0)),
                       ("setcred", lambda: pam.pam_setcred(handle, PAM_ESTABLISH_CRED)),
                       ("open_session", lambda: pam.pam_open_session(handle, 0))):
        rc = call()
        if rc != 0:
            print(f"fail {step} {pam.pam_strerror(handle, rc).decode()}", flush=True)
            pam.pam_end(handle, rc)
            return 1
    print("open", flush=True)
    sys.stdin.readline()
    pam.pam_close_session(handle, 0)
    pam.pam_setcred(handle, PAM_DELETE_CRED)
    pam.pam_end(handle, 0)
    print("closed", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
