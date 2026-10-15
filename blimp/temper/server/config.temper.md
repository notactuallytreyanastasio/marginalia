# server

The accept loop: one forked child per request. This library has no tests on
purpose, so the shipped file has no test runner (a failing runner calls
`exit(1)` before the server listens). The tests are in `servertest`.

    export let name = "server";
