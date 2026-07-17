# Kontor: How I shipped a tax app as the Product Owner (while the AI did the typing)

*The short version of a hero's journey — a designer, an AI, and the German tax office.*

## The confession

I didn't write the code. I'm a UI designer, not a Swift developer — the source code of
"Kontor," my local, offline-first accounting app for macOS, was typed by my AI
pair-programmer (Claude Code, in the terminal, one step at a time). And yet this app is
mine, because I was its **Product Owner**. I've spent my whole life around software, I
think in systems, and I'm ambitious and pedantic enough to keep breaking a problem down
until it becomes solvable. I owned the *what* and the *why*: I specified, decided,
verified, and took responsibility. The AI had its fingers on the keyboard; the judgment
calls were mine. In under three weeks and roughly 127 commits, that turned into a real,
shipped app — guarded by 226 green tests.

## The old world

For years I did my entire freelance bookkeeping in Obsidian, using little `math.js`
calculation blocks. Charming, hand-rolled, completely mine — until quarterly filings,
accrual VAT, reverse-charge, artists' social insurance, and bad-debt write-offs slowly
turned my beautiful notebook into a house of cards I held my breath around. I also use two
wonderful apps by developer **Timo Partl** — **WorkingHours** for time tracking and
**SubTotal** for invoicing. What I was missing was the third tool: the place where it all
comes together into a monthly, quarterly, and yearly close. Kontor became that tool — not
a replacement for Timo's apps, but the piece that turns two into a dream team. (Proof this
isn't after-the-fact romance: the earliest versions even had importers for my old data
from Obsidian *and* SubTotal. They were deleted the moment the migration was done — you
kick away the ladder once you're over the wall.)

## The heart of it: two calendars for one invoice

The app's quiet superpower — the one nobody would guess from the outside — is this: the
same invoice lives in **two calendars at once**. My VAT is owed on an *accrual* basis:
the moment I *write* the invoice. My profit counts on a *cash* basis: only when the money
actually *lands*. Invoice written in December, paid in January? The VAT falls into Q4, the
profit into the next year. One invoice, two periods, two effects. Get that separation
wrong and you will miscalculate somewhere — and you might never notice.

