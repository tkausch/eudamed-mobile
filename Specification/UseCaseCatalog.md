# EUDAMED Mobile — Use Case Catalogue (v2, remote-only)

**Scope:** A v1 iOS app with three tabs — **Devices (UDI)**, **Actors**, **Scan** — querying the live EUDAMED API directly through `RemoteUdiDeviceRepository` and `RemoteActorRepository`. No local persistence of EUDAMED records, no sync, no caching layer.

**Assumptions** (inferred — correct anything wrong):
- Repository names are `RemoteUdiDeviceRepository` and `RemoteActorRepository`; both are `async` and throwing, and both support paged queries.
- `CachingUdiDeviceRepository`, `LocalUdiDevicesRepository`, the SwiftData model layer, and the whole sync path are removed from the app. `UdiDevice` / `Actor` survive as plain value types.
- Devices and Actors each get their own query form with fields specific to that entity — no shared "universal search" field.
- The app remains read-only against EUDAMED, with no account and no backend of your own.
- iPhone first, portrait, iOS 17+.
- **Consequence to accept explicitly:** the app no longer works offline at all. The old story "search in a basement plant room with no signal" is dead. Section 1 handles this as an honest failure mode rather than pretending otherwise.

---

## Actors

- **Regulatory affairs specialist** — checks registration, legislation, risk class, and market status. Now gets live data by construction, but needs to know when a query was truncated by the API rather than by reality.
- **Hospital biomedical engineer / procurement** — has a device or manufacturer in hand and wants identification and registration confirmation before accepting or buying.
- **Field technician at the device** — standing in front of equipment with a barcode, phone in one hand. Primary user of the Scan tab; the most likely to have bad signal.
- **First-time user** — opens the app with an empty form and no idea what a Basic UDI-DI or an SRN is.
- **EUDAMED API** (non-human actor) — slow, rate-limited, occasionally down, and capped at roughly 10,000 results per query. Every story in this catalogue is downstream of its behaviour.

---

## 1. Working against a live API

**Constraints (all tabs):** every user-visible search issues at least one network request; no EUDAMED response is written to disk. Request timeout 15 s (assumed). Query text never leaves the device except as an EUDAMED API parameter; no analytics on query content.

### 1.1 Understand the app's first screen
**As a** first-time user, **I want** the empty Devices tab to show me what I can search for, **so that** I don't stare at a blank form guessing what a Basic UDI-DI is.

*Priority:* Must

**Acceptance criteria**
- **Given** I have never run a search **When** I open the Devices tab **Then** the query form is shown with an explanation of what the app queries and that results come from EUDAMED live.
- **Given** the empty state **When** I read a field label such as Basic UDI-DI or SRN **Then** a short plain-language explanation of that identifier is reachable without leaving the screen.
- **Given** I have run at least one search in this session **When** I return to the tab **Then** the introductory explanation does not reappear in place of my results.

### 1.2 See that a query is running and stop it
**As a** biomedical engineer, **I want** a running query to be visibly in flight and cancellable, **so that** a slow EUDAMED response doesn't read as a frozen app.

*Priority:* Must

**Acceptance criteria**
- **Given** I submit a query **When** the request takes longer than 300 ms **Then** an in-progress state is shown and a cancel action is available.
- **Given** a query is running **When** I cancel it **Then** the request is cancelled, the previous results (if any) remain on screen, and no error is presented.
- **Given** a query is running **When** I submit a new query **Then** the in-flight request is cancelled and its response can never replace the newer results.

### 1.3 Recover from no connection
**As a** field technician, **I want** a connection failure to say so plainly and let me retry, **so that** I don't read "no results" as "this device is not registered".

*Priority:* Must

**Acceptance criteria**
- **Given** the device is offline **When** I submit any query **Then** I am told the app requires a connection, and the message is visibly distinct from a zero-result state.
- **Given** a request failed for lack of connection **When** connectivity returns **Then** a retry action re-runs the identical query without me re-entering the fields.
- **Given** the device is offline **When** I open any tab **Then** the query form still renders and my typed input is preserved.

### 1.4 Survive EUDAMED being slow, down, or rate-limiting
**As a** regulatory affairs specialist, **I want** server-side failures distinguished from my own mistakes, **so that** I know whether to fix my query or come back later.

*Priority:* Must

**Acceptance criteria**
- **Given** EUDAMED returns a 5xx or times out **When** the error is shown **Then** it identifies the failure as being on the EUDAMED side and offers retry.
- **Given** EUDAMED returns a rate-limit response **When** the error is shown **Then** I am told to wait, and automatic retries use increasing delays rather than a tight loop.
- **Given** a request fails **When** I retry three times in succession without success **Then** the app stops retrying automatically and leaves further attempts to me.

