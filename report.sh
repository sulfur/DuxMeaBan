#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$ROOT_DIR/assets"
CONFIG_DIR="$ROOT_DIR/config"
DATA_DIR="$ROOT_DIR/data"
OUT_DIR="$ROOT_DIR/out"

ASCII_BANNER_PATH="$ASSETS_DIR/ascii-art.txt"
TITLE_BANNER_PATH="$ASSETS_DIR/meaban.txt"
MAIN_MENU_LOGO_PATH="$ASSETS_DIR/nuovo-logo.txt"
SUMMARY_ASCII_PATH="$ASSETS_DIR/summary-ascii.txt"
PROFILE_CONFIGS_PATH="$CONFIG_DIR/profiles.json"
REPORT_CONFIG_PATH="$CONFIG_DIR/report.json"
REPORTS_PATH="$DATA_DIR/reports.json"
ASSIST_SCRIPT="$ROOT_DIR/scripts/assist.mjs"
CHECK_PROFILE_SCRIPT="$ROOT_DIR/scripts/check-profile-status.mjs"
PAYLOAD_PATH="$OUT_DIR/legal-report.json"
TEXT_PATH="$OUT_DIR/legal-report.txt"
SCREENSHOT_PATH="$OUT_DIR/assist-sent.png"
SUBMIT_MAP_PATH="$OUT_DIR/assist-submit-map.json"
ASSIST_LOG_PATH="$OUT_DIR/assist.log"

BOLD=""
DIM=""
PRIMARY_FG=""
SELECT_FG=""
MUTED_FG=""
BORDER_FG=""
YELLOW=""
GREEN=""
RED=""
RESET=""
BOX_THEME="${DUXMEABAN_BOX_THEME:-unicode}"
BOX_TL="╭"
BOX_TR="╮"
BOX_BL="╰"
BOX_BR="╯"
BOX_H="─"
BOX_V="│"
NODE_BIN="${NODE_BIN:-}"
NODE_PLATFORM=""
NODE_PROFILE_CONFIGS_PATH=""
NODE_REPORT_CONFIG_PATH=""
NODE_REPORTS_PATH=""
NODE_OUT_DIR=""
NODE_ASSIST_SCRIPT=""
NODE_CHECK_PROFILE_SCRIPT=""
NODE_PAYLOAD_PATH=""
NODE_TEXT_PATH=""
NODE_SCREENSHOT_PATH=""
NODE_SUBMIT_MAP_PATH=""

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  PRIMARY_FG=$'\033[38;2;181;194;183m'
  SELECT_FG=$'\033[38;2;98;70;107m'
  MUTED_FG=$'\033[38;2;130;140;132m'
  BORDER_FG=$'\033[90m'
  YELLOW=$'\033[33m'
  GREEN=$'\033[32m'
  RED=$'\033[31m'
  RESET=$'\033[0m'
fi

if [[ "$BOX_THEME" == "ascii" ]]; then
  BOX_TL="+"
  BOX_TR="+"
  BOX_BL="+"
  BOX_BR="+"
  BOX_H="-"
  BOX_V="|"
fi

PROFILE_LINES=()
COLLECTED_POST_URLS=()
SELECTED_PROFILE_LINE=""
PROFILE_ID=""
PROFILE_DISPLAY=""
PROFILE_FIRST_NAME=""
PROFILE_LAST_NAME=""
PROFILE_EMAIL=""
PROFILE_SIGNATURE=""
PROFILE_ACTIVE=""

REPORT_LINES=()
SELECTED_REPORT_LINE=""
REPORT_ID=""
REPORT_TARGET=""
REPORT_STATUS=""
REPORT_CREATED_AT=""
REPORT_CONFIGURATION=""
REPORT_PROFILE_URL=""

BANNER_RENDERED=0
MENU_TOP_ROW=1
LAST_KEY=""
INPUT_RESULT=""
ENABLE_ASCII_BANNER=0
TERMINAL_CLEANED_UP=0
ORIGINAL_STTY_STATE=""
CAPTURED_STATUS=0
HOME_REQUESTED=0

write_default_report_config() {
  cat >"$REPORT_CONFIG_PATH" <<'EOF'
{
  "country": "Italy",
  "legalIssue": "OtherTDR_Select",
  "specificLawUrl": "https://www.normattiva.it/uri-res/N2Ls?urn:nir:stato:legge:1952;645~art4",
  "officialEntryUrl": "https://help.instagram.com/contact/406206379945942",
  "referenceDocuments": [
    "https://www.normattiva.it/uri-res/N2Ls?urn:nir:stato:legge:1952;645~art4"
  ],
  "why": "Ritengo che il contenuto segnalato violi la normativa italiana vigente in materia di apologia del fascismo, in particolare la Legge 20 giugno 1952, n. 645 (Legge Scelba), art. 4.\n\nAi sensi di tale disposizione, e' punito chiunque:\n\nfaccia propaganda per la costituzione di movimenti aventi finalita' fasciste;\noppure esalti pubblicamente esponenti, principi, fatti o metodi del fascismo o le sue finalita' antidemocratiche.\n\nNel contenuto segnalato si riscontrano elementi riconducibili a tali condotte, in quanto:\n\nvengono presentati e/o valorizzati aspetti ideologici, simbolici o storici legati al fascismo;\ntali contenuti risultano idonei a configurare una forma di esaltazione pubblica di un'ideologia vietata dall'ordinamento italiano.\n\nSi evidenzia inoltre che:\n\nla stessa legge prevede un aggravamento della pena quando tali condotte avvengono tramite mezzi di diffusione pubblica, come internet e social media.\n\nPer completezza, si richiama anche il contesto costituzionale:\n\nla XII disposizione transitoria e finale della Costituzione italiana vieta la riorganizzazione del partito fascista, principio attuato proprio dalla Legge Scelba.\n\nAlla luce di quanto sopra, il contenuto segnalato appare potenzialmente in violazione della normativa italiana e merita una valutazione approfondita ai fini della sua rimozione."
}
EOF
}

resolve_node_bin() {
  if [[ -n "$NODE_BIN" ]]; then
    :
  elif command -v node >/dev/null 2>&1; then
    NODE_BIN="$(command -v node)"
  elif command -v nodejs >/dev/null 2>&1; then
    NODE_BIN="$(command -v nodejs)"
  else
    printf '%sNode.js non trovato. Installa "node" o "nodejs" e riprova.%s\n' "$RED" "$RESET" >&2
    exit 1
  fi

  NODE_PLATFORM="$("$NODE_BIN" -p "process.platform" 2>/dev/null | tr -d '\r\n')"
}

to_node_path() {
  local path="$1"
  local drive_letter=""
  local windows_rest=""
  local fallback=""

  if [[ "$NODE_PLATFORM" != "win32" ]]; then
    printf '%s\n' "$path"
    return
  fi

  if [[ "$path" =~ ^/mnt/([[:alpha:]])/(.*)$ ]]; then
    drive_letter="${BASH_REMATCH[1]}"
    windows_rest="${BASH_REMATCH[2]}"
    drive_letter="${drive_letter^^}"
    printf '%s:/%s\n' "$drive_letter" "$windows_rest"
    return
  fi

  if command -v wslpath >/dev/null 2>&1; then
    fallback="$(wslpath -m "$path" 2>/dev/null || true)"
    if [[ -n "$fallback" ]]; then
      printf '%s\n' "$fallback"
      return
    fi
  fi

  printf '%s\n' "$path"
}

refresh_node_paths() {
  NODE_PROFILE_CONFIGS_PATH="$(to_node_path "$PROFILE_CONFIGS_PATH")"
  NODE_REPORT_CONFIG_PATH="$(to_node_path "$REPORT_CONFIG_PATH")"
  NODE_REPORTS_PATH="$(to_node_path "$REPORTS_PATH")"
  NODE_OUT_DIR="$(to_node_path "$OUT_DIR")"
  NODE_ASSIST_SCRIPT="$(to_node_path "$ASSIST_SCRIPT")"
  NODE_CHECK_PROFILE_SCRIPT="$(to_node_path "$CHECK_PROFILE_SCRIPT")"
  NODE_PAYLOAD_PATH="$(to_node_path "$PAYLOAD_PATH")"
  NODE_TEXT_PATH="$(to_node_path "$TEXT_PATH")"
  NODE_SCREENSHOT_PATH="$(to_node_path "$SCREENSHOT_PATH")"
  NODE_SUBMIT_MAP_PATH="$(to_node_path "$SUBMIT_MAP_PATH")"
}

ensure_json_array_file() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    printf '[]\n' >"$path"
  fi
}

ensure_application_state() {
  resolve_node_bin
  refresh_node_paths
  mkdir -p "$ASSETS_DIR" "$CONFIG_DIR" "$DATA_DIR" "$OUT_DIR"
  ensure_json_array_file "$PROFILE_CONFIGS_PATH"
  ensure_json_array_file "$REPORTS_PATH"

  if [[ ! -f "$REPORT_CONFIG_PATH" ]]; then
    write_default_report_config
  fi
}

banner_file_full_lines() {
  local path="$1"

  awk '
    {
      lines[++count] = $0
      if ($0 ~ /[^[:space:]]/) {
        if (first == 0) first = count
        last = count

        match($0, /[^ ]/)
        indent = (RSTART > 0 ? RSTART - 1 : 0)

        if (min_indent == "" || indent < min_indent) {
          min_indent = indent
        }
      }
    }
    END {
      if (first == 0) exit

      if (min_indent == "") {
        min_indent = 0
      }

      for (i = first; i <= last; i++) {
        line = lines[i]

        if (min_indent > 0 && length(line) >= min_indent) {
          line = substr(line, min_indent + 1)
        }

        print line
      }
    }
  ' "$path"
}

trimmed_banner_lines() {
  local path="$1"
  local step="$2"
  local cols="$3"

  awk -v step="$step" -v cols="$cols" '
    {
      lines[++count] = $0
      if ($0 ~ /[^[:space:]]/) {
        if (first == 0) first = count
        last = count

        match($0, /[^ ]/)
        indent = (RSTART > 0 ? RSTART - 1 : 0)

        if (min_indent == "" || indent < min_indent) {
          min_indent = indent
        }
      }
    }
    END {
      if (first == 0) exit

      if (min_indent == "") {
        min_indent = 0
      }

      for (i = first; i <= last; i++) {
        if (((i - first) % step) != 0) continue
        line = lines[i]

        if (min_indent > 0 && length(line) >= min_indent) {
          line = substr(line, min_indent + 1)
        }

        if (length(line) > cols) {
          start = int((length(line) - cols) / 2) + 1
          if (start < 1) start = 1
          line = substr(line, start, cols)
        }
        print line
      }
    }
  ' "$path"
}

banner_file_max_width() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    printf '0'
    return
  fi

  awk '
    {
      if (length($0) > max) {
        max = length($0)
      }
    }
    END {
      print max + 0
    }
  ' "$path"
}

