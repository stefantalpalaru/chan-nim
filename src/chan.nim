{.deadCodeElim: on.}

from posix import Tpthread_mutex, Tpthread_cond

when defined(windows):
  const
    chan_lib = "libchan.dll"
elif defined(macosx):
  const
    chan_lib = "libchan.dylib"
else:
  const
    chan_lib = "libchan.so"

###########
# queue.h #
###########

# Defines a circular buffer which acts as a FIFO queue.
type 
    queue_t* = object 
        size*: cint
        next*: cint
        capacity*: cint
        data*: ptr pointer

# Allocates and returns a new queue. The capacity specifies the maximum
# number of items that can be in the queue at one time. A capacity greater
# than INT_MAX / sizeof(void*) is considered an error. Returns NULL if
# initialization failed.
proc queue_init*(capacity: csize): ptr queue_t {.cdecl, importc: "queue_init", dynlib: chan_lib.}

# Releases the queue resources.
proc queue_dispose*(queue: ptr queue_t) {.cdecl, importc: "queue_dispose", dynlib: chan_lib.}

# Enqueues an item in the queue. Returns 0 if the add succeeded or -1 if it
# failed. If -1 is returned, errno will be set.
proc queue_add*(queue: ptr queue_t; value: pointer): cint {.cdecl, importc: "queue_add", dynlib: chan_lib.}

# Dequeues an item from the head of the queue. Returns NULL if the queue is
# empty.
proc queue_remove*(queue: ptr queue_t): pointer {.cdecl, importc: "queue_remove", dynlib: chan_lib.}

# Returns, but does not remove, the head of the queue. Returns NULL if the
# queue is empty.
proc queue_peek*(a2: ptr queue_t): pointer {.cdecl, importc: "queue_peek", dynlib: chan_lib.}

##########
# chan.h #
##########

# Defines a thread-safe communication pipe. Channels are either buffered or
# unbuffered. An unbuffered channel is synchronized. Receiving on either type
# of channel will block until there is data to receive. If the channel is
# unbuffered, the sender blocks until the receiver has received the value. If
# the channel is buffered, the sender only blocks until the value has been
# copied to the buffer, meaning it will block if the channel is full.
type 
    chan_t* = object 
        # Buffered channel properties
        queue*: ptr queue_t

        # Unbuffered channel properties
        r_mu*: Tpthread_mutex
        w_mu*: Tpthread_mutex
        data*: pointer

        # Shared properties
        m_mu*: Tpthread_mutex
        r_cond*: Tpthread_cond
        w_cond*: Tpthread_cond
        closed*: cint
        r_waiting*: cint
        w_waiting*: cint

# Allocates and returns a new channel. The capacity specifies whether the
# channel should be buffered or not. A capacity of 0 will create an unbuffered
# channel. Sets errno and returns NULL if initialization failed.
proc init*(capacity: csize): ptr chan_t {.cdecl, importc: "chan_init", dynlib: chan_lib.}

# Releases the channel resources.
proc dispose*(chan: ptr chan_t) {.cdecl, importc: "chan_dispose", dynlib: chan_lib.}

# Once a channel is closed, data cannot be sent into it. If the channel is
# buffered, data can be read from it until it is empty, after which reads will
# return an error code. Reading from a closed channel that is unbuffered will
# return an error code. Closing a channel does not release its resources. This
# must be done with a call to chan_dispose. Returns 0 if the channel was
# successfully closed, -1 otherwise.
proc close*(chan: ptr chan_t): cint {.cdecl, importc: "chan_close", dynlib: chan_lib.}

# Returns 0 if the channel is open and 1 if it is closed.
proc is_closed*(chan: ptr chan_t): cint {.cdecl, importc: "chan_is_closed", dynlib: chan_lib.}

# Sends a value into the channel. If the channel is unbuffered, this will
# block until a receiver receives the value. If the channel is buffered and at
# capacity, this will block until a receiver receives a value. Returns 0 if
# the send succeeded or -1 if it failed.
proc send*(chan: ptr chan_t; data: pointer): cint {.cdecl, importc: "chan_send", dynlib: chan_lib.}

# Receives a value from the channel. This will block until there is data to
# receive. Returns 0 if the receive succeeded or -1 if it failed.
proc recv*(chan: ptr chan_t; data: ptr pointer): cint {.cdecl, importc: "chan_recv", dynlib: chan_lib.}

# Returns the number of items in the channel buffer. If the channel is
# unbuffered, this will return 0.
proc size*(chan: ptr chan_t): cint {.cdecl, importc: "chan_size", dynlib: chan_lib.}

# A select statement chooses which of a set of possible send or receive
# operations will proceed. The return value indicates which channel's
# operation has proceeded. If more than one operation can proceed, one is
# selected randomly. If none can proceed, -1 is returned. Select is intended
# to be used in conjunction with a switch statement. In the case of a receive
# operation, the received value will be pointed to by the provided pointer. In
# the case of a send, the value at the same index as the channel will be sent.
proc select*(recv_chans: ptr ptr chan_t; recv_count: cint; recv_out: ptr pointer; send_chans: ptr ptr chan_t; send_count: cint; send_msgs: ptr pointer): cint {.cdecl, importc: "chan_select", dynlib: chan_lib.}

# Typed interface to send/recv chan.
proc send_int32*(a2: ptr chan_t; a3: int32): cint {.cdecl, importc: "chan_send_int32", dynlib: chan_lib.}
proc send_int64*(a2: ptr chan_t; a3: int64): cint {.cdecl, importc: "chan_send_int64", dynlib: chan_lib.}
when sizeof(int) == 8:
    proc send_int*(c: ptr chan_t, v: int): cint =
        return send_int64(c, v.int64)
else:
    proc send_int*(c: ptr chan_t, v: int): cint =
        return send_int32(c, v.int32)
proc send_double*(a2: ptr chan_t; a3: cdouble): cint {.cdecl, importc: "chan_send_double", dynlib: chan_lib.}
proc send_buf*(a2: ptr chan_t; a3: pointer; a4: csize): cint {.cdecl, importc: "chan_send_buf", dynlib: chan_lib.}
proc recv_int32*(a2: ptr chan_t; a3: ptr int32): cint {.cdecl, importc: "chan_recv_int32", dynlib: chan_lib.}
proc recv_int64*(a2: ptr chan_t; a3: ptr int64): cint {.cdecl, importc: "chan_recv_int64", dynlib: chan_lib.}
when sizeof(int) == 8:
    proc recv_int*(c: ptr chan_t, v: ptr int): cint =
        return recv_int64(c, cast[ptr int64](v))
else:
    proc recv_int*(c: ptr chan_t, v: ptr int): cint =
        return recv_int32(c, cast[ptr int32](v))
proc recv_double*(a2: ptr chan_t; a3: ptr cdouble): cint {.cdecl, importc: "chan_recv_double", dynlib: chan_lib.}
proc recv_buf*(a2: ptr chan_t; a3: pointer; a4: csize): cint {.cdecl, importc: "chan_recv_buf", dynlib: chan_lib.}