---

## 2. Device search (Devices tab)

**Constraints (device search):** the query form is a `Form`-based builder specific to `UdiDevicesQuery`; no field is shared with the Actors tab.

### 2.1 Search by trade name
**As a** biomedical engineer, **I want to** find a device by the name printed on its label, **so that** I can identify it without deciphering the barcode.

*Priority:* Must

**Acceptance criteria**
- **Given** the device query form **When** I enter a trade name and submit **Then** a `UdiDevicesQuery(tradeName:)` is issued and matching devices are listed.
- **Given** I enter a partial trade name such as "Acme Cath" **When** I submit **Then** devices whose trade name contains that fragment are returned. *(Blocked — see Open question 2.)*
- **Given** I enter only whitespace **When** I submit **Then** the field is treated as unset rather than sent as an empty-string filter.

### 2.2 Search by manufacturer
**As a** regulatory affairs specialist, **I want to** list a manufacturer's devices by SRN, **so that** I can review a portfolio in one pass.

*Priority:* Must

**Acceptance criteria**
- **Given** I enter a manufacturer SRN **When** I submit **Then** devices with that `mfSrn` are listed and each row shows `mfName`, not only the SRN.
- **Given** I enter an SRN in the wrong shape **When** I submit **Then** I am told the identifier looks malformed before a request is issued.
- **Given** an SRN that returns nothing **When** the empty state appears **Then** I am offered a jump to the Actors tab to check whether that SRN exists at all.

### 2.3 Filter by risk class and legislation
**As a** regulatory affairs specialist, **I want to** narrow to a risk class or to MDR versus IVDR, **so that** I only see devices relevant to the review in front of me.

*Priority:* Must

**Acceptance criteria**
- **Given** the query form **When** I open the risk class control **Then** I choose human-readable labels ("Class IIa"), never raw `riskClassId` integers.
- **Given** I select a risk class and submit **Then** the corresponding id is sent as a query parameter and only matching devices are returned.
- **Given** reference data could not be loaded **When** I open the control **Then** I am told the labels are unavailable and offered a retry, rather than shown a list of numbers.

### 2.4 Look a device up by identifier
**As a** biomedical engineer, **I want to** query directly by Primary DI or Basic UDI-DI, **so that** I can confirm an identifier I already hold.

*Priority:* Must

**Acceptance criteria**
- **Given** I enter a Primary DI **When** exactly one device matches **Then** its detail is opened directly rather than shown as a one-row list.
- **Given** I enter an identifier EUDAMED does not know **When** the empty state appears **Then** it states that EUDAMED returned no record for that identifier, with the query timestamp.
- **Given** a Basic UDI-DI matching several device records **When** I submit **Then** all of them are listed and the shared Basic UDI-DI is shown once above the list.

### 2.5 Combine, count, and clear device filters
**As a** regulatory affairs specialist, **I want to** apply several device filters together and reset them in one action, **so that** I can iterate without retyping.

*Priority:* Must

**Acceptance criteria**
- **Given** I set trade name and risk class **When** I submit **Then** results satisfy both conditions (AND, not OR).
- **Given** filters are active **When** I look at the results screen **Then** the number of active filters is visible without reopening the form.
- **Given** filters are active **When** I use the clear action **Then** every field resets and the results list is emptied rather than left showing stale matches.

### 2.6 Re-run a recent device query
**As a** returning user, **I want to** repeat a recent device query with one tap, **so that** I don't rebuild the same filter set on every visit.

*Priority:* Should

**Acceptance criteria**
- **Given** I have submitted at least one device query **When** I return in a new app session **Then** my recent device queries are listed, most recent first, capped at 10.
- **Given** a recent query is listed **When** I tap it **Then** the form is repopulated and the query is re-issued live — results are never restored from the previous run.
- **Given** recent queries exist **When** I clear them **Then** the list stays empty after a relaunch.

*(Note: this stores query parameters only. No EUDAMED response is persisted, so it does not reintroduce caching.)*

---

## 3. Device results and detail

**Constraints (results):** first page renders within 2 s of the API responding; scrolling stays smooth at 1,000 loaded rows on an iPhone 12.

### 3.1 Tell devices apart in the result list
**As a** biomedical engineer, **I want** each row to carry enough to distinguish devices, **so that** I don't open five to find one.

*Priority:* Must

