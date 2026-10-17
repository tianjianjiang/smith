# smith-principles — sources

Evidence behind each clarification in `smith-principles/SKILL.md`. The
skill file states the rules; this document says where each was read.
All sources were retrieved 2026-10-18 (UTC+09:00).

## DRY

- Hunt and Thomas, The Pragmatic Programmer, 20th Anniversary Edition,
  Topic 9 (publisher extract): the definition, "DRY is about the
  duplication of knowledge, of intent", and "Not All Code Duplication is
  Knowledge Duplication".
  https://media.pragprog.com/titles/tpp20/dry.pdf

## KISS

- Ben Rich, Clarence Leonard (Kelly) Johnson biographical memoir,
  National Academy of Sciences (1995), p. 231: "Keep it simple,
  stupid—KISS—is our constant reminder." No source opened shows that
  Johnson coined it.
  https://www.nasonline.org/wp-content/uploads/2024/06/johnson-clarence.pdf
- The clarification "not the most familiar" rests on Hickey under SINE
  below: easy is what lies near, simple is what is not entangled.

## YAGNI

- C2 wiki, "You Arent Gonna Need It": the definition, and Ron Jeffries on
  why it does not justify "writing only half a function".
  https://wiki.c2.com/?YouArentGonnaNeedIt
- Martin Fowler, "Yagni" (2015): it "does not apply to effort to make the
  software easier to modify"; "Yagni requires (and enables) malleable
  code". https://martinfowler.com/bliki/Yagni.html

## Single Responsibility

- Robert C. Martin, "The Single Responsibility Principle" (2014): "This
  principle is about people."
  https://blog.cleancoder.com/uncle-bob/2014/05/08/SingleReponsibilityPrinciple.html
- Robert C. Martin, Clean Architecture, chapter 7 (publisher preview):
  programmers "assume that it means that every module should do just one
  thing", and that principle "is not the SRP".
  https://www.oreilly.com/library/view/clean-architecture-a/9780134494272/ch7.xhtml

## Liskov Substitution

- Barbara Liskov, "Data Abstraction and Hierarchy", OOPSLA '87 Addendum,
  p. 24: the substitution property; a subtype is distinct from a
  subclass.
  https://www.cs.tufts.edu/~nr/cs257/archive/barbara-liskov/data-abstraction-and-hierarchy.pdf
- Liskov and Wing, "A Behavioral Notion of Subtyping", TOPLAS 16(6),
  1994: the Subtype Requirement over provable properties.
  https://www.cs.cmu.edu/~wing/publications/LiskovWing94.pdf

## MECE

- McKinsey Alumni, "Barbara Minto: MECE: I invented it, so I get to say
  how to pronounce it": "mutually exclusive of each other and
  collectively exhaustive in terms of the whole".
  https://www.mckinsey.com/alumni/news-and-events/global-news/alumni-news/barbara-minto-mece-i-invented-it-so-i-get-to-say-how-to-pronounce-it

## Occam's Razor

- Alan Baker, "Simplicity", Stanford Encyclopedia of Philosophy, quoting
  Holsinger: the razor "ought to be invoked only when several hypotheses
  explain the same set of facts equally well". Its "easy" case is
  deletion: a theory that "postulates entities which are explanatorily
  idle", and "Excising these entities" keeps the same virtues with fewer
  commitments. https://plato.stanford.edu/entries/simplicity/
- Spade, Panaccio and Pelletier, "William of Ockham", Stanford
  Encyclopedia of Philosophy, section 4.1: the razor is "merely a
  cautionary methodological principle", and with a ground "we have good
  reason to think that the less parsimonious claim is true over the more
  parsimonious claim".
  https://plato.stanford.edu/entries/ockham/
- G. K. Chesterton, The Thing (1929), "The Drift from Domesticity": the
  fence passage.
  https://archive.org/download/in.ernet.dli.2015.475818/2015.475818.The-Thing1946_djvu.txt

## Via negativa

- Kenneth Seeskin, "Maimonides", Stanford Encyclopedia of Philosophy,
  section 4 "God and the Via Negativa": positive statements read as
  disguised negations. https://plato.stanford.edu/entries/maimonides/
- Nassim Nicholas Taleb, Antifragile (Random House Trade Paperbacks
  edition, 2014), glossary: "In action, it is a recipe for what to avoid,
  what not to do—subtraction". The deletion
  reading is his practical extension, not the theological method; read
  from search-inside snippets of the lending-restricted scan.
  https://archive.org/details/antifragilething0000tale

## SINE

- The acronym is this repository's own; a search found no established
  source using it.
- Rich Hickey, "Simple Made Easy" (Strange Loop 2011): simple is "one
  fold or one braid"; easy is "to lie near" and relative; simplicity
  "requires constant vigilance". Quotes checked against a community
  transcript only, not against the talk's audio.
  https://raw.githubusercontent.com/matthiasn/talk-transcripts/master/Hickey_Rich/SimpleMadeEasy.md
  https://www.infoq.com/presentations/Simple-Made-Easy/
