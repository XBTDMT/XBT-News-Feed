# How News Feed decides what to interrupt you for

News Feed sends two kinds of notification and never one per story: an **urgent alert** for the few things that
should reach you now, and one **recap** of everything else. This page gives the rules as the code applies them,
with every number. The rules text a new install starts with is `UrgencyRules.defaults` in
`PulseFeed/PulseFeed/Design/Urgency.swift`; market moves are in `Design/MarketShock.swift`; the alert modes in
`Design/AlertMode.swift`; the recap in `Design/SummaryComposer.swift` and `Services/FeedEngine.swift`.

## Three tiers

Every new story is placed in one tier:

| Tier | What happens |
|---|---|
| **Urgent** | Its own notification at once, within the budget below. |
| **Headline** | No interruption; it leads the next recap. |
| **Summary** | Rolled into the next recap. |

## What makes a story urgent

A story is urgent when its headline matches an urgent pattern or names someone you follow with an event word (the
keyword layer, which runs on every story and on every power state), **or** when the model, asked about the story,
rates it *breaking*.

### Urgent patterns

A pattern is a lowercase piece of text the headline must contain; `a&b` means both must appear. A pattern written
`<category or topic>: <pattern>` applies only to stories from that category or catalog topic, so it can only fire
while that topic is on (a topic you never switched on brings in no stories).

- **World events, everywhere:** ceasefire, peace deal, invasion, invades, declares war, war breaks out, coup,
  assassinat(ion), martial law, nuclear strike.
- **Crypto:** exchange hack, hacked & exchange, insolven(t) & exchange, halts withdrawals, all-time high & bitcoin,
  ETF approv(al).
- **Finance:** circuit breaker, emergency rate.
- **AI:** GPT- / Claude / Gemini with releas(e) or launch, frontier model, new model & Anthropic, new model &
  OpenAI.
- **Music:** tour dates, announces & tour, world tour.

### Names you follow

A name you follow (picked in the welcome flow's Follow step, typed into a type-anything box, or added to the rules)
makes a story urgent when the headline contains the name as whole words (a plural or possessive counts:
"Porsches", "LeBron's") **and** one of these event words: trade, traded, acquire, sign, signs, signing, waive,
release, releases, launch, launches, unveil, announce, announces, tour, dates, fired, hired, retire, injur(y),
out for, suspend, recall, reveal. A new install follows nobody until you choose.

### The model's vote

When Apple's on-device model (or Claude, with your own key) summarises a story, it also rates it. The prompt
defines breaking news as "a major, singular event an informed person would want to hear about RIGHT NOW": a war
breaking out or a ceasefire, a coup or an assassination, a major disaster, a market index or major asset moving
more than 2–3 % in a day or setting a record, a major death, or a major turn for someone or something you follow;
not routine results, previews, rumours or opinion. A *breaking* rating makes the story urgent; an *important* one
makes it a headline.

Not every story is put to the model. On power, it sees the stories that score above 3 on your interest keywords or
that two or more outlets carry; on battery, above 5, or two or more outlets; on a critically low battery (on
battery and either under 20 % or in Low Power Mode), none. At most 10 stories a check and 400 model calls a day
across both engines. Without the model, only the keyword layer decides.

### What demotes a match

A headline containing rumor, rumour, report:, reportedly, opinion, preview, power rankings or recap is demoted: a
keyword match (a pattern or a followed name) drops from urgent to headline, and the model's *breaking* vote does
not lift it.

### Headline patterns

These lead the recap without interrupting: retire, blockbuster, dies at, dead at, passes away, resigns, steps down,
record high, record low, all-time high, wins championship, wins title, sacked, fired.

## The budget

At most **3 urgent alerts in any hour and 10 in any 24 hours**, counted since the app started; story alerts and
market alerts share it. A story that finds the budget spent is not lost: it waits, un-notified, for the next
recap. A change to the two numbers in the rules takes effect at the next launch.

## Market moves

For the instruments you chose (up to five), a big move gets its own alert, decided from the numbers, never from
headlines:

| Instrument | Alerts at |
|---|---|
| SPY, QQQ, MAG7 | a move of ±2.5 % or more on the day (a rolling 24 hours with the keyless prices, below) |
| BTC, ETH, SOL, XRP | a move of ±7 % or more over 24 hours |
| Gold, oil, DXY, EUR/USD | never |

With the keyless prices, the stocks are tokenized copies that trade around the clock, so their change is a rolling
24 hours rather than the day's; with a Finnhub key it is the day's change on the exchange.

**Once per move.** After an alert, that instrument and direction stay latched until the move falls back under half
the threshold (or turns the other way). The latch is stored, so a relaunch or a new day does not repeat it: a −3 %
Friday still reads −3 % all weekend, and alerts once. A move that finds the budget spent is latched without an
alert.

Market alerts are on by default; Settings › Notifications › **Alert on big market moves** switches them off.

## The recap

Every 15 minutes by default (5, 15, 30 or 60 minutes, or off, in Settings › Notifications), one notification
covers the unread stories (up to the newest 60) that arrived since the last recap and did not get an alert of
their own. Nothing new means nothing sent, and the clock starts again.

The banner's title is the count ("What's new · 12 stories") and its second line names the lead headlines, the one
line always visible. The body is written by the on-device model (or, with your key, by Claude when the on-device
model cannot): three to five short sentences, the first of which must name the most important story on its own.
When the model is unavailable or its answer does not parse, and always on a critically low battery, the body is the
plain list instead: the headline-tier stories, then the top three others. **Mark these read** on the notification
marks its stories read.

## Alert modes

Chosen in the welcome flow's Alerts step or Settings › Notifications:

| Mode | Urgent stories | Market moves | Recap |
|---|---|---|---|
| **Breaking + recap** (the default) | alerted at once | alerted | sent |
| **Recap only** | lead the next recap instead | not alerted | sent |
| **Quiet** | nothing | nothing | nothing |

In Quiet, the menu bar count and the popover still show what is new.

Two more filters apply to every mode: **Quiet Hours** (Settings › Notifications) sends nothing between the hours
you set, and the stories that arrive then wait for the first recap after them; and each category's own switch
under **Category Notifications** keeps its stories out of alerts and recaps alike.

## Changing the rules

Settings › Notifications › **Urgency rules** shows all of the above as one editable text: the urgent patterns, the
followed names, the headline patterns, the demoting words, and the market numbers (`spy move % = 2.5`,
`btc move % = 7`, `alerts per hour = 3`, `alerts per day = 10`). **Reset to defaults** brings back the built-in
text.
