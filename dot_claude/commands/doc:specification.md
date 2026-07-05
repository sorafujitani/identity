---
description: Gather and organize internal implementation GitHub links, implementation overview, official documentation, usage examples, issues, discussions, and prerequisite knowledge for a given code snippet or language feature. Use as a command with arguments.
---

# Specification Deep Dive

Target: `$ARGUMENTS`

## Purpose

Generate a structured reference document for the given code, language feature, API, or library function.
No implementation work — knowledge aggregation and verified source linking only.

## Phase 1: Identify Target

- If `$ARGUMENTS` is empty, ask the user what to investigate
- If ambiguous (e.g. `useEffect` without React/Preact context), ask for clarification
- Determine language, framework, and version from the user's project context

## Phase 2: Parallel Research via 3 Agents

Launch 3 Agent tool calls **in parallel**. Each agent MUST use WebSearch and WebFetch.
Fabricated URLs cause broken links and destroy user trust — every URL must be verified via WebSearch/WebFetch before inclusion.

### Agent 1: Implementation Research

Research the internal implementation of `$ARGUMENTS`.

Tasks:
1. WebSearch for the source code on GitHub (e.g. `$ARGUMENTS source site:github.com`)
2. Identify the repository, file path, and collect a line-level permalink
3. WebFetch the GitHub source file to verify the link works
4. Summarize the implementation: call flow, key data structures, algorithms
5. Note any important internal details (e.g. caching, lazy evaluation, error handling)

Output format:
- Repository URL
- Source code permalink (with line numbers)
- Implementation summary (3-10 sentences covering call flow and key structures)

### Agent 2: Official Documentation & Usage Research

Research official documentation and usage patterns for `$ARGUMENTS`.

Tasks:
1. WebSearch for official documentation (e.g. `$ARGUMENTS official documentation`)
2. WebSearch for API reference and tutorials
3. WebFetch each documentation URL to verify it exists and extract the relevant content
4. Collect a minimal working code example from official sources
5. Note the version the documentation applies to

Output format:
- Table of documentation links with names and version notes
- Minimal usage code example (from official sources)

### Agent 3: Community & Prerequisite Knowledge Research

Research community discussions and prerequisite knowledge for `$ARGUMENTS`.

Tasks:
1. WebSearch for GitHub Issues and Discussions (e.g. `$ARGUMENTS site:github.com issue OR discussion`)
2. Identify design decisions, common pitfalls, and workarounds from the threads
3. Identify prerequisite concepts needed to understand this feature
4. WebSearch for official documentation of each prerequisite concept
5. WebFetch to verify all collected URLs

Output format:
- Table of related issues/discussions with title, URL, and one-line summary
- Table of prerequisite concepts with why they matter and reference URLs
- If no issues/discussions found, explicitly state so

## Phase 3: Verification & Integration

After all 3 agents complete:
1. Merge results, deduplicate URLs
2. Flag any contradictions between sources
3. Mark unverified items explicitly
4. Format into the output template below

## Output Format

Output the result directly as text in Claude Code's response. Do NOT write to a file.

Claude Code's terminal converts markdown pipe tables into Unicode box-drawing characters, making them impossible to copy as markdown. Therefore, NEVER use pipe tables (`| ... | ... |`). Use definition lists and bullet lists instead.

All prose in Japanese. Technical terms and code identifiers unchanged.

Use this structure (no pipe tables anywhere):

### Section 1: H1 heading + overview

# [Target Name]

[1-2 sentence overview]

### Section 2: Implementation

## Implementation

- **Repository**: [URL]
- **Source Code**: [GitHub permalink with line numbers]

### Implementation Overview

[Prose summary of internal behavior]

### Section 3: Official Documentation

## Official Documentation

- **[Document Name]** — [URL] (version/notes)
- **[Document Name]** — [URL] (version/notes)

### Section 4: Usage

## Usage

A fenced code block with a minimal working example.

### Section 5: Related Issues / Discussions

## Related Issues / Discussions

- **[Title]** — [URL]
  [One-line summary]
- **[Title]** — [URL]
  [One-line summary]

If none found, write: "関連するissue/discussionは見つかりませんでした"

### Section 6: Prerequisite Knowledge

## Prerequisite Knowledge

- **[Concept]** — [Reference URL]
  [Why this concept is needed to understand the target]
- **[Concept]** — [Reference URL]
  [Why this concept is needed to understand the target]

## Rules

- **No guessed URLs**: Guessed URLs rot immediately and erode trust. Every URL must be verified via WebSearch/WebFetch before output.
- **Version awareness**: Documentation drifts between versions. Always note which version a doc applies to, so the reader knows if it matches their environment.
- **Explicit uncertainty**: Gaps filled with guesses look authoritative but mislead. State "確認できませんでした" for anything unverified.
- **Implementation depth**: The reader wants to understand "why it works that way", not read every line. Summarize call flow and key structures in 3-10 sentences.
