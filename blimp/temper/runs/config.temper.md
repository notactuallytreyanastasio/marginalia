# runs

Everything Phoenix kept in processes and ETS, put into the database where a
forked child can see it: background runs (`Marginalia.Runs`), change
notification (`Phoenix.PubSub`), boot recovery (`Marginalia.Recovery`), the
answer cache (`Marginalia.Cache`) and the mutterings table with its clock
(`Marginalia.Mutterings`).

    export let name = "runs";
