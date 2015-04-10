# compile with --threads:on

import chan, posix, strutils

var
    passed = 0

proc assert_true(expression:bool, channel: ptr chan_t, msg: string) =
    if not expression:
        chan.dispose(channel)
        write(stderr, "Assertion failed: $#\n".format(msg))
        quit(QuitFailure)

proc pass() =
    write(stdout, ".")
    flushFile(stdout)
    inc passed

proc wait_for_reader(channel: ptr chan_t) =
    while true:
        discard pthread_mutex_lock(addr channel.m_mu)
        var send = channel.r_waiting > 0
        discard pthread_mutex_unlock(addr channel.m_mu)
        if (send):
            break
        discard sched_yield()

proc wait_for_writer(channel: ptr chan_t) =
    while true:
        discard pthread_mutex_lock(addr channel.m_mu)
        var recv = channel.w_waiting > 0
        discard pthread_mutex_unlock(addr channel.m_mu)
        if (recv):
            break
        discard sched_yield()

proc test_chan_init_buffered() =
    var
        size: csize = 5
        channel = chan.init(size)

    assert_true(channel.queue != nil, channel, "Queue is NULL")
    assert_true(channel.queue.capacity.csize == size, channel, "Size is not 5")
    assert_true(not channel.closed.bool, channel, "channel is closed")

    chan.dispose(channel)
    pass()

proc test_chan_init_unbuffered() =
    var channel = chan.init(0)

    assert_true(channel.queue == nil, channel, "Queue is not NULL")
    assert_true(not channel.closed.bool, channel, "channel is closed")

    chan.dispose(channel)
    pass()

proc test_chan_init() =
    test_chan_init_buffered()
    test_chan_init_unbuffered()

proc test_chan_close() =
    var channel = chan.init(0)

    assert_true(not channel.closed.bool, channel, "channel is closed")
    assert_true(not chan.is_closed(channel).bool, channel, "channel is closed")
    assert_true(chan.close(channel) == 0, channel, "Close failed")
    assert_true(channel.closed.bool, channel, "channel is not closed")
    assert_true(chan.close(channel) == -1, channel, "Close succeeded")
    assert_true(chan.is_closed(channel).bool, channel, "channel is not closed")
    
    chan.dispose(channel)
    pass()

proc test_chan_send_buffered() =
    var
        channel = chan.init(1)
        msg: cstring = "foo"

    assert_true(chan.size(channel) == 0, channel, "Queue is not empty")
    assert_true(chan.send(channel, msg) == 0, channel, "Send failed")
    assert_true(chan.size(channel) == 1, channel, "Queue is empty")
    
    chan.dispose(channel)
    pass()

proc receiver(channel: pointer): pointer {.noconv.} =
    var msg: pointer
    discard chan.recv(cast[ptr chan_t](channel), addr msg)
    return nil

proc test_chan_send_unbuffered() =
    var
        channel = chan.init(0)
        msg: cstring = "foo"
        th: Tpthread
    discard pthread_create(addr th, nil, receiver, cast[pointer](channel))

    wait_for_reader(channel)

    assert_true(chan.size(channel) == 0, channel, "channel size is not 0")
    assert_true(not channel.w_waiting.bool, channel, "channel has sender")
    assert_true(chan.send(channel, msg) == 0, channel, "Send failed")
    assert_true(not channel.w_waiting.bool, channel, "channel has sender")
    assert_true(chan.size(channel) == 0, channel, "channel size is not 0")

    discard pthread_join(th, nil)
    chan.dispose(channel)
    pass()

proc test_chan_send() =
    test_chan_send_buffered()
    test_chan_send_unbuffered()

proc test_chan_recv_buffered() =
    var
        channel = chan.init(1)
        msg: cstring = "foo"

    assert_true(chan.size(channel) == 0, channel, "Queue is not empty")
    discard chan.send(channel, msg)
    assert_true(chan.size(channel) == 1, channel, "Queue is empty")
    var received: pointer
    assert_true(chan.recv(channel, addr received) == 0, channel, "Recv failed")
    assert_true(msg == cast[cstring](received), channel, "Messages are not equal 1")
    assert_true(chan.size(channel) == 0, channel, "Queue is not empty")
    
    chan.dispose(channel)
    pass()

proc sender(channel: pointer): pointer {.noconv.} =
    discard chan.send(cast[ptr chan_t](channel), "foo".cstring)
    return nil

