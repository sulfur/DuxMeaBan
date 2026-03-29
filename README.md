# DuxMeaBan -  by sulf

<img width="1357" height="876" alt="Screenshot 2026-03-29 013318" src="https://github.com/user-attachments/assets/18c8a683-703f-4c2c-a427-74114dbd2391" />

`Linux-only` terminal application with a `Bash TUI` and `Playwright` helpers for:

- preparing a legal report from a local template
- filling the related browser flow
- storing sender profiles
- tracking local report history
- checking the public status of reported accounts over time

## How It Works

The project has three layers:

1. `report.sh`
   Main text UI. It handles menus, profiles, input, progress bars, summaries, and local history.

2. `config/report.json`
   Base legal template. It contains the fields used to build the request payload: country, issue type, legal references, and explanation text.

3. `scripts/*.mjs`
   Node/Playwright scripts for browser automation:
   - `assist.mjs`: main form-completion flow
   - `check-profile-status.mjs`: public account-status check used by `Report List`

In practice:

- choose or create a sender configuration
- enter the `Profile URL`
- optionally add post links
- the script generates both text and JSON report artifacts
- the Playwright flow starts
- the result is recorded in local history
- `Report List` can later check whether the target profile is still publicly available

## Requirements

- Linux
- `bash`
- Node.js `18+`
- `npm`
- a supported browser available in `PATH`

Supported browsers:

- `chromium`
- `chromium-browser`
- `google-chrome`
- `google-chrome-stable`
- `microsoft-edge`
- `microsoft-edge-stable`

Optional:

- `PLAYWRIGHT_BROWSER_PATH` to explicitly set the browser executable

## Installation

```bash
npm install
chmod +x ./report.sh
```

Run:

```bash
./report.sh
```

Or:

```bash
npm run start
```

## Main Menu

On startup, the TUI home screen exposes three sections:

- `New Report`
- `Report List`
- `Configuration`

Main controls:

- `UP/DOWN/LEFT/RIGHT` to navigate
- `ENTER` to confirm
- `CTRL+H` to return to the home screen

## Configuration

This section manages saved sender profiles.

Each configuration contains:

- `First Name`
- `Last Name`
- `Email`

`Signature` is generated automatically as:

```text
First Name Last Name
```

For each profile you can:

- edit it
- delete it
- activate/deactivate it

If a profile is marked as `active`, `New Report` uses it directly without asking you to choose one manually.

## New Report

Flow:

1. use the active profile, or ask you to choose a configuration
2. request the `Profile URL`
3. request optional `Post Links`
4. build the local report artifacts
5. start the browser automation
6. show the progress bar
7. save the history entry and open the final summary screen

Runtime output files:

- `out/legal-report.txt`
- `out/legal-report.json`
- `out/assist.log`
- `out/assist-sent.png`
- `out/assist-submit-map.json`

## Report List

This section shows reports stored locally in `data/reports.json`.

Each card displays:

- reported account
- account status
- local date/time of the request

Displayed states:

- `Loading`
- `Pending`
- `Banned`

Logic:

- when entering `Report List`, the script checks the visible profiles
- `Refresh` re-checks only the selected account
- the check is performed by `scripts/check-profile-status.mjs`

## Project Structure

- `report.sh`
  Bash TUI entry point

- `scripts/assist.mjs`
  Playwright script for the main browser flow

- `scripts/check-profile-status.mjs`
  Playwright script used to verify whether a profile is still publicly available

- `config/report.json`
  Base legal template used to build the request

- `assets/`
  ASCII art and TUI assets

## Local Runtime Files

These files are created locally and are not intended for publishing:

- `config/profiles.json`
- `data/reports.json`
- `out/`
- `screenshots/`

## Request Template

The project builds the request starting from `config/report.json`.

Current values:

```json
{
  "country": "Italy",
  "legalIssue": "OtherTDR_Select",
  "specificLawUrl": "https://www.normattiva.it/uri-res/N2Ls?urn:nir:stato:legge:1952;645~art4",
  "officialEntryUrl": "https://help.instagram.com/contact/406206379945942",
  "referenceDocuments": [
    "https://www.normattiva.it/uri-res/N2Ls?urn:nir:stato:legge:1952;645~art4"
  ]
}
```

### Links Used to Build the Request

- official form / entrypoint:
  `https://help.instagram.com/contact/406206379945942`

- main legal reference:
  `https://www.normattiva.it/uri-res/N2Ls?urn:nir:stato:legge:1952;645~art4`

- reference document included in the request:
  `https://www.normattiva.it/uri-res/N2Ls?urn:nir:stato:legge:1952;645~art4`

### Base Message Used in the Request

The current base text used in the `why` field is:

```text
Ritengo che il contenuto segnalato violi la normativa italiana vigente in materia di apologia del fascismo, in particolare la Legge 20 giugno 1952, n. 645 (Legge Scelba), art. 4.

Ai sensi di tale disposizione, e' punito chiunque:

faccia propaganda per la costituzione di movimenti aventi finalita' fasciste;
oppure esalti pubblicamente esponenti, principi, fatti o metodi del fascismo o le sue finalita' antidemocratiche.

Nel contenuto segnalato si riscontrano elementi riconducibili a tali condotte, in quanto:

vengono presentati e/o valorizzati aspetti ideologici, simbolici o storici legati al fascismo;
tali contenuti risultano idonei a configurare una forma di esaltazione pubblica di un'ideologia vietata dall'ordinamento italiano.

Si evidenzia inoltre che:

la stessa legge prevede un aggravamento della pena quando tali condotte avvengono tramite mezzi di diffusione pubblica, come internet e social media.

Per completezza, si richiama anche il contesto costituzionale:

la XII disposizione transitoria e finale della Costituzione italiana vieta la riorganizzazione del partito fascista, principio attuato proprio dalla Legge Scelba.

Alla luce di quanto sopra, il contenuto segnalato appare potenzialmente in violazione della normativa italiana e merita una valutazione approfondita ai fini della sua rimozione.
```

## How the Payload Is Built

The final payload contains:

- country: `Italy`
- legal issue: `OtherTDR_Select`
- main legal reference URL
- explanation text (`why`)
- reported profile URL
- attached post URLs

Generated artifacts:

- `legal-report.txt`
  human-readable version of the report

- `legal-report.json`
  JSON payload consumed by the browser scripts

## Available npm Scripts

```bash
npm run start
npm run assist
npm run check-status
```

Advanced direct usage:

- `npm run assist`
  runs `scripts/assist.mjs` directly

- `npm run check-status`
  runs `scripts/check-profile-status.mjs` directly

## Operational Notes

- the project is prepared for Linux
- sender local data and report history are intentionally excluded from publishing
- if no browser is found, set `PLAYWRIGHT_BROWSER_PATH`
- if the profile is the only URL provided, the script still warns that some flows may prefer direct content URLs
