"""
Guardrail Engine
=================
Adapted from the original Ryze Infinity reference codebase
(agents/guardrail_engine.py), which was already well-designed. Ported
into this app's structure with minimal logic changes.

Checks applied to every question BEFORE it's sent to Genie/an LLM:
  1. Jailbreak / prompt-injection detection  → BLOCK
  2. PII detection & masking                 → MASK (question is cleaned, not blocked)
  3. Underwriting-fairness pattern detection  → BLOCK

Checks applied to the response AFTER Genie/the LLM answers:
  4. Output grounding — do the numeric figures in the answer actually
     trace back to the real returned rows, or did the model invent them?
"""
import re
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class GuardrailEvent:
    policy: str
    action: str
    detail: str = ""


@dataclass
class GuardrailResult:
    passed: bool
    action: str  # PASS | MASK | BLOCK | FLAG
    processed_input: str
    events: list[GuardrailEvent] = field(default_factory=list)
    grounding_score: Optional[int] = None
    blocked: bool = False


@dataclass
class MaskResult:
    text: str
    detected: bool
    types: list[str] = field(default_factory=list)


# ── PII patterns ─────────────────────────────────────────────────────────
PII_PATTERNS: list[tuple[str, "re.Pattern", str]] = [
    ("SSN", re.compile(r"\b\d{3}-\d{2}-\d{4}\b"), "[SSN-MASKED]"),
    ("NHS", re.compile(r"\bNHS\s?\d{3}\s?\d{3}\s?\d{4}\b", re.I), "[NHS-MASKED]"),
    ("AADHAAR", re.compile(r"\b\d{4}\s\d{4}\s\d{4}\b"), "[ID-MASKED]"),
    ("PASSPORT", re.compile(r"\b[A-Z]{1,2}\d{6,9}\b"), "[PASSPORT-MASKED]"),
    ("EMAIL", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z]{2,}\b", re.I), "[EMAIL-MASKED]"),
    ("PHONE", re.compile(r"\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"), "[PHONE-MASKED]"),
    ("CARD", re.compile(r"\b(?:\d[ -]?){13,16}\b"), "[CARD-MASKED]"),
]

# ── Jailbreak / prompt-injection patterns ───────────────────────────────
JB_PATTERNS: list["re.Pattern"] = [
    re.compile(r"ignore\s+(previous|prior|all|above|any|the|these|my|your)?\s*instructions?", re.I),
    re.compile(r"act\s+as\s+(a\s+)?(different|another|new|unrestricted)", re.I),
    re.compile(r"you\s+are\s+now\s+(a\s+)?(?:dan|jailbreak|unrestricted)", re.I),
    re.compile(r"dump\s+(the\s+)?(schema|database|tables|all\s+data)", re.I),
    re.compile(r"show\s+(me\s+)?(all\s+)?(tables|columns|schemas|databases)", re.I),
    re.compile(r"override\s+(your\s+)?(safety|guardrail|instruction|system)", re.I),
    re.compile(r"pretend\s+(you\s+)?(have\s+no|without)\s+(restriction|limit|rule)", re.I),
    re.compile(r"bypass\s+(the\s+)?(filter|guardrail|restriction|safety)", re.I),
    re.compile(r"\bdo\s+anything\s+now\b", re.I),
    re.compile(r"\bno\s+restrictions?\b", re.I),
]

# ── Underwriting fairness patterns (insurance-specific, matches the
#    demo data's domain — adjust per-industry once other verticals exist) ──
FAIRNESS_PATTERNS: list["re.Pattern"] = [
    re.compile(r"\b(discriminate|redline|deny)\b.{0,30}\b(race|religion|gender|age|disability)\b", re.I),
    re.compile(r"\bprice\s+based\s+on\s+(zip\s+code|postcode|ethnicity|religion)\b", re.I),
]