**Acceptance criteria**
- **Given** results are shown **When** I read a row **Then** it shows trade name (falling back to device name), manufacturer name, and Primary DI.
- **Given** a device has neither trade name nor device name **When** it is listed **Then** the row still identifies it by Primary DI and is never blank.
- **Given** results are shown **When** I look above the list **Then** the number of matches is stated, distinguishing "returned so far" from any total the API reports.

### 3.2 Page through a large result set and know when it is truncated
**As a** regulatory affairs specialist, **I want to** know when EUDAMED stopped giving me results rather than running out of them, **so that** I don't conclude a portfolio is smaller than it is.

*Priority:* Must

**Acceptance criteria**
- **Given** a result set larger than one page **When** I scroll to the end **Then** the next page is requested automatically and appended without losing my scroll position.
- **Given** a query exceeds EUDAMED's result-depth limit **When** I reach the last reachable page **Then** I am told the result set was capped by the API and advised to narrow the query.
- **Given** a page request fails mid-scroll **When** the failure occurs **Then** already-loaded results stay on screen and only the failed page offers retry.

### 3.3 Understand an empty device result
**As a** regulatory affairs specialist, **I want to** know why nothing came back, **so that** I can tell "not registered in EUDAMED" from "my filters were too narrow".

*Priority:* Must

**Acceptance criteria**
- **Given** a query returns zero results **When** the empty state appears **Then** it restates the applied filters and offers to clear or loosen them.
- **Given** a query returns zero results **When** the empty state appears **Then** it states that EUDAMED itself returned nothing at a named time, and does not assert the device is unregistered when only non-identifier filters were used.

### 3.4 Read a device's full record
**As a** regulatory affairs specialist, **I want to** see every populated field, **so that** the app replaces a lookup on the EUDAMED website.

*Priority:* Must

**Acceptance criteria**
- **Given** I open a device **When** the detail appears **Then** identification, classification, and characteristics are grouped as separate sections.
- **Given** an optional field is nil **When** the detail appears **Then** it is omitted rather than shown with an empty value.
- **Given** the list row carried only partial data and detail requires a second request **When** that request fails **Then** the fields already known are shown and the missing section offers retry.

### 3.5 See labels instead of codes
**As a** biomedical engineer, **I want** coded fields resolved to text, **so that** I don't need a lookup table to read a record.

*Priority:* Must

**Acceptance criteria**
- **Given** reference data loaded successfully **When** I view a device **Then** `riskClassId`, `applicableLegislationId`, `statusId`, `deviceStatusTypeId`, and `placedOnTheMarketId` show their reference labels.
- **Given** reference data is unavailable or a code has no entry **When** I view that field **Then** the raw code is shown together with a note that the label could not be resolved — the field never silently disappears.

### 3.6 Judge market status, version, and unknown characteristics
**As a** regulatory affairs specialist, **I want** market status, record version, and "not stated" flags handled honestly, **so that** I don't read missing data as a negative answer.

*Priority:* Must

**Acceptance criteria**
- **Given** a characteristic such as implantable, sterile, or latex-containing is nil **When** I view the device **Then** it is presented as not stated or omitted — never as "No".
- **Given** a device whose status indicates it is no longer placed on the market **When** I view it **Then** that status appears in the first screenful without scrolling.
- **Given** `versionNumber` differs from `latestVersion` in the API response **When** I view the device **Then** I am told which version I am looking at and that a newer version exists.

---

## 4. Actor search (Actors tab)

**Constraints (actor search):** a query form built for `ActorsQuery`, with its own fields (SRN, actor name, actor type, country) and no reuse of device fields.

### 4.1 Search actors by name or SRN
**As a** procurement officer, **I want to** look an economic operator up by name or SRN, **so that** I can verify who I am actually buying from.

*Priority:* Must

**Acceptance criteria**
- **Given** the actor query form **When** I enter an actor name and submit **Then** an `ActorsQuery` is issued and matching actors are listed.
- **Given** I enter an SRN **When** exactly one actor matches **Then** its detail is opened directly.
- **Given** I submit with every field empty **When** the form is validated **Then** the query is not issued and I am told at least one criterion is required.

### 4.2 Filter actors by type and country
**As a** regulatory affairs specialist, **I want to** restrict results to manufacturers, authorised representatives, or importers in a given country, **so that** I can find the right role in a supply chain rather than every company with a similar name.

*Priority:* Must

**Acceptance criteria**
- **Given** the actor form **When** I open the actor-type control **Then** I choose readable role labels, not raw type ids.
- **Given** I select an actor type and a country and submit **Then** both are sent as query parameters and results satisfy both.
- **Given** the country list cannot be resolved from reference data **When** I open the control **Then** I am told so and can still submit the rest of the query.

