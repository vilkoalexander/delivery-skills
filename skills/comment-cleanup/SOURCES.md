# Sources

References behind `RULES.md`. Not loaded during a cleanup.

- [Best practices for writing code comments — Ellen Spertus, Stack Overflow blog](https://stackoverflow.blog/2021/12/23/best-practices-for-writing-code-comments/) — comments do not duplicate code, and do not excuse unclear code. Its rules 6 and 7 ask for links to sources and references; `RULES.md` departs from them on purpose and keeps links in commit messages.
- [Linux kernel coding style, §8 Commenting](https://www.kernel.org/doc/html/latest/process/coding-style.html) — the danger of over-commenting, no boilerplate that repeats the signature, and a small comment on data declarations.
- [Go Doc Comments — go.dev](https://go.dev/doc/comment) — a doc comment says what the caller needs to know, never the algorithm inside.
- [Google TypeScript Style Guide](https://google.github.io/styleguide/tsguide.html) — JSDoc for the user of the code, line comments for the implementation.
- [A Philosophy of Software Design — John Ousterhout](https://web.stanford.edu/~ouster/cgi-bin/book.php) — comments carry what the code cannot; interface comments belong at module boundaries.
