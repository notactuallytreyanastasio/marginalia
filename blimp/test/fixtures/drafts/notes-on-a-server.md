# Notes on a Small Server

Most of what a web server does is wait. It binds a port, sits in a loop, and hands each connection to something that knows what to do with it. The interesting part is how little has to be true for that to work: a socket, a way to read bytes from it, and a way to write some back.

I wrote the first version of this one in an afternoon and spent the following week finding out which of its assumptions were wrong. The worst of them was that a single read would return a whole request. It does not. A read returns whatever has arrived so far, and a request with a large body arrives in many pieces.

## Reading a request properly

The fix is to read until the header block ends, find the Content-Length, and keep reading until that many body bytes have been collected. Collecting the pieces in a list and joining them once at the end is much cheaper than appending to a string on every read, which copies the whole accumulator each time.

```
def read_body(fd, chunks, have, need)
  if have >= need
    chunks
  else
    more = read(fd)
    read_body(fd, append(chunks, more), have + length(more), need)
  end
end
```

This is the entire trick. Everything else about the server is routing and rendering, and those are the parts that look hard but are not.

## What I would do differently

I would fork a child per request from the start. A long-running interpreter that never frees memory will eventually be killed by its own appetite, and a parent that only accepts and forks stays small forever. The child answers one request and exits, and its garbage goes with it.

The other thing is logging. A server that answers correctly and says nothing about it is a server you debug by guessing. One line per request, with the method, the path and the status, would have saved me most of that week.
