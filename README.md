# NegI 
**Version:** 0.0.4 (PoC pre-alpha prototype)
**Implementation status:** Updating as reference while porting to C + LLVM

<div align="center">
<img src="logo.svg" width="256" height="256"/>
</div>

## Description

NegI - (Negitiation Interface) or (Negated Identity) is not a language in the traditional sense; it is a **semantic substrate**. It is designed to solve the "Ship of Theseus" problem in software: allowing a system to replace its components, semantics, and even its underlying runtime without losing its identity.

## Running/Building
The `ophanim.lua` (backend name) is a 1 file library for Lua 5.5. You can either load it via `require` or just copy/paste the code. It only depends on lua core libraries, and even those can be removed. Personally, I'm testing on lua 5.5 binary. You can get lua binaries here: https://luabinaries.sourceforge.net/download.html. To test the demo, you can launch the `repl.lua`.
```bash
lua55 repl.lua
```

# 0.1.0 roadmap (finished PoC version)
1. Just finish manifests inside root context (Especially Error, to check if we getting stuck in halt)
2. Parsed content manifest (Module), so user can ask it where the error did happen in relation to text "code"

# Some additional info
This is a prototype, currently I'm rewriting it in C + LLVM-C + clang-c, because Lua have no multi-therading support and lacks proper file and hardware access (while I can add dependencies, people might find it difficult to install because of current lua ecosystem).

- Practical NegI examples I use for tests located at `repl.lua` line 8.
- To see how manifest are working and structured see `local manifest = {...` and `dispatch = function (`
- To see what things do you can refer to `FLESH.NegI.Manifests` in `ophanim.lua`, for example:
`NegI "context" inner` will index NegI `Frame` with `context` literal and return an object with authority to show context (look into `protocol` to see what it can do).

If you're looking for docs you should read the code for now, because it has most of the info inside comments, which I usually keep updated. I have plans to make real docs, but for now I want to focus on implementation.

`negi.lark` is an old file from python implementation attempt, it shows how in lark NegI syntax is parsed.

I still updating this version occasionally, just to test features on practice and against C version.