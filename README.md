# Pitch 

A reflowing, opinionated code formatter for the Scheme programming
language, modelled after [`black`](https://github.com/psf/black) for
Python. Supports R6RS and R7RS Scheme.

## Principles 

- Discards prior formatting 
- Line-length driven line breaking
- AST equivalence check
- Idempotence - `pitch(pitch(x) == pitch(x)`
- Near-zero configuration 

## Architecture 

- Lossless lexer → CST → cost-based optimal layout via a `pretty-expressive`-style engine → per-form style table (similar to [Racket `fmt`](https://docs.racket-lang.org/fmt/index.html)).
- Uses [SRFI 272](https://github.com/scheme-requests-for-implementation/srfi-272)'s style grammar as configuration format.
- Uses Scheme `read` and `equal?` to verify AST equivalence.

## References 

- [`laesare`](https://gitlab.com/weinholt/laesare) - An R6RS/R7RS lexer and reader which we modify for the Lossless lexer → CST step.
- [`bwbensonjr/laesare`](https://github.com/bwbensonjr/laesare) - Our fork of `laesare` that captures the exact source substring.
- [Chez Scheme](https://github.com/cisco/chezscheme) - Our preferred R6RS Scheme implementation.




