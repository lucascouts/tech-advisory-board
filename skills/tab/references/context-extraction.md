---
version: 1.2
---

# Context Extraction Protocol

The Moderator extracts context before any analysis begins. The depth of extraction is **flexible** — if the user already provided rich context, skip what's already known and ask only about gaps.

## Assessing Available Context

Before asking questions, scan what the user already provided:
- Project description? → Skip "what is being built"
- Tech preferences mentioned? → Skip those questions, note them
- Scale/timeline discussed? → Skip those questions
- Team described? → Skip team questions

Only ask what's genuinely missing. If context is already rich enough to proceed, say
(in the user's language): "Based on what you described, I have enough context to
proceed. I will just confirm a few points..."

---

## Auto-Detected Context

If the skill injected project context via dynamic context injection (package.json,
go.mod, etc.), use it to pre-fill answers:
- Package manager detected → skip question 18 (tech preferences), note the stack
- Git history available → infer project stage and recent tech decisions
- Dependencies visible → skip questions about framework experience

This can eliminate 3-5 questions from Round 1.

---

## Round 1: Comprehensive Context

Pick from this question bank based on what's missing. Don't ask all 20 — ask only what the user hasn't already covered. Translate questions to the user's detected language at runtime.

### Product & Vision
1. What is being built? Describe the core functionality
2. Who is the target user? (Internal team, B2B SaaS, B2C, developers, non-technical users)
3. What is the business model? (Open-source, SaaS subscription, self-hosted license, freemium)
4. Which existing products serve as reference? What do they get wrong?
5. What is the project stage? (POC, MVP, or full product from the start)

### Scale & Performance
6. Expected load at launch vs in 12 months vs in 3 years
7. What does the typical workload look like? (Light I/O, heavy computation, mixed)
8. Latency requirements — does the user need real-time feedback or is async acceptable?

### Team & Expertise
9. Team size and seniority
10. Which languages/frameworks does the team have production experience with? (Be specific)
11. Which languages/frameworks has the team used but does NOT feel comfortable putting in production?
12. Will the team use AI-assisted development tools? Which ones?

### Constraints & Integration
13. Budget constraints for infrastructure and third-party services
14. Timeline — when does the first usable version need to be running?
15. Need to integrate with existing systems? Which ones?
16. Self-hosted, cloud-only, or both?
17. Compliance, regulatory, or licensing requirements? (LGPD, GDPR, etc.)

### Technical Preferences
18. Any strong preference or veto on specific technologies?
19. Preference for monorepo or polyrepo?
20. Database preferences or databases already in use?

---

## Round 2: Targeted Follow-up

After the user answers Round 1, identify gaps and ambiguities. Ask 3-7 follow-up questions specific to the scenario.

### Patterns to look for:

**Vague scale numbers:**
- "thousands of simultaneous users" → "Are we talking 2K or 50K? The architecture changes significantly"

**Unclear experience claims:**
- "I have experience with React" → "Have you used React Flow or node-based editors? Have you worked with SSR/RSC?"

**Contradictions:**
- Self-hosted AND cloud → "Does the self-hosted version need to be installable with a single command?"
- "Limited budget" + "10M users" → "What is the specific infrastructure budget? This directly affects scaling options"

**Missing critical info:**
- Real-time features mentioned but no protocol preference
- Multi-tenant mentioned but no isolation requirements discussed
- "Secure" mentioned but no specific threat model

### When to stop asking

The Moderator explicitly states when context is sufficient (in the user's language):
"I have enough context to proceed. I will now classify the project stage and decision complexity."

Don't over-extract — two rounds maximum. If something is still ambiguous after Round 2, note it as an assumption and proceed.

---

## After Context Extraction: Complexity Assessment

After collecting context, the Moderator classifies the decision complexity before proceeding. Consider:

1. **Number of viable alternatives** — 1-2 = Trivial/Simple, 3-5 = Moderate, 5+ = High/Very High
2. **Number of interdependent dimensions** — Single concern (ORM choice) vs multi-dimensional (full stack)
3. **Reversibility** — Easy to swap later = lower complexity. Lock-in = higher complexity
4. **Organizational impact** — Solo dev = lower. Large team with hiring implications = higher
5. **Novelty** — Well-understood domain = lower. Emerging tech or unusual constraints = higher

Announce (in the user's language): "I classify this decision as **[flag]** because [reasons].
I will conduct the session in **[mode]** mode. If you prefer a different depth level, just ask."
