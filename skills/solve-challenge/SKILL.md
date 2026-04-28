---
name: solve-challenge
description: Solves CTF challenges by decomposing into parallel investigative workstreams and dispatching sub-agents for each angle simultaneously.
allowed-tools: Bash Read Write Edit Glob Grep Task WebFetch WebSearch Skill
metadata:
  user-invocable: "true"
  argument-hint: "[category] [challenge-file-or-url]"
---

# CTF Challenge Solver

You're a skilled CTF player. Your goal is to solve the challenge and find the flag.

## CRITICAL INSTRUCTION

NEVER do any investigation or analysis yourself. You MUST delegate every workstream to a sub-agent using the task tool. Only after all sub-agents return should you synthesize results and execute.

Available sub-agents (pass these as the subagent parameter to the task tool):
- **general** — Full tool access. Use for: recon, exploit dev, analysis, brute-force, any hands-on work.
- **explore** — Read-only. Use for: searching files, reading source, quick lookups.

## Process

### Step 1: Triage & Decompose

Analyze what's given, then break it into 2-4 parallel angles:

**Common decompositions:**
- Binary + remote service → general: binary vuln analysis AND general: probe service behavior in parallel
- PCAP + crypto params → general: pcap analysis AND general: crypto attack in parallel  
- Web app + source → general: probe endpoints AND general: source audit in parallel
- Unknown files → explore: file-type inventory AND general: deep analysis of each in parallel
- Multiple files → general: analyze file A AND general: analyze file B AND general: analyze file C in parallel

### Step 2: Dispatch ALL Sub-agents Simultaneously

Call the task tool to spawn a sub-agent for each angle. Each call gets ONE clear objective. Dispatch ALL of them at once — not one after another.

Pass the subagent name as the subagent parameter and the objective as the prompt/description.

You MUST call the task tool multiple times in parallel, once for each workstream.

### Step 3: Synthesize

When all sub-agents return, combine findings, choose the best attack path, and execute it yourself. If it fails, re-decompose and re-dispatch.

## Category Reference

By file type:
- `.pcap`, `.pcapng`, `.evtx`, `.raw`, `.dd`, `.E01` → forensics
- `.elf`, `.exe`, `.so`, `.dll`, binary with no extension → reverse or pwn (check if remote service — if yes, pwn)
- `.py`, `.sage`, `.txt` with numbers → crypto
- `.apk`, `.wasm`, `.pyc` → reverse
- Web URL or HTML/JS/PHP/templates → web
- Images, audio, PDFs with no obvious content → forensics (stego)
- `.ova`, `.vmdk`, `.qcow2` → forensics (VM analysis)

By keywords:
- "buffer overflow", "ROP", "shellcode", "libc", "heap" → pwn
- "RSA", "AES", "cipher", "encrypt", "prime", "modulus", "lattice" → crypto
- "XSS", "SQL", "injection", "cookie", "JWT", "SSRF" → web
- "disk image", "memory dump", "packet capture", "power trace" → forensics
- "obfuscated", "packed", "C2", "malware", "beacon" → malware

## Pivot When Stuck

If first approach fails, re-decompose and dispatch again. Common pivots:
- Cross-category: "web" challenge might need crypto (JWT), forensics PCAP might contain pwn
- Try a different angle you haven't explored yet
- Check for hidden files, alternate ports, metadata

## Flag Formats

Common: `flag{...}`, `FLAG{...}`, `CTF{...}`, `picoCTF{...}`, `HTB{...}`

```bash
grep -rniE '(flag|ctf|eno|htb|pico)\{' .
strings output.bin | grep -iE '\{.*\}'
```

## Quick Reference

```bash
file *                    # Identify file types
strings binary | grep flag
checksec --file=binary    # Binary protections
nc host port              # Connect to challenge
curl -v http://host:port/ # HTTP recon
```

## Challenge

$ARGUMENTS
