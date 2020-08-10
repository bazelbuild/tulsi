# bazel_cache_reader

`bazel_cache_reader` is used for helping `lldb` find DSYMs for builds done with
Tulsi. DSYM locations are stored by Tulsi in a sqlite3 database located at
`~/Library/Application Support/Tulsi/Scripts/symbol_cache.db`.
`lldb` is set up to find the DSYMs using `~/.lldbinit` as specified
[here](https://lldb.llvm.org/use/symbols.html).

Easy debugging of `bazel_cache_reader` can be done using `Console.app`, turning
on "debug and info" messages, and filtering for `bazel_cache_reader`.
