# webtest

Tests for `web`, kept in their own library so `web` ships without a test
runner (a library with tests carries a runner that runs at load and calls
`exit(1)` on a failure, before the server listens).

    export let name = "webtest";