### 4.3 Tell actors apart in the result list
**As a** procurement officer, **I want** each actor row to show role and country alongside the name, **so that** I can pick between three companies with near-identical names.

*Priority:* Must

**Acceptance criteria**
- **Given** actor results are shown **When** I read a row **Then** it shows actor name, SRN, actor type, and country.
- **Given** two actors share a name **When** both are listed **Then** their SRNs are visible without opening either.
- **Given** an actor query returns zero results **When** the empty state appears **Then** it restates the filters, offers to clear them, and states that EUDAMED returned nothing at a named time.

### 4.4 View an actor's registration record
**As a** regulatory affairs specialist, **I want to** see an actor's registration details and status, **so that** I can confirm the operator is validly registered and by which competent authority.

*Priority:* Must

**Acceptance criteria**
- **Given** I open an actor **When** the detail appears **Then** SRN, legal name, actor type, address, country, and registration status are shown, with nil fields omitted.
- **Given** an actor's status indicates the registration is not valid or has ended **When** I view it **Then** that status is visible in the first screenful.
- **Given** I use the copy action on the SRN **When** I invoke it **Then** the value is placed on the clipboard.

### 4.5 Re-run a recent actor query
**As a** returning user, **I want** my recent actor queries kept separately from my device queries, **so that** one tab's history doesn't clutter the other.

*Priority:* Could

**Acceptance criteria**
- **Given** I have run queries in both tabs **When** I open the Actors tab **Then** only actor queries are listed, capped at 10.
- **Given** I tap a recent actor query **When** it re-runs **Then** it is issued live against the API.

---

## 5. Scanning (Scan tab)

### 5.1 Scan a UDI barcode and reach the device
**As a** field technician, **I want to** point the camera at a device label and land on its EUDAMED record, **so that** I never retype a 20-character identifier.

*Priority:* Must

**Acceptance criteria**
- **Given** camera access is granted **When** I frame a UDI carrier **Then** it is decoded and a device query for the extracted Device Identifier is issued without further taps.
- **Given** the decode succeeds and exactly one device matches **When** the response arrives **Then** the device detail opens directly.
- **Given** the decode succeeds but EUDAMED returns nothing **When** the empty state appears **Then** the scanned identifier is shown, distinguished from a decode failure, and can be edited into the device form.

### 5.2 Handle camera permission
**As a** field technician, **I want** a denied camera permission to leave me a way forward, **so that** the Scan tab isn't a dead end.

*Priority:* Must

**Acceptance criteria**
- **Given** I have never been asked **When** I open the Scan tab **Then** the purpose of camera access is explained before the system prompt appears.
- **Given** I denied camera access **When** I open the Scan tab **Then** I am offered both a route to Settings and manual identifier entry that runs the same lookup.
- **Given** the device has no usable camera **When** I open the tab **Then** manual entry is presented without a permission prompt.

### 5.3 Cope with an unreadable or unexpected code
**As a** field technician, **I want** a scratched or non-UDI barcode to fail informatively, **so that** I know whether to reposition the phone or give up on the label.

*Priority:* Must

**Acceptance criteria**
- **Given** I hold the camera on a damaged carrier for 10 seconds without a decode **When** that elapses **Then** I am offered manual entry rather than left scanning indefinitely.
- **Given** a barcode decodes but contains no recognisable Device Identifier **When** it is parsed **Then** I am told the code was read but is not a UDI, with the decoded text shown.
- **Given** a UDI carrier containing production data such as lot or serial **When** it is parsed **Then** only the Device Identifier is used for the query, and the extra fields are shown as scanned context.

### 5.4 Scan while offline or on bad signal
**As a** field technician, **I want** a scan taken with no signal to be preserved, **so that** a trip to the basement isn't wasted.

*Priority:* Should

**Acceptance criteria**
- **Given** the device is offline **When** a scan decodes successfully **Then** the decoded identifier is retained on screen and I am told the lookup needs a connection.
- **Given** a retained identifier and restored connectivity **When** I retry **Then** the lookup runs without me rescanning.

---

## 6. Moving between devices and actors

### 6.1 Jump from a device to its manufacturer
**As a** procurement officer, **I want to** open the manufacturer's actor record from a device, **so that** I can check the operator's registration in the same breath as the device's.

*Priority:* Should

**Acceptance criteria**
- **Given** a device detail with a populated `mfSrn` **When** I tap the manufacturer **Then** an actor lookup for that SRN is issued and its detail opens.
- **Given** the manufacturer SRN returns no actor **When** the lookup completes **Then** I am told the SRN was not found in the actor registry, and the device detail remains reachable with one back action.

