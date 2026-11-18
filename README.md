# Terminal

Run command-line tools: look round the files, see what the system is doing, and try commands, in a terminal with its own shell.
An app for [Dazzle](https://github.com/dazzleos/dazzle).

Install it on Dazzle from Settings, Software.

## Building

Terminal is built with Dazzle's modules (kete_vc4 and the rest) and tools,
through Dazzle's `addApp` (see its `build.zig`): a commit of Dazzle's, as
`build.zig.zon` pins it. Zig is the version Dazzle's `scripts/zig` fetches:

    git clone https://github.com/dazzleos/dazzle ../dazzle
    ../dazzle/scripts/zig build test    # the tests, on this computer
    ../dazzle/scripts/zig build         # the program, and zig-out/apps

With changes of your own to Dazzle, build with that checkout instead:
`--fork=../dazzle`. To move Terminal on to a newer Dazzle, pin its commit:

    git -C ../dazzle archive --format=tar.gz -o /tmp/dazzle.tar.gz <commit>
    zig fetch /tmp/dazzle.tar.gz        # prints the hash for build.zig.zon

(the archive has only the commit's files, so this is quick, and its hash
is the one fetching the commit from GitHub gives).

`zig-out/apps` has Terminal's archive, icon, screenshot and catalogue
(`apps.json`), signed with `-Dsigning-key` or `DAZZLE_SIGNING_KEY`. Each
push to the default branch publishes them as the "latest" release, one of
the sources Dazzle's catalogue lists.

To try a build on a Pi before publishing it, serve it with Dazzle's
(Settings, Software, Software server):

    cd ../dazzle && zig build serve -- --source=terminal=../terminal/zig-out
