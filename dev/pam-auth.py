#!/usr/bin/env python3
"""pam-auth.py SERVICE USER CONFDIR [PASSWORD] - one pam_authenticate through the real
libpam, with the stack read from CONFDIR (pam_start_confdir), answering every prompt
with PASSWORD. Prints "success" or PAM's error, then what the stack said (cue prompts).
dev/pam-test.sh drives the lock screen's and the greeter's stacks with it."""
import ctypes
import sys

pam = ctypes.CDLL("libpam.so.0")
libc = ctypes.CDLL(None)
libc.calloc.restype = ctypes.c_void_p
libc.strdup.restype = ctypes.c_void_p
libc.strdup.argtypes = [ctypes.c_char_p]


class Msg(ctypes.Structure):
    _fields_ = [("style", ctypes.c_int), ("msg", ctypes.c_char_p)]


class Resp(ctypes.Structure):
    _fields_ = [("resp", ctypes.c_void_p), ("code", ctypes.c_int)]


CONV = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.POINTER(Msg)),
                        ctypes.POINTER(ctypes.POINTER(Resp)), ctypes.c_void_p)


class Conv(ctypes.Structure):
    _fields_ = [("conv", CONV), ("data", ctypes.c_void_p)]


said = []
password = sys.argv[4].encode() if len(sys.argv) > 4 else b""


def conv(n, msgs, resp, _data):
    r = ctypes.cast(libc.calloc(n, ctypes.sizeof(Resp)), ctypes.POINTER(Resp))
    for i in range(n):
        m = msgs[i].contents
        said.append(m.msg.decode(errors="replace") if m.msg else "")
        if m.style in (1, 2):                      # PAM_PROMPT_ECHO_OFF / ON
            r[i].resp = libc.strdup(password)
    resp[0] = r
    return 0


c = Conv(CONV(conv), None)
h = ctypes.c_void_p()
pam.pam_start_confdir.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(Conv), ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
pam.pam_strerror.restype = ctypes.c_char_p
rc = pam.pam_start_confdir(sys.argv[1].encode(), sys.argv[2].encode(), ctypes.byref(c), sys.argv[3].encode(), ctypes.byref(h))
if rc != 0:
    print("pam_start failed", rc)
    sys.exit(2)
rc = pam.pam_authenticate(h, 0)
print("success" if rc == 0 else pam.pam_strerror(h, rc).decode(), "|", " / ".join(said))
pam.pam_end(h, rc)
sys.exit(0 if rc == 0 else 1)
