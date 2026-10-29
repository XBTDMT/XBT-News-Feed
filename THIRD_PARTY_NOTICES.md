# Third-party notices

News Feed (PulseFeed) is licensed under the GNU General Public License, version 3 or later (see [LICENSE](LICENSE)). It bundles or links the third-party work below. Copyright lines and licence names are taken from the bundled files or from each package's own licence file in a local SwiftPM checkout (`PulseFeed/.build/checkouts/`, read on 2026-09-07 at the versions `PulseFeed/Package.resolved` pins). Where no licence file could be read locally the licence is stated as the project publishes it and marked **not verified locally**.

## Bundled in this repository

### Readability.js and Readability-readerable.js

- Files: `PulseFeed/PulseFeed/Resources/JS/Readability.js`, `PulseFeed/PulseFeed/Resources/JS/Readability-readerable.js`, and the byte-identical copies under `PulseFeed/Resources/JS/` that the Makefile copies into the app bundle.
- Origin: Mozilla's Readability library (https://github.com/mozilla/readability), which is based on Arc90's readability.js 1.7.1.
- Licence: **Apache License, Version 2.0**. Each file carries this header:

  ```
  Copyright (c) 2010 Arc90 Inc

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
  ```

### Manrope (font)

- File: `PulseFeed/PulseFeed/Resources/Fonts/Manrope[wght].ttf`, with its licence text in `PulseFeed/PulseFeed/Resources/Fonts/OFL.txt`; both are copied into the app bundle (`Contents/Resources/Fonts/`) and the font is registered at launch for the Stream design.
- Copyright 2018 The Manrope Project Authors (https://github.com/sharanda/manrope).
- Licence: **SIL Open Font License, Version 1.1**; the full text is in `OFL.txt` alongside the font.

### Archivo Black (one glyph outline)

- The app's master icon draws the letter "X" of Archivo Black as a fourteen-point outline whose coordinates are hard-coded in `PulseFeed/PulseFeed/Design/XTileGlyph.swift`. No font file is bundled and the font is never embedded or loaded; only that one glyph's outline is used.
- Archivo Black is designed by Omnibus-Type and published under the **SIL Open Font License, Version 1.1** (https://fonts.google.com/specimen/Archivo+Black). The font file is not in this repository, so its copyright line is stated as the project publishes it and is **not verified locally**.

## Swift packages declared in `PulseFeed/Package.swift`

`Package.swift` declares minimum versions (`from:`); the versions below are what the local `Package.resolved` pinned when this file was written, and they were re-derived unchanged on 2026-10-23 from `PulseFeed/Package.resolved`, which is committed, so a fresh clone resolves the same versions. Licence files were read from `PulseFeed/.build/checkouts/<package>/`.

| Package | Resolved | Licence | Copyright | Verified |
|---|---|---|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.10.0 | MIT | Copyright (C) 2015-2025 Gwendal Roué | yes, `LICENSE` |
| [FeedKit](https://github.com/nmdias/FeedKit) | 10.4.0 | MIT | Copyright (c) 2016 - 2025 Nuno Dias | yes, `LICENSE` |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | 2.11.3 | MIT | Copyright (c) 2009-2025 Jonathan Hedley (https://jsoup.org/); Swift port copyright (c) 2016-2025 Nabil Chatbi | yes, `LICENSE` |
| [SwiftAnthropic](https://github.com/jamesrochabrun/SwiftAnthropic) | 2.2.1 | MIT, as published by the project (its README carries an MIT licence badge) | James Rochabrun | **not verified locally**: the 2.2.1 checkout ships no LICENSE file |
| [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) | 1.3.0 | MIT | Copyright (c) 2023 Steffan Andrews - https://github.com/orchetect | yes, `LICENSE` |
| [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) | 1.1.0 | MIT | Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com) | yes, `license` |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.9.0 | MIT (with the external licences below) | Copyright (c) 2006-2013 Andy Matuschak; 2009-2013 Elgato Systems GmbH; 2011-2014 Kornel Lesiński; 2015-2017 Mayur Pawashe; 2014 C.W. Betts; 2014 Petroules Corporation; 2014 Big Nerd Ranch | yes, `LICENSE` |

`Sparkle.framework` is embedded in the app bundle (`Contents/Frameworks/`). Its `LICENSE` also lists the following components under their own terms:

- `bspatch.c` and `bsdiff.c` from bsdiff 4.3: Copyright 2003-2005 Colin Percival, BSD 2-clause licence.
- `sais.c` and `sais.h` from sais-lite (2010/08/07): Copyright (c) 2008-2010 Yuta Mori, MIT licence.
- Portable C implementation of Ed25519 (https://github.com/orlp/ed25519): Copyright (c) 2015 Orson Peters, zlib licence.
- `SUSignatureVerifier.m`: Copyright (c) 2011 Mark Hamlin, BSD 2-clause licence.

[GRDBQuery](https://github.com/groue/GRDBQuery) (MIT, Copyright (C) 2021 Gwendal Roué) is referenced in a comment in `Package.swift` but is not a dependency and is not linked.

### Transitive packages

These are pulled in by the packages above (chiefly SwiftAnthropic's HTTP stack) and are not used directly by this app. The list was re-derived from `PulseFeed/Package.resolved` on 2026-10-23: 30 pins, the seven packages above and these 23. Licences were read from the local checkouts on 2026-09-07.

- **Apache License 2.0:** async-http-client, swift-nio, swift-nio-extras, swift-nio-http2, swift-nio-ssl, swift-nio-transport-services, swift-crypto, swift-asn1, swift-certificates, swift-log, swift-collections, swift-algorithms, swift-async-algorithms, swift-atomics, swift-numerics, swift-system, swift-configuration, swift-distributed-tracing, swift-http-types, swift-http-structured-headers, swift-service-context, swift-service-lifecycle.
- **MIT:** LRUCache (Copyright (c) 2021 Nick Lockwood).

## Data services

The app has no server: every request below goes from the user's Mac straight to the service, only for what the
user switched on or chose. No key ships with the app; the two free keys and the optional Claude key are each
person's own. The terms summarised here were read on 2026-10-22 and 2026-10-23; each service can change them. The
credit line the shown prices need sits beside the prices in every design, at 10 pt or more; the full list is in
Settings › Power › Data sources and under Prices in the welcome flow.

| Service | What the app uses it for | Key | Attribution and conditions |
|---|---|---|---|
| The feeds' publishers | The RSS, Atom and JSON feeds in the catalog or added by the user, and the article pages the reader opens | none | Headlines, excerpts, images and articles belong to their publishers. The app bundles no content: it fetches each feed on the user's Mac and links every story back to its source. |
| [Google News](https://news.google.com) RSS search | A typed interest the catalog does not cover becomes a search feed (`news.google.com/rss/search`), polled every 15 minutes | none | The feed is published "solely for the purpose of rendering Google News results within a personal feed reader for personal, non-commercial use"; results are not redistributed. No credit is asked; each article belongs to its publisher. Google's robots.txt disallows `/rss/` for crawlers; a reader fetching the feed its user asked for is not crawling, but that point is not settled. |
| [CoinGecko](https://www.coingecko.com) keyless public API | BTC, ETH, SOL and XRP; and, without a Finnhub key, tokenized copies of SPY, QQQ and the MAG7 stocks and PAX Gold | none | **"Powered by CoinGecko"**, linked to coingecko.com, required by CoinGecko's API Terms to be "placed in a visible location, close to where the data is displayed", in a font no smaller than 10; the app shows it beside the prices. CoinGecko owns the data and is not liable for it; crypto prices are volatile. The keyless pool allows about 10–30 calls a minute per IP and is described by CoinGecko as not meant for production polling; the app makes one call per poll, minutes apart. |
| [Frankfurter](https://frankfurter.dev) (European Central Bank reference rates) | EUR/USD, and a dollar index computed from the ECB's rates with ICE's DXY formula, labelled "USD idx" (DXY is ICE's index and name) | none | **"Source: ECB"**: the ECB allows free use when the information appears accurately and the ECB is cited as the source. The rates are daily. |
| [Gemini](https://www.gemini.com) public market-data WebSocket | Live one-minute prices for the chosen coins while the Mac is on power | none | **"Data provided by Gemini"**, the wording Gemini's Market Data Agreement recommends. Permitted use is personal or internal; the data is not redistributed. |
| [Finnhub](https://finnhub.io) | Real exchange quotes for SPY, QQQ, MAG7 (through MAGS), gold (GLD), oil (USO) and the dollar (UUP) | the user's own, free | Finnhub's free plans are for personal use, and data may not be redistributed or shared. The app credits "Quotes: Finnhub". |
| [balldontlie](https://app.balldontlie.io/) | Live NBA scores for the teams the user follows | the user's own, free | The terms allow personal and commercial use of the data; an API key may not be shared or distributed, which is why none ships. |
| [Jolpica F1](https://github.com/jolpica/jolpica-f1) | The catalog's "F1 Schedule" (hourly) and "F1 Results" (every 30 minutes) sources, `api.jolpi.ca/ergast/f1/…`, three requests an hour when both are on | none | Credit: **"F1 schedule and results: Jolpica F1 (https://github.com/jolpica/jolpica-f1), data under CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/)."** Jolpica's Terms make the API free for **non-commercial use** only and license the data CC BY-NC-SA 4.0; a fork that is sold or carries ads cannot rely on it. Rate limits: 4 requests a second and 500 an hour per IP, unauthenticated, and Jolpica asks for a User-Agent naming the app and its version. |
| [Hacker News](https://news.ycombinator.com) | The catalog's "Hacker News" source, the site's own RSS feed (`news.ycombinator.com/rss`), every 15 minutes. The code keeps a fallback for HN's public Firebase JSON API (`hacker-news.firebaseio.com`), which no current source uses | none | Verdict of the terms check: **unclear (leaning ok), kept with the caveat.** Y Combinator's Terms of Use bar "data mining, robots, scraping or similar data gathering" of the site in general and grant nothing for the RSS feed in words; the case for keeping it is the site's own advertised RSS link and a robots.txt that does not disallow `/rss` (the app's 15 minutes between fetches is far longer than its `Crawl-delay: 30` seconds). Kept within these limits: personal use in the person's own reader, the RSS only, each story linked to its source and its HN comments, nothing redistributed or sold. The Terms' Commercial Use clause reads "you agree not to display, distribute … or upload for any commercial purposes, any portion of the Site". No credit is asked. The Firebase API's README says "There is currently no rate limit." |
| [Anthropic](https://www.anthropic.com) Claude API | Only with the user's own API key: story summaries, the recap and the daily brief when Claude is used instead of, or after, the on-device model | the user's own | Governed by the user's own agreement with Anthropic. |

## Apple frameworks

SwiftUI, AppKit, FoundationModels, WebKit, UserNotifications, AVFoundation, IOKit and the other system frameworks the app links are part of macOS and are used under Apple's SDK terms; SF Symbols are used as Apple permits within apps.