proc test_chan_recv_unbuffered() =
    var
        channel = chan.init(0)
        th: Tpthread
    discard pthread_create(addr th, nil, sender, channel)

    assert_true(chan.size(channel) == 0, channel, "channel size is not 0")
    assert_true(not channel.r_waiting.bool, channel, "channel has reader")
    var msg: pointer
    assert_true(chan.recv(channel, addr msg) == 0, channel, "Recv failed")
    assert_true(cast[cstring](msg) == "foo".cstring, channel, "Messages are not equal 2")
    assert_true(not channel.r_waiting.bool, channel, "channel has reader")
    assert_true(chan.size(channel) == 0, channel, "channel size is not 0")

    discard pthread_join(th, nil)
    chan.dispose(channel)
    pass()

proc test_chan_recv() =
    test_chan_recv_buffered()
    test_chan_recv_unbuffered()

proc test_chan_select_recv() =
    var
        chan1 = chan.init(0)
        chan2 = chan.init(1)
        chans = [chan1, chan2]
        recv: pointer
        msg: cstring = "foo"

    discard chan.send(chan2, msg)

    case chan.select(addr chans[0], 2, addr recv, nil, 0, nil):
        of 0:
            chan.dispose(chan1)
            chan.dispose(chan2)
            write(stderr, "Received on wrong channel\n")
            quit(QuitFailure)
        of 1:
            if cast[cstring](recv) != msg:
                chan.dispose(chan1)
                chan.dispose(chan2)
                write(stderr, "Messages are not equal 3\n")
                quit(QuitFailure)
            recv = nil
        else:
            chan.dispose(chan1)
            chan.dispose(chan2)
            write(stderr, "Received on no channels\n")
            quit(QuitFailure)

    var th: Tpthread
    discard pthread_create(addr th, nil, sender, chan1)
    wait_for_writer(chan1)

    case chan.select(addr chans[0], 2, addr recv, nil, 0, nil):
        of 0:
            if cast[cstring](recv) != "foo".cstring:
                chan.dispose(chan1)
                chan.dispose(chan2)
                write(stderr, "Messages are not equal 4\n")
                quit(QuitFailure)
            recv = nil
        of 1:
            chan.dispose(chan1)
            chan.dispose(chan2)
            write(stderr, "Received on wrong channel\n")
            quit(QuitFailure)
        else:
            chan.dispose(chan1)
            chan.dispose(chan2)
            write(stderr, "Received on no channels\n")
            quit(QuitFailure)

    case chan.select(addr chan2, 1, cast[ptr pointer](addr msg), nil, 0, nil):
        of 0:
            chan.dispose(chan1)
            chan.dispose(chan2)
            write(stderr, "Received on channel\n")
            quit(QuitFailure)
        else:
            discard

    discard pthread_join(th, nil)
    chan.dispose(chan1)
    chan.dispose(chan2)
    pass()

proc test_chan_select_send() =
    var
        chan1 = chan.init(0)
        chan2 = chan.init(1)
        chans = [chan1, chan2]
        msg = ["foo".cstring, "bar".cstring]

    case chan.select(nil, 0, nil, addr chans[0], 2, cast[ptr pointer](addr msg[0])):
        of 0:
            chan.dispose(chan1)
            chan.dispose(chan2)
            write(stderr, "Sent on wrong channel\n")
            quit(QuitFailure)
        of 1:
            discard
        else:
            chan.dispose(chan1)
            chan.dispose(chan2)
            write(stderr, "Sent on no channels\n")
            quit(QuitFailure)

    var recv: pointer
    discard chan.recv(chan2, addr recv)
    if cast[cstring](recv) != "bar".cstring:
        chan.dispose(chan1)
        chan.dispose(chan2)
        write(stderr, "Messages are not equal 5\n")
        quit(QuitFailure)

    discard chan.send(chan2, "foo".cstring)

    var th: Tpthread
    discard pthread_create(addr th, nil, receiver, chan1)
    wait_for_reader(chan1)

    case chan.select(nil, 0, nil, addr chans[0], 2, cast[ptr pointer](addr msg[0])):
        of 0:
            discard
        of 1:
            chan.dispose(chan1)
            chan.dispose(chan2)
            write(stderr, "Sent on wrong channel\n")
            quit(QuitFailure)
        else:
            chan.dispose(chan1)
            chan.dispose(chan2)
            write(stderr, "Sent on no channels\n")
            quit(QuitFailure)

    case chan.select(nil, 0, nil, addr chan1, 1, cast[ptr pointer](addr msg[0])):
        of 0:
            chan.dispose(chan1)
            chan.dispose(chan2)
            write(stderr, "Sent on channel\n")
            quit(QuitFailure)
        else:
            discard

    discard pthread_join(th, nil)
    chan.dispose(chan1)
    chan.dispose(chan2)
    pass()

