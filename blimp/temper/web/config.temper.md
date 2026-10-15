# web

The router. It assembles every page group, serves the static files, runs the
plugs the Phoenix router's pipelines ran, checks the CSRF token of every
write, and hands each request or event to the group that owns its path.

    export let name = "web";
