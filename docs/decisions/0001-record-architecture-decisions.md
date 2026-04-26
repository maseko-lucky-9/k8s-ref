# 1. Record architecture decisions

Date: 2026-04-26

## Status

Accepted

## Context

This repo is the production K8s reference architecture for Prudentia Digital's freelance portfolio. It will be inspected by potential clients evaluating senior K8s engineering capability. Every non-trivial decision (MicroK8s vs k3s, Helm vs Kustomize, Loki vs Elasticsearch, etc.) needs a clear rationale a hiring manager can read in 60 seconds.

The global CLAUDE.md rule applies: *"On any non-trivial decision (architecture, library choice, trade-off), write an ADR to `docs/decisions/NNN-<slug>.md` before implementing. Capture: problem, options considered, decision, consequences."*

## Decision

We will use **Architecture Decision Records (ADRs)** as described by Michael Nygard ([original article](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)).

- File location: `docs/decisions/`
- Filename pattern: `NNNN-<kebab-case-slug>.md` (4-digit zero-padded)
- Format: this file's structure (Title, Date, Status, Context, Decision, Consequences)
- Statuses: `Proposed`, `Accepted`, `Superseded by NNNN`, `Deprecated`
- An ADR is **append-only** once Accepted — superseding ADRs link back

## Consequences

**Positive**
- Hiring managers and future maintainers can trace why a choice was made
- Forces explicit thinking before code lands
- Aligns with global engineering principle of "decisions over preferences"

**Negative / cost**
- Small overhead per non-trivial decision (~10 min per ADR)
- Risk of bikeshedding "is this trivial enough to skip" — bias toward writing the ADR

**Neutral**
- Tooling: keep simple Markdown. No `adr-tools` CLI required. New ADRs are created by copying this template.