proc test_chan_select() =
    test_chan_select_recv()
    test_chan_select_send()

proc test_chan_int() =
    var
        channel = chan.init(1)
        s: cint = 12345
        r: cint = 0
    discard chan.send_int(channel, s)
    discard chan.recv_int(channel, addr r)
    assert_true(s == r, channel, "Wrong value of int(12345)")

    var
        s32: int32 = 12345
        r32: int32 = 0
    discard chan.send_int32(channel, s32)
    discard chan.recv_int32(channel, addr r32)
    assert_true(s32 == r32, channel, "Wrong value of int32(12345)")

    var
        s64: int64 = 12345
        r64: int64 = 0
    discard chan.send_int64(channel, s64)
    discard chan.recv_int64(channel, addr r64)
    assert_true(s64 == r64, channel, "Wrong value of int64(12345)")

    chan.dispose(channel)
    pass()

proc test_chan_double() =
    var
        channel = chan.init(1)
        s: float64 = 123.45
        r: float64 = 0
    discard chan.send_double(channel, s)
    discard chan.recv_double(channel, addr r)
    assert_true(s == r, channel, "Wrong value of double(123.45)")

    chan.dispose(channel)
    pass()

proc test_chan_buf() =
    var
        channel = chan.init(1)
        s: array[256, char]
        r: array[256, char]
        str1 = "hello world".cstring
        str2 = "Hello World".cstring
    copyMem(s.cstring, str1.pointer, str1.len)
    discard chan.send_buf(channel, s.cstring, len(s))
    copyMem(s.cstring, str2.pointer, str2.len)
    discard chan.recv_buf(channel, addr r, len(s))
    assert_true(cmp(r.cstring, s.cstring).bool, channel, "Wrong value of buf")

    chan.dispose(channel)
    pass()

proc test_chan_multi() =
    var
        channel = chan.init(5)
        th: array[100, Tpthread]
    for i in 0..49:
       discard pthread_create(addr th[i], nil, sender, channel)

    while true:
       discard pthread_mutex_lock(addr channel.m_mu)
       var all_waiting = channel.w_waiting == 45
       discard pthread_mutex_unlock(addr channel.m_mu)
       if (all_waiting):
           break
       discard sched_yield()

    for i in 50..99:
       discard pthread_create(addr th[i], nil, receiver, channel)

    for i in 0..99:
       discard pthread_join(th[i], nil)

    chan.dispose(channel)
    pass()

proc test_chan_multi2() =
    var
        channel = chan.init(5)
        th: array[100, Tpthread]
    for i in 0..99:
        discard pthread_create(addr th[i], nil, receiver, channel)

    while true:
       discard pthread_mutex_lock(addr channel.m_mu)
       var all_waiting = channel.r_waiting == 100
       discard pthread_mutex_unlock(addr channel.m_mu)
       if (all_waiting):
           break
       discard sched_yield()

    # Simulate 5 high-priority writing threads.
    discard pthread_mutex_lock(addr channel.m_mu)
    for i in 0..4:
        assert_true(0 == queue_add(channel.queue, "foo".cstring), channel,
            "Simulate writer thread")
        discard pthread_cond_signal(addr channel.r_cond) # wakeup reader

    # Simulate 6th high-priority waiting writer.
    assert_true(channel.queue.size == channel.queue.capacity, channel,
        "6th writer has to wait")
    inc channel.w_waiting
    # Simulated writer must be woken up by reader.
    discard pthread_cond_wait(addr channel.w_cond, addr channel.m_mu)
    dec channel.w_waiting
    discard pthread_mutex_unlock(addr channel.m_mu)

    # Wake up other waiting reader.
    for i in 5..99:
        discard chan.send(channel, "foo".cstring)

    for i in 0..99:
        discard pthread_join(th[i], nil)

    chan.dispose(channel)
    pass()

test_chan_init()
test_chan_close()
test_chan_send()
test_chan_recv()
test_chan_select()
test_chan_int()
test_chan_double()
test_chan_buf()
test_chan_multi()
test_chan_multi2()
echo("\n$# passed".format(passed))