render_banner_file() {
  local path="$1"
  local step="$2"
  local color="$3"
  local cols=0
  local pad=0
  local block_width=0
  local line=""
  local -a lines=()

  if [[ ! -f "$path" ]]; then
    return
  fi

  mapfile -t lines < <(trimmed_banner_lines "$path" "$step" "$(get_terminal_cols)")

  if (( ${#lines[@]} == 0 )); then
    return
  fi

  for line in "${lines[@]}"; do
    if (( ${#line} > block_width )); then
      block_width="${#line}"
    fi
  done

  cols="$(get_terminal_cols)"

  if (( cols > block_width )); then
    pad=$(( (cols - block_width) / 2 ))
  fi

  for line in "${lines[@]}"; do
    printf '%*s%s%s%s\n' "$pad" '' "$color" "$line" "$RESET"
  done
}

tui_load_trimmed_banner_lines() {
  local path="$1"
  local step="${2:-1}"
  local max_cols="${3:-$(get_terminal_cols)}"
  mapfile -t BANNER_LINES < <(trimmed_banner_lines "$path" "$step" "$max_cols")
}

tui_banner_lines_max_width() {
  local max_width=0
  local line=""

  for line in "${BANNER_LINES[@]}"; do
    if (( ${#line} > max_width )); then
      max_width="${#line}"
    fi
  done

  printf '%s' "$max_width"
}

tui_rainbow_color_for_cell() {
  local row_index="$1"
  local col_index="$2"
  local palette_index=$(( ((col_index / 2) + row_index) % 8 ))

  case "$palette_index" in
    0) printf '\033[38;2;255;0;0m' ;;
    1) printf '\033[38;2;255;128;0m' ;;
    2) printf '\033[38;2;255;255;0m' ;;
    3) printf '\033[38;2;0;255;0m' ;;
    4) printf '\033[38;2;0;255;255m' ;;
    5) printf '\033[38;2;0;128;255m' ;;
    6) printf '\033[38;2;90;0;255m' ;;
    *) printf '\033[38;2;255;0;255m' ;;
  esac
}

tui_render_rainbow_logo_at() {
  local row="$1"
  local col="$2"
  local line=""
  local row_index=0
  local col_index=0
  local char=""
  local color=""

  tui_load_trimmed_banner_lines "$MAIN_MENU_LOGO_PATH" 1

  for row_index in "${!BANNER_LINES[@]}"; do
    line="${BANNER_LINES[$row_index]}"
    tui_move_cursor "$((row + row_index))" "$col"

    for ((col_index = 0; col_index < ${#line}; col_index++)); do
      char="${line:col_index:1}"

      if [[ "$char" == " " ]]; then
        printf ' '
      else
        color="$(tui_rainbow_color_for_cell "$row_index" "$col_index")"
        printf '%s%s%s' "$color" "$char" "$RESET"
      fi
    done
  done
}

tui_render_banner_file_in_area_at() {
  local path="$1"
  local top_row="$2"
  local col="$3"
  local width="$4"
  local height="$5"
  local color="${6:-$PRIMARY_FG}"
  local area_width="$width"
  local area_height="$height"
  local step=1
  local source_width=0
  local source_height=0
  local scaled_width=0
  local scaled_height=0
  local line=""
  local scaled_line=""
  local row_pad=0
  local col_pad=0
  local draw_row=0
  local idx=0
  local src_row=0
  local src_col=0
  local block_row=0
  local block_col=0
  local block_line=""
  local representative=" "
  local char=""
  local -a source_lines=()
  local -a scaled_lines=()

  if [[ ! -f "$path" ]] || (( area_width < 1 || area_height < 1 )); then
    return
  fi

  mapfile -t source_lines < <(banner_file_full_lines "$path")
  source_height="${#source_lines[@]}"

  if (( source_height == 0 )); then
    return
  fi

  for idx in "${!source_lines[@]}"; do
    line="${source_lines[$idx]}"
    line="${line%"${line##*[![:space:]]}"}"
    source_lines[$idx]="$line"

    if (( ${#line} > source_width )); then
      source_width="${#line}"
    fi
  done

  while (( ((source_height + step - 1) / step) > area_height || ((source_width + step - 1) / step) > area_width )); do
    step=$((step + 1))
  done

  for ((src_row = 0; src_row < source_height; src_row += step)); do
    scaled_line=""

    for ((src_col = 0; src_col < source_width; src_col += step)); do
      representative=" "

      for ((block_row = src_row; block_row < source_height && block_row < src_row + step; block_row++)); do
        block_line="${source_lines[$block_row]}"

        for ((block_col = src_col; block_col < ${#block_line} && block_col < src_col + step; block_col++)); do
          char="${block_line:block_col:1}"

          if [[ "$char" != " " ]]; then
            representative="$char"
            break 2
          fi
        done
      done

      scaled_line+="$representative"
    done

    scaled_line="${scaled_line%"${scaled_line##*[![:space:]]}"}"
    scaled_lines+=("$scaled_line")

    if (( ${#scaled_line} > scaled_width )); then
      scaled_width="${#scaled_line}"
    fi
  done

  scaled_height="${#scaled_lines[@]}"

  if (( area_height > scaled_height )); then
    row_pad=$(( (area_height - scaled_height) / 2 ))
  fi

  if (( area_width > scaled_width )); then
    col_pad=$(( (area_width - scaled_width) / 2 ))
  fi

  draw_row=$((top_row + row_pad))

  for idx in "${!scaled_lines[@]}"; do
    if (( draw_row + idx > top_row + height - 1 )); then
      break
    fi

    tui_move_cursor "$((draw_row + idx))" "$((col + col_pad))"
    printf '%s%s%s' "$color" "${scaled_lines[$idx]}" "$RESET"
  done
}

render_title_fallback() {
  local mode="$1"
  local color="$2"

  case "$mode" in
    mini)
      tui_print_centered_line ' __  __ _____    _    ____    _    _   _ ' "$color"
      tui_print_centered_line '|  \/  | ____|  / \  | __ )  / \  | \ | |' "$color"
      tui_print_centered_line '| |\/| |  _|   / _ \ |  _ \ / _ \ |  \| |' "$color"
      tui_print_centered_line '| |  | | |___ / ___ \| |_) / ___ \| |\  |' "$color"
      tui_print_centered_line '|_|  |_|_____/_/   \_\____/_/   \_\_| \_|' "$color"
      ;;
    *)
      tui_print_centered_line 'MEABAN' "$color"
      ;;
  esac
}

get_terminal_cols() {
  local value=""

  if [[ "${COLUMNS-}" =~ ^[0-9]+$ ]] && (( COLUMNS > 0 )); then
    printf '%s' "$COLUMNS"
    return
  fi

  value="$(tput cols 2>/dev/null || true)"

  if [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 )); then
    printf '%s' "$value"
    return
  fi

  value="$(stty size 2>/dev/null | awk '{ print $2 }' || true)"

  if [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 )); then
    printf '%s' "$value"
    return
  fi

  printf '80'
}

get_terminal_rows() {
  local value=""

  if [[ "${LINES-}" =~ ^[0-9]+$ ]] && (( LINES > 0 )); then
    printf '%s' "$LINES"
    return
  fi

  value="$(tput lines 2>/dev/null || true)"

  if [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 )); then
    printf '%s' "$value"
    return
  fi

  value="$(stty size 2>/dev/null | awk '{ print $1 }' || true)"

  if [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 )); then
    printf '%s' "$value"
    return
  fi

  printf '24'
}

cleanup_terminal() {
  if (( TERMINAL_CLEANED_UP == 1 )); then
    return
  fi

  TERMINAL_CLEANED_UP=1

  if [[ -n "$ORIGINAL_STTY_STATE" ]]; then
    stty "$ORIGINAL_STTY_STATE" 2>/dev/null || stty sane 2>/dev/null || true
  else
    stty sane 2>/dev/null || true
  fi

  if [[ -t 1 ]]; then
    printf '\033[0m\033[?25h'
    clear 2>/dev/null || true
  else
    printf '\033[0m\033[?25h'
  fi

  printf '\n'
}

handle_interrupt() {
  cleanup_terminal
  exit 130
}

prepare_terminal() {
  TERMINAL_CLEANED_UP=0

  if [[ -z "$ORIGINAL_STTY_STATE" ]]; then
    ORIGINAL_STTY_STATE="$(stty -g 2>/dev/null || true)"
  fi

  stty sane 2>/dev/null || true
  stty erase '^?' 2>/dev/null || true
  printf '\033[0m\033[?25h'
  clear 2>/dev/null || printf '\033[2J\033[H'
}

show_home_screen() {
  local cols
  local art_step=1

  cols="$(get_terminal_cols)"

  if [[ "$cols" -lt 180 ]]; then
    art_step=2
  fi

  clear 2>/dev/null || true
  render_banner_file "$ASCII_BANNER_PATH" "$art_step" "$CYAN"
  printf '\n'
  render_banner_file "$TITLE_BANNER_PATH" 1 "$WHITE"
  printf '\n'
}

pause_app() {
  read -r -p "Premi INVIO per continuare" _
}

read_required() {
  local prompt="$1"
  local default_value="${2-}"
  local value=""

  while true; do
    if [[ -n "$default_value" ]]; then
      read -r -p "$prompt [$default_value]: " value
      value="${value:-$default_value}"
    else
      read -r -p "$prompt: " value
    fi

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return
    fi
  done
}

parse_profile_line() {
  local line="$1"
  IFS='|' read -r PROFILE_ID PROFILE_DISPLAY PROFILE_FIRST_NAME PROFILE_LAST_NAME PROFILE_EMAIL PROFILE_SIGNATURE <<<"$line"
}

load_profile_lines() {
  mapfile -t PROFILE_LINES < <("$NODE_BIN" - "$NODE_PROFILE_CONFIGS_PATH" <<'NODE'
const fs = require('fs');

const [profilesPath] = process.argv.slice(2);
const raw = fs.existsSync(profilesPath) ? fs.readFileSync(profilesPath, 'utf8').trim() : '[]';
const records = raw ? JSON.parse(raw) : [];

const valid = (Array.isArray(records) ? records : [])
  .filter((record) => record && record.firstName && record.lastName && record.email)
  .map((record) => ({
    id: String(record.id || ''),
    firstName: String(record.firstName).trim(),
    lastName: String(record.lastName).trim(),
    email: String(record.email).trim(),
    signature: String(record.signature || `${String(record.firstName || '').trim()} ${String(record.lastName || '').trim()}`).trim()
  }))
  .sort((a, b) => {
    return `${a.firstName} ${a.lastName} ${a.email}`.localeCompare(`${b.firstName} ${b.lastName} ${b.email}`);
  });

for (const record of valid) {
  const display = `${record.firstName} ${record.lastName} <${record.email}>`;
  console.log([record.id, display, record.firstName, record.lastName, record.email, record.signature].join('|'));
}
NODE
)
}

upsert_profile_record() {
  local existing_id="$1"
  local first_name="$2"
  local last_name="$3"
  local email="$4"
  local signature="$5"

  "$NODE_BIN" - "$NODE_PROFILE_CONFIGS_PATH" "$existing_id" "$first_name" "$last_name" "$email" "$signature" <<'NODE'
const fs = require('fs');
const { randomUUID } = require('crypto');

const [profilesPath, existingIdArg, firstNameArg, lastNameArg, emailArg, signatureArg] = process.argv.slice(2);
const existingId = String(existingIdArg || '').trim();
const firstName = String(firstNameArg || '').trim();
const lastName = String(lastNameArg || '').trim();
const email = String(emailArg || '').trim();
const signature = String(signatureArg || `${firstName} ${lastName}`).trim();

if (!firstName || !lastName || !email) {
  throw new Error('La configurazione richiede Nome, Cognome ed Email.');
}

const raw = fs.existsSync(profilesPath) ? fs.readFileSync(profilesPath, 'utf8').trim() : '[]';
const records = raw ? JSON.parse(raw) : [];
const normalizedEmail = email.toLowerCase();

let index = -1;

if (existingId) {
  index = records.findIndex((record) => String(record.id || '') === existingId);
} else {
  index = records.findIndex((record) => String(record.email || '').trim().toLowerCase() === normalizedEmail);
}

const nextRecord = {
  id: index >= 0 ? String(records[index].id || '') : randomUUID(),
  firstName,
  lastName,
  email,
  signature
};

if (index >= 0) {
  records[index] = nextRecord;
} else {
  records.push(nextRecord);
}

fs.writeFileSync(profilesPath, JSON.stringify(records, null, 2));
NODE
}

edit_profile_interactive() {
  local existing_line="${1-}"
  local existing_id=""
  local first_name_default=""
  local last_name_default=""
  local email_default=""
  local first_name=""
  local last_name=""
  local email=""

  if [[ -n "$existing_line" ]]; then
    parse_profile_line "$existing_line"
    existing_id="$PROFILE_ID"
    first_name_default="$PROFILE_FIRST_NAME"
    last_name_default="$PROFILE_LAST_NAME"
    email_default="$PROFILE_EMAIL"
  fi

  first_name="$(read_required "Nome" "$first_name_default")"
  last_name="$(read_required "Cognome" "$last_name_default")"
  email="$(read_required "Email" "$email_default")"
  local signature="$(tui_trim_value "$first_name $last_name")"
  upsert_profile_record "$existing_id" "$first_name" "$last_name" "$email" "$signature"
}

ensure_profile_configurations_exist() {
  load_profile_lines

  if (( ${#PROFILE_LINES[@]} > 0 )); then
    return
  fi

  show_home_screen
  printf '%sNessuna configurazione salvata. Crea prima Nome, Cognome ed Email.%s\n\n' "$YELLOW" "$RESET"
  edit_profile_interactive
}

select_profile_line() {
  local prompt="$1"
  local choice=""

  SELECTED_PROFILE_LINE=""
  load_profile_lines

  if (( ${#PROFILE_LINES[@]} == 0 )); then
    return 1
  fi

  while true; do
    printf '%s\n' "$prompt"

    for index in "${!PROFILE_LINES[@]}"; do
      parse_profile_line "${PROFILE_LINES[$index]}"
      printf '%d. %s\n' "$((index + 1))" "$PROFILE_DISPLAY"
    done

    read -r -p "Numero configurazione: " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#PROFILE_LINES[@]} )); then
      SELECTED_PROFILE_LINE="${PROFILE_LINES[$((choice - 1))]}"
      return
    fi
  done
}

collect_post_urls() {
  COLLECTED_POST_URLS=()
  local value=""

  printf 'Inserisci i link dei post da segnalare, uno per riga. Premi INVIO su una riga vuota per terminare.\n'

  while true; do
    read -r -p "Link post: " value

    if [[ -z "$value" ]]; then
      break
    fi

    COLLECTED_POST_URLS+=("$value")
  done
}

build_report_artifacts() {
  local profile_url="$1"
  local post_urls_blob="$2"

  "$NODE_BIN" - "$NODE_REPORT_CONFIG_PATH" "$NODE_OUT_DIR" "$profile_url" "$post_urls_blob" <<'NODE'
const fs = require('fs');
const path = require('path');

const [reportConfigPath, outputDir, profileUrlArg, postUrlsBlobArg] = process.argv.slice(2);
const profileUrl = String(profileUrlArg || '').trim();
const postUrls = String(postUrlsBlobArg || '')
  .split(/\r?\n/)
  .map((value) => value.trim())
  .filter(Boolean);

const rawConfig = fs.readFileSync(reportConfigPath, 'utf8');
const config = JSON.parse(rawConfig);

const unique = [];
const seen = new Set();

for (const value of [profileUrl, ...postUrls]) {
  const trimmed = String(value || '').trim();
  const key = trimmed.toLowerCase();

  if (!trimmed || seen.has(key)) {
    continue;
  }

  seen.add(key);
  unique.push(trimmed);
}

const referenceDocuments = Array.isArray(config.referenceDocuments) ? config.referenceDocuments : [];
const why = String(config.why || '').trim();

const reportText = [
  `Select the country where you are claiming legal rights. : ${config.country}`,
  `What legal issue do you wish to report? : ${config.legalIssue}`,
  `What specific laws do you believe are violated by the reported content? : ${config.specificLawUrl}`,
  'Why do you believe this content violates the specific laws you believe to be violated? :',
  why,
  '',
  'Reported content URLs:',
  ...(unique.length > 0 ? unique.map((value) => `- ${value}`) : ['- INSERT_INSTAGRAM_PROFILE_OR_POST_URL']),
  '',
  'Reference documents:',
  ...(referenceDocuments.length > 0 ? referenceDocuments.map((value) => `- ${value}`) : ['- NO_REFERENCE_DOCUMENTS'])
].join('\n');

const payload = {
  generatedAtUtc: new Date().toISOString(),
  country: config.country,
  legalIssue: config.legalIssue,
  specificLawUrl: config.specificLawUrl,
  why: config.why,
  officialEntryUrl: config.officialEntryUrl,
  reportedContentUrls: unique,
  referenceDocuments,
  reportText,
  notes: [
    'This project prepares the report text, fills the official form, and submits the final legal request automatically.',
    'It does not log in, bypass platform checks, or guarantee anonymity toward Meta.'
  ]
};

fs.mkdirSync(outputDir, { recursive: true });
fs.writeFileSync(path.join(outputDir, 'legal-report.txt'), reportText);
fs.writeFileSync(path.join(outputDir, 'legal-report.json'), JSON.stringify(payload, null, 2));
NODE
}

append_report_history() {
  local configuration_name="$1"
  local first_name="$2"
  local last_name="$3"
  local email="$4"
  local signature="$5"
  local profile_url="$6"
  local post_urls_blob="$7"

  "$NODE_BIN" - "$NODE_REPORTS_PATH" "$configuration_name" "$first_name" "$last_name" "$email" "$signature" "$profile_url" "$post_urls_blob" "$NODE_TEXT_PATH" "$NODE_PAYLOAD_PATH" "$NODE_SCREENSHOT_PATH" "$NODE_SUBMIT_MAP_PATH" <<'NODE'
const fs = require('fs');
const { randomUUID } = require('crypto');

const [
  reportsPath,
  configurationName,
  firstName,
  lastName,
  email,
  signature,
  profileUrl,
  postUrlsBlob,
  textPath,
  jsonPath,
  screenshotPath,
  submitMapPath
] = process.argv.slice(2);
const raw = fs.existsSync(reportsPath) ? fs.readFileSync(reportsPath, 'utf8').trim() : '[]';
const reports = raw ? JSON.parse(raw) : [];
const pad = (value) => String(value).padStart(2, '0');
const now = new Date();
const createdAtLocal = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;
const deriveUsername = (profileUrl) => {
  const rawUrl = String(profileUrl || '').trim();

  if (!rawUrl) {
    return '';
  }

  try {
    const parsed = new URL(rawUrl);
    const parts = parsed.pathname.split('/').filter(Boolean);
    return parts[0] ? `@${parts[0]}` : rawUrl;
  } catch {
    return rawUrl;
  }
};

reports.push({
  id: randomUUID(),
  createdAtLocal,
  configurationName,
  senderFirstName: firstName,
  senderLastName: lastName,
  senderEmail: email,
  senderSignature: signature,
  profileUrl,
  postUrls: String(postUrlsBlob || '').split(/\r?\n/).map((value) => value.trim()).filter(Boolean),
  courtOrder: 'no',
  consent: 'yes',
  status: 'Submitted',
  accountStatus: 'Pending',
  accountStatusCheckedAtLocal: '',
  reportedUsername: deriveUsername(profileUrl),
  textPath,
  jsonPath,
  screenshotPath,
  submitMapPath
});

fs.writeFileSync(reportsPath, JSON.stringify(reports, null, 2));
NODE
}

print_report_rows() {
  "$NODE_BIN" - "$NODE_REPORTS_PATH" <<'NODE'
const fs = require('fs');

const [reportsPath] = process.argv.slice(2);
const raw = fs.existsSync(reportsPath) ? fs.readFileSync(reportsPath, 'utf8').trim() : '[]';
const reports = raw ? JSON.parse(raw) : [];

reports
  .slice()
  .sort((a, b) => String(b.createdAtLocal || '').localeCompare(String(a.createdAtLocal || '')))
  .forEach((report) => {
    const visibleStatus = String(report.accountStatus || '').trim() || 'Pending';
    console.log([
      String(report.createdAtLocal || ''),
      String(report.configurationName || ''),
      String(report.senderFirstName || ''),
      String(report.senderLastName || ''),
      String(report.senderEmail || ''),
      visibleStatus
    ].join('|'));
  });
NODE
}

run_assist() {
  local first_name="$1"
  local last_name="$2"
  local email="$3"
  local signature="$4"
  local profile_url="$5"

  if [[ ! -d "$ROOT_DIR/node_modules/playwright-core" ]]; then
    printf '%sMissing dependency: playwright-core. Run "npm install" first.%s\n' "$RED" "$RESET"
    return 1
  fi

  if [[ "$profile_url" =~ ^https?://(www\.)?instagram\.com/[^/?#]+/?$ ]]; then
    printf '%sAVVISO: il form ufficiale privilegia URL diretti al contenuto; un URL profilo potrebbe non bastare.%s\n' "$YELLOW" "$RESET"
  fi

  "$NODE_BIN" "$NODE_ASSIST_SCRIPT" \
    --payload "$NODE_PAYLOAD_PATH" \
    --screenshot "$NODE_SCREENSHOT_PATH" \
    --submit-map "$NODE_SUBMIT_MAP_PATH" \
    --profile-url "$profile_url" \
    --first-name "$first_name" \
    --last-name "$last_name" \
    --email "$email" \
    --signature "$signature" \
    --court-order "no" \
    --consent "yes" \
    --headless
}

new_report_menu() {
  local profile_url=""
  local post_urls=()
  local post_urls_blob=""

  ensure_profile_configurations_exist
  show_home_screen
  select_profile_line "Quale configurazione vuoi usare per la richiesta?"
  parse_profile_line "$SELECTED_PROFILE_LINE"
  printf '\n'

  profile_url="$(read_required "URL del profilo Instagram da segnalare")"
  collect_post_urls
  post_urls=("${COLLECTED_POST_URLS[@]}")
  post_urls_blob="$(printf '%s\n' "${post_urls[@]}")"

  build_report_artifacts "$profile_url" "$post_urls_blob"

  if run_assist "$PROFILE_FIRST_NAME" "$PROFILE_LAST_NAME" "$PROFILE_EMAIL" "$PROFILE_SIGNATURE" "$profile_url"; then
    append_report_history "$PROFILE_DISPLAY" "$PROFILE_FIRST_NAME" "$PROFILE_LAST_NAME" "$PROFILE_EMAIL" "$PROFILE_SIGNATURE" "$profile_url" "$post_urls_blob"
    printf '\n%sRichiesta inviata con configurazione "%s".%s\n' "$GREEN" "$PROFILE_DISPLAY" "$RESET"
    printf 'Screenshot finale: %s\n' "$SCREENSHOT_PATH"
    printf 'Mappa submit: %s\n' "$SUBMIT_MAP_PATH"
    printf 'Storico aggiornato in: %s\n' "$REPORTS_PATH"
  else
    printf '\n%sAssist fallito.%s\n' "$RED" "$RESET"
  fi

  printf '\n'
  pause_app
}

report_list_menu() {
  local line=""
  local has_rows=0
  local created=""
  local configuration=""
  local first_name=""
  local last_name=""
  local email=""
  local status=""

  show_home_screen
  printf '%-19s %-36s %-14s %-14s %-30s %-15s\n' "Created" "Configuration" "Nome" "Cognome" "Email" "Status"
  printf '%-19s %-36s %-14s %-14s %-30s %-15s\n' "-------------------" "------------------------------------" "--------------" "--------------" "------------------------------" "---------------"

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    has_rows=1
    IFS='|' read -r created configuration first_name last_name email status <<<"$line"
    printf '%-19s %-36s %-14s %-14s %-30s %-15s\n' "$created" "${configuration:0:36}" "${first_name:0:14}" "${last_name:0:14}" "${email:0:30}" "$status"
  done < <(print_report_rows)

  if [[ "$has_rows" == "0" ]]; then
    printf '%sNessuna richiesta registrata.%s\n' "$YELLOW" "$RESET"
  fi

  printf '\n'
  pause_app
}

configuration_menu() {
  local choice=""

  while true; do
    show_home_screen
    load_profile_lines

    printf 'Configurazioni disponibili:\n'

    if (( ${#PROFILE_LINES[@]} == 0 )); then
      printf '%sNessuna configurazione salvata.%s\n' "$YELLOW" "$RESET"
    else
      for index in "${!PROFILE_LINES[@]}"; do
        parse_profile_line "${PROFILE_LINES[$index]}"
        printf '%d. %s\n' "$((index + 1))" "$PROFILE_DISPLAY"
      done
    fi

    printf '\nC. Create new\nE. Edit existing\nB. Back\n\n'
    read -r -p "Scelta: " choice

    case "${choice^^}" in
      C)
        show_home_screen
        edit_profile_interactive
        ;;
      E)
        if (( ${#PROFILE_LINES[@]} == 0 )); then
          printf '%sNessuna configurazione da modificare.%s\n\n' "$YELLOW" "$RESET"
          pause_app
        else
          show_home_screen
          select_profile_line "Quale configurazione vuoi modificare?"
          edit_profile_interactive "$SELECTED_PROFILE_LINE"
        fi
        ;;
      B)
        return
        ;;
    esac
  done
}

main_menu() {
  local choice=""

  ensure_application_state
  ensure_profile_configurations_exist

  while true; do
    show_home_screen
    printf '1. New Report\n2. Report List\n3. Configuration\n\nQ. Exit\n\n'
    read -r -p "Scelta: " choice

    case "${choice^^}" in
      1)
        new_report_menu
        ;;
      2)
        report_list_menu
        ;;
      3)
        configuration_menu
        ;;
      Q)
        exit 0
        ;;
    esac
  done
}

tui_count_trimmed_banner_lines() {
  local path="$1"
  local step="$2"
  local cols="$3"

  trimmed_banner_lines "$path" "$step" "$cols" | awk 'END { print NR + 0 }'
}

tui_render_banner_once() {
  if (( BANNER_RENDERED == 1 )); then
    return
  fi

  clear 2>/dev/null || true
  MENU_TOP_ROW=2
  BANNER_RENDERED=1
}

tui_clear_menu_area() {
  local start_row
  local total_lines

  tui_render_banner_once
  start_row=$((MENU_TOP_ROW - 1))

  if (( start_row < 1 )); then
    start_row=1
  fi

  total_lines=$(( $(get_terminal_rows) - start_row + 1 ))
  if (( total_lines < 1 )); then
    total_lines=1
  fi

  tui_clear_block_at "$start_row" "$total_lines"
}

tui_begin_draw() {
  tui_clear_menu_area
  printf '\033[%d;1H' "$MENU_TOP_ROW"
}

tui_begin_view() {
  tui_clear_menu_area
  printf '\033[%d;1H' "$MENU_TOP_ROW"
}

tui_move_cursor() {
  local row="$1"
  local col="${2:-1}"
  printf '\033[%d;%dH' "$row" "$col"
}

tui_render_centered_text_at() {
  local row="$1"
  local text="$2"
  local color="$3"
  local cols
  local col=1

  cols="$(get_terminal_cols)"

  if (( cols > ${#text} )); then
    col=$(( ((cols - ${#text}) / 2) + 1 ))
  fi

  tui_clear_line_at "$row"
  tui_move_cursor "$row" "$col"
  printf '%s%s%s' "$color" "$text" "$RESET"
}

tui_print_centered_line() {
  local text="$1"
  local color="${2:-$PRIMARY_FG}"
  local cols
  local pad=0

  cols="$(get_terminal_cols)"

  if (( cols > ${#text} )); then
    pad=$(( (cols - ${#text}) / 2 ))
  fi

  printf '%*s%s%s%s\n' "$pad" '' "$color" "$text" "$RESET"
}

tui_block_start_col() {
  local width="$1"
  local cols
  local start_col=1

  cols="$(get_terminal_cols)"

  if (( cols > width )); then
    start_col=$(( ((cols - width) / 2) + 1 ))
  fi

  printf '%s' "$start_col"
}

tui_clear_line_at() {
  local row="$1"
  tui_move_cursor "$row" 1
  printf '\033[2K'
}

tui_clear_block_at() {
  local start_row="$1"
  local line_count="$2"
  local offset=0

  if (( start_row < 1 )); then
    start_row=1
  fi

  if (( line_count < 1 )); then
    line_count=1
  fi

  for ((offset = 0; offset < line_count; offset++)); do
    tui_clear_line_at "$((start_row + offset))"
  done

  tui_move_cursor "$start_row" 1
}

tui_clear_region_between_rows() {
  local start_row="$1"
  local end_row="$2"
  local line_count=0

  if (( start_row < 1 )); then
    start_row=1
  fi

  if (( end_row < start_row )); then
    return
  fi

  line_count=$((end_row - start_row + 1))
  tui_clear_block_at "$start_row" "$line_count"
}

tui_repeat_char() {
  local count="$1"
  local char="${2--}"
  local idx=0

  if (( count <= 0 )); then
    return
  fi

  for ((idx = 0; idx < count; idx++)); do
    printf '%s' "$char"
  done
}

tui_fit_box_width() {
  local desired="$1"
  local minimum="${2:-24}"
  local cols
  local width

  cols="$(get_terminal_cols)"
  width="$desired"

  if (( width > cols - 4 )); then
    width=$((cols - 4))
  fi

  if (( width < minimum )); then
    width="$minimum"
  fi

  if (( width > cols )); then
    width="$cols"
  fi

  printf '%s' "$width"
}

tui_draw_box_at() {
  local row="$1"
  local col="$2"
  local width="$3"
  local height="$4"
  local color="${5:-$BORDER_FG}"
  local inner_width=0
  local inner_height=0
  local idx=0

  if (( width < 2 || height < 2 )); then
    return
  fi

  if (( row < 1 )); then
    row=1
  fi

  if (( col < 1 )); then
    col=1
  fi

  inner_width=$((width - 2))
  inner_height=$((height - 2))

  tui_move_cursor "$row" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_TL" "$(tui_repeat_char "$inner_width" "$BOX_H")" "$BOX_TR" "$RESET"

  for ((idx = 0; idx < inner_height; idx++)); do
    tui_move_cursor "$((row + 1 + idx))" "$col"
    printf '%s%s%s%*s%s%s%s' "$color" "$BOX_V" "$RESET" "$inner_width" '' "$color" "$BOX_V" "$RESET"
  done

  tui_move_cursor "$((row + height - 1))" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_BL" "$(tui_repeat_char "$inner_width" "$BOX_H")" "$BOX_BR" "$RESET"
}

tui_render_box_centered_text_at() {
  local row="$1"
  local col="$2"
  local width="$3"
  local text="$4"
  local text_color="${5:-$PRIMARY_FG}"
  local border_color="${6:-$BORDER_FG}"
  local inner_width=$((width - 2))
  local content=""

  content="$(tui_center_text "$text" "$inner_width")"
  tui_move_cursor "$row" "$col"
  printf '%s%s%s%s%s%s%s%s' "$border_color" "$BOX_V" "$RESET" "$text_color" "$content" "$RESET" "$border_color" "${BOX_V}${RESET}"
}

tui_render_header_box_at() {
  local top_row="$1"
  local title="$2"
  local hint="${3-}"
  local desired_width="${4:-74}"
  local width
  local col
  local height=3

  width="$(tui_fit_box_width "$desired_width" 28)"
  col="$(tui_block_start_col "$width")"

  if [[ -n "$hint" ]]; then
    height=4
  fi

  tui_clear_block_at "$top_row" 4
  tui_draw_box_at "$top_row" "$col" "$width" "$height" "$BORDER_FG"
  tui_render_box_centered_text_at "$((top_row + 1))" "$col" "$width" "$title" "${PRIMARY_FG}${BOLD}" "$BORDER_FG"

  if [[ -n "$hint" ]]; then
    tui_render_box_centered_text_at "$((top_row + 2))" "$col" "$width" "$hint" "$MUTED_FG" "$BORDER_FG"
  fi
}

tui_render_header_box() {
  local title="$1"
  local hint="${2-}"
  local desired_width="${3:-74}"
  local top_row=$((MENU_TOP_ROW - 1))

  tui_render_header_box_at "$top_row" "$title" "$hint" "$desired_width"
}

tui_render_profile_editor_box() {
  local title="$1"
  local geometry=""
  local width
  local col
  local top_row="$MENU_TOP_ROW"
  local height=11
  local clear_row=0
  local clear_height=0

  geometry="$(tui_profile_editor_geometry)"
  IFS='|' read -r top_row col width height _ <<<"$geometry"

  clear_row="$top_row"
  clear_height="$height"

  if (( top_row > 1 )); then
    clear_row=$((top_row - 1))
    clear_height=$((height + 1))
  fi

  tui_clear_block_at "$clear_row" "$clear_height"
  tui_draw_box_at "$top_row" "$col" "$width" "$height" "$BORDER_FG"
  tui_render_box_centered_text_at "$((top_row + 1))" "$col" "$width" "$title" "${PRIMARY_FG}${BOLD}" "$BORDER_FG"
}

tui_profile_editor_geometry() {
  local top_row=0
  local width
  local col
  local height=9
  local label_width=10
  local content_indent=2
  local value_width=0
  local notice_row=0

  top_row="$(tui_centered_group_top_row "$height" "$MENU_TOP_ROW")"
  width="$(tui_fit_box_width 76 58)"
  col="$(tui_block_start_col "$width")"
  value_width=$((width - 2 - content_indent - label_width - 1))
  notice_row=$((top_row + height - 2))

  printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "$top_row" \
    "$col" \
    "$width" \
    "$height" \
    "$label_width" \
    "$content_indent" \
    "$notice_row"
}

tui_render_profile_editor_field_at() {
  local row="$1"
  local col="$2"
  local width="$3"
  local label_width="$4"
  local content_indent="$5"
  local label="$6"
  local value="$7"
  local selected="$8"
  local inner_width=$((width - 2))
  local value_width=$((inner_width - content_indent - label_width - 1))
  local text_color="$PRIMARY_FG"
  local label_text="${label}:"
  local shown_value=""
  local content=""
  local padded_content=""

  if [[ "$selected" == "1" ]]; then
    text_color="${SELECT_FG}${BOLD}"
  fi

  shown_value="$(tui_truncate_text "$value" "$value_width")"
  printf -v content '%*s%-*s %s' "$content_indent" '' "$label_width" "$label_text" "$shown_value"
  printf -v padded_content '%-*s' "$inner_width" "$content"

  tui_move_cursor "$row" "$col"
  printf '%s%s%s%s%s%s%s%s' "$BORDER_FG" "$BOX_V" "$RESET" "$text_color" "$padded_content" "$RESET" "$BORDER_FG" "${BOX_V}${RESET}"
}

tui_render_profile_editor_notice_at() {
  local row="$1"
  local col="$2"
  local width="$3"
  local notice="${4-}"
  local color="${5:-$RED}"

  tui_render_box_centered_text_at "$row" "$col" "$width" "$notice" "$color" "$BORDER_FG"
}

tui_render_profile_editor_form() {
  local title="$1"
  local active_index="$2"
  local notice="${3-}"
  shift 3
  local field_values=("$@")
  local geometry=""
  local top_row=0
  local col=0
  local width=0
  local height=0
  local label_width=0
  local content_indent=0
  local notice_row=0
  local field_row=0
  local idx=0
  local -a field_labels=("Nome" "Cognome" "Email")

  geometry="$(tui_profile_editor_geometry)"
  IFS='|' read -r top_row col width height label_width content_indent notice_row <<<"$geometry"

  tui_render_profile_editor_box "$title"

  for idx in "${!field_labels[@]}"; do
    field_row=$((top_row + 3 + idx))
    tui_render_profile_editor_field_at \
      "$field_row" \
      "$col" \
      "$width" \
      "$label_width" \
      "$content_indent" \
      "${field_labels[$idx]}" \
      "${field_values[$idx]}" \
      "$([[ "$idx" == "$active_index" ]] && printf 1 || printf 0)"
  done

  tui_render_profile_editor_notice_at "$notice_row" "$col" "$width" "$notice"
}

tui_new_report_layout_geometry() {
  local show_profile_card="${1:-0}"
  local header_height=3
  local summary_height=0
  local input_height=5
  local group_height=0
  local group_top=0
  local header_top=0
  local summary_top=0
  local input_top=0

  if (( show_profile_card == 1 )); then
    summary_height=5
  fi

  group_height=$((header_height + 1 + input_height))
  if (( summary_height > 0 )); then
    group_height=$((group_height + summary_height + 1))
  fi

  group_top="$(tui_centered_group_top_row "$group_height" "$MENU_TOP_ROW")"
  header_top="$group_top"
  input_top=$((group_top + header_height + 1))

  if (( summary_height > 0 )); then
    summary_top="$input_top"
    input_top=$((summary_top + summary_height + 1))
  fi

  printf '%s|%s|%s\n' "$header_top" "$summary_top" "$input_top"
}

tui_new_report_input_geometry() {
  local show_profile_card="${1:-0}"
  local box_row=0
  local width
  local col
  local height=5
  local label_width=8
  local content_indent=2
  local notice_row=0
  local layout=""
  local header_row=0
  local summary_row=0

  layout="$(tui_new_report_layout_geometry "$show_profile_card")"
  IFS='|' read -r header_row summary_row box_row <<<"$layout"

  width="$(tui_fit_box_width 82 54)"
  col="$(tui_block_start_col "$width")"
  notice_row=$((box_row + 3))

  printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "$box_row" \
    "$col" \
    "$width" \
    "$height" \
    "$label_width" \
    "$content_indent" \
    "$notice_row"
}

tui_render_new_report_profile_summary() {
  local top_row="$1"
  local width
  local col
  local height=5
  local full_name="$PROFILE_FIRST_NAME $PROFILE_LAST_NAME"

  width="$(tui_fit_box_width 42 34)"
  col="$(tui_block_start_col "$width")"

  tui_clear_block_at "$top_row" "$height"
  tui_draw_box_at "$top_row" "$col" "$width" "$height" "$BORDER_FG"
  tui_render_box_centered_text_at "$((top_row + 1))" "$col" "$width" "Configurazione scelta" "${PRIMARY_FG}${BOLD}" "$BORDER_FG"
  tui_render_box_centered_text_at "$((top_row + 2))" "$col" "$width" "$full_name" "$PRIMARY_FG" "$BORDER_FG"
  tui_render_box_centered_text_at "$((top_row + 3))" "$col" "$width" "$PROFILE_EMAIL" "$PRIMARY_FG" "$BORDER_FG"
}

tui_render_new_report_input_static() {
  local input_title="$1"
  local field_label="$2"
  local helper_text="${3-}"
  local show_profile_card="${4:-0}"
  local geometry=""
  local box_row=0
  local col=0
  local width=0
  local height=0
  local label_width=0
  local content_indent=0
  local notice_row=0
  local layout=""
  local header_row=0
  local summary_row=0

  tui_begin_view
  layout="$(tui_new_report_layout_geometry "$show_profile_card")"
  IFS='|' read -r header_row summary_row _ <<<"$layout"
  tui_render_header_box_at "$header_row" "New Report" "" 84

  if (( show_profile_card == 1 )); then
    tui_render_new_report_profile_summary "$summary_row"
  fi

  geometry="$(tui_new_report_input_geometry "$show_profile_card")"
  IFS='|' read -r box_row col width height label_width content_indent notice_row <<<"$geometry"

  tui_clear_block_at "$box_row" "$height"
  tui_draw_box_at "$box_row" "$col" "$width" "$height" "$BORDER_FG"
  tui_render_box_centered_text_at "$((box_row + 1))" "$col" "$width" "$input_title" "${PRIMARY_FG}${BOLD}" "$BORDER_FG"
  tui_render_profile_editor_field_at "$((box_row + 2))" "$col" "$width" "$label_width" "$content_indent" "$field_label" "" 1
  tui_render_box_centered_text_at "$notice_row" "$col" "$width" "$helper_text" "$MUTED_FG" "$BORDER_FG"
}

tui_render_new_report_input_dynamic() {
  local field_label="$1"
  local value="$2"
  local helper_text="${3-}"
  local notice_text="${4-}"
  local show_profile_card="${5:-0}"
  local geometry=""
  local box_row=0
  local col=0
  local width=0
  local height=0
  local label_width=0
  local content_indent=0
  local notice_row=0

  geometry="$(tui_new_report_input_geometry "$show_profile_card")"
  IFS='|' read -r box_row col width height label_width content_indent notice_row <<<"$geometry"

  tui_render_profile_editor_field_at "$((box_row + 2))" "$col" "$width" "$label_width" "$content_indent" "$field_label" "$value" 1

  if [[ -n "$notice_text" ]]; then
    tui_render_box_centered_text_at "$notice_row" "$col" "$width" "$notice_text" "$RED" "$BORDER_FG"
  else
    tui_render_box_centered_text_at "$notice_row" "$col" "$width" "$helper_text" "$MUTED_FG" "$BORDER_FG"
  fi
}

tui_capture_boxed_input() {
  local input_title="$1"
  local field_label="$2"
  local default_value="${3-}"
  local allow_empty="${4:-0}"
  local helper_text="${5-}"
  local show_profile_card="${6:-0}"
  local buffer="$default_value"
  local notice=""
  local geometry=""
  local box_row=0
  local col=0
  local width=0
  local height=0
  local label_width=0
  local content_indent=0
  local notice_row=0
  local value_width=0
  local visible_value=""
  local input_col=0
  local current_row=0
  local resolved=""

  INPUT_RESULT=""
  HOME_REQUESTED=0

  tui_render_new_report_input_static "$input_title" "$field_label" "$helper_text" "$show_profile_card"
  printf '\033[?25h'

  while true; do
    tui_render_new_report_input_dynamic "$field_label" "$buffer" "$helper_text" "$notice" "$show_profile_card"
    notice=""

    geometry="$(tui_new_report_input_geometry "$show_profile_card")"
    IFS='|' read -r box_row col width height label_width content_indent notice_row <<<"$geometry"
    value_width=$((width - 2 - content_indent - label_width - 1))
    visible_value="$(tui_truncate_text "$buffer" "$value_width")"
    input_col=$((col + 1 + content_indent + label_width + 1))
    current_row=$((box_row + 2))
    tui_move_cursor "$current_row" "$((input_col + ${#visible_value}))"

    if ! tui_read_key; then
      printf '\033[?25l'
      return 1
    fi

    case "$LAST_KEY" in
      CTRL_HOME)
        HOME_REQUESTED=1
        printf '\033[?25l'
        return 130
        ;;
      BACKSPACE)
        if [[ -n "$buffer" ]]; then
          buffer="${buffer%?}"
        fi
        ;;
      ENTER)
        resolved="$(tui_trim_value "$buffer")"

        if [[ -z "$resolved" && "$allow_empty" != "1" ]]; then
          notice="Campo obbligatorio."
          continue
        fi

        INPUT_RESULT="$resolved"
        printf '\033[?25l'
        return 0
        ;;
      SPACE)
        buffer+=" "
        ;;
      *)
        if [[ "${#LAST_KEY}" == "1" && "$LAST_KEY" =~ [[:print:]] ]]; then
          buffer+="$LAST_KEY"
        fi
        ;;
    esac
  done
}

tui_progress_geometry() {
  local top_row
  local width
  local col
  local height=5

  top_row=$(( $(tui_centered_group_top_row 9 "$MENU_TOP_ROW") + 4 ))
  width="$(tui_fit_box_width 72 44)"
  col="$(tui_block_start_col "$width")"

  printf '%s|%s|%s|%s\n' "$top_row" "$col" "$width" "$height"
}

tui_render_progress_static() {
  local title="$1"
  local geometry=""
  local header_top=0
  local top_row=0
  local col=0
  local width=0
  local height=0
  local clear_row=0
  local clear_height=0

  geometry="$(tui_progress_geometry)"
  IFS='|' read -r top_row col width height <<<"$geometry"
  header_top=$((top_row - 4))

  tui_begin_view
  tui_render_header_box_at "$header_top" "$title" "" 84
  clear_row=$((MENU_TOP_ROW + 2))
  clear_height=$(( $(get_terminal_rows) - clear_row + 1 ))
  if (( clear_height < height )); then
    clear_height="$height"
  fi
  tui_clear_block_at "$clear_row" "$clear_height"
  tui_draw_box_at "$top_row" "$col" "$width" "$height" "$BORDER_FG"
  tui_render_box_centered_text_at "$((top_row + 1))" "$col" "$width" "Operazione in corso" "${PRIMARY_FG}${BOLD}" "$BORDER_FG"
}

tui_update_progress_bar() {
  local percent="$1"
  local status_text="${2-}"
  local geometry=""
  local top_row=0
  local col=0
  local width=0
  local height=0
  local inner_width=0
  local bar_width=0
  local filled=0
  local bar_row=0
  local text_row=0
  local bar_text=""
  local bar_core=""
  local empty_count=0

  geometry="$(tui_progress_geometry)"
  IFS='|' read -r top_row col width height <<<"$geometry"

  if (( percent < 0 )); then
    percent=0
  elif (( percent > 100 )); then
    percent=100
  fi

  inner_width=$((width - 2))
  bar_width=$((inner_width - 10))
  if (( bar_width < 10 )); then
    bar_width=10
  fi
  filled=$((percent * bar_width / 100))
  empty_count=$((bar_width - filled))
  bar_core="$(tui_repeat_char "$filled" "#")$(tui_repeat_char "$empty_count" ".")"
  bar_text="[$bar_core] ${percent}%"
  bar_row=$((top_row + 2))
  text_row=$((top_row + 3))

  tui_render_box_centered_text_at "$bar_row" "$col" "$width" "$bar_text" "${SELECT_FG}${BOLD}" "$BORDER_FG"
  tui_render_box_centered_text_at "$text_row" "$col" "$width" "$status_text" "$MUTED_FG" "$BORDER_FG"
}

tui_assist_progress_percent() {
  local tick="$1"
  local progress=8

  if [[ -f "$ASSIST_LOG_PATH" ]]; then
    if grep -q "Compilo la parte legale del form." "$ASSIST_LOG_PATH" 2>/dev/null; then
      progress=24
    fi
    if grep -q "Compilo i dati del segnalante." "$ASSIST_LOG_PATH" 2>/dev/null; then
      progress=42
    fi
    if grep -q "Compilo i link del profilo e dei post." "$ASSIST_LOG_PATH" 2>/dev/null; then
      progress=62
    fi
    if grep -q "Compilo ordinanza, consenso e firma." "$ASSIST_LOG_PATH" 2>/dev/null; then
      progress=82
    fi
    if grep -q "Submit finale confermato" "$ASSIST_LOG_PATH" 2>/dev/null; then
      progress=96
    fi
  fi

  if (( tick > 0 )); then
    local time_progress=$((8 + tick))
    if (( time_progress > progress )); then
      progress="$time_progress"
    fi
  fi

  if (( progress > 94 )); then
    progress=94
  fi

  printf '%s' "$progress"
}

tui_run_assist_with_progress() {
  local first_name="$1"
  local last_name="$2"
  local email="$3"
  local signature="$4"
  local profile_url="$5"
  local pid=0
  local tick=0
  local percent=0
  local exit_code=0

  mkdir -p "$OUT_DIR"
  : >"$ASSIST_LOG_PATH"

  tui_render_progress_static "Invio richiesta"
  tui_update_progress_bar 4 "Avvio assist"

  set +e
  run_assist "$first_name" "$last_name" "$email" "$signature" "$profile_url" >"$ASSIST_LOG_PATH" 2>&1 &
  pid=$!
  set -e

  while kill -0 "$pid" 2>/dev/null; do
    percent="$(tui_assist_progress_percent "$tick")"
    tui_update_progress_bar "$percent" "Elaborazione in corso"
    sleep 0.15
    tick=$((tick + 1))
  done

  set +e
  wait "$pid"
  exit_code=$?
  set -e

  if (( exit_code == 0 )); then
    tui_update_progress_bar 100 "Completato"
  else
    tui_update_progress_bar 100 "Terminato con errori"
  fi

  sleep 0.2
  return "$exit_code"
}

tui_wrap_file_lines() {
  local path="$1"
  local width="$2"

  if [[ "$path" == "-" || "$path" == "/dev/stdin" ]]; then
    if command -v fold >/dev/null 2>&1; then
      fold -w "$width"
    else
      cat
    fi
    return 0
  fi

  if [[ ! -f "$path" ]]; then
    return 0
  fi

  if command -v fold >/dev/null 2>&1; then
    fold -w "$width" "$path"
  else
    cat "$path"
  fi
}

tui_render_box_text_at() {
  local row="$1"
  local col="$2"
  local width="$3"
  local text="$4"
  local text_color="${5:-$PRIMARY_FG}"
  local inner_width=$((width - 2))
  local shown_text=""
  local padded_text=""

  shown_text="$(tui_truncate_text "$text" "$inner_width")"
  printf -v padded_text '%-*s' "$inner_width" "$shown_text"
  tui_move_cursor "$row" "$col"
  printf '%s%s%s%s%s%s%s%s' "$BORDER_FG" "$BOX_V" "$RESET" "$text_color" "$padded_text" "$RESET" "$BORDER_FG" "${BOX_V}${RESET}"
}

tui_show_report_summary_box() {
  local status_text="$1"
  local status_color="$2"
  local configuration_name="$3"
  local profile_url="$4"
  local post_count="$5"
  local report_target=""
  local show_ascii=1
  local offset=0
  local rows=0
  local cols=0
  local report_width=54
  local report_height=19
  local art_width=46
  local art_height=24
  local gap=5
  local group_width=0
  local group_height=0
  local group_top=0
  local start_col=1
  local report_top=0
  local report_col=0
  local art_top=0
  local art_col=0
  local text_area_height=0
  local content_start_row=0
  local hint_row=0
  local wrap_width=0
  local idx=0
  local absolute_index=0
  local content_line=""
  local total_lines=0
  local max_offset=0
  local -a content_lines=()

  while true; do
    tui_begin_view
    rows="$(get_terminal_rows)"
    cols="$(get_terminal_cols)"
    report_target="$(tui_report_target_from_profile_url "$profile_url")"
    show_ascii=1
    report_width=54
    art_width=46
    gap=5

    if (( cols < 116 )); then
      report_width=50
      art_width=38
      gap=4
    fi

    report_width="$(tui_fit_box_width "$report_width" 42)"

    if (( cols < 100 || rows < 28 )); then
      show_ascii=0
    fi

    if (( show_ascii == 1 )) && (( cols < report_width + art_width + gap + 4 )); then
      gap=2
      art_width=$((cols - report_width - gap - 4))
    fi

    if (( show_ascii == 1 )) && (( art_width < 24 )); then
      show_ascii=0
    fi

    report_height=$((rows - 12))
    if (( report_height < 17 )); then
      report_height=17
    elif (( report_height > 22 )); then
      report_height=22
    fi

    if (( show_ascii == 1 )); then
      art_height=$((report_height + 6))
      if (( art_height > rows - 6 )); then
        art_height=$((rows - 6))
      fi
      if (( art_height < report_height )); then
        art_height="$report_height"
      fi

      group_width=$((report_width + gap + art_width))
      group_height="$art_height"
    else
      art_width=0
      art_height=0
      gap=0
      group_width="$report_width"
      group_height="$report_height"
    fi

    if (( cols > group_width )); then
      start_col=$(( ((cols - group_width) / 2) + 1 ))
    else
      start_col=1
    fi

    group_top="$(tui_centered_group_top_row "$group_height" "$MENU_TOP_ROW")"
    report_top=$((group_top + ((group_height - report_height) / 2)))
    report_col="$start_col"
    art_top="$group_top"
    art_col=$((start_col + report_width + gap))
    text_area_height=$((report_height - 4))
    if (( text_area_height < 4 )); then
      text_area_height=4
    fi
    content_start_row=$((report_top + 3))
    hint_row="$(tui_bottom_hint_row)"
    wrap_width=$((report_width - 4))
    content_lines=()

    while IFS= read -r content_line; do
      content_lines+=("$content_line")
    done < <(
      {
        printf 'Mittente: %s\n' "$configuration_name"
        printf 'Target: %s\n' "$report_target"
        printf 'Profilo: %s\n' "$profile_url"
        printf 'Post allegati: %s\n' "$post_count"
        printf 'Output: %s\n' "${TEXT_PATH##*/}"
        if [[ -f "$SCREENSHOT_PATH" ]]; then
          printf 'Screenshot: %s\n' "${SCREENSHOT_PATH##*/}"
        fi
        if [[ -f "$ASSIST_LOG_PATH" ]] && [[ "$status_text" == Errore* ]]; then
          printf 'Log: %s\n' "${ASSIST_LOG_PATH##*/}"
        fi
        printf '\n'
        printf 'Testo richiesta\n'
        printf '\n'
        if [[ -f "$TEXT_PATH" ]]; then
          cat "$TEXT_PATH"
        else
          printf 'Nessun testo report disponibile.\n'
        fi
      } | tui_wrap_file_lines /dev/stdin "$wrap_width"
    )

    if (( ${#content_lines[@]} == 0 )); then
      content_lines=("Nessun riepilogo disponibile.")
    fi

    tui_draw_box_at "$report_top" "$report_col" "$report_width" "$report_height" "$BORDER_FG"
    tui_render_box_centered_text_at "$((report_top + 1))" "$report_col" "$report_width" "Report" "${PRIMARY_FG}${BOLD}" "$BORDER_FG"
    tui_render_box_centered_text_at "$((report_top + 2))" "$report_col" "$report_width" "$status_text" "$status_color" "$BORDER_FG"
    if (( show_ascii == 1 )); then
      tui_render_banner_file_in_area_at "$SUMMARY_ASCII_PATH" "$art_top" "$art_col" "$art_width" "$art_height" "${PRIMARY_FG}${BOLD}"
    fi

    total_lines="${#content_lines[@]}"
    max_offset=$((total_lines - text_area_height))
    if (( max_offset < 0 )); then
      max_offset=0
    fi
    if (( offset > max_offset )); then
      offset="$max_offset"
    fi

    for ((idx = 0; idx < text_area_height; idx++)); do
      absolute_index=$((offset + idx))
      if (( absolute_index < total_lines )); then
        tui_render_box_text_at "$((content_start_row + idx))" "$report_col" "$report_width" "${content_lines[$absolute_index]}" "$PRIMARY_FG"
      else
        tui_render_box_text_at "$((content_start_row + idx))" "$report_col" "$report_width" "" "$PRIMARY_FG"
      fi
    done

    tui_clear_line_at "$hint_row"
    tui_render_hint_line_at "$hint_row" "INVIO torna al menu  UP/DOWN scorri testo  CTRL+H home"

    if ! tui_read_key; then
      return 0
    fi

    case "$LAST_KEY" in
      CTRL_HOME)
        HOME_REQUESTED=1
        return 130
        ;;
      ENTER)
        return 0
        ;;
      UP)
        if (( offset > 0 )); then
          offset=$((offset - 1))
        fi
        ;;
      DOWN)
        if (( offset < max_offset )); then
          offset=$((offset + 1))
        fi
        ;;
    esac
  done
}

tui_render_box_menu_item_at() {
  local row="$1"
  local col="$2"
  local width="$3"
  local label="$4"
  local selected="$5"
  local color="$PRIMARY_FG"
  local inner_width=$((width - 2))
  local visible_label=""
  local content=""
  local label_col=0
  local prefix_col=0
  local prefix="> "

  if [[ "$selected" == "1" ]]; then
    color="${SELECT_FG}${BOLD}"
  fi

  visible_label="$(tui_truncate_text "$label" "$((inner_width - 2))")"
  printf -v content '%*s' "$inner_width" ''
  label_col=$(( (inner_width - ${#visible_label}) / 2 ))
  content="${content:0:label_col}${visible_label}${content:$((label_col + ${#visible_label}))}"

  if [[ "$selected" == "1" ]]; then
    prefix_col=$((label_col - ${#prefix}))
    if (( prefix_col < 0 )); then
      prefix_col=0
    fi
    content="${content:0:prefix_col}${prefix}${content:$((prefix_col + ${#prefix}))}"
  fi

  tui_move_cursor "$row" "$col"
  printf '%s%s%s%s%s%s%s%s' "$BORDER_FG" "$BOX_V" "$RESET" "$color" "$content" "$RESET" "$BORDER_FG" "${BOX_V}${RESET}"
}

tui_render_box_menu_item_left_at() {
  local row="$1"
  local col="$2"
  local width="$3"
  local label="$4"
  local selected="$5"
  local color="$PRIMARY_FG"
  local inner_width=$((width - 2))
  local visible_label=""
  local display=""
  local content=""

  visible_label="$(tui_truncate_text "$label" "$((inner_width - 4))")"

  if [[ "$selected" == "1" ]]; then
    color="${SELECT_FG}${BOLD}"
    display="> ${visible_label}"
  else
    display="  ${visible_label}"
  fi

  printf -v content '%-*s' "$inner_width" "$display"
  tui_move_cursor "$row" "$col"
  printf '%s%s%s%s%s%s%s%s' "$BORDER_FG" "$BOX_V" "$RESET" "$color" "$content" "$RESET" "$BORDER_FG" "${BOX_V}${RESET}"
}

tui_trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

tui_truncate_text() {
  local text="$1"
  local width="$2"

  if (( width <= 0 )); then
    printf ''
    return
  fi

  if (( ${#text} <= width )); then
    printf '%s' "$text"
    return
  fi

  if (( width == 1 )); then
    printf '%s' "${text:0:1}"
    return
  fi

  printf '%s' "${text:0:$((width - 1))}~"
}

tui_report_target_from_profile_url() {
  local raw_url="$1"
  local cleaned="$1"

  cleaned="${cleaned%%\?*}"
  cleaned="${cleaned%%#*}"
  cleaned="${cleaned#https://}"
  cleaned="${cleaned#http://}"
  cleaned="${cleaned#www.}"
  cleaned="${cleaned#instagram.com/}"
  cleaned="${cleaned#/}"
  cleaned="${cleaned%%/*}"

  if [[ -n "$cleaned" && "$cleaned" != "$raw_url" ]]; then
    printf '@%s' "$cleaned"
    return
  fi

  printf '%s' "$raw_url"
}

tui_center_text() {
  local text="$1"
  local width="$2"
  local trimmed=""
  local left_pad=0
  local right_pad=0

  trimmed="$(tui_truncate_text "$text" "$width")"

  if (( ${#trimmed} >= width )); then
    printf '%s' "$trimmed"
    return
  fi

  left_pad=$(( (width - ${#trimmed}) / 2 ))
  right_pad=$(( width - ${#trimmed} - left_pad ))
  printf '%*s%s%*s' "$left_pad" '' "$trimmed" "$right_pad" ''
}

tui_capture_status() {
  set +e
  "$@"
  CAPTURED_STATUS=$?
  set -e
  return 0
}

tui_read_key() {
  local first=""
  local second=""
  local third=""

  LAST_KEY=""

  if ! IFS= read -rsn1 first; then
    LAST_KEY="EOF"
    return 1
  fi

  if [[ "$first" == $'\x08' ]]; then
    LAST_KEY="CTRL_HOME"
    return 0
  fi

  if [[ -z "$first" || "$first" == $'\n' || "$first" == $'\r' ]]; then
    LAST_KEY="ENTER"
    return 0
  fi

  if [[ "$first" == $'\x1b' ]]; then
    IFS= read -rsn1 -t 0.02 second || true

    if [[ "$second" == "[" ]]; then
      IFS= read -rsn1 -t 0.02 third || true

      case "$third" in
        A) LAST_KEY="UP" ;;
        B) LAST_KEY="DOWN" ;;
        C) LAST_KEY="RIGHT" ;;
        D) LAST_KEY="LEFT" ;;
        *) LAST_KEY="ESC" ;;
      esac
    else
      LAST_KEY="ESC"
    fi

    return 0
  fi

  case "$first" in
    $'\x7f'|$'\b')
      LAST_KEY="BACKSPACE"
      ;;
    ' ')
      LAST_KEY="SPACE"
      ;;
    *)
      LAST_KEY="$first"
      ;;
  esac
}

tui_show_intro_splash() {
  local rows
  local cols
  local art_width=0
  local art_height=0
  local start_row=1
  local start_col=1
  local prompt_row=1
  local prompt_text="---> Premi Invio <---"
  local prompt_color=""
  local blink_state=0
  local key=""
  local junk=""
  local index=0
  local line=""
  local -a intro_lines=()

  if [[ ! -f "$ASCII_BANNER_PATH" ]]; then
    return 0
  fi

  mapfile -t intro_lines < <(banner_file_full_lines "$ASCII_BANNER_PATH")

  if (( ${#intro_lines[@]} == 0 )); then
    return 0
  fi

  for line in "${intro_lines[@]}"; do
    if (( ${#line} > art_width )); then
      art_width=${#line}
    fi
  done

  art_height="${#intro_lines[@]}"
  rows="$(get_terminal_rows)"
  cols="$(get_terminal_cols)"

  if (( rows > (art_height + 1) )); then
    start_row=$(( ((rows - (art_height + 1)) / 2) + 1 ))
  fi

  if (( cols > art_width )); then
    start_col=$(( ((cols - art_width) / 2) + 1 ))
  fi

  clear 2>/dev/null || printf '\033[2J\033[H'

  for ((index = 0; index < art_height; index++)); do
    tui_move_cursor "$((start_row + index))" "$start_col"
    printf '%s%s%s' "${PRIMARY_FG}${BOLD}" "${intro_lines[$index]}" "$RESET"
  done

  prompt_row=$((start_row + art_height))

  while true; do
    if (( blink_state == 0 )); then
      prompt_color="${YELLOW}${BOLD}"
    else
      prompt_color="${PRIMARY_FG}${BOLD}"
    fi

    tui_render_centered_text_at "$prompt_row" "$prompt_text" "$prompt_color"

    if IFS= read -rsn1 -t 0.55 key; then
      if [[ -z "$key" || "$key" == $'\n' || "$key" == $'\r' ]]; then
        clear 2>/dev/null || printf '\033[2J\033[H'
        return 0
      fi

      if [[ "$key" == $'\x1b' ]]; then
        IFS= read -rsn2 -t 0.02 junk || true
      fi
    else
      blink_state=$((1 - blink_state))
    fi
  done
}

tui_capture_line_input() {
  local prompt="$1"
  local default_value="${2-}"
  local allow_empty="${3:-0}"
  local buffer=""
  local char=""
  local junk=""
  local resolved=""
  local prompt_text=""
  local prompt_pad=0
  local cols=0

  INPUT_RESULT=""

  if [[ -n "$default_value" ]]; then
    prompt_text="$prompt [$default_value]: "
  else
    prompt_text="$prompt: "
  fi

  cols="$(get_terminal_cols)"
  if (( cols > ${#prompt_text} )); then
    prompt_pad=$(( (cols - ${#prompt_text}) / 2 ))
  fi

  printf '%*s%s%s%s' "$prompt_pad" '' "${PRIMARY_FG}${BOLD}" "$prompt_text" "$RESET"

  while true; do
    if ! IFS= read -rsn1 char; then
      return 1
    fi

    case "$char" in
      $'\x08')
        HOME_REQUESTED=1
        printf '\n'
        return 130
        ;;
      '')
        resolved="$buffer"

        if [[ -z "$resolved" && -n "$default_value" ]]; then
          resolved="$default_value"
        fi

        resolved="$(tui_trim_value "$resolved")"

        if [[ -z "$resolved" && "$allow_empty" != "1" ]]; then
          printf '\n'
          tui_print_centered_line "Campo obbligatorio." "$RED"

          if [[ -n "$default_value" ]]; then
            prompt_text="$prompt [$default_value]: "
          else
            prompt_text="$prompt: "
          fi

          prompt_pad=0
          if (( cols > ${#prompt_text} )); then
            prompt_pad=$(( (cols - ${#prompt_text}) / 2 ))
          fi

          printf '%*s%s%s%s' "$prompt_pad" '' "${PRIMARY_FG}${BOLD}" "$prompt_text" "$RESET"
          buffer=""
          continue
        fi

        INPUT_RESULT="$resolved"
        printf '\n'
        return 0
        ;;
      $'\n'|$'\r')
        continue
        ;;
      $'\x7f')
        if [[ -n "$buffer" ]]; then
          buffer="${buffer%?}"
          printf '\b \b'
        fi
        ;;
      $'\x1b')
        IFS= read -rsn2 -t 0.02 junk || true
        ;;
      *)
        if [[ "$char" =~ [[:print:]] ]]; then
          buffer+="$char"
          printf '%s' "$char"
        fi
        ;;
    esac
  done
}

tui_read_required() {
  tui_capture_line_input "$1" "${2-}" 0
}

tui_read_optional_line() {
  tui_capture_line_input "$1" "${2-}" 1
}

tui_wait_for_enter_or_home() {
  local prompt="${1:-Premi INVIO per continuare}"

  printf '\n'
  tui_print_centered_line "$prompt" "$MUTED_FG"

  while tui_read_key; do
    case "$LAST_KEY" in
      ENTER)
        return 0
        ;;
      CTRL_HOME)
        HOME_REQUESTED=1
        return 130
        ;;
    esac
  done

  return 1
}

tui_render_menu_item() {
  local label="$1"
  local selected="$2"
  local prefix="  "
  local color="$PRIMARY_FG"
  local text=""
  local cols=0
  local pad=0

  if [[ "$selected" == "1" ]]; then
    prefix="> "
    color="${SELECT_FG}${BOLD}"
  fi

  text="${prefix}${label}"
  cols="$(get_terminal_cols)"

  if (( cols > ${#text} )); then
    pad=$(( (cols - ${#text}) / 2 ))
  fi

  printf '%*s%s%s%s\n' "$pad" '' "$color" "$text" "$RESET"
}

tui_render_menu_item_at() {
  local row="$1"
  local label="$2"
  local selected="$3"
  local prefix="  "
  local color="$PRIMARY_FG"

  if [[ "$selected" == "1" ]]; then
    prefix="> "
    color="${SELECT_FG}${BOLD}"
  fi

  tui_render_centered_text_at "$row" "${prefix}${label}" "$color"
}

tui_parse_profile_line() {
  local line="$1"
  IFS='|' read -r PROFILE_ID PROFILE_DISPLAY PROFILE_FIRST_NAME PROFILE_LAST_NAME PROFILE_EMAIL PROFILE_SIGNATURE PROFILE_ACTIVE <<<"$line"
}

tui_load_profile_lines() {
  mapfile -t PROFILE_LINES < <("$NODE_BIN" - "$NODE_PROFILE_CONFIGS_PATH" <<'NODE'
const fs = require('fs');

const [profilesPath] = process.argv.slice(2);
const raw = fs.existsSync(profilesPath) ? fs.readFileSync(profilesPath, 'utf8').trim() : '[]';
const records = raw ? JSON.parse(raw) : [];

const valid = (Array.isArray(records) ? records : [])
  .filter((record) => record && record.firstName && record.lastName && record.email)
  .map((record) => ({
    id: String(record.id || ''),
    firstName: String(record.firstName).trim(),
    lastName: String(record.lastName).trim(),
    email: String(record.email).trim(),
    signature: String(record.signature || `${String(record.firstName || '').trim()} ${String(record.lastName || '').trim()}`).trim(),
    active: Boolean(record.active)
  }))
  .sort((a, b) => {
    if (a.active !== b.active) {
      return Number(b.active) - Number(a.active);
    }

    return `${a.firstName} ${a.lastName} ${a.email}`.localeCompare(`${b.firstName} ${b.lastName} ${b.email}`);
  });

for (const record of valid) {
  const display = `${record.firstName} ${record.lastName} <${record.email}>`;
  console.log([
    record.id,
    display,
    record.firstName,
    record.lastName,
    record.email,
    record.signature,
    record.active ? 'yes' : 'no'
  ].join('|'));
}
NODE
)
}

tui_get_active_profile_line() {
  tui_load_profile_lines
  SELECTED_PROFILE_LINE=""

  for line in "${PROFILE_LINES[@]}"; do
    tui_parse_profile_line "$line"

    if [[ "$PROFILE_ACTIVE" == "yes" ]]; then
      SELECTED_PROFILE_LINE="$line"
      return 0
    fi
  done

  return 1
}

tui_upsert_profile_record() {
  local existing_id="$1"
  local first_name="$2"
  local last_name="$3"
  local email="$4"
  local signature="$5"

  "$NODE_BIN" - "$NODE_PROFILE_CONFIGS_PATH" "$existing_id" "$first_name" "$last_name" "$email" "$signature" <<'NODE'
const fs = require('fs');
const { randomUUID } = require('crypto');

const [profilesPath, existingIdArg, firstNameArg, lastNameArg, emailArg, signatureArg] = process.argv.slice(2);
const existingId = String(existingIdArg || '').trim();
const firstName = String(firstNameArg || '').trim();
const lastName = String(lastNameArg || '').trim();
const email = String(emailArg || '').trim();
const signature = String(signatureArg || `${firstName} ${lastName}`).trim();

if (!firstName || !lastName || !email) {
  throw new Error('La configurazione richiede Nome, Cognome ed Email.');
}

const raw = fs.existsSync(profilesPath) ? fs.readFileSync(profilesPath, 'utf8').trim() : '[]';
const records = raw ? JSON.parse(raw) : [];
const normalizedEmail = email.toLowerCase();

let index = -1;

if (existingId) {
  index = records.findIndex((record) => String(record.id || '') === existingId);
} else {
  index = records.findIndex((record) => String(record.email || '').trim().toLowerCase() === normalizedEmail);
}

const nextRecord = {
  id: index >= 0 ? String(records[index].id || '') : randomUUID(),
  firstName,
  lastName,
  email,
  signature,
  active: index >= 0 ? Boolean(records[index].active) : records.length === 0
};

if (index >= 0) {
  records[index] = nextRecord;
} else {
  records.push(nextRecord);
}

fs.writeFileSync(profilesPath, JSON.stringify(records, null, 2));
NODE
}

tui_set_profile_active_state() {
  local target_id="$1"
  local active_value="$2"

  "$NODE_BIN" - "$NODE_PROFILE_CONFIGS_PATH" "$target_id" "$active_value" <<'NODE'
const fs = require('fs');

const [profilesPath, targetId, activeValue] = process.argv.slice(2);
const raw = fs.existsSync(profilesPath) ? fs.readFileSync(profilesPath, 'utf8').trim() : '[]';
const records = raw ? JSON.parse(raw) : [];
const activate = String(activeValue || '').trim() === 'yes';

for (const record of records) {
  if (String(record.id || '') === String(targetId || '')) {
    record.active = activate;
  } else if (activate) {
    record.active = false;
  } else if (typeof record.active !== 'boolean') {
    record.active = false;
  }
}

fs.writeFileSync(profilesPath, JSON.stringify(records, null, 2));
NODE
}

tui_delete_profile_record() {
  local target_id="$1"

  "$NODE_BIN" - "$NODE_PROFILE_CONFIGS_PATH" "$target_id" <<'NODE'
const fs = require('fs');

const [profilesPath, targetId] = process.argv.slice(2);
const raw = fs.existsSync(profilesPath) ? fs.readFileSync(profilesPath, 'utf8').trim() : '[]';
const records = raw ? JSON.parse(raw) : [];
const nextRecords = records.filter((record) => String(record.id || '') !== String(targetId || ''));
fs.writeFileSync(profilesPath, JSON.stringify(nextRecords, null, 2));
NODE
}

tui_parse_report_line() {
  local line="$1"
  IFS='|' read -r REPORT_ID REPORT_TARGET REPORT_STATUS REPORT_CREATED_AT REPORT_CONFIGURATION REPORT_PROFILE_URL <<<"$line"
}

tui_set_report_line_status_local() {
  local report_index="$1"
  local next_status="$2"

  if (( report_index < 0 || report_index >= ${#REPORT_LINES[@]} )); then
    return
  fi

  tui_parse_report_line "${REPORT_LINES[$report_index]}"
  REPORT_LINES[$report_index]="${REPORT_ID}|${REPORT_TARGET}|${next_status}|${REPORT_CREATED_AT}|${REPORT_CONFIGURATION}|${REPORT_PROFILE_URL}"
}

tui_load_report_lines() {
  mapfile -t REPORT_LINES < <("$NODE_BIN" - "$NODE_REPORTS_PATH" <<'NODE'
const fs = require('fs');

const [reportsPath] = process.argv.slice(2);
const raw = fs.existsSync(reportsPath) ? fs.readFileSync(reportsPath, 'utf8').trim() : '[]';
const reports = raw ? JSON.parse(raw) : [];

reports
  .filter((report) => !report.hidden)
  .sort((a, b) => String(b.createdAtLocal || '').localeCompare(String(a.createdAtLocal || '')))
  .forEach((report) => {
    const profileUrl = String(report.profileUrl || '').trim();
    let target = String(report.reportedUsername || '').trim();

    if (!target && profileUrl) {
      try {
        const parsed = new URL(profileUrl);
        const parts = parsed.pathname.split('/').filter(Boolean);
        target = parts[0] ? `@${parts[0]}` : profileUrl;
      } catch {
        target = profileUrl;
      }
    }

    if (!target) {
      target = '(senza target)';
    }

    let accountStatus = String(report.accountStatus || '').trim();

    if (!accountStatus) {
      accountStatus = 'Pending';
    }

    console.log([
      String(report.id || ''),
      target,
      accountStatus,
      String(report.createdAtLocal || ''),
      String(report.configurationName || ''),
      profileUrl
    ].join('|'));
  });
NODE
)
}

tui_set_report_account_status() {
  local target_id="$1"
  local account_status="$2"

  "$NODE_BIN" - "$NODE_REPORTS_PATH" "$target_id" "$account_status" <<'NODE'
const fs = require('fs');

const [reportsPath, targetId, accountStatusArg] = process.argv.slice(2);
const raw = fs.existsSync(reportsPath) ? fs.readFileSync(reportsPath, 'utf8').trim() : '[]';
const reports = raw ? JSON.parse(raw) : [];
const normalizedStatus = String(accountStatusArg || '').trim().toLowerCase() === 'banned' ? 'Banned' : 'Pending';
const pad = (value) => String(value).padStart(2, '0');
const now = new Date();
const checkedAtLocal = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;

for (const report of reports) {
  if (String(report.id || '') !== String(targetId || '')) {
    continue;
  }

  report.accountStatus = normalizedStatus;
  report.accountStatusCheckedAtLocal = checkedAtLocal;

  if (!report.reportedUsername) {
    const rawUrl = String(report.profileUrl || '').trim();

    if (rawUrl) {
      try {
        const parsed = new URL(rawUrl);
        const parts = parsed.pathname.split('/').filter(Boolean);
        report.reportedUsername = parts[0] ? `@${parts[0]}` : rawUrl;
      } catch {
        report.reportedUsername = rawUrl;
      }
    }
  }
}

fs.writeFileSync(reportsPath, JSON.stringify(reports, null, 2));
NODE
}

run_profile_status_check() {
  local profile_url="$1"
  local output=""
  local exit_code=0
  local status="Pending"

  if [[ -z "$profile_url" ]]; then
    printf 'Pending\n'
    return 0
  fi

  set +e
  output="$("$NODE_BIN" "$NODE_CHECK_PROFILE_SCRIPT" --profile-url "$profile_url" 2>/dev/null)"
  exit_code=$?
  set -e

  if (( exit_code != 0 )); then
    return "$exit_code"
  fi

  output="${output//$'\r'/}"
  status="$(printf '%s\n' "$output" | tail -n 1 | tr -d '\n' | tr -d '\r')"

  case "${status,,}" in
    banned)
      printf 'Banned\n'
      ;;
    *)
      printf 'Pending\n'
      ;;
  esac
}

tui_refresh_report_statuses() {
  local mode="${1:-all}"
  local target_id="${2-}"
  local target_label="${3-}"
  local target_url="${4-}"
  local selected_index="${5:-0}"
  local focus_mode="${6:-cards}"
  local action_index="${7:-0}"
  local total=0
  local idx=0
  local processed=0
  local failures=0
  local line=""
  local label=""
  local profile_url=""
  local report_id=""
  local report_index=0
  local status=""
  local -a refresh_lines=()

  if [[ ! -d "$ROOT_DIR/node_modules/playwright-core" ]]; then
    return 2
  fi

  if [[ ! -f "$CHECK_PROFILE_SCRIPT" ]]; then
    return 2
  fi

  if [[ "$mode" == "single" ]]; then
    if [[ -z "$target_id" || -z "$target_url" ]]; then
      return 1
    fi

    tui_load_report_lines

    for idx in "${!REPORT_LINES[@]}"; do
      tui_parse_report_line "${REPORT_LINES[$idx]}"

      if [[ "$REPORT_ID" == "$target_id" ]]; then
        refresh_lines+=("${idx}|${target_id}|${target_label}|${target_url}")
        break
      fi
    done
  else
    tui_load_report_lines

    for idx in "${!REPORT_LINES[@]}"; do
      line="${REPORT_LINES[$idx]}"
      tui_parse_report_line "$line"
      refresh_lines+=("${idx}|${REPORT_ID}|${REPORT_TARGET}|${REPORT_PROFILE_URL}")
    done
  fi

  total="${#refresh_lines[@]}"

  if (( total == 0 )); then
    return 0
  fi

  tui_render_report_list_view "$selected_index" "$focus_mode" "$action_index" ""

  for idx in "${!refresh_lines[@]}"; do
    IFS='|' read -r report_index report_id label profile_url <<<"${refresh_lines[$idx]}"

    tui_set_report_line_status_local "$report_index" "Loading"
    tui_render_report_card_region "$selected_index"
    tui_render_report_action_region "$selected_index" "${#REPORT_LINES[@]}" "$focus_mode" "$action_index"
    tui_render_report_footer_region "$selected_index" "${#REPORT_LINES[@]}" "$focus_mode" ""

    status="Pending"
    if status="$(run_profile_status_check "$profile_url")"; then
      :
    else
      status="Pending"
      failures=$((failures + 1))
    fi

    tui_set_report_account_status "$report_id" "$status"
    tui_set_report_line_status_local "$report_index" "$status"

    processed=$((processed + 1))
    tui_render_report_card_region "$selected_index"
    tui_render_report_action_region "$selected_index" "${#REPORT_LINES[@]}" "$focus_mode" "$action_index"
    tui_render_report_footer_region "$selected_index" "${#REPORT_LINES[@]}" "$focus_mode" ""
  done

  if (( failures > 0 )); then
    return 2
  fi

  return 0
}

tui_hide_report_record() {
  local target_id="$1"

  "$NODE_BIN" - "$NODE_REPORTS_PATH" "$target_id" <<'NODE'
const fs = require('fs');

const [reportsPath, targetId] = process.argv.slice(2);
const raw = fs.existsSync(reportsPath) ? fs.readFileSync(reportsPath, 'utf8').trim() : '[]';
const reports = raw ? JSON.parse(raw) : [];

for (const report of reports) {
  if (String(report.id || '') === String(targetId || '')) {
    report.hidden = true;
  }
}

fs.writeFileSync(reportsPath, JSON.stringify(reports, null, 2));
NODE
}

tui_render_profile_card() {
  local selected="$1"
  local first_name="$2"
  local last_name="$3"
  local email="$4"
  local active_value="$5"
  local color="$PRIMARY_FG"
  local width=38
  local active_label="No"

  if [[ "$selected" == "1" ]]; then
    color="${SELECT_FG}${BOLD}"
  fi

  if [[ "$active_value" == "yes" ]]; then
    active_label="Si"
  fi

  tui_print_centered_line "${BOX_TL}$(tui_repeat_char "$width" "$BOX_H")${BOX_TR}" "$color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "$first_name" "$width")${BOX_V}" "$color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "$last_name" "$width")${BOX_V}" "$color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "$email" "$width")${BOX_V}" "$color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "Attiva: $active_label" "$width")${BOX_V}" "$color"
  tui_print_centered_line "${BOX_BL}$(tui_repeat_char "$width" "$BOX_H")${BOX_BR}" "$color"
}

tui_render_new_profile_card() {
  local selected="$1"
  local color="$PRIMARY_FG"
  local width=38

  if [[ "$selected" == "1" ]]; then
    color="${SELECT_FG}${BOLD}"
  fi

  tui_print_centered_line "${BOX_TL}$(tui_repeat_char "$width" "$BOX_H")${BOX_TR}" "$color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "" "$width")${BOX_V}" "$color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "Nuova configurazione" "$width")${BOX_V}" "$color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "" "$width")${BOX_V}" "$color"
  tui_print_centered_line "${BOX_BL}$(tui_repeat_char "$width" "$BOX_H")${BOX_BR}" "$color"
}

tui_render_report_card() {
  local selected="$1"
  local target="$2"
  local status="$4"
  local created_at="$5"
  local color="$PRIMARY_FG"
  local status_color="$PRIMARY_FG"
  local width=38

  if [[ "$selected" == "1" ]]; then
    color="${SELECT_FG}${BOLD}"
  fi

  case "${status,,}" in
    banned*)
      status_color="${RED}${BOLD}"
      ;;
    loading*)
      status_color="${YELLOW}${BOLD}"
      ;;
    pending*)
      status_color="$MUTED_FG"
      ;;
    *)
      status_color="$color"
      ;;
  esac

  tui_print_centered_line "${BOX_TL}$(tui_repeat_char "$width" "$BOX_H")${BOX_TR}" "$color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "$target" "$width")${BOX_V}" "$color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "" "$width")${BOX_V}" "$color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "$status" "$width")${BOX_V}" "$status_color"
  tui_print_centered_line "${BOX_V}$(tui_center_text "$created_at" "$width")${BOX_V}" "$color"
  tui_print_centered_line "${BOX_BL}$(tui_repeat_char "$width" "$BOX_H")${BOX_BR}" "$color"
}

tui_render_action_list() {
  local selected_index="$1"
  shift
  local action_index=0
  local action_label=""

  printf '\n%sAzioni%s\n' "${PRIMARY_FG}${BOLD}" "$RESET"

  for action_label in "$@"; do
    if (( action_index == selected_index )); then
      printf '  %s> %s%s\n' "${SELECT_FG}${BOLD}" "$action_label" "$RESET"
    else
      printf '  %s  %s%s\n' "$PRIMARY_FG" "$action_label" "$RESET"
    fi

    action_index=$((action_index + 1))
  done
}

tui_render_hint_line_at() {
  local row="$1"
  local text="$2"
  local color="${3:-$MUTED_FG}"

  tui_render_centered_text_at "$row" "$text" "$color"
}

tui_bottom_notice_row() {
  local rows
  rows="$(get_terminal_rows)"

  if (( rows < 2 )); then
    rows=2
  fi

  printf '%s' "$((rows - 1))"
}

tui_bottom_hint_row() {
  local rows
  rows="$(get_terminal_rows)"

  if (( rows < 1 )); then
    rows=1
  fi

  printf '%s' "$rows"
}

tui_render_notice_line_at() {
  local row="$1"
  local text="${2-}"
  local color="${3:-$GREEN}"

  tui_clear_line_at "$row"

  if [[ -n "$text" ]]; then
    tui_render_centered_text_at "$row" "$text" "$color"
  fi
}

tui_render_action_region_at() {
  local start_row="$1"
  local selected_index="$2"
  local hint_text="$3"
  shift 3
  local labels=("$@")
  local idx=0
  local item_row=0
  local width
  local col
  local height=4
  local clear_row=0
  local clear_height=0
  local label_count="${#labels[@]}"

  if (( label_count > 0 )); then
    height=$((label_count + 2))
  fi

  width="$(tui_fit_box_width 58 32)"
  col="$(tui_block_start_col "$width")"

  clear_row=$((start_row - 1))
  if (( clear_row < 1 )); then
    clear_row=1
  fi
  clear_height=$((height + 2))
  tui_clear_block_at "$clear_row" "$clear_height"
  tui_draw_box_at "$start_row" "$col" "$width" "$height" "$BORDER_FG"

  if (( ${#labels[@]} > 0 )); then
    for idx in "${!labels[@]}"; do
      item_row=$((start_row + 1 + idx))
      tui_render_box_menu_item_at "$item_row" "$col" "$width" "${labels[$idx]}" "$([[ "$idx" == "$selected_index" ]] && printf 1 || printf 0)"
    done
  fi
}

tui_update_action_selection_at() {
  local start_row="$1"
  local previous_index="$2"
  local current_index="$3"
  shift 3
  local labels=("$@")
  local idx=0
  local width
  local col

  width="$(tui_fit_box_width 58 32)"
  col="$(tui_block_start_col "$width")"

  if [[ "$previous_index" == "$current_index" ]]; then
    return
  fi

  for idx in "$previous_index" "$current_index"; do
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 0 && idx < ${#labels[@]} )); then
      tui_render_box_menu_item_at "$((start_row + 1 + idx))" "$col" "$width" "${labels[$idx]}" "$([[ "$idx" == "$current_index" ]] && printf 1 || printf 0)"
    fi
  done
}

tui_update_configuration_action_selection() {
  local selected_index="$1"
  local previous_action_index="$2"
  local current_action_index="$3"
  local total_profiles="$4"
  local action_row
  local active_label="Attiva: No"
  local total_cards=$((total_profiles + 1))

  action_row="$(tui_configuration_action_row "$selected_index" "$total_cards")"

  if (( selected_index >= total_profiles )); then
    return
  fi

  tui_parse_profile_line "${PROFILE_LINES[$selected_index]}"

  if [[ "$PROFILE_ACTIVE" == "yes" ]]; then
    active_label="Attiva: Si"
  fi

  tui_render_action_region_at "$action_row" "$current_action_index" "UP su \"Modifica\" torna alla selezione schede." "Modifica" "Elimina" "$active_label"
}

tui_update_report_action_selection() {
  local previous_action_index="$1"
  local current_action_index="$2"
  local selected_index="$3"
  local total_reports="$4"
  local action_row
  action_row="$(tui_report_action_row "$selected_index" "$total_reports")"
  tui_render_action_region_at "$action_row" "$current_action_index" "UP su \"Nascondi\" torna alla selezione schede." "Nascondi" "Refresh"
}

tui_card_grid_columns() {
  local card_total_width="${1:-32}"
  local max_cols="${2:-4}"
  local cols
  local grid_cols=1

  cols="$(get_terminal_cols)"
  grid_cols=$(( cols / card_total_width ))

  if (( grid_cols < 1 )); then
    grid_cols=1
  elif (( grid_cols > max_cols )); then
    grid_cols="$max_cols"
  fi

  printf '%s' "$grid_cols"
}

tui_card_grid_page_size() {
  local columns="$1"
  local max_rows="${2:-2}"
  printf '%s' "$((columns * max_rows))"
}

tui_card_grid_page_start() {
  local selected_index="$1"
  local page_size="$2"

  if (( page_size <= 0 )); then
    printf '0'
    return
  fi

  printf '%s' "$(( (selected_index / page_size) * page_size ))"
}

tui_card_grid_visible_count() {
  local total_cards="$1"
  local page_start="$2"
  local page_size="$3"
  local visible_count=$((total_cards - page_start))

  if (( visible_count < 0 )); then
    visible_count=0
  elif (( visible_count > page_size )); then
    visible_count="$page_size"
  fi

  printf '%s' "$visible_count"
}

tui_card_grid_rows_used() {
  local visible_count="$1"
  local columns="$2"
  local rows_used=1

  if (( visible_count <= 0 )); then
    printf '1'
    return
  fi

  rows_used=$(( (visible_count + columns - 1) / columns ))
  if (( rows_used < 1 )); then
    rows_used=1
  elif (( rows_used > 2 )); then
    rows_used=2
  fi

  printf '%s' "$rows_used"
}

tui_centered_region_top_row() {
  local content_height="$1"
  local lower_limit_row="$2"
  local minimum_top=$((MENU_TOP_ROW + 3))
  local available_height=0
  local top_row="$minimum_top"

  if (( content_height < 1 )); then
    content_height=1
  fi

  if (( lower_limit_row <= minimum_top )); then
    printf '%s' "$minimum_top"
    return
  fi

  available_height=$((lower_limit_row - minimum_top + 1))

  if (( available_height > content_height )); then
    top_row=$((minimum_top + ((available_height - content_height) / 2)))
  fi

  printf '%s' "$top_row"
}

tui_centered_group_top_row() {
  local group_height="$1"
  local minimum_top="${2:-$MENU_TOP_ROW}"
  local lower_limit_row
  local available_height=0
  local top_row="$minimum_top"

  lower_limit_row=$(( $(get_terminal_rows) - 2 ))

  if (( group_height < 1 )); then
    group_height=1
  fi

  if (( lower_limit_row <= minimum_top )); then
    printf '%s' "$minimum_top"
    return
  fi

  available_height=$((lower_limit_row - minimum_top + 1))

  if (( available_height > group_height )); then
    top_row=$((minimum_top + ((available_height - group_height) / 2)))
  fi

  printf '%s' "$top_row"
}

tui_configuration_grid_columns() {
  tui_card_grid_columns 32 4
}

tui_configuration_page_size() {
  local columns
  columns="$(tui_configuration_grid_columns)"
  tui_card_grid_page_size "$columns" 2
}

tui_configuration_page_start() {
  local selected_index="$1"
  local total_cards="$2"
  local page_size

  page_size="$(tui_configuration_page_size)"
  tui_card_grid_page_start "$selected_index" "$page_size"
}

tui_configuration_visible_count() {
  local selected_index="$1"
  local total_cards="$2"
  local page_start
  local page_size

  page_start="$(tui_configuration_page_start "$selected_index" "$total_cards")"
  page_size="$(tui_configuration_page_size)"
  tui_card_grid_visible_count "$total_cards" "$page_start" "$page_size"
}

tui_configuration_rows_used() {
  local selected_index="$1"
  local total_cards="$2"
  local visible_count
  local columns

  visible_count="$(tui_configuration_visible_count "$selected_index" "$total_cards")"
  columns="$(tui_configuration_grid_columns)"
  tui_card_grid_rows_used "$visible_count" "$columns"
}

tui_report_grid_columns() {
  tui_card_grid_columns 32 4
}

tui_report_page_size() {
  local columns
  columns="$(tui_report_grid_columns)"
  tui_card_grid_page_size "$columns" 2
}

tui_report_page_start() {
  local selected_index="$1"
  local total_reports="$2"
  local page_size

  page_size="$(tui_report_page_size)"
  tui_card_grid_page_start "$selected_index" "$page_size"
}

tui_report_visible_count() {
  local selected_index="$1"
  local total_reports="$2"
  local page_start
  local page_size

  page_start="$(tui_report_page_start "$selected_index" "$total_reports")"
  page_size="$(tui_report_page_size)"
  tui_card_grid_visible_count "$total_reports" "$page_start" "$page_size"
}

tui_report_rows_used() {
  local selected_index="$1"
  local total_reports="$2"
  local visible_count
  local columns

  visible_count="$(tui_report_visible_count "$selected_index" "$total_reports")"
  columns="$(tui_report_grid_columns)"
  tui_card_grid_rows_used "$visible_count" "$columns"
}

tui_render_profile_list_card_at() {
  local row="$1"
  local col="$2"
  local selected="$3"
  local first_name="$4"
  local last_name="$5"
  local email="$6"
  local width=26
  local color="$PRIMARY_FG"

  if [[ "$selected" == "1" ]]; then
    color="${SELECT_FG}${BOLD}"
  fi

  tui_move_cursor "$row" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_TL" "$(tui_repeat_char "$width" "$BOX_H")" "$BOX_TR" "$RESET"
  tui_move_cursor "$((row + 1))" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_V" "$(tui_center_text "$first_name" "$width")" "$BOX_V" "$RESET"
  tui_move_cursor "$((row + 2))" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_V" "$(tui_center_text "$last_name" "$width")" "$BOX_V" "$RESET"
  tui_move_cursor "$((row + 3))" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_V" "$(tui_center_text "$email" "$width")" "$BOX_V" "$RESET"
  tui_move_cursor "$((row + 4))" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_BL" "$(tui_repeat_char "$width" "$BOX_H")" "$BOX_BR" "$RESET"
}

tui_render_new_profile_list_card_at() {
  local row="$1"
  local col="$2"
  local selected="$3"
  local width=26
  local color="$PRIMARY_FG"

  if [[ "$selected" == "1" ]]; then
    color="${SELECT_FG}${BOLD}"
  fi

  tui_move_cursor "$row" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_TL" "$(tui_repeat_char "$width" "$BOX_H")" "$BOX_TR" "$RESET"
  tui_move_cursor "$((row + 1))" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_V" "$(tui_center_text "" "$width")" "$BOX_V" "$RESET"
  tui_move_cursor "$((row + 2))" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_V" "$(tui_center_text "Nuova Config" "$width")" "$BOX_V" "$RESET"
  tui_move_cursor "$((row + 3))" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_V" "$(tui_center_text "" "$width")" "$BOX_V" "$RESET"
  tui_move_cursor "$((row + 4))" "$col"
  printf '%s%s%s%s%s' "$color" "$BOX_BL" "$(tui_repeat_char "$width" "$BOX_H")" "$BOX_BR" "$RESET"
}

tui_render_report_list_card_at() {
  local row="$1"
  local col="$2"
  local selected="$3"
  local target="$4"
  local status="$5"
  local created_at="$6"
  local width=26
  local border_color="$PRIMARY_FG"
  local text_color="$PRIMARY_FG"
  local status_color="$PRIMARY_FG"

  if [[ "$selected" == "1" ]]; then
    border_color="${SELECT_FG}${BOLD}"
    text_color="${SELECT_FG}${BOLD}"
  fi

  case "${status,,}" in
    banned*)
      status_color="${RED}${BOLD}"
      ;;
    pending*)
      status_color="$MUTED_FG"
      ;;
    *)
      status_color="$text_color"
      ;;
  esac

  tui_draw_box_at "$row" "$col" "$((width + 2))" 5 "$border_color"
  tui_render_box_centered_text_at "$((row + 1))" "$col" "$((width + 2))" "$target" "$text_color" "$border_color"
  tui_render_box_centered_text_at "$((row + 2))" "$col" "$((width + 2))" "$status" "$status_color" "$border_color"
  tui_render_box_centered_text_at "$((row + 3))" "$col" "$((width + 2))" "$created_at" "$text_color" "$border_color"
}

tui_configuration_action_row() {
  local rows
  local row
  rows="$(get_terminal_rows)"
  row=$((rows - 7))

  if (( row < MENU_TOP_ROW + 10 )); then
    row=$((MENU_TOP_ROW + 10))
  fi

  printf '%s' "$row"
}

tui_render_configuration_card_region() {
  local selected_index="$1"
  local total_profiles="$2"
  local card_row=0
  local header_top=0
  local total_cards=$((total_profiles + 1))
  local grid_cols
  local page_size
  local page_start
  local visible_count
  local rows_used
  local content_height=5
  local action_row=0
  local slot=0
  local card_index=0
  local col=1
  local card_total_width=32
  local block_width=0
  local start_col=1
  local row_offset=0
  local col_offset=0
  local display_cols=1
  local row=0
  local clear_bottom=0

  grid_cols="$(tui_configuration_grid_columns)"
  page_size="$(tui_configuration_page_size)"
  page_start="$(tui_configuration_page_start "$selected_index" "$total_cards")"
  visible_count="$(tui_configuration_visible_count "$selected_index" "$total_cards")"
  rows_used="$(tui_configuration_rows_used "$selected_index" "$total_cards")"
  content_height=$((rows_used * 6 - 1))
  action_row="$(tui_configuration_action_row)"
  card_row="$(tui_centered_region_top_row "$content_height" "$((action_row - 2))")"
  header_top=$((card_row - 4))
  if (( header_top < MENU_TOP_ROW )); then
    header_top="$MENU_TOP_ROW"
  fi

  clear_bottom=$((action_row - 1))
  tui_clear_region_between_rows "$MENU_TOP_ROW" "$clear_bottom"
  tui_render_header_box_at "$header_top" "Configuration" "" 78
  display_cols="$grid_cols"
  if (( visible_count < display_cols )); then
    display_cols="$visible_count"
  fi
  if (( display_cols < 1 )); then
    display_cols=1
  fi

  block_width=$((display_cols * card_total_width - 2))
  start_col="$(tui_block_start_col "$block_width")"

  for ((slot = 0; slot < visible_count; slot++)); do
    card_index=$((page_start + slot))
    row_offset=$((slot / grid_cols))
    col_offset=$((slot % grid_cols))
    col=$((start_col + (col_offset * card_total_width)))

    if (( card_index >= total_cards )); then
      continue
    fi

    row=$((card_row + (row_offset * 6)))

    if (( card_index == total_profiles )); then
      tui_render_new_profile_list_card_at "$row" "$col" "$([[ "$card_index" == "$selected_index" ]] && printf 1 || printf 0)"
    else
      tui_parse_profile_line "${PROFILE_LINES[$card_index]}"
      tui_render_profile_list_card_at "$row" "$col" "$([[ "$card_index" == "$selected_index" ]] && printf 1 || printf 0)" "$PROFILE_FIRST_NAME" "$PROFILE_LAST_NAME" "$PROFILE_EMAIL"
    fi
  done
}

tui_render_configuration_action_region() {
  local selected_index="$1"
  local total_profiles="$2"
  local focus_mode="$3"
  local action_index="$4"
  local action_row
  local active_label="Attiva: No"
  local total_cards=$((total_profiles + 1))

  action_row="$(tui_configuration_action_row "$selected_index" "$total_cards")"

  if [[ "$focus_mode" != "actions" ]]; then
    tui_clear_block_at "$action_row" 7
    return
  fi

  if (( total_profiles == 0 )) || (( selected_index >= total_profiles )); then
    tui_clear_block_at "$action_row" 7
    return
  fi

  tui_parse_profile_line "${PROFILE_LINES[$selected_index]}"

  if [[ "$PROFILE_ACTIVE" == "yes" ]]; then
    active_label="Attiva: Si"
  fi

  tui_render_action_region_at "$action_row" "$action_index" "UP su \"Modifica\" torna alla selezione schede." "Modifica" "Elimina" "$active_label"
}

tui_render_configuration_footer_region() {
  local selected_index="$1"
  local total_cards="$2"
  local focus_mode="$3"
  local notice="${4-}"
  local notice_row
  local hint_row
  local grid_cols
  local page_size
  local page_start
  local visible_count
  local window_end
  local current_page
  local total_pages
  local info_text=""
  local hint_text=""
  local notice_color="$MUTED_FG"

  notice_row="$(tui_bottom_notice_row)"
  hint_row="$(tui_bottom_hint_row)"
  grid_cols="$(tui_configuration_grid_columns)"
  page_size="$(tui_configuration_page_size)"
  page_start="$(tui_configuration_page_start "$selected_index" "$total_cards")"
  visible_count="$(tui_configuration_visible_count "$selected_index" "$total_cards")"
  window_end=$((page_start + visible_count))
  current_page=$(( (page_start / page_size) + 1 ))
  total_pages=$(( (total_cards + page_size - 1) / page_size ))

  info_text="Scheda $((selected_index + 1))/$total_cards  Pagina $current_page/$total_pages  Visibili $((page_start + 1))-$window_end"
  hint_text="LEFT/RIGHT schede  UP/DOWN righe  INVIO azioni  CTRL+H home"

  if [[ "$focus_mode" == "actions" ]]; then
    hint_text="UP/DOWN azioni  INVIO conferma  UP su prima voce torna alle schede  CTRL+H home"
  fi

  if [[ -n "$notice" ]]; then
    notice_color="$GREEN"
  fi

  tui_clear_line_at "$notice_row"
  tui_clear_line_at "$hint_row"
  tui_render_notice_line_at "$notice_row" "${notice:-$info_text}" "$notice_color"
  tui_render_hint_line_at "$hint_row" "$hint_text"
}

tui_report_action_row() {
  local rows
  local row
  rows="$(get_terminal_rows)"
  row=$((rows - 6))

  if (( row < MENU_TOP_ROW + 10 )); then
    row=$((MENU_TOP_ROW + 10))
  fi

  printf '%s' "$row"
}

tui_render_report_card_region() {
  local selected_index="$1"
  local card_row=0
  local header_top=0
  local total_reports="${#REPORT_LINES[@]}"
  local grid_cols
  local page_size
  local page_start
  local visible_count
  local rows_used
  local content_height=5
  local action_row=0
  local display_cols
  local card_total_width=32
  local block_width=0
  local start_col=1
  local slot=0
  local card_index=0
  local row_offset=0
  local col_offset=0
  local col=1
  local row=0
  local clear_bottom=0

  grid_cols="$(tui_report_grid_columns)"
  page_size="$(tui_report_page_size)"
  page_start="$(tui_report_page_start "$selected_index" "$total_reports")"
  visible_count="$(tui_report_visible_count "$selected_index" "$total_reports")"
  rows_used="$(tui_report_rows_used "$selected_index" "$total_reports")"
  content_height=$((rows_used * 6 - 1))
  action_row="$(tui_report_action_row "$selected_index" "$total_reports")"
  card_row="$(tui_centered_region_top_row "$content_height" "$((action_row - 2))")"
  header_top=$((card_row - 4))
  if (( header_top < MENU_TOP_ROW )); then
    header_top="$MENU_TOP_ROW"
  fi
  clear_bottom=$((action_row - 1))
  tui_clear_region_between_rows "$MENU_TOP_ROW" "$clear_bottom"
  tui_render_header_box_at "$header_top" "Report List" "" 78

  if (( total_reports == 0 )); then
    tui_render_hint_line_at "$card_row" "Nessuna richiesta visibile." "$YELLOW"
    return
  fi

  display_cols="$grid_cols"
  if (( visible_count < display_cols )); then
    display_cols="$visible_count"
  fi
  if (( display_cols < 1 )); then
    display_cols=1
  fi
  block_width=$((display_cols * card_total_width - 2))
  start_col="$(tui_block_start_col "$block_width")"

  for ((slot = 0; slot < visible_count; slot++)); do
    card_index=$((page_start + slot))
    row_offset=$((slot / grid_cols))
    col_offset=$((slot % grid_cols))
    col=$((start_col + (col_offset * card_total_width)))
    row=$((card_row + (row_offset * 6)))
    tui_parse_report_line "${REPORT_LINES[$card_index]}"
    tui_render_report_list_card_at "$row" "$col" "$([[ "$card_index" == "$selected_index" ]] && printf 1 || printf 0)" "$REPORT_TARGET" "$REPORT_STATUS" "$REPORT_CREATED_AT"
  done
}

tui_render_report_action_region() {
  local selected_index="$1"
  local total_reports="$2"
  local focus_mode="$3"
  local action_index="$4"
  local action_row
  action_row="$(tui_report_action_row "$selected_index" "$total_reports")"

  if [[ "$focus_mode" != "actions" ]]; then
    tui_clear_block_at "$action_row" 7
    return
  fi

  if (( ${#REPORT_LINES[@]} == 0 )); then
    tui_clear_block_at "$action_row" 7
    return
  fi

  tui_render_action_region_at "$action_row" "$action_index" "UP su \"Nascondi\" torna alla selezione schede." "Nascondi" "Refresh"
}

tui_render_report_footer_region() {
  local selected_index="$1"
  local total_reports="$2"
  local focus_mode="$3"
  local notice="${4-}"
  local notice_row
  local hint_row
  local page_size
  local page_start
  local visible_count
  local window_end
  local current_page
  local total_pages
  local info_text=""
  local hint_text=""
  local notice_color="$MUTED_FG"

  notice_row="$(tui_bottom_notice_row)"
  hint_row="$(tui_bottom_hint_row)"
  tui_clear_line_at "$notice_row"
  tui_clear_line_at "$hint_row"

  if (( total_reports > 0 )); then
    page_size="$(tui_report_page_size)"
    page_start="$(tui_report_page_start "$selected_index" "$total_reports")"
    visible_count="$(tui_report_visible_count "$selected_index" "$total_reports")"
    window_end=$((page_start + visible_count))
    current_page=$(( (page_start / page_size) + 1 ))
    total_pages=$(( (total_reports + page_size - 1) / page_size ))
    info_text="Scheda $((selected_index + 1))/$total_reports  Pagina $current_page/$total_pages  Visibili $((page_start + 1))-$window_end"
  else
    info_text="Nessun report visibile."
  fi

  hint_text="LEFT/RIGHT schede  UP/DOWN righe  INVIO azioni  CTRL+H home"
  if [[ "$focus_mode" == "actions" ]]; then
    hint_text="UP/DOWN azioni  INVIO conferma  UP su prima voce torna alle schede  CTRL+H home"
  fi

  if [[ -n "$notice" ]]; then
    notice_color="$GREEN"
  fi

  tui_render_notice_line_at "$notice_row" "${notice:-$info_text}" "$notice_color"
  tui_render_hint_line_at "$hint_row" "$hint_text"
}

tui_render_new_report_card_region() {
  local selected_index="$1"
  local card_row
  local notice_row
  local header_top
  local clear_bottom

  notice_row="$(tui_bottom_notice_row)"
  card_row="$(tui_centered_region_top_row 5 "$((notice_row - 3))")"
  header_top=$((card_row - 4))
  if (( header_top < MENU_TOP_ROW )); then
    header_top="$MENU_TOP_ROW"
  fi

  clear_bottom=$((notice_row - 1))
  tui_clear_region_between_rows "$MENU_TOP_ROW" "$clear_bottom"
  tui_render_header_box_at "$header_top" "New Report" "" 84
  tui_move_cursor "$card_row" 1
  tui_parse_profile_line "${PROFILE_LINES[$selected_index]}"
  tui_render_profile_card 1 "$PROFILE_FIRST_NAME" "$PROFILE_LAST_NAME" "$PROFILE_EMAIL" "$PROFILE_ACTIVE"
}

tui_render_new_report_footer_region() {
  local selected_index="$1"
  local active_locked="${2:-0}"
  local notice_row
  local hint_row
  local hint_text="LEFT/RIGHT schede  INVIO conferma  CTRL+H home"

  if (( active_locked == 1 )); then
    hint_text="INVIO conferma  CTRL+H home"
  fi

  notice_row="$(tui_bottom_notice_row)"
  hint_row="$(tui_bottom_hint_row)"
  tui_clear_line_at "$notice_row"
  tui_clear_line_at "$hint_row"
  tui_render_notice_line_at "$notice_row" "Scheda $((selected_index + 1))/${#PROFILE_LINES[@]}" "$MUTED_FG"
  tui_render_hint_line_at "$hint_row" "$hint_text"
}

tui_main_menu_geometry() {
  local rows
  local cols
  local menu_width=26
  local menu_height=6
  local gap=6
  local logo_width=0
  local logo_height=0
  local group_width=0
  local group_height=0
  local start_col=1
  local top_row=2
  local menu_top=2
  local logo_top=2
  local logo_col=1

  tui_load_trimmed_banner_lines "$MAIN_MENU_LOGO_PATH" 1
  logo_width="$(tui_banner_lines_max_width)"
  logo_height="${#BANNER_LINES[@]}"
  rows="$(get_terminal_rows)"
  cols="$(get_terminal_cols)"

  if (( logo_width < 1 )); then
    logo_width=0
    gap=0
  fi

  if (( menu_width + gap + logo_width > cols - 4 )); then
    gap=3
  fi

  if (( menu_width + gap + logo_width > cols - 4 )); then
    gap=0
    logo_width=0
    logo_height=0
  fi

  group_width=$((menu_width + gap + logo_width))
  group_height="$menu_height"
  if (( logo_height > group_height )); then
    group_height="$logo_height"
  fi

  if (( cols > group_width )); then
    start_col=$(( ((cols - group_width) / 2) + 1 ))
  fi

  if (( rows > group_height + 4 )); then
    top_row=$(( ((rows - 2 - group_height) / 2) + 1 ))
    if (( top_row < 2 )); then
      top_row=2
    fi
  fi

  menu_top=$((top_row + ((group_height - menu_height) / 2)))
  logo_col=$((start_col + menu_width + gap))
  logo_top="$top_row"

  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$menu_top" \
    "$start_col" \
    "$menu_width" \
    "$menu_height" \
    "$logo_top" \
    "$logo_col" \
    "$logo_width" \
    "$logo_height"
}

tui_render_main_menu_items() {
  local selected="$1"
  local base_row="$2"
  local col="$3"
  local width="$4"

  tui_render_box_menu_item_left_at "$((base_row + 1))" "$col" "$width" "New Report" "$([[ "$selected" == "0" ]] && printf 1 || printf 0)"
  tui_render_box_menu_item_left_at "$((base_row + 2))" "$col" "$width" "Report List" "$([[ "$selected" == "1" ]] && printf 1 || printf 0)"
  tui_render_box_menu_item_left_at "$((base_row + 3))" "$col" "$width" "Configuration" "$([[ "$selected" == "2" ]] && printf 1 || printf 0)"
  tui_render_box_menu_item_left_at "$((base_row + 4))" "$col" "$width" "Exit" "$([[ "$selected" == "3" ]] && printf 1 || printf 0)"
}

tui_render_main_menu_footer() {
  local hint_row
  hint_row="$(tui_bottom_hint_row)"
  tui_clear_line_at "$hint_row"
  tui_render_hint_line_at "$hint_row" "UP/DOWN seleziona  INVIO conferma  CTRL+H home"
}

tui_render_main_menu_view() {
  local selected="$1"
  local geometry=""
  local menu_top=0
  local menu_col=0
  local menu_width=0
  local menu_height=0
  local logo_top=0
  local logo_col=0
  local logo_width=0
  local logo_height=0

  tui_begin_view
  geometry="$(tui_main_menu_geometry)"
  IFS='|' read -r menu_top menu_col menu_width menu_height logo_top logo_col logo_width logo_height <<<"$geometry"
  tui_clear_block_at 1 "$(get_terminal_rows)"
  tui_draw_box_at "$menu_top" "$menu_col" "$menu_width" "$menu_height" "$BORDER_FG"
  tui_render_main_menu_items "$selected" "$menu_top" "$menu_col" "$menu_width"
  if (( logo_width > 0 && logo_height > 0 )); then
    tui_render_rainbow_logo_at "$logo_top" "$logo_col"
  fi
  tui_render_main_menu_footer
}

tui_update_main_menu_selection() {
  local previous="$1"
  local current="$2"
  local idx=0
  local label=""
  local labels=("New Report" "Report List" "Configuration" "Exit")
  local geometry=""
  local menu_top=0
  local menu_col=0
  local menu_width=0

  if [[ "$previous" == "$current" ]]; then
    return
  fi

  geometry="$(tui_main_menu_geometry)"
  IFS='|' read -r menu_top menu_col menu_width _ _ _ _ _ <<<"$geometry"

  for idx in "$previous" "$current"; do
    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 0 && idx < 4 )); then
      label="${labels[$idx]}"
      tui_render_box_menu_item_left_at "$((menu_top + 1 + idx))" "$menu_col" "$menu_width" "$label" "$([[ "$idx" == "$current" ]] && printf 1 || printf 0)"
    fi
  done
}

tui_render_configuration_static() {
  tui_begin_view
}

tui_render_configuration_dynamic() {
  local selected_index="$1"
  local focus_mode="$2"
  local action_index="$3"
  local notice="${4-}"
  local total_profiles="${#PROFILE_LINES[@]}"
  local total_cards=$((total_profiles + 1))

  tui_render_configuration_card_region "$selected_index" "$total_profiles"
  tui_render_configuration_action_region "$selected_index" "$total_profiles" "$focus_mode" "$action_index"
  tui_render_configuration_footer_region "$selected_index" "$total_cards" "$focus_mode" "$notice"
}

tui_render_configuration_view() {
  tui_render_configuration_static
  tui_render_configuration_dynamic "$@"
}

tui_render_report_list_static() {
  tui_begin_view
}

tui_render_report_list_dynamic() {
  local selected_index="$1"
  local focus_mode="$2"
  local action_index="$3"
  local notice="${4-}"
  local total_reports="${#REPORT_LINES[@]}"

  tui_render_report_card_region "$selected_index"
  tui_render_report_action_region "$selected_index" "$total_reports" "$focus_mode" "$action_index"
  tui_render_report_footer_region "$selected_index" "$total_reports" "$focus_mode" "$notice"
}

tui_render_report_list_view() {
  tui_render_report_list_static
  tui_render_report_list_dynamic "$@"
}

tui_render_new_report_selection_static() {
  local active_locked="$1"

  tui_begin_view
}

tui_render_new_report_selection_dynamic() {
  local selected_index="$1"
  local active_locked="$2"
  tui_render_new_report_card_region "$selected_index"
  tui_render_new_report_footer_region "$selected_index" "$active_locked"
}

tui_render_new_report_selection_view() {
  local selected_index="$1"
  local active_locked="$2"

  tui_render_new_report_selection_static "$active_locked"
  tui_render_new_report_selection_dynamic "$selected_index" "$active_locked"
}

tui_edit_profile_interactive() {
  local existing_line="${1-}"
  local existing_id=""
  local first_name_default=""
  local last_name_default=""
  local email_default=""
  local form_title="Nuova Configurazione"
  local active_index=0
  local notice=""
  local idx=0
  local geometry=""
  local top_row=0
  local col=0
  local width=0
  local height=0
  local label_width=0
  local content_indent=0
  local notice_row=0
  local input_col=0
  local cursor_row=0
  local current_value=""
  local trimmed_value=""
  local -a field_labels=("Nome" "Cognome" "Email")
  local -a field_values=()

  if [[ -n "$existing_line" ]]; then
    tui_parse_profile_line "$existing_line"
    existing_id="$PROFILE_ID"
    first_name_default="$PROFILE_FIRST_NAME"
    last_name_default="$PROFILE_LAST_NAME"
    email_default="$PROFILE_EMAIL"
    form_title="Modifica Configurazione"
  fi

  field_values=("$first_name_default" "$last_name_default" "$email_default")

  for idx in "${!field_values[@]}"; do
    if [[ -z "$(tui_trim_value "${field_values[$idx]}")" ]]; then
      active_index="$idx"
      break
    fi
  done

  tui_begin_view
  printf '\033[?25h'

  while true; do
    tui_render_profile_editor_form "$form_title" "$active_index" "$notice" "${field_values[@]}"
    notice=""

    geometry="$(tui_profile_editor_geometry)"
    IFS='|' read -r top_row col width height label_width content_indent notice_row <<<"$geometry"
    input_col=$((col + 1 + content_indent + label_width + 1))
    cursor_row=$((top_row + 3 + active_index))
    current_value="$(tui_truncate_text "${field_values[$active_index]}" "$((width - 2 - content_indent - label_width - 1))")"
    tui_move_cursor "$cursor_row" "$((input_col + ${#current_value}))"

    if ! tui_read_key; then
      printf '\033[?25l'
      return 1
    fi

    case "$LAST_KEY" in
      CTRL_HOME)
        HOME_REQUESTED=1
        printf '\033[?25l'
        return 130
        ;;
      BACKSPACE)
        if [[ -n "${field_values[$active_index]}" ]]; then
          field_values[$active_index]="${field_values[$active_index]%?}"
        fi
        ;;
      UP)
        if (( active_index > 0 )); then
          active_index=$((active_index - 1))
        fi
        ;;
      DOWN)
        if (( active_index < 2 )); then
          active_index=$((active_index + 1))
        fi
        ;;
      ENTER)
        trimmed_value="$(tui_trim_value "${field_values[$active_index]}")"

        if [[ -z "$trimmed_value" ]]; then
          notice="Campo obbligatorio."
          continue
        fi

        field_values[$active_index]="$trimmed_value"

        if (( active_index < 2 )); then
          active_index=$((active_index + 1))
        else
          break
        fi
        ;;
      SPACE)
        field_values[$active_index]+=" "
        ;;
      *)
        if [[ "${#LAST_KEY}" == "1" && "$LAST_KEY" =~ [[:print:]] ]]; then
          field_values[$active_index]+="$LAST_KEY"
        fi
        ;;
    esac
  done

  printf '\033[?25l'

  local first_name="$(tui_trim_value "${field_values[0]}")"
  local last_name="$(tui_trim_value "${field_values[1]}")"
  local email="$(tui_trim_value "${field_values[2]}")"
  local signature="$(tui_trim_value "$first_name $last_name")"

  if ! tui_upsert_profile_record "$existing_id" "$first_name" "$last_name" "$email" "$signature"; then
    return 1
  fi

  tui_load_profile_lines
  if (( ${#PROFILE_LINES[@]} == 0 )); then
    return 1
  fi

  return 0
}

tui_ensure_profile_configurations_exist() {
  tui_load_profile_lines

  if (( ${#PROFILE_LINES[@]} > 0 )); then
    return 0
  fi

  tui_begin_draw
  tui_print_centered_line "Nessuna configurazione salvata. Crea prima Nome, Cognome ed Email." "$YELLOW"
  printf '\n'
  tui_capture_status tui_edit_profile_interactive
  return "$CAPTURED_STATUS"
}

tui_collect_post_urls() {
  local show_profile_card="${1:-0}"
  local prompt_index=1
  COLLECTED_POST_URLS=()

  while true; do
    tui_capture_status tui_capture_boxed_input "Link Post $prompt_index" "URL" "" 1 "INVIO vuoto per terminare" "$show_profile_card"
    if (( CAPTURED_STATUS != 0 )); then
      return "$CAPTURED_STATUS"
    fi

    if [[ -z "$INPUT_RESULT" ]]; then
      return 0
    fi

    COLLECTED_POST_URLS+=("$INPUT_RESULT")
    prompt_index=$((prompt_index + 1))
  done
}

tui_choose_profile_for_report() {
  local selected_index=0
  local active_locked=0
  local redraw_mode="full"
  local next_index=0

  if tui_get_active_profile_line; then
    active_locked=1

    for idx in "${!PROFILE_LINES[@]}"; do
      if [[ "${PROFILE_LINES[$idx]}" == "$SELECTED_PROFILE_LINE" ]]; then
        selected_index="$idx"
        break
      fi
    done
  fi

  while true; do
    if [[ "$redraw_mode" == "full" ]]; then
      tui_render_new_report_selection_view "$selected_index" "$active_locked"
      redraw_mode=""
    elif [[ "$redraw_mode" == "dynamic" ]]; then
      tui_render_new_report_selection_dynamic "$selected_index" "$active_locked"
      redraw_mode=""
    fi

    if ! tui_read_key; then
      return 1
    fi

    case "$LAST_KEY" in
      CTRL_HOME)
        HOME_REQUESTED=1
        return 0
        ;;
      LEFT)
        if (( active_locked == 0 )); then
          next_index=$(( (selected_index - 1 + ${#PROFILE_LINES[@]}) % ${#PROFILE_LINES[@]} ))

          if (( next_index != selected_index )); then
            selected_index="$next_index"
            redraw_mode="dynamic"
          fi
        fi
        ;;
      RIGHT)
        if (( active_locked == 0 )); then
          next_index=$(( (selected_index + 1) % ${#PROFILE_LINES[@]} ))

          if (( next_index != selected_index )); then
            selected_index="$next_index"
            redraw_mode="dynamic"
          fi
        fi
        ;;
      ENTER)
        SELECTED_PROFILE_LINE="${PROFILE_LINES[$selected_index]}"
        return 0
        ;;
    esac
  done
}

tui_configuration_menu() {
  local selected_index=0
  local focus_mode="cards"
  local action_index=0
  local notice=""
  local total_profiles=0
  local total_cards=1
  local result=0
  local next_active="no"
  local redraw_mode="full"
  local next_index=0
  local previous_action_index=0
  local grid_cols=1

  while true; do
    tui_load_profile_lines
    total_profiles="${#PROFILE_LINES[@]}"
    total_cards=$((total_profiles + 1))

    if (( selected_index >= total_cards )); then
      selected_index=$((total_cards - 1))
    fi

    if (( total_profiles == 0 )); then
      selected_index=0
      focus_mode="cards"
      action_index=0
    elif [[ "$focus_mode" == "actions" && "$selected_index" -ge "$total_profiles" ]]; then
      focus_mode="cards"
      action_index=0
    fi

    if [[ "$redraw_mode" == "full" ]]; then
      tui_render_configuration_view "$selected_index" "$focus_mode" "$action_index" "$notice"
      redraw_mode=""
    elif [[ "$redraw_mode" == "card" ]]; then
      tui_render_configuration_card_region "$selected_index" "$total_profiles"
      tui_render_configuration_action_region "$selected_index" "$total_profiles" "$focus_mode" "$action_index"
      tui_render_configuration_footer_region "$selected_index" "$total_cards" "$focus_mode" "$notice"
      redraw_mode=""
    elif [[ "$redraw_mode" == "actions" ]]; then
      tui_render_configuration_action_region "$selected_index" "$total_profiles" "$focus_mode" "$action_index"
      tui_render_configuration_footer_region "$selected_index" "$total_cards" "$focus_mode" "$notice"
      redraw_mode=""
    elif [[ "$redraw_mode" == "action_select" ]]; then
      tui_update_configuration_action_selection "$selected_index" "$previous_action_index" "$action_index" "$total_profiles"
      redraw_mode=""
    fi

    notice=""

    if ! tui_read_key; then
      return 1
    fi

    case "$LAST_KEY" in
      CTRL_HOME)
        HOME_REQUESTED=1
        return 0
        ;;
      LEFT)
        if [[ "$focus_mode" == "cards" && "$total_cards" -gt 1 ]]; then
          if (( selected_index > 0 )); then
            selected_index=$((selected_index - 1))
            redraw_mode="card"
          fi
        fi
        ;;
      RIGHT)
        if [[ "$focus_mode" == "cards" && "$total_cards" -gt 1 ]]; then
          if (( selected_index + 1 < total_cards )); then
            selected_index=$((selected_index + 1))
            redraw_mode="card"
          fi
        fi
        ;;
      DOWN)
        if [[ "$focus_mode" == "cards" && "$total_cards" -gt 0 ]]; then
          grid_cols="$(tui_configuration_grid_columns)"
          next_index=$((selected_index + grid_cols))
          if (( next_index < total_cards )); then
            selected_index="$next_index"
            redraw_mode="card"
          fi
        elif [[ "$focus_mode" == "actions" && "$action_index" -lt 2 ]]; then
          previous_action_index="$action_index"
          action_index=$((action_index + 1))
          redraw_mode="action_select"
        fi
        ;;
      UP)
        if [[ "$focus_mode" == "cards" && "$total_cards" -gt 0 ]]; then
          grid_cols="$(tui_configuration_grid_columns)"
          next_index=$((selected_index - grid_cols))
          if (( next_index >= 0 )); then
            selected_index="$next_index"
            redraw_mode="card"
          fi
        elif [[ "$focus_mode" == "actions" ]]; then
          if (( action_index == 0 )); then
            focus_mode="cards"
            redraw_mode="actions"
          else
            previous_action_index="$action_index"
            action_index=$((action_index - 1))
            redraw_mode="action_select"
          fi
        fi
        ;;
      ENTER)
        if [[ "$focus_mode" == "cards" ]]; then
          if (( selected_index == total_profiles )); then
            tui_capture_status tui_edit_profile_interactive
            result=$CAPTURED_STATUS

            if (( HOME_REQUESTED == 1 )); then
              return 0
            elif (( result == 130 )); then
              return 130
            elif (( result != 0 )); then
              notice="Creazione annullata."
            else
              notice="Configurazione salvata."
            fi
            redraw_mode="full"
          elif (( total_profiles > 0 )); then
            focus_mode="actions"
            action_index=0
            redraw_mode="actions"
          fi
        elif (( selected_index < total_profiles )); then
          tui_parse_profile_line "${PROFILE_LINES[$selected_index]}"

          case "$action_index" in
            0)
              tui_capture_status tui_edit_profile_interactive "${PROFILE_LINES[$selected_index]}"
              result=$CAPTURED_STATUS

              if (( HOME_REQUESTED == 1 )); then
                return 0
              elif (( result == 130 )); then
                return 130
              elif (( result == 0 )); then
                notice="Configurazione aggiornata."
              fi
              redraw_mode="full"
              ;;
            1)
              tui_delete_profile_record "$PROFILE_ID"
              focus_mode="cards"
              action_index=0
              notice="Configurazione eliminata."
              redraw_mode="full"
              ;;
            2)
              next_active="yes"

              if [[ "$PROFILE_ACTIVE" == "yes" ]]; then
                next_active="no"
              fi

              tui_set_profile_active_state "$PROFILE_ID" "$next_active"
              notice="Configurazione attiva aggiornata."
              redraw_mode="card"
              ;;
          esac
        fi
        ;;
    esac
  done
}

tui_report_list_menu() {
  local selected_index=0
  local focus_mode="cards"
  local action_index=0
  local notice=""
  local redraw_mode="full"
  local next_index=0
  local previous_action_index=0
  local grid_cols=1
  local total_reports=0
  local result=0

  tui_load_report_lines
  total_reports="${#REPORT_LINES[@]}"

  if (( total_reports > 0 )); then
    tui_capture_status tui_refresh_report_statuses all "" "" "" "$selected_index" "$focus_mode" "$action_index"
    result=$CAPTURED_STATUS

    if (( result == 0 )); then
      notice="Stati account aggiornati."
    else
      notice="Verifica parziale: alcuni account sono rimasti Pending."
    fi
  fi

  while true; do
    tui_load_report_lines
    total_reports="${#REPORT_LINES[@]}"

    if (( total_reports == 0 )); then
      focus_mode="cards"
      action_index=0
      selected_index=0
    elif (( selected_index >= total_reports )); then
      selected_index=$(( total_reports - 1 ))
    fi

    if [[ "$redraw_mode" == "full" ]]; then
      tui_render_report_list_view "$selected_index" "$focus_mode" "$action_index" "$notice"
      redraw_mode=""
    elif [[ "$redraw_mode" == "card" ]]; then
      tui_render_report_card_region "$selected_index"
      tui_render_report_footer_region "$selected_index" "$total_reports" "$focus_mode" "$notice"
      redraw_mode=""
    elif [[ "$redraw_mode" == "actions" ]]; then
      tui_render_report_action_region "$selected_index" "$total_reports" "$focus_mode" "$action_index"
      tui_render_report_footer_region "$selected_index" "$total_reports" "$focus_mode" "$notice"
      redraw_mode=""
    elif [[ "$redraw_mode" == "footer" ]]; then
      tui_render_report_footer_region "$selected_index" "$total_reports" "$focus_mode" "$notice"
      redraw_mode=""
    elif [[ "$redraw_mode" == "action_select" ]]; then
      tui_update_report_action_selection "$previous_action_index" "$action_index" "$selected_index" "$total_reports"
      redraw_mode=""
    fi

    notice=""

    if ! tui_read_key; then
      return 1
    fi

    case "$LAST_KEY" in
      CTRL_HOME)
        HOME_REQUESTED=1
        return 0
        ;;
      LEFT)
        if [[ "$focus_mode" == "cards" && total_reports -gt 0 ]]; then
          if (( selected_index > 0 )); then
            selected_index=$((selected_index - 1))
            redraw_mode="card"
          fi
        fi
        ;;
      RIGHT)
        if [[ "$focus_mode" == "cards" && total_reports -gt 0 ]]; then
          if (( selected_index + 1 < total_reports )); then
            selected_index=$((selected_index + 1))
            redraw_mode="card"
          fi
        fi
        ;;
      DOWN)
        if [[ "$focus_mode" == "cards" && total_reports -gt 0 ]]; then
          grid_cols="$(tui_report_grid_columns)"
          next_index=$((selected_index + grid_cols))
          if (( next_index < total_reports )); then
            selected_index="$next_index"
            redraw_mode="card"
          fi
        elif [[ "$focus_mode" == "actions" && "$action_index" -lt 1 ]]; then
          previous_action_index="$action_index"
          action_index=$((action_index + 1))
          redraw_mode="action_select"
        fi
        ;;
      UP)
        if [[ "$focus_mode" == "cards" && total_reports -gt 0 ]]; then
          grid_cols="$(tui_report_grid_columns)"
          next_index=$((selected_index - grid_cols))
          if (( next_index >= 0 )); then
            selected_index="$next_index"
            redraw_mode="card"
          fi
        elif [[ "$focus_mode" == "actions" ]]; then
          if (( action_index == 0 )); then
            focus_mode="cards"
            redraw_mode="actions"
          else
            previous_action_index="$action_index"
            action_index=$((action_index - 1))
            redraw_mode="action_select"
          fi
        fi
        ;;
      ENTER)
        if (( total_reports == 0 )); then
          notice="Nessun report da mostrare."
          redraw_mode="footer"
        elif [[ "$focus_mode" == "cards" ]]; then
          focus_mode="actions"
          action_index=0
          redraw_mode="actions"
        else
          tui_parse_report_line "${REPORT_LINES[$selected_index]}"

          case "$action_index" in
            0)
              tui_hide_report_record "$REPORT_ID"
              focus_mode="cards"
              action_index=0
              notice="Report nascosto."
            redraw_mode="full"
              ;;
            1)
              result=0
              focus_mode="cards"
              action_index=0
              tui_capture_status tui_refresh_report_statuses single "$REPORT_ID" "$REPORT_TARGET" "$REPORT_PROFILE_URL" "$selected_index" "$focus_mode" "$action_index"
              result=$CAPTURED_STATUS
              if (( result == 0 )); then
                notice="Controllo aggiornato."
              else
                notice="Controllo incompleto: stato lasciato su Pending."
              fi
              redraw_mode="full"
              ;;
          esac
        fi
        ;;
    esac
  done
}

tui_new_report_menu() {
  local result=0
  local profile_url=""
  local post_urls_blob=""
  local configuration_name=""
  local show_profile_card=1

  tui_capture_status tui_ensure_profile_configurations_exist
  result=$CAPTURED_STATUS
  if (( result != 0 )); then
    if (( HOME_REQUESTED == 1 )); then
      return 0
    elif (( result == 130 )); then
      return 130
    fi

    return 1
  fi

  tui_load_profile_lines

  if ! tui_get_active_profile_line; then
    tui_capture_status tui_choose_profile_for_report
    result=$CAPTURED_STATUS
    if (( HOME_REQUESTED == 1 )); then
      return 0
    elif (( result != 0 )); then
      if (( result == 130 )); then
        return 130
      fi

      return 1
    fi
  fi

  tui_parse_profile_line "$SELECTED_PROFILE_LINE"
  configuration_name="$PROFILE_FIRST_NAME $PROFILE_LAST_NAME <$PROFILE_EMAIL>"

  if [[ "$PROFILE_ACTIVE" == "yes" ]]; then
    show_profile_card=0
  fi

  tui_capture_status tui_capture_boxed_input "Profile URL" "URL" "" 0 "" "$show_profile_card"
  result=$CAPTURED_STATUS
  if (( result != 0 )); then
    if (( HOME_REQUESTED == 1 )); then
      return 0
    elif (( result == 130 )); then
      return 130
    fi
    return 1
  fi
  profile_url="$INPUT_RESULT"

  tui_capture_status tui_collect_post_urls "$show_profile_card"
  result=$CAPTURED_STATUS
  if (( result != 0 )); then
    if (( HOME_REQUESTED == 1 )); then
      return 0
    elif (( result == 130 )); then
      return 130
    fi
    return 1
  fi

  if (( ${#COLLECTED_POST_URLS[@]} > 0 )); then
    post_urls_blob="$(printf '%s\n' "${COLLECTED_POST_URLS[@]}")"
  fi

  tui_begin_view
  tui_print_centered_line "Preparazione report" "${PRIMARY_FG}${BOLD}"
  printf '\n'
  tui_print_centered_line "Profilo: $profile_url" "$PRIMARY_FG"
  tui_print_centered_line "Post allegati: ${#COLLECTED_POST_URLS[@]}" "$PRIMARY_FG"
  if (( show_profile_card == 1 )); then
    tui_print_centered_line "Configurazione: $configuration_name" "$PRIMARY_FG"
  fi
  printf '\n'

  if ! build_report_artifacts "$profile_url" "$post_urls_blob"; then
    tui_capture_status tui_show_report_summary_box "Errore durante la generazione dei file." "$RED" "$configuration_name" "$profile_url" "${#COLLECTED_POST_URLS[@]}"
    result=$CAPTURED_STATUS
    if (( HOME_REQUESTED == 1 )); then
      return 0
    fi
    return "$result"
  fi

  tui_capture_status tui_run_assist_with_progress "$PROFILE_FIRST_NAME" "$PROFILE_LAST_NAME" "$PROFILE_EMAIL" "$PROFILE_SIGNATURE" "$profile_url"
  result=$CAPTURED_STATUS

  if (( result == 0 )); then
    append_report_history "$configuration_name" "$PROFILE_FIRST_NAME" "$PROFILE_LAST_NAME" "$PROFILE_EMAIL" "$PROFILE_SIGNATURE" "$profile_url" "$post_urls_blob"
    tui_capture_status tui_show_report_summary_box "Richiesta inviata" "$GREEN" "$configuration_name" "$profile_url" "${#COLLECTED_POST_URLS[@]}"
  else
    tui_capture_status tui_show_report_summary_box "Errore durante l'invio assistito" "$RED" "$configuration_name" "$profile_url" "${#COLLECTED_POST_URLS[@]}"
  fi

  result=$CAPTURED_STATUS
  if (( HOME_REQUESTED == 1 )); then
    return 0
  fi
  return "$result"
}

tui_main_menu() {
  local selected_index=0
  local result=0
  local redraw_mode="full"
  local next_index=0

  ensure_application_state
  tui_render_banner_once
  tui_load_profile_lines

  if (( ${#PROFILE_LINES[@]} == 0 )); then
    tui_begin_draw
    tui_print_centered_line "Nessuna configurazione salvata. Crea Nome, Cognome ed Email per iniziare." "$YELLOW"
    printf '\n'
    tui_capture_status tui_edit_profile_interactive
    result=$CAPTURED_STATUS

    if (( result != 0 && result != 130 )); then
      return "$result"
    fi

    if (( HOME_REQUESTED == 1 )); then
      HOME_REQUESTED=0
    fi
  fi

  while true; do
    if [[ "$redraw_mode" == "full" ]]; then
      tui_render_main_menu_view "$selected_index"
      redraw_mode=""
    fi

    if ! tui_read_key; then
      return 0
    fi

    case "$LAST_KEY" in
      CTRL_HOME)
        if (( selected_index != 0 )); then
          tui_update_main_menu_selection "$selected_index" 0
          selected_index=0
        fi
        ;;
      UP)
        next_index=$(( (selected_index - 1 + 4) % 4 ))
        tui_update_main_menu_selection "$selected_index" "$next_index"
        selected_index="$next_index"
        ;;
      DOWN)
        next_index=$(( (selected_index + 1) % 4 ))
        tui_update_main_menu_selection "$selected_index" "$next_index"
        selected_index="$next_index"
        ;;
      ENTER)
        case "$selected_index" in
          0)
            tui_capture_status tui_new_report_menu
            result=$CAPTURED_STATUS
            ;;
          1)
            tui_capture_status tui_report_list_menu
            result=$CAPTURED_STATUS
            ;;
          2)
            tui_capture_status tui_configuration_menu
            result=$CAPTURED_STATUS
            ;;
          3)
            return 0
            ;;
        esac

        redraw_mode="full"

        if (( HOME_REQUESTED == 1 )); then
          selected_index=0
          HOME_REQUESTED=0
        fi

        if (( result == 130 )); then
          selected_index=0
        fi
        ;;
    esac
  done
}

trap 'cleanup_terminal' EXIT
trap 'handle_interrupt' INT TERM
prepare_terminal
printf '\033[?25l'
tui_show_intro_splash
tui_main_menu