### 6.2 Jump from an actor to its devices
**As a** regulatory affairs specialist, **I want to** list an actor's devices from its record, **so that** I don't copy the SRN across tabs by hand.

*Priority:* Should

**Acceptance criteria**
- **Given** an actor detail **When** I choose to see its devices **Then** the Devices tab opens with a device query pre-filled with that SRN and already executed.
- **Given** that query returns results **When** I go back **Then** the actor detail is restored rather than reset to the actor query form.

---

## Design constraints

Apply across the catalogue; not restated per story.

- **Palette:** system blue as the single accent on `systemBackground`; no second accent colour. Correct under Dark Mode and Increase Contrast.
- **Components:** stock SwiftUI only — `TabView` (three tabs), `NavigationStack`, `List` with `.insetGrouped`, `Form` for both query builders.
- **Icons:** SF Symbols only. `barcode` or `shippingbox` (Devices), `building.2` (Actors), `barcode.viewfinder` (Scan), `line.3.horizontal.decrease.circle` (filters), `wifi.exclamationmark` (connection failure), `arrow.clockwise` (retry).
- **Accessibility:** Dynamic Type to AX5 with no truncation of identifiers; every icon-only control carries a label; VoiceOver reads a result row as one coherent statement, not four fragments.
- **Network etiquette:** typed input is debounced by at least 400 ms before any request; concurrent in-flight requests per tab are capped at one; paging requests are serialised.
- **Privacy:** no analytics on query content; nothing but EUDAMED API parameters leaves the device; no EUDAMED response is written to disk.

---

## Open questions

1. **Repository naming and surface.** Confirm `RemoteUdiDeviceRepository` / `RemoteActorRepository`, and whether both expose paging (offset/page token) and Swift concurrency cancellation. Stories 1.2, 3.2, and all of section 4 depend on it.

2. **Partial matching is now the API's problem.** With the local `#Predicate` gone, contains-style matching on trade name and actor name depends entirely on what EUDAMED's query parameters support. If the API is exact-match only, stories 2.1 and 4.1 degrade to "type it exactly right" and the app loses much of its point. This is the single biggest unknown in the rewrite.

3. **Truly no caching, or no *persistent* caching?** Dropping `CachingUdiDeviceRepository` means every scroll, every back-navigation, and every re-run hits EUDAMED. A short-lived in-memory result buffer for the current session would cut request volume sharply without reintroducing sync or a database. Decide whether that counts as "caching" for your purposes — story 3.2's paging behaviour changes either way.

4. **Reference data lifetime.** Risk classes, legislations, statuses, actor types, and countries are needed to render almost every screen. Fetching them on every launch costs requests; holding them in memory for the session is the minimum. Bundling a snapshot in the app is a third option with a staleness cost. Stories 2.3, 3.5, and 4.2 hinge on this.

5. **Depth cap behaviour.** EUDAMED's ~10,000-result ceiling now surfaces directly to the user mid-scroll. Does the API signal that the cap was hit, or does it just stop returning pages? Story 3.2's second criterion is untestable until this is known.

6. **Rate limits.** No published limit means the debounce and retry-backoff numbers in this catalogue are guesses. This is one of the questions already outstanding with SANTE-EUDAMED-SUPPORT.

7. **Barcode scope.** Which carriers does v1 decode — GS1 DataMatrix and GS1-128 only, or also HIBC and ICCBBA? And does the Device Identifier extracted from a GS1 AI (01) map to EUDAMED's `primaryDi`, its `basicUdi`, or neither reliably? Section 5 is built on the assumption that it maps to Primary DI.

8. **Actor endpoint parity.** Does `EudamedClient` already expose the actor endpoints with the same query flexibility as devices? If actor queries are SRN-only, story 4.1's name search and 4.2 both collapse.

9. **Offline as a product decision.** Removing the local store removes the plant-room use case, which was a Must in v1. Story 5.4 is the minimum mitigation. Confirm this trade is deliberate.

---

## Out of scope

- Any local persistence of EUDAMED records: SwiftData models, sync, offline search, staleness indicators, reset-local-data. Removed by decision, not oversight.
- Saved devices, favourites, watchlists, and change notifications.
- Any write path to EUDAMED.
- swissdamed / Swiss market data.
- Accounts, sign-in, and cross-device sync.
- Device version history and comparison between versions.
- Export (CSV, PDF, share sheet) of result sets.
- iPad-specific layout and macOS Catalyst.