On top of that, the app fills out the VAT return **exactly the way the form works**, using
the real ELSTER codes (ELSTER being the tax office's e-filing system): KZ 81/86 for the
taxable base, KZ 66 for input tax, KZ 83 for the amount due — rounding to the cent the way
ELSTER itself does. Two special cases are my favorites. **Reverse-charge (§13b)**, the
cash-neutral foreign expense: I owe the German VAT on a US tool like Figma and deduct it in
the same breath, so it nets to zero — yet the net amount is still a real, profit-reducing
business expense. And **bad-debt relief (§17)**: if a client never pays, I claw back the
VAT I'd fronted — except the ELSTER form has no field for it, so the correction has to
quietly *reduce the taxable base* instead of showing up as its own line. Honest about
provenance: I didn't invent the tax rules. They come from my real life as a KSK-insured
freelancer, and I'd written them down in a detailed spec beforehand. What's new and
hand-built is translating them into a stubbornly tested calculation engine — verified
against a made-up demo persona (a fictional Berlin designer), so no real financial data
ever lives in the open-source repo, with a dedicated PII check that sounds the alarm if
anyone tries.

## The bank statement that learns

The obvious dream was: hand the AI my bank statement, let it categorize everything
automatically. We built it — and scrapped it. The amount-based guessing once confidently
turned a €14 pharmacy charge into "new phone." So I flipped it around. Kontor guesses
**nothing** on its own. I triage every bank movement myself, card by card, and the app
**learns per merchant** — book "Figma" once as a business reverse-charge expense, and it
proposes that itself next time. Only active booking teaches it; skipping a card
deliberately teaches it nothing. It ships with a tiny, non-personal set of starter rules
(common tools: Figma, Anthropic, OpenAI, GitHub → reverse-charge; Adobe, with German VAT →
domestic 19%). And the absent hero of the story: automatic bank matching is still
deliberately *not* back in. Sometimes the best AI feature is the one you leave out.

## The monsters

My boss fights rarely looked dangerous. The dangerous ones looked *right*.

**The typographic quotes.** The pretty, curly `"…"` instead of the straight `"…"` as a
string delimiter in the code — and the Swift build breaks, with a cryptic error. In the
diff they look identical; you stare at two matching lines and one of them is poison. The
fix wasn't code, it was a watchdog: a tiny script that, before every commit, hunts for the
one character that never legitimately appears in Swift source.

**The OCR beast.** Kontor reads receipts. Apple does the text recognition (on-device, no
cloud upload) — but turning a bag of floating word-fragments back into "*this* is the net
amount" was hand-work: matching right-aligned numbers to their labels, parsing English
date formats (Figma's "June 4, 2025"), German thousands-dots. The nastiest head was
invisible: rendering the PDF pages ran through a shared system drawing apparatus that's
only allowed on the main thread — but Kontor called it from a background task, and the
batch processor rendered several receipts *at once*. Two workers, one easel, crash. A
sporadic, hard-to-reproduce failure — the worst kind. The fix: every render gets its own
easel; a new test deliberately runs eight renders in parallel, off the main thread.

**"Looks right, isn't."** My most feared monster: the plausible wrong number. My headline
figure — "what's actually left for me" — was computed independently in three places, and
the wrong version was the one the AI server happened to use. It reported **€2,233**; the
monthly close said **€1,043**. The €1,190 gap was exactly one business expense the wrong
formula had simply forgotten. The fix has a name that reads like a moral: "the profit
waterfall has *one* source." Add to that an import parser that silently turned English
"1332.80" into 133,280, and a quarterly task that cloned itself *daily* every time I
checked it off. The lesson over everything: the enemy isn't the error that screams, it's
the duplication that whispers. Every number needs exactly one source.

**The data dragon.** This database holds my *real* financial data. An overeager
emergency path would have shoved it aside and restarted the app empty on any harmless
hiccup — a briefly locked file, say. The fix: a second, calm retry first; and if
everything truly fails, the old database is only ever **moved, never deleted**. Whether an
AI-built emergency repair clears out the treasure vault on a hiccup is not a coder
question — it's a Product Owner question. And that one, nobody could take off my hands.

## Out into the world

Kontor is free and open source — not out of virtue, but out of very German logic: I'm
KSK-insured, and *selling* software commercially could jeopardize that status. Giving it
away is fine. Distribution runs through GitHub and Homebrew, complete with the little
Gatekeeper dance on first launch (deliberately not expensively notarized). The App Store
dragon had several lives: submitted → **rejected twice** (the optional local AI server
broke rule 2.4.5; my voluntary donation broke the mandatory in-app-purchase rule 3.1.1) →
cancelled outright → resubmitted three days later as a lean, AI-server-free,
donation-free, Germany-only variant, reusing a restored old listing so existing user data
carries over seamlessly. And the punchline, almost too perfect for a story about humans
and machines: at one point I **rebuilt the entire git history to remove "Claude" as a
co-author from every single commit** — not out of shame, but so the repository stands
cleanly under *my* name, as the one who carries the responsibility. The ghostwriter,
erasing itself from the credits by its own hand.

## What I keep

Three truths. **The real enemy is duplication, not the bug** — almost every nasty bug came
from the same truth living in two places and drifting apart. One number, one source.
**Small-for-one-case beats big-for-everyone** — Kontor can't do double-entry books or the
small-business VAT exemption; it does exactly my tax situation, and so it does it right.
And **"ask, don't assume"** is the most valuable clause in any contract with an AI:
wherever the machine stopped and asked when unsure, it turned out well; wherever it
plausibly kept guessing, it turned into a boss fight.

The most honest reckoning of the whole setup: the AI typed the code I wouldn't have typed
myself — which is enormous, and I won't play it down. But it took none of the
responsibility off my hands. It would happily have written me three subtly different
versions of the same number and believed all three, until I — the Product Owner with the
pedantic eye — got the feeling that *this can't be right*. No compiler has that feeling,
no AI has it; only the human who sends the number to the tax office at month's end and
stands behind it. Kontor is now my third tool, next to WorkingHours and SubTotal: my dream
team. One of them I owned, specified, verified, and pushed through. An AI typed the code;
the product is mine. And that, it turns out, is also a way to build an app — maybe the one
that has the most to do with judgment.

---

*Not a substitute for tax advice — every calculation is a simplified estimate and should be
checked independently before filing. Thanks to Timo Partl for WorkingHours and SubTotal, the
two-thirds of my dream team I didn't have to build myself.*