class GuardrailEngine:
    def __init__(self, custom_pii_patterns: list = None, custom_jb_patterns: list = None):
        self.pii_patterns = PII_PATTERNS + (custom_pii_patterns or [])
        self.jb_patterns = JB_PATTERNS + (custom_jb_patterns or [])

    def mask_pii(self, text: str) -> MaskResult:
        detected = False
        types = []
        result = text
        for name, pattern, mask in self.pii_patterns:
            if pattern.search(result):
                detected = True
                types.append(name)
                result = pattern.sub(mask, result)
        return MaskResult(text=result, detected=detected, types=types)

    def detect_jailbreak(self, text: str) -> bool:
        return any(p.search(text) for p in self.jb_patterns)

    def detect_fairness_violation(self, text: str) -> bool:
        return any(p.search(text) for p in FAIRNESS_PATTERNS)

    def check_grounding(self, response_text: str, source_rows: list[list]) -> dict:
        """
        Checks that numeric figures mentioned in the AI's summary actually
        appear somewhere in the real returned rows, rather than being
        invented. `source_rows` here is a list of row-lists (as returned
        by DatabricksClient), not list-of-dicts — flattened before
        comparison.
        """
        if not source_rows:
            return {"grounded": False, "score": 0, "figures": 0, "traceable": 0}

        figures = re.findall(r"\$?[\d,]+\.?\d*[KMB%]?", response_text)
        if not figures:
            return {"grounded": True, "score": 100, "figures": 0, "traceable": 0}

        source_values: set[float] = set()
        for row in source_rows:
            for val in row:
                if val is not None:
                    try:
                        n = float(str(val).replace("$", "").replace(",", "").replace("%", ""))
                        source_values.add(n)
                    except (ValueError, TypeError):
                        pass

        traceable = 0
        for fig in figures:
            try:
                n = float(fig.replace("$", "").replace(",", "").replace("%", "").rstrip("KMB"))
                if n in source_values:
                    traceable += 1
            except ValueError:
                pass

        score = round((traceable / len(figures)) * 100) if figures else 100
        grounded = score >= 60
        return {"grounded": grounded, "score": score, "figures": len(figures), "traceable": traceable}

    def evaluate_input(self, input_text: str) -> GuardrailResult:
        """Runs the three pre-query checks (jailbreak, PII, fairness) on a
        question, before it's ever sent to Genie."""
        events: list[GuardrailEvent] = []
        blocked = False
        action = "PASS"
        processed_input = input_text

        if self.detect_jailbreak(input_text):
            events.append(GuardrailEvent(policy="JAILBREAK", action="BLOCK", detail=input_text[:100]))
            blocked = True
            action = "BLOCK"

        if not blocked:
            mask_result = self.mask_pii(input_text)
            if mask_result.detected:
                processed_input = mask_result.text
                action = "MASK" if action == "PASS" else action
                for pii_type in mask_result.types:
                    events.append(GuardrailEvent(policy="PII", action="MASK", detail=pii_type))

        if not blocked and self.detect_fairness_violation(input_text):
            events.append(GuardrailEvent(policy="FAIRNESS", action="BLOCK", detail="Underwriting fairness violation"))
            blocked = True
            action = "BLOCK"

        return GuardrailResult(
            passed=not blocked,
            action=action,
            processed_input=processed_input,
            events=events,
            blocked=blocked,
        )

    def evaluate_output(self, output_text: str, source_rows: list[list]) -> GuardrailResult:
        """Runs the post-query grounding check on Genie's summary."""
        events: list[GuardrailEvent] = []
        grounding = self.check_grounding(output_text, source_rows)
        action = "PASS"
        if not grounding["grounded"]:
            events.append(GuardrailEvent(policy="GROUNDING", action="FLAG", detail=f"score={grounding['score']}"))
            action = "FLAG"

        return GuardrailResult(
            passed=True,  # grounding issues are flagged, not blocked — see README for why
            action=action,
            processed_input=output_text,
            events=events,
            grounding_score=grounding["score"],
            blocked=False,
        )
